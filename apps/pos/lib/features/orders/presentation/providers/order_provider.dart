/// Riverpod providers for the order (ticket) feature.
///
/// Manages the active ticket being built by the cashier, the list of open
/// tickets, and actions like adding / removing items and sending to kitchen.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/core/printing/models/print_models.dart';
import 'package:gastrocore_pos/core/printing/providers/print_use_case_provider.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:gastrocore_pos/features/kitchen/domain/entities/kitchen_ticket_entity.dart';
import 'package:gastrocore_pos/features/kitchen/presentation/providers/kitchen_provider.dart';
import 'package:gastrocore_pos/features/orders/data/repositories/order_repository_impl.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/order_item_entity.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/product_entity.dart';
import 'package:gastrocore_pos/core/services/fare_engine.dart';
import 'package:gastrocore_pos/core/services/fare_models.dart';
import 'package:gastrocore_pos/features/auth/domain/entities/user_entity.dart';
import 'package:gastrocore_pos/features/overrides/domain/entities/override_action.dart';
import 'package:gastrocore_pos/features/overrides/presentation/providers/override_provider.dart';

// ---------------------------------------------------------------------------
// Swiss VAT configuration (effective 2024-01-01)
// ---------------------------------------------------------------------------

/// Standard Swiss MWST configuration for fare calculation.
///
/// Rates per ESTV: 8.1% normal, 2.6% reduced (food takeaway), 3.8% special.
/// Prices are tax-inclusive (Bruttopreise) as is standard in Switzerland.
const _swissFareConfig = FareConfig(
  isTaxInclusive: true,
  currency: 'CHF',
  roundingRule: RoundingRule(rule: 'round', unit: 'five_percent'),
  taxRates: [
    // Food: 8.1% dine-in, 2.6% takeaway (the core Swiss restaurant rule)
    TaxRateConfig(
      name: 'food',
      rate: 8.1,
      dineInRate: '8.1',
      takeawayRate: '2.6',
    ),
    // Beverages (non-alcoholic): 8.1% always
    TaxRateConfig(
      name: 'beverage',
      rate: 8.1,
      dineInRate: '8.1',
      takeawayRate: '8.1',
    ),
    // Alcohol: 8.1% always (never reduced)
    TaxRateConfig(
      name: 'alcohol',
      rate: 8.1,
      dineInRate: '8.1',
      takeawayRate: '8.1',
    ),
    // Standard fallback: 8.1%
    TaxRateConfig(
      name: 'standard',
      rate: 8.1,
      dineInRate: '8.1',
      takeawayRate: '8.1',
    ),
    // Accommodation: 3.8%
    TaxRateConfig(name: 'accommodation', rate: 3.8),
  ],
);

/// Convert [OrderType] enum to the string key expected by [FareEngine].
String _orderTypeKey(OrderType type) {
  switch (type) {
    case OrderType.takeaway:
    case OrderType.delivery:
      return 'takeaway';
    case OrderType.dineIn:
    case OrderType.online:
      return 'dine_in';
  }
}

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

/// Provides a singleton [OrderRepositoryImpl] backed by the app database.
final orderRepositoryProvider = Provider<OrderRepositoryImpl>((ref) {
  final db = ref.watch(databaseProvider);
  return OrderRepositoryImpl(db);
});

// ---------------------------------------------------------------------------
// Current ticket (the order being built)
// ---------------------------------------------------------------------------

/// The active ticket the cashier is currently working on.
///
/// `null` means no order is in progress. Use [CurrentTicketNotifier] methods
/// to create a new order, add / remove items, and persist changes.
final currentTicketProvider =
    StateNotifierProvider<CurrentTicketNotifier, TicketEntity?>((ref) {
  return CurrentTicketNotifier(ref);
});

class CurrentTicketNotifier extends StateNotifier<TicketEntity?> {
  final Ref _ref;

  CurrentTicketNotifier(this._ref) : super(null);

  /// Start a new draft ticket.
  ///
  /// Fetches the next order number, creates the entity in memory, and
  /// sets it as the current state. The ticket is **not** persisted until
  /// [saveCurrentTicket] is called or the first item is added.
  Future<void> createNewTicket({
    OrderType orderType = OrderType.dineIn,
    String? tableId,
    String? waiterId,
    String? customerName,
    int guestCount = 1,
    required String deviceId,
  }) async {
    final repo = _ref.read(orderRepositoryProvider);
    final tenantId = _ref.read(tenantIdProvider);
    final nextNumber = await repo.getNextOrderNumber(tenantId);

    state = TicketEntity(
      id: IdGenerator.generateId(),
      tenantId: tenantId,
      orderNumber: IdGenerator.generateOrderNumber(nextNumber),
      orderType: orderType,
      tableId: tableId,
      waiterId: waiterId,
      customerName: customerName,
      guestCount: guestCount,
      status: TicketStatus.draft,
      channel: OrderChannel.pos,
      openedAt: DateTime.now(),
      deviceId: deviceId,
    );
  }

  /// Add a product to the current ticket as a new order item.
  ///
  /// [selectedModifiers] contains any modifier entities applied to this item
  /// (already resolved from the modifier selection UI). The item subtotal is
  /// calculated from the product price, quantity, and modifier deltas.
  /// Tax is computed tax-inclusive using Swiss MWST rates.
  /// Resolve the best Gang ID for a product.
  ///
  /// Resolution order:
  ///   1. Explicitly passed [gangId] (waiter override)
  ///   2. Product-level [product.defaultGangId]
  ///   3. Category-level default (looked up from gang templates map)
  ///   4. null (no Gang assigned)
  String? resolveGang(ProductEntity product, {String? gangId}) {
    if (gangId != null) return gangId;
    if (product.defaultGangId != null) return product.defaultGangId;
    // Category-level fallback is applied by the UI before calling addItem,
    // or can be supplied explicitly. No further resolution needed here.
    return null;
  }

  void addItem(
    ProductEntity product, {
    double quantity = 1,
    List<OrderItemModifierEntity> selectedModifiers = const [],
    String? notes,
    int course = 1,
    /// Gang to assign to this item. If null, resolves from product default.
    String? gangId,
    /// Category-level default Gang (fallback when product has no default).
    String? categoryGangId,
  }) {
    if (state == null) return;

    // Resolve Gang: explicit > product default > category default
    final resolvedGangId =
        gangId ?? product.defaultGangId ?? categoryGangId;

    final modifierTotal =
        selectedModifiers.fold<int>(0, (s, m) => s + m.priceDelta);
    final subtotal = ((product.price + modifierTotal) * quantity).round();

    final itemId = IdGenerator.generateId();

    // Re-key modifier entities to reference this order item.
    final modifiers = selectedModifiers.map((m) {
      return m.copyWith(orderItemId: itemId);
    }).toList();

    // Compute Swiss MWST for this item based on current order type.
    // Tax is extracted from the inclusive gross price.
    final taxAmount = _extractItemTax(
      grossPrice: subtotal,
      taxGroup: product.taxGroup,
      orderType: state!.orderType,
    );

    final item = OrderItemEntity(
      id: itemId,
      tenantId: state!.tenantId,
      ticketId: state!.id,
      productId: product.id,
      productName: product.name,
      quantity: quantity,
      unitPrice: product.price,
      subtotal: subtotal,
      taxAmount: taxAmount,
      notes: notes,
      course: course,
      gangId: resolvedGangId,
      modifiers: modifiers,
      taxGroup: product.taxGroup,
    );

    state = state!.addItem(item);
  }

  /// Override the Gang assignment for an existing order item.
  ///
  /// Used by the waiter to change a Gang after the item was added.
  void updateItemGang(String itemId, String? gangId) {
    if (state == null) return;
    final updatedItems = state!.items.map((item) {
      if (item.id != itemId) return item;
      return item.copyWith(gangId: () => gangId);
    }).toList();
    state = state!.copyWith(items: updatedItems);
  }

  /// Extract the MWST amount from a tax-inclusive gross price.
  ///
  /// Formula: MwSt = gross × rate / (100 + rate)
  static int _extractItemTax({
    required int grossPrice,
    required String taxGroup,
    required OrderType orderType,
  }) {
    final rateConfig = _swissFareConfig.findTaxRate(taxGroup) ??
        const TaxRateConfig(name: 'standard', rate: 8.1);
    final rate = rateConfig.effectiveRate(_orderTypeKey(orderType));
    if (rate <= 0) return 0;
    // Gross-inclusive extraction: MwSt = gross × rate / (100 + rate)
    return (grossPrice * rate / (100 + rate)).round();
  }

  /// Remove an item from the current ticket by [itemId].
  void removeItem(String itemId) {
    if (state == null) return;
    state = state!.removeItem(itemId);
  }

  /// Update the quantity of an existing item and recalculate totals.
  void updateItemQuantity(String itemId, double newQty) {
    if (state == null) return;

    final updatedItems = state!.items.map((item) {
      if (item.id != itemId) return item;
      final modifierTotal =
          item.modifiers.fold<int>(0, (s, m) => s + m.priceDelta);
      final newSubtotal = ((item.unitPrice + modifierTotal) * newQty).round();
      return item.copyWith(quantity: newQty, subtotal: newSubtotal);
    }).toList();

    state = state!.copyWith(items: updatedItems).calculateTotals();
  }

  /// Persist the current ticket to the database. Called when the user
  /// confirms or sends the order.
  Future<TicketEntity?> saveCurrentTicket() async {
    if (state == null) return null;

    final repo = _ref.read(orderRepositoryProvider);

    // If ticket is still a draft (never persisted), create it
    if (state!.status == TicketStatus.draft) {
      final saved = await repo.createTicket(
        state!.copyWith(status: TicketStatus.open),
      );
      state = saved;
      return saved;
    }

    // If already persisted, just return current state
    return state;
  }

  /// Mark all un-sent items as "sent" and persist to the database.
  ///
  /// Also creates a [KitchenTicket] row (with items) so the KDS screen
  /// picks up the order automatically via its reactive stream.
  Future<void> sendToKitchen() async {
    if (state == null) return;

    final repo = _ref.read(orderRepositoryProvider);
    final kitchenRepo = _ref.read(kitchenRepositoryProvider);
    final currentUser = _ref.read(currentUserProvider);

    // Persist ticket first if it is still a local draft.
    if (state!.status == TicketStatus.draft) {
      final saved = await repo.createTicket(
        state!.copyWith(status: TicketStatus.open),
      );
      state = saved;
    }

    // Collect items that haven't been sent to kitchen yet.
    final unsentItems =
        state!.items.where((item) => !item.sentToKitchen).toList();

    // Mark un-sent items as "sent".
    for (final item in unsentItems) {
      await repo.updateItemStatus(item.id, OrderItemStatus.sent);
    }

    // Update ticket status.
    await repo.updateTicketStatus(state!.id, TicketStatus.sent);

    // Create KDS kitchen ticket for the unsent items.
    if (unsentItems.isNotEmpty) {
      final kitchenTicket = await kitchenRepo.createTicketFromOrder(
        ticket: state!,
        items: unsentItems,
        waiterName: currentUser?.name,
      );

      // Printer fallback — fine-dining must always have a physical paper trail
      // at the pass, even when the KDS tablet is showing the ticket. If no
      // printer is configured the call fails silently (use case returns false).
      if (kitchenTicket != null) {
        unawaited(_printKitchenTicket(kitchenTicket, state!.orderType));
      }
    }

    // Refresh state from DB.
    state = await repo.getTicketById(state!.id);
  }

  /// Best-effort print of a kitchen ticket. Never throws — kitchen flow
  /// continues even when a printer is unplugged or misconfigured.
  Future<void> _printKitchenTicket(
    KitchenTicketEntity kitchenTicket,
    OrderType orderType,
  ) async {
    try {
      final useCase = _ref.read(printKitchenTicketUseCaseProvider);
      final data = KitchenTicketData(
        tableNo: kitchenTicket.tableName ?? _orderTypeLabel(orderType),
        orderNo: kitchenTicket.orderNumber,
        waiterName: kitchenTicket.waiterName,
        printerGroup: 'Kueche',
        dateTime: kitchenTicket.sentAt,
        items: kitchenTicket.items
            .map((i) => KitchenItem(
                  name: i.productName,
                  quantity: i.quantity,
                  modifiers: i.modifiersText
                          ?.split(',')
                          .map((s) => s.trim())
                          .where((s) => s.isNotEmpty)
                          .toList() ??
                      const [],
                  notes: i.notes,
                ))
            .toList(),
      );
      await useCase(data);
    } catch (_) {
      // Printer unavailable — KDS still has the ticket on screen.
    }
  }

  String _orderTypeLabel(OrderType orderType) {
    switch (orderType) {
      case OrderType.takeaway:
        return 'Takeaway';
      case OrderType.delivery:
        return 'Delivery';
      case OrderType.online:
        return 'Online';
      case OrderType.dineIn:
        return 'Dine-in';
    }
  }

  /// Load an existing ticket from the database as the current ticket.
  Future<void> loadTicket(String ticketId) async {
    final repo = _ref.read(orderRepositoryProvider);
    state = await repo.getTicketById(ticketId);
  }

  /// Update the order type (dine-in, takeaway, delivery) and recalculate
  /// Swiss MWST for all existing items.
  ///
  /// Switching dine-in ↔ takeaway changes food tax from 8.1% to 2.6%.
  void updateOrderType(OrderType orderType) {
    if (state == null) return;

    // Recalculate tax for every item using the new order type.
    final recalculated = state!.items.map((item) {
      final newTax = _extractItemTax(
        grossPrice: item.subtotal,
        taxGroup: item.taxGroup,
        orderType: orderType,
      );
      return item.copyWith(taxAmount: newTax);
    }).toList();

    state = state!
        .copyWith(orderType: orderType, items: recalculated)
        .calculateTotals();
  }

  // =========================================================================
  // Discount
  // =========================================================================

  /// Apply a discount to the current ticket and persist to DB.
  ///
  /// [discountType]: percentage or fixed.
  /// [discountValue]: percent (0-100) or amount in cents.
  /// [approvedBy]: the manager/admin who authorised the discount.
  ///               Pass `null` for manager/admin applying their own discount.
  /// [requestedBy]: the staff member who initiated the request.
  Future<void> applyDiscount({
    required DiscountType discountType,
    required int discountValue,
    required String reason,
    required UserEntity requestedBy,
    UserEntity? approvedBy,
  }) async {
    if (state == null) return;

    // Persist ticket first if still a draft.
    if (state!.status == TicketStatus.draft) {
      await saveCurrentTicket();
    }

    final repo = _ref.read(orderRepositoryProvider);

    // Update in-memory state immediately for responsive UI.
    state = state!.copyWith(
      discountType: discountType,
      discountValue: discountValue,
    ).calculateTotals();

    // Persist discount to DB and recalculate totals.
    await repo.updateTicketDiscount(
      state!.id,
      discountType: discountType,
      discountValue: discountValue,
    );

    // Reload state from DB with updated totals.
    state = await repo.getTicketById(state!.id);

    // Log override if an approver was involved.
    if (approvedBy != null) {
      await _ref.read(managerOverrideProvider.notifier).logOverride(
            requestedByUser: requestedBy,
            approver: approvedBy,
            action: discountType == DiscountType.percentage
                ? OverrideAction.discountPercent
                : OverrideAction.discountFixed,
            entityType: 'ticket',
            entityId: state!.id,
            reason: reason,
            metadata: {
              'discountType': discountType.name,
              'discountValue': discountValue,
              'ticketTotal': state!.total,
            },
          );
    }
  }

  /// Remove any discount from the current ticket.
  Future<void> removeDiscount() async {
    if (state == null) return;
    if (state!.discountType == DiscountType.none) return;

    state = state!.copyWith(
      discountType: DiscountType.none,
      discountValue: 0,
    ).calculateTotals();

    final repo = _ref.read(orderRepositoryProvider);
    await repo.removeTicketDiscount(state!.id);
    state = await repo.getTicketById(state!.id);
  }

  /// Clear the current ticket (e.g. after payment).
  void clear() {
    state = null;
  }
}

// ---------------------------------------------------------------------------
// Open tickets list
// ---------------------------------------------------------------------------

/// All open (non-completed, non-cancelled) tickets for the current tenant.
final openTicketsProvider = FutureProvider<List<TicketEntity>>((ref) async {
  final repo = ref.watch(orderRepositoryProvider);
  final tenantId = ref.watch(tenantIdProvider);
  return repo.getOpenTickets(tenantId);
});

/// Fetch any ticket by ID (open, completed, or voided).
///
/// Used by void / refund screens which may need to access completed tickets.
final ticketByIdProvider =
    FutureProvider.family<TicketEntity?, String>((ref, ticketId) async {
  final repo = ref.watch(orderRepositoryProvider);
  return repo.getTicketById(ticketId);
});

// ---------------------------------------------------------------------------
// Swiss MWST fare breakdown for the current ticket
// ---------------------------------------------------------------------------

/// Computes the complete Swiss VAT fare breakdown for the active ticket.
///
/// Recalculates automatically whenever the ticket changes (items added /
/// removed, order type toggled). Consumed by the POS order panel to display
/// the per-rate MWST breakdown.
///
/// Returns `null` when no ticket is active or when the ticket is empty.
final swissTicketFareProvider = Provider<FareBreakdown?>((ref) {
  final ticket = ref.watch(currentTicketProvider);
  if (ticket == null || ticket.items.isEmpty) return null;

  final orderTypeStr = _orderTypeKey(ticket.orderType);

  final lineItems = ticket.items.map((item) {
    final modifierTotal =
        item.modifiers.fold<int>(0, (s, m) => s + m.priceDelta);
    return FareLineItem(
      productId: item.productId,
      productName: item.productName,
      quantity: item.quantity.ceil(),
      unitPrice: item.unitPrice,
      modifierTotal: modifierTotal,
      taxGroup: item.taxGroup,
      isTaxFree: item.isTaxFree,
      isTaxInclusive: true,
      specialDiscountAmount: item.specialDiscountAmount,
      isWeightBased: item.isWeightBased,
      weight: item.weight != null ? (item.weight! * 1000).round() : 0,
    );
  }).toList();

  return FareEngine.calculateFare(
    items: lineItems,
    config: _swissFareConfig,
    orderType: orderTypeStr,
  );
});
