/// Ticket (order) entity -- the central domain object of the POS system.
///
/// A ticket represents a single order from open to close. It aggregates
/// line items, tracks status, and computes totals. All monetary values are
/// in cents (int) to avoid floating-point rounding.
library;

import 'package:gastrocore_pos/features/orders/domain/entities/order_item_entity.dart';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// The type of service for this order.
enum OrderType {
  dineIn,
  takeaway,
  delivery,
  online,
}

/// Full lifecycle status of a ticket.
enum TicketStatus {
  /// Ticket created, items being added.
  draft,

  /// Order placed / confirmed.
  open,

  /// Sent to kitchen / bar.
  sent,

  /// At least one item is being prepared.
  inProgress,

  /// All items ready for pickup / serving.
  ready,

  /// All items served to the guest.
  served,

  /// Bill requested / payment in progress.
  billRequested,

  /// Fully paid and closed.
  completed,

  /// Cancelled before payment.
  cancelled,

  /// Voided after payment (requires manager approval).
  voided,
}

/// The sales channel that created this order.
enum OrderChannel {
  /// Created at the POS terminal.
  pos,

  /// Created by a waiter on a mobile device.
  waiter,

  /// Created via QR code self-order.
  qr,

  /// Created at a self-service kiosk.
  kiosk,

  /// Created via online ordering platform.
  web,
}

/// Type of discount applied to the ticket.
enum DiscountType {
  /// No discount.
  none,

  /// Fixed amount in cents.
  fixed,

  /// Percentage of subtotal.
  percentage,
}

// ---------------------------------------------------------------------------
// TicketEntity
// ---------------------------------------------------------------------------

/// Immutable representation of a restaurant order (ticket).
class TicketEntity {
  final String id;
  final String tenantId;

  /// Human-readable order number (e.g. "0042").
  final String orderNumber;

  final OrderType orderType;

  /// Table this order is assigned to (null for takeaway / delivery).
  final String? tableId;

  /// Waiter who opened or owns this order.
  final String? waiterId;

  /// Optional customer name for delivery / takeaway. Kept separate from
  /// [customerId] because walk-in orders may capture a name without a
  /// full CRM record.
  final String? customerName;

  /// Optional FK to `customers.id`. When non-null the ticket is linked
  /// to a loyalty account and payments can redeem puan against the
  /// balance. Null for walk-in / ad-hoc orders.
  final String? customerId;

  /// Number of guests at the table.
  final int guestCount;

  final TicketStatus status;
  final OrderChannel channel;

  /// Line items on this ticket.
  final List<OrderItemEntity> items;

  /// Sum of all line-item subtotals in cents.
  final int subtotal;

  /// Total tax amount in cents.
  final int taxAmount;

  /// Total discount amount in cents.
  final int discountAmount;

  /// The type of discount applied.
  final DiscountType discountType;

  /// The raw discount value (cents for fixed, percentage for percentage).
  final int discountValue;

  /// Grand total in cents (subtotal + tax - discount).
  final int total;

  // -------------------------------------------------------------------------
  // Expanded fare fields (OrderPin-compatible)
  // -------------------------------------------------------------------------

  /// Original dish total before any discounts.
  final int dishesOriginTotal;

  /// Dishes total before tax.
  final int dishesTotalPreTax;

  /// Total tax on dishes.
  final int dishesTaxTotal;

  /// Service fee amount in cents (tax included if applicable).
  final int serviceFeeAmount;

  /// Packaging fee in cents (takeaway/delivery).
  final int packageFeeAmount;

  /// Delivery fee in cents.
  final int deliveryFeeAmount;

  /// Ad-hoc charges added at checkout.
  final int temporaryChargeTotal;

  /// Sum of all named special discounts.
  final int specialDiscountTotal;

  /// Coupon deduction in cents.
  final int couponTotal;

  /// Rounding adjustment in cents.
  final int roundDownTotal;

  /// What the customer should pay after all adjustments.
  final int receivableTotal;

  /// Remaining unpaid balance.
  final int unpaidTotal;

  /// Total refunded amount.
  final int refundTotal;

  // -------------------------------------------------------------------------
  // Order metadata
  // -------------------------------------------------------------------------

  /// Takeaway / delivery pickup code.
  final String? pickupCode;

  /// Reason for cancellation (if cancelled).
  final String? cancelReason;

  /// Name of the cashier who processed payment.
  final String? cashierName;

  /// Free-text notes for the entire order.
  final String? notes;

  /// When the ticket was opened.
  final DateTime openedAt;

  /// When the ticket was fully paid / closed.
  final DateTime? closedAt;

  /// Device that created this ticket.
  final String deviceId;

  const TicketEntity({
    required this.id,
    required this.tenantId,
    required this.orderNumber,
    required this.orderType,
    this.tableId,
    this.waiterId,
    this.customerName,
    this.customerId,
    this.guestCount = 1,
    this.status = TicketStatus.draft,
    this.channel = OrderChannel.pos,
    this.items = const [],
    this.subtotal = 0,
    this.taxAmount = 0,
    this.discountAmount = 0,
    this.discountType = DiscountType.none,
    this.discountValue = 0,
    this.total = 0,
    this.dishesOriginTotal = 0,
    this.dishesTotalPreTax = 0,
    this.dishesTaxTotal = 0,
    this.serviceFeeAmount = 0,
    this.packageFeeAmount = 0,
    this.deliveryFeeAmount = 0,
    this.temporaryChargeTotal = 0,
    this.specialDiscountTotal = 0,
    this.couponTotal = 0,
    this.roundDownTotal = 0,
    this.receivableTotal = 0,
    this.unpaidTotal = 0,
    this.refundTotal = 0,
    this.pickupCode,
    this.cancelReason,
    this.cashierName,
    this.notes,
    required this.openedAt,
    this.closedAt,
    required this.deviceId,
  });

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  /// Total number of line items (sum of quantities).
  int get itemCount =>
      items.fold<int>(0, (sum, item) => sum + item.quantity.ceil());

  /// Whether the ticket is still accepting modifications.
  bool get isOpen =>
      status == TicketStatus.draft ||
      status == TicketStatus.open ||
      status == TicketStatus.sent ||
      status == TicketStatus.inProgress;

  /// Whether the ticket has been fully paid.
  bool get isPaid => status == TicketStatus.completed;

  /// Return a new ticket with [item] appended to the items list
  /// and totals recalculated.
  TicketEntity addItem(OrderItemEntity item) {
    final newItems = [...items, item];
    return _withRecalculatedTotals(newItems);
  }

  /// Return a new ticket with the item matching [itemId] removed
  /// and totals recalculated.
  TicketEntity removeItem(String itemId) {
    final newItems = items.where((i) => i.id != itemId).toList();
    return _withRecalculatedTotals(newItems);
  }

  /// Return a new ticket with totals recalculated from the current items.
  TicketEntity calculateTotals() {
    return _withRecalculatedTotals(items);
  }

  /// Internal: recalculate subtotal, discount, and total from [newItems].
  ///
  /// Swiss MWST standard: prices are tax-inclusive (Bruttopreise).
  /// [subtotal] is the gross sum (tax already inside). [taxAmount] is the
  /// extracted informational MwSt — it must NOT be added to the total again.
  /// Total = subtotal (gross) − discount.
  TicketEntity _withRecalculatedTotals(List<OrderItemEntity> newItems) {
    final newSubtotal =
        newItems.fold<int>(0, (sum, item) => sum + item.subtotal);
    // taxAmount is extracted from the inclusive gross — informational only.
    final newTax =
        newItems.fold<int>(0, (sum, item) => sum + item.taxAmount);

    int newDiscountAmount;
    switch (discountType) {
      case DiscountType.none:
        newDiscountAmount = 0;
      case DiscountType.fixed:
        newDiscountAmount = discountValue;
      case DiscountType.percentage:
        newDiscountAmount = (newSubtotal * discountValue / 100).round();
    }

    // Tax-inclusive: total = gross − discount (tax is already inside gross).
    final newTotal = newSubtotal - newDiscountAmount;

    return copyWith(
      items: newItems,
      subtotal: newSubtotal,
      taxAmount: newTax,
      discountAmount: newDiscountAmount,
      total: newTotal < 0 ? 0 : newTotal,
    );
  }

  /// Create a copy with selectively overridden fields.
  TicketEntity copyWith({
    String? id,
    String? tenantId,
    String? orderNumber,
    OrderType? orderType,
    String? Function()? tableId,
    String? Function()? waiterId,
    String? Function()? customerName,
    String? Function()? customerId,
    int? guestCount,
    TicketStatus? status,
    OrderChannel? channel,
    List<OrderItemEntity>? items,
    int? subtotal,
    int? taxAmount,
    int? discountAmount,
    DiscountType? discountType,
    int? discountValue,
    int? total,
    int? dishesOriginTotal,
    int? dishesTotalPreTax,
    int? dishesTaxTotal,
    int? serviceFeeAmount,
    int? packageFeeAmount,
    int? deliveryFeeAmount,
    int? temporaryChargeTotal,
    int? specialDiscountTotal,
    int? couponTotal,
    int? roundDownTotal,
    int? receivableTotal,
    int? unpaidTotal,
    int? refundTotal,
    String? Function()? pickupCode,
    String? Function()? cancelReason,
    String? Function()? cashierName,
    String? Function()? notes,
    DateTime? openedAt,
    DateTime? Function()? closedAt,
    String? deviceId,
  }) {
    return TicketEntity(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      orderNumber: orderNumber ?? this.orderNumber,
      orderType: orderType ?? this.orderType,
      tableId: tableId != null ? tableId() : this.tableId,
      waiterId: waiterId != null ? waiterId() : this.waiterId,
      customerName:
          customerName != null ? customerName() : this.customerName,
      customerId: customerId != null ? customerId() : this.customerId,
      guestCount: guestCount ?? this.guestCount,
      status: status ?? this.status,
      channel: channel ?? this.channel,
      items: items ?? this.items,
      subtotal: subtotal ?? this.subtotal,
      taxAmount: taxAmount ?? this.taxAmount,
      discountAmount: discountAmount ?? this.discountAmount,
      discountType: discountType ?? this.discountType,
      discountValue: discountValue ?? this.discountValue,
      total: total ?? this.total,
      dishesOriginTotal: dishesOriginTotal ?? this.dishesOriginTotal,
      dishesTotalPreTax: dishesTotalPreTax ?? this.dishesTotalPreTax,
      dishesTaxTotal: dishesTaxTotal ?? this.dishesTaxTotal,
      serviceFeeAmount: serviceFeeAmount ?? this.serviceFeeAmount,
      packageFeeAmount: packageFeeAmount ?? this.packageFeeAmount,
      deliveryFeeAmount: deliveryFeeAmount ?? this.deliveryFeeAmount,
      temporaryChargeTotal: temporaryChargeTotal ?? this.temporaryChargeTotal,
      specialDiscountTotal: specialDiscountTotal ?? this.specialDiscountTotal,
      couponTotal: couponTotal ?? this.couponTotal,
      roundDownTotal: roundDownTotal ?? this.roundDownTotal,
      receivableTotal: receivableTotal ?? this.receivableTotal,
      unpaidTotal: unpaidTotal ?? this.unpaidTotal,
      refundTotal: refundTotal ?? this.refundTotal,
      pickupCode: pickupCode != null ? pickupCode() : this.pickupCode,
      cancelReason:
          cancelReason != null ? cancelReason() : this.cancelReason,
      cashierName: cashierName != null ? cashierName() : this.cashierName,
      notes: notes != null ? notes() : this.notes,
      openedAt: openedAt ?? this.openedAt,
      closedAt: closedAt != null ? closedAt() : this.closedAt,
      deviceId: deviceId ?? this.deviceId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TicketEntity &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          tenantId == other.tenantId &&
          orderNumber == other.orderNumber &&
          orderType == other.orderType &&
          tableId == other.tableId &&
          waiterId == other.waiterId &&
          customerName == other.customerName &&
          customerId == other.customerId &&
          guestCount == other.guestCount &&
          status == other.status &&
          channel == other.channel &&
          subtotal == other.subtotal &&
          taxAmount == other.taxAmount &&
          discountAmount == other.discountAmount &&
          discountType == other.discountType &&
          discountValue == other.discountValue &&
          total == other.total &&
          dishesOriginTotal == other.dishesOriginTotal &&
          dishesTotalPreTax == other.dishesTotalPreTax &&
          dishesTaxTotal == other.dishesTaxTotal &&
          serviceFeeAmount == other.serviceFeeAmount &&
          packageFeeAmount == other.packageFeeAmount &&
          deliveryFeeAmount == other.deliveryFeeAmount &&
          temporaryChargeTotal == other.temporaryChargeTotal &&
          specialDiscountTotal == other.specialDiscountTotal &&
          couponTotal == other.couponTotal &&
          roundDownTotal == other.roundDownTotal &&
          receivableTotal == other.receivableTotal &&
          unpaidTotal == other.unpaidTotal &&
          refundTotal == other.refundTotal &&
          pickupCode == other.pickupCode &&
          cancelReason == other.cancelReason &&
          cashierName == other.cashierName &&
          notes == other.notes &&
          openedAt == other.openedAt &&
          closedAt == other.closedAt &&
          deviceId == other.deviceId;

  @override
  int get hashCode => Object.hash(
        id,
        tenantId,
        orderNumber,
        orderType,
        tableId,
        waiterId,
        customerName,
        guestCount,
        status,
        channel,
      );

  @override
  String toString() =>
      'TicketEntity(id: $id, order: $orderNumber, status: ${status.name}, '
      'total: $total, receivable: $receivableTotal)';
}
