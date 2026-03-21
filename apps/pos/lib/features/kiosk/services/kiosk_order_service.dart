/// Kiosk-specific order service.
///
/// Converts an in-memory [KioskCartItem] list into a persisted
/// [TicketEntity] tagged [OrderChannel.kiosk], dispatches it to the
/// kitchen, and returns the human-readable order number.
///
/// Swiss MWST rules (tax-inclusive prices):
///   food        → 8.1 % dine-in   / 2.6 % takeaway
///   beverage / alcohol / standard  → 8.1 % always
///   accommodation → 3.8 % always
///
/// 5-Rappen rounding is applied to the final CHF cash total when the
/// customer pays with cash (card totals are exact).
library;

import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/kitchen/data/repositories/kitchen_repository_impl.dart';
import 'package:gastrocore_pos/features/kiosk/domain/kiosk_cart_item.dart';
import 'package:gastrocore_pos/features/orders/data/repositories/order_repository_impl.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/order_item_entity.dart';
import 'package:gastrocore_pos/core/utils/money.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';

// ---------------------------------------------------------------------------
// KioskOrderService
// ---------------------------------------------------------------------------

/// Service that turns a kiosk cart into a persisted kitchen order.
class KioskOrderService {
  final OrderRepositoryImpl _orderRepo;
  final KitchenRepositoryImpl _kitchenRepo;

  KioskOrderService({
    required OrderRepositoryImpl orderRepo,
    required KitchenRepositoryImpl kitchenRepo,
  })  : _orderRepo = orderRepo,
        _kitchenRepo = kitchenRepo;

  // =========================================================================
  // Order submission
  // =========================================================================

  /// Convert the cart into a ticket, send it to the kitchen, and return the
  /// order number (e.g. "0042").
  ///
  /// [orderType] should be [OrderType.dineIn] or [OrderType.takeaway];
  /// this drives the Swiss VAT rate applied to food items.
  Future<String> submitOrder({
    required String tenantId,
    required String deviceId,
    required List<KioskCartItem> items,
    required OrderType orderType,
  }) async {
    assert(items.isNotEmpty, 'Cannot submit an empty cart');

    final nextNumber = await _orderRepo.getNextOrderNumber(tenantId);
    final orderNumber = IdGenerator.generateOrderNumber(nextNumber);
    final ticketId = IdGenerator.generateId();
    final now = DateTime.now();

    // Build order-item entities from the cart.
    final orderItems = items.map((cartItem) {
      final itemId = IdGenerator.generateId();
      final reKeyed = cartItem.modifiers
          .map((m) => m.copyWith(orderItemId: itemId))
          .toList();

      final taxAmount = _extractTax(
        grossPrice: cartItem.subtotal,
        taxGroup: cartItem.product.taxGroup,
        orderType: orderType,
      );

      return OrderItemEntity(
        id: itemId,
        tenantId: tenantId,
        ticketId: ticketId,
        productId: cartItem.product.id,
        productName: cartItem.product.name,
        quantity: cartItem.quantity.toDouble(),
        unitPrice: cartItem.unitPrice,
        subtotal: cartItem.subtotal,
        taxAmount: taxAmount,
        modifiers: reKeyed,
        taxGroup: cartItem.product.taxGroup,
        notes: cartItem.notes,
      );
    }).toList();

    final subtotal =
        orderItems.fold<int>(0, (sum, i) => sum + i.subtotal);
    final taxAmount =
        orderItems.fold<int>(0, (sum, i) => sum + i.taxAmount);

    final ticket = TicketEntity(
      id: ticketId,
      tenantId: tenantId,
      orderNumber: orderNumber,
      orderType: orderType,
      status: TicketStatus.open,
      channel: OrderChannel.kiosk,
      openedAt: now,
      deviceId: deviceId,
      items: orderItems,
      subtotal: subtotal,
      taxAmount: taxAmount,
      total: subtotal,
      receivableTotal: subtotal,
      unpaidTotal: subtotal,
    );

    // Persist the ticket (createTicket already inserts all items).
    await _orderRepo.createTicket(ticket);

    // Mark all items as sent and dispatch kitchen ticket.
    for (final item in orderItems) {
      await _orderRepo.updateItemStatus(item.id, OrderItemStatus.sent);
    }
    await _orderRepo.updateTicketStatus(ticketId, TicketStatus.sent);
    await _kitchenRepo.createTicketFromOrder(
      ticket: ticket,
      items: orderItems,
      waiterName: 'Kiosk',
    );

    return orderNumber;
  }

  // =========================================================================
  // Rounding
  // =========================================================================

  /// Round [cents] to the nearest 5 Rappen for Swiss cash payments.
  ///
  /// Delegates to [Money.roundTo5Rappen] for consistency with the rest of
  /// the codebase. Examples:
  ///   1231 → 1230,  1233 → 1235,  1235 → 1235
  static int roundToFiveRappen(int cents) =>
      Money(cents).roundTo5Rappen().cents;

  // =========================================================================
  // Swiss VAT extraction (tax-inclusive gross prices)
  // =========================================================================

  static int _extractTax({
    required int grossPrice,
    required String taxGroup,
    required OrderType orderType,
  }) {
    final rate = _taxRate(taxGroup, orderType);
    if (rate <= 0) return 0;
    return (grossPrice * rate / (100 + rate)).round();
  }

  /// Returns the applicable MWST rate (%) for [taxGroup] × [orderType].
  static double taxRate(String taxGroup, OrderType orderType) =>
      _taxRate(taxGroup, orderType);

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
