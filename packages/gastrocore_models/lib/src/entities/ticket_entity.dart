/// Ticket (order) entity — the central domain object of the POS system.
library;

import 'order_item_entity.dart';

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
  draft,
  open,
  sent,
  inProgress,
  ready,
  served,
  billRequested,
  completed,
  cancelled,
  voided,
}

/// The sales channel that created this order.
enum OrderChannel {
  pos,
  waiter,
  qr,
  kiosk,
  web,
}

/// Type of discount applied to the ticket.
enum DiscountType {
  none,
  fixed,
  percentage,
}

// ---------------------------------------------------------------------------
// TicketEntity
// ---------------------------------------------------------------------------

/// Immutable representation of a restaurant order (ticket).
class TicketEntity {
  final String id;
  final String tenantId;
  final String orderNumber;
  final OrderType orderType;
  final String? tableId;
  final String? waiterId;
  final String? customerName;
  final int guestCount;
  final TicketStatus status;
  final OrderChannel channel;
  final List<OrderItemEntity> items;
  final int subtotal;
  final int taxAmount;
  final int discountAmount;
  final DiscountType discountType;
  final int discountValue;
  final int total;
  final int dishesOriginTotal;
  final int dishesTotalPreTax;
  final int dishesTaxTotal;
  final int serviceFeeAmount;
  final int packageFeeAmount;
  final int deliveryFeeAmount;
  final int temporaryChargeTotal;
  final int specialDiscountTotal;
  final int couponTotal;
  final int roundDownTotal;
  final int receivableTotal;
  final int unpaidTotal;
  final int refundTotal;
  final String? pickupCode;
  final String? cancelReason;
  final String? cashierName;
  final String? notes;
  final DateTime openedAt;
  final DateTime? closedAt;
  final String deviceId;

  const TicketEntity({
    required this.id,
    required this.tenantId,
    required this.orderNumber,
    required this.orderType,
    this.tableId,
    this.waiterId,
    this.customerName,
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

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  int get itemCount =>
      items.fold<int>(0, (sum, item) => sum + item.quantity.ceil());

  bool get isOpen =>
      status == TicketStatus.draft ||
      status == TicketStatus.open ||
      status == TicketStatus.sent ||
      status == TicketStatus.inProgress;

  bool get isPaid => status == TicketStatus.completed;

  TicketEntity addItem(OrderItemEntity item) {
    return _withRecalculatedTotals([...items, item]);
  }

  TicketEntity removeItem(String itemId) {
    return _withRecalculatedTotals(
        items.where((i) => i.id != itemId).toList());
  }

  TicketEntity calculateTotals() {
    return _withRecalculatedTotals(items);
  }

  TicketEntity _withRecalculatedTotals(List<OrderItemEntity> newItems) {
    final newSubtotal =
        newItems.fold<int>(0, (sum, item) => sum + item.subtotal);
    final newTax = newItems.fold<int>(0, (sum, item) => sum + item.taxAmount);

    int newDiscountAmount;
    switch (discountType) {
      case DiscountType.none:
        newDiscountAmount = 0;
      case DiscountType.fixed:
        newDiscountAmount = discountValue;
      case DiscountType.percentage:
        newDiscountAmount = (newSubtotal * discountValue / 100).round();
    }

    final newTotal = newSubtotal - newDiscountAmount;

    return copyWith(
      items: newItems,
      subtotal: newSubtotal,
      taxAmount: newTax,
      discountAmount: newDiscountAmount,
      total: newTotal < 0 ? 0 : newTotal,
    );
  }

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  factory TicketEntity.fromJson(Map<String, dynamic> json) => TicketEntity(
        id: json['id'] as String,
        tenantId: json['tenant_id'] as String,
        orderNumber: json['order_number'] as String,
        orderType: OrderType.values.firstWhere(
          (e) => e.name == (json['order_type'] as String?)?.replaceAll('_', ''),
          orElse: () => OrderType.dineIn,
        ),
        tableId: json['table_id'] as String?,
        waiterId: json['waiter_id'] as String?,
        customerName: json['customer_name'] as String?,
        guestCount: json['guest_count'] as int? ?? 1,
        status: TicketStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => TicketStatus.draft,
        ),
        channel: OrderChannel.values.firstWhere(
          (e) => e.name == json['channel'],
          orElse: () => OrderChannel.pos,
        ),
        items: (json['items'] as List<dynamic>? ?? [])
            .map((i) => OrderItemEntity.fromJson(i as Map<String, dynamic>))
            .toList(),
        subtotal: (json['subtotal'] as num?)?.toInt() ?? 0,
        taxAmount: (json['tax_amount'] as num?)?.toInt() ?? 0,
        discountAmount: (json['discount_amount'] as num?)?.toInt() ?? 0,
        discountType: DiscountType.values.firstWhere(
          (e) => e.name == json['discount_type'],
          orElse: () => DiscountType.none,
        ),
        discountValue: (json['discount_value'] as num?)?.toInt() ?? 0,
        total: (json['total'] as num?)?.toInt() ?? 0,
        dishesOriginTotal: (json['dishes_origin_total'] as num?)?.toInt() ?? 0,
        dishesTotalPreTax: (json['dishes_total_pre_tax'] as num?)?.toInt() ?? 0,
        dishesTaxTotal: (json['dishes_tax_total'] as num?)?.toInt() ?? 0,
        serviceFeeAmount: (json['service_fee_amount'] as num?)?.toInt() ?? 0,
        packageFeeAmount: (json['package_fee_amount'] as num?)?.toInt() ?? 0,
        deliveryFeeAmount: (json['delivery_fee_amount'] as num?)?.toInt() ?? 0,
        temporaryChargeTotal:
            (json['temporary_charge_total'] as num?)?.toInt() ?? 0,
        specialDiscountTotal:
            (json['special_discount_total'] as num?)?.toInt() ?? 0,
        couponTotal: (json['coupon_total'] as num?)?.toInt() ?? 0,
        roundDownTotal: (json['round_down_total'] as num?)?.toInt() ?? 0,
        receivableTotal: (json['receivable_total'] as num?)?.toInt() ?? 0,
        unpaidTotal: (json['unpaid_total'] as num?)?.toInt() ?? 0,
        refundTotal: (json['refund_total'] as num?)?.toInt() ?? 0,
        pickupCode: json['pickup_code'] as String?,
        cancelReason: json['cancel_reason'] as String?,
        cashierName: json['cashier_name'] as String?,
        notes: json['notes'] as String?,
        openedAt: DateTime.parse(json['opened_at'] as String),
        closedAt: json['closed_at'] != null
            ? DateTime.parse(json['closed_at'] as String)
            : null,
        deviceId: json['device_id'] as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenant_id': tenantId,
        'order_number': orderNumber,
        'order_type': orderType.name,
        if (tableId != null) 'table_id': tableId,
        if (waiterId != null) 'waiter_id': waiterId,
        if (customerName != null) 'customer_name': customerName,
        'guest_count': guestCount,
        'status': status.name,
        'channel': channel.name,
        'items': items.map((i) => i.toJson()).toList(),
        'subtotal': subtotal,
        'tax_amount': taxAmount,
        'discount_amount': discountAmount,
        'discount_type': discountType.name,
        'discount_value': discountValue,
        'total': total,
        'dishes_origin_total': dishesOriginTotal,
        'dishes_total_pre_tax': dishesTotalPreTax,
        'dishes_tax_total': dishesTaxTotal,
        'service_fee_amount': serviceFeeAmount,
        'package_fee_amount': packageFeeAmount,
        'delivery_fee_amount': deliveryFeeAmount,
        'temporary_charge_total': temporaryChargeTotal,
        'special_discount_total': specialDiscountTotal,
        'coupon_total': couponTotal,
        'round_down_total': roundDownTotal,
        'receivable_total': receivableTotal,
        'unpaid_total': unpaidTotal,
        'refund_total': refundTotal,
        if (pickupCode != null) 'pickup_code': pickupCode,
        if (cancelReason != null) 'cancel_reason': cancelReason,
        if (cashierName != null) 'cashier_name': cashierName,
        if (notes != null) 'notes': notes,
        'opened_at': openedAt.toIso8601String(),
        if (closedAt != null) 'closed_at': closedAt!.toIso8601String(),
        'device_id': deviceId,
      };

  // ---------------------------------------------------------------------------
  // copyWith
  // ---------------------------------------------------------------------------

  TicketEntity copyWith({
    String? id,
    String? tenantId,
    String? orderNumber,
    OrderType? orderType,
    String? Function()? tableId,
    String? Function()? waiterId,
    String? Function()? customerName,
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
          status == other.status &&
          channel == other.channel &&
          total == other.total &&
          receivableTotal == other.receivableTotal &&
          deviceId == other.deviceId;

  @override
  int get hashCode => Object.hash(
        id,
        tenantId,
        orderNumber,
        orderType,
        status,
        channel,
        total,
        receivableTotal,
        deviceId,
      );

  @override
  String toString() =>
      'TicketEntity(id: $id, order: $orderNumber, status: ${status.name}, '
      'total: $total, receivable: $receivableTotal)';
}
