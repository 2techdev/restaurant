/// Waiter-specific order service.
///
/// Wraps the core [OrderRepositoryImpl], [KitchenRepositoryImpl], and
/// [TableRepositoryImpl] with waiter-oriented semantics:
/// - Orders are tagged with [waiterId], [tableId], and [OrderChannel.waiter].
/// - Provides helpers for the waiter order flow: open → sent → served.
/// - [claimTable] / [releaseTable] own a table across sessions.
/// - [reorderFromTable] quick-copies items from a table's last open order.
library;

import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/kitchen/data/repositories/kitchen_repository_impl.dart';
import 'package:gastrocore_pos/features/orders/data/repositories/order_repository_impl.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/order_item_entity.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/product_entity.dart';
import 'package:gastrocore_pos/features/tables/data/repositories/table_repository_impl.dart';
import 'package:gastrocore_pos/features/tables/domain/entities/table_entity.dart';

// ---------------------------------------------------------------------------
// WaiterOrderService
// ---------------------------------------------------------------------------

/// Service layer for all waiter-facing order actions.
///
/// Injected via [waiterOrderServiceProvider]; never instantiated directly.
class WaiterOrderService {
  final OrderRepositoryImpl _orderRepo;
  final KitchenRepositoryImpl _kitchenRepo;
  final TableRepositoryImpl _tableRepo;

  WaiterOrderService({
    required OrderRepositoryImpl orderRepo,
    required KitchenRepositoryImpl kitchenRepo,
    required TableRepositoryImpl tableRepo,
  })  : _orderRepo = orderRepo,
        _kitchenRepo = kitchenRepo,
        _tableRepo = tableRepo;

  // =========================================================================
  // Ticket creation & management
  // =========================================================================

  /// Open a new draft ticket on behalf of [waiterId] for [tableId].
  ///
  /// Tagged [OrderChannel.waiter] so the sync service and KDS can distinguish
  /// waiter orders from POS-created ones.
  Future<TicketEntity> openNewOrder({
    required String tenantId,
    required String waiterId,
    required String waiterName,
    required String tableId,
    required String deviceId,
    int guestCount = 2,
    OrderType orderType = OrderType.dineIn,
  }) async {
    final nextNumber = await _orderRepo.getNextOrderNumber(tenantId);
    final ticket = TicketEntity(
      id: IdGenerator.generateId(),
      tenantId: tenantId,
      orderNumber: IdGenerator.generateOrderNumber(nextNumber),
      orderType: orderType,
      tableId: tableId,
      waiterId: waiterId,
      cashierName: waiterName,
      guestCount: guestCount,
      status: TicketStatus.draft,
      channel: OrderChannel.waiter,
      openedAt: DateTime.now(),
      deviceId: deviceId,
    );
    await _tableRepo.updateTableStatus(tableId, TableStatus.occupied);
    return _orderRepo.createTicket(ticket);
  }

  /// Add a product to an existing open ticket.
  ///
  /// Returns the updated [TicketEntity] after the item is persisted,
  /// or `null` if the ticket is closed / not found.
  ///
  /// [course] tags the item with a Gang number (1..kMaxGangs) so the
  /// fine-dining Hold & Fire flow can dispatch each course independently.
  /// Defaults to 1 to match single-course waiter flows.
  Future<TicketEntity?> addItemToTicket({
    required String ticketId,
    required ProductEntity product,
    double quantity = 1,
    List<OrderItemModifierEntity> modifiers = const [],
    String? notes,
    int course = 1,
  }) async {
    final ticket = await _orderRepo.getTicketById(ticketId);
    if (ticket == null || !ticket.isOpen) return null;

    final modifierTotal = modifiers.fold<int>(0, (s, m) => s + m.priceDelta);
    final subtotal = ((product.price + modifierTotal) * quantity).round();
    final taxAmount = _extractTax(
      grossPrice: subtotal,
      taxGroup: product.taxGroup,
      orderType: ticket.orderType,
    );

    final itemId = IdGenerator.generateId();
    final reKeyedModifiers =
        modifiers.map((m) => m.copyWith(orderItemId: itemId)).toList();

    final item = OrderItemEntity(
      id: itemId,
      tenantId: ticket.tenantId,
      ticketId: ticketId,
      productId: product.id,
      productName: product.name,
      quantity: quantity,
      unitPrice: product.price,
      subtotal: subtotal,
      taxAmount: taxAmount,
      notes: notes,
      course: course,
      modifiers: reKeyedModifiers,
      taxGroup: product.taxGroup,
    );

    await _orderRepo.addItemToTicket(ticketId, item);
    return _orderRepo.getTicketById(ticketId);
  }

  /// Remove an item from a ticket. Returns the refreshed ticket.
  Future<TicketEntity?> removeItemFromTicket({
    required String ticketId,
    required String itemId,
  }) async {
    await _orderRepo.removeItemFromTicket(itemId);
    return _orderRepo.getTicketById(ticketId);
  }

  // =========================================================================
  // Kitchen dispatch
  // =========================================================================

  /// Send all un-sent items on [ticketId] to the kitchen.
  ///
  /// Returns the refreshed ticket. Idempotent — only unsent items are sent.
  Future<TicketEntity?> sendToKitchen({
    required String ticketId,
    required String waiterName,
  }) async {
    final ticket = await _orderRepo.getTicketById(ticketId);
    if (ticket == null) return null;

    final unsent = ticket.items.where((i) => !i.sentToKitchen).toList();
    for (final item in unsent) {
      await _orderRepo.updateItemStatus(item.id, OrderItemStatus.sent);
    }

    await _orderRepo.updateTicketStatus(ticketId, TicketStatus.sent);

    if (unsent.isNotEmpty) {
      await _kitchenRepo.createTicketFromOrder(
        ticket: ticket,
        items: unsent,
        waiterName: waiterName,
      );
    }

    return _orderRepo.getTicketById(ticketId);
  }

  /// Fire a single Gang (course) — scope the kitchen dispatch to items
  /// tagged with [OrderItemEntity.course] == [gang].
  ///
  /// This mirrors the fine-dining [CurrentTicketNotifier.fireGang] flow so
  /// the waiter tablet and the POS shell have one canonical Hold & Fire
  /// pattern. Returns the refreshed ticket. Idempotent.
  Future<TicketEntity?> fireGang({
    required String ticketId,
    required int gang,
    required String waiterName,
  }) async {
    final ticket = await _orderRepo.getTicketById(ticketId);
    if (ticket == null) return null;

    final unsentForGang = ticket.items
        .where((i) => !i.sentToKitchen && i.course == gang)
        .toList();
    if (unsentForGang.isEmpty) return ticket;

    for (final item in unsentForGang) {
      await _orderRepo.updateItemStatus(item.id, OrderItemStatus.sent);
    }

    if (ticket.status == TicketStatus.draft ||
        ticket.status == TicketStatus.open) {
      await _orderRepo.updateTicketStatus(ticketId, TicketStatus.sent);
    }

    await _kitchenRepo.createTicketFromOrder(
      ticket: ticket,
      items: unsentForGang,
      waiterName: waiterName,
    );

    return _orderRepo.getTicketById(ticketId);
  }

  // =========================================================================
  // Status helpers
  // =========================================================================

  /// Mark an order as served (all items delivered to the table).
  Future<void> markServed(String ticketId) async {
    await _orderRepo.updateTicketStatus(ticketId, TicketStatus.served);
    final ticket = await _orderRepo.getTicketById(ticketId);
    if (ticket == null) return;
    for (final item in ticket.items) {
      if (item.status == OrderItemStatus.ready ||
          item.status == OrderItemStatus.sent ||
          item.status == OrderItemStatus.preparing) {
        await _orderRepo.updateItemStatus(item.id, OrderItemStatus.served);
      }
    }
  }

  /// Request the bill for a table (signals POS to handle payment).
  Future<void> requestBill(String ticketId) async {
    await _orderRepo.updateTicketStatus(ticketId, TicketStatus.billRequested);
  }

  // =========================================================================
  // Active orders for a waiter
  // =========================================================================

  /// All non-completed orders assigned to [waiterId] via the waiter channel.
  Future<List<TicketEntity>> getActiveOrdersForWaiter({
    required String tenantId,
    required String waiterId,
  }) async {
    final open = await _orderRepo.getOpenTickets(tenantId);
    return open
        .where((t) =>
            t.waiterId == waiterId && t.channel == OrderChannel.waiter)
        .toList();
  }

  /// All open orders for a specific table (any channel).
  Future<List<TicketEntity>> getOrdersForTable({
    required String tenantId,
    required String tableId,
  }) async {
    return _orderRepo.getTicketsByTable(tableId);
  }

  // =========================================================================
  // Table ownership
  // =========================================================================

  /// Claim [tableId] as occupied (marks it in use by this waiter).
  Future<void> claimTable(String tableId, String waiterId) async {
    await _tableRepo.updateTableStatus(tableId, TableStatus.occupied);
  }

  /// Release [tableId] back to available (e.g. bill paid, guests left).
  Future<void> releaseTable(String tableId) async {
    await _tableRepo.updateTableStatus(tableId, TableStatus.available);
  }

  // =========================================================================
  // Quick reorder
  // =========================================================================

  /// Copy items from the table's most-recent open order into a new draft.
  ///
  /// Returns `null` if no previous order exists for the table.
  Future<TicketEntity?> reorderFromTable({
    required String tenantId,
    required String waiterId,
    required String waiterName,
    required String tableId,
    required String deviceId,
  }) async {
    // Use the most recent open order for this table as the template.
    final existing = await _orderRepo.getTicketsByTable(tableId);
    if (existing.isEmpty) return null;

    final template = existing.first;
    final newTicket = await openNewOrder(
      tenantId: tenantId,
      waiterId: waiterId,
      waiterName: waiterName,
      tableId: tableId,
      deviceId: deviceId,
      guestCount: template.guestCount,
    );

    for (final oldItem in template.items) {
      final newItemId = IdGenerator.generateId();
      final newItem = OrderItemEntity(
        id: newItemId,
        tenantId: tenantId,
        ticketId: newTicket.id,
        productId: oldItem.productId,
        productName: oldItem.productName,
        quantity: oldItem.quantity,
        unitPrice: oldItem.unitPrice,
        subtotal: oldItem.subtotal,
        taxAmount: oldItem.taxAmount,
        taxGroup: oldItem.taxGroup,
        modifiers: oldItem.modifiers
            .map((m) => m.copyWith(orderItemId: newItemId))
            .toList(),
      );
      await _orderRepo.addItemToTicket(newTicket.id, newItem);
    }

    return _orderRepo.getTicketById(newTicket.id);
  }

  // =========================================================================
  // Internal helpers
  // =========================================================================

  /// Extract Swiss MWST from a tax-inclusive gross price.
  static int _extractTax({
    required int grossPrice,
    required String taxGroup,
    required OrderType orderType,
  }) {
    final rate = _taxRate(taxGroup, orderType);
    if (rate <= 0) return 0;
    return (grossPrice * rate / (100 + rate)).round();
  }

  static double _taxRate(String taxGroup, OrderType orderType) {
    final isTakeaway =
        orderType == OrderType.takeaway || orderType == OrderType.delivery;
    switch (taxGroup) {
      case 'food':
        return isTakeaway ? 2.6 : 8.1;
      case 'beverage':
      case 'alcohol':
      case 'standard':
        return 8.1;
      case 'accommodation':
        return 3.8;
      default:
        return 8.1;
    }
  }
}
