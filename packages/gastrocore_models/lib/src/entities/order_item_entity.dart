/// Order line item and order-item-modifier entities.
library;

// ---------------------------------------------------------------------------
// OrderItemStatus enum
// ---------------------------------------------------------------------------

/// Lifecycle status of a single order line item.
enum OrderItemStatus {
  ordered,
  sent,
  preparing,
  ready,
  served,
  voidStatus,
}

// ---------------------------------------------------------------------------
// OrderItemModifierEntity
// ---------------------------------------------------------------------------

/// A modifier applied to a specific order item (snapshot at order time).
class OrderItemModifierEntity {
  final String id;
  final String orderItemId;
  final String modifierId;
  final String modifierName;

  /// Price adjustment in cents.
  final int priceDelta;

  const OrderItemModifierEntity({
    required this.id,
    required this.orderItemId,
    required this.modifierId,
    required this.modifierName,
    required this.priceDelta,
  });

  factory OrderItemModifierEntity.fromJson(Map<String, dynamic> json) =>
      OrderItemModifierEntity(
        id: json['id'] as String,
        orderItemId: json['order_item_id'] as String? ?? '',
        modifierId: json['modifier_id'] as String,
        modifierName: json['modifier_name'] as String,
        priceDelta: (json['price_delta'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'order_item_id': orderItemId,
        'modifier_id': modifierId,
        'modifier_name': modifierName,
        'price_delta': priceDelta,
      };

  OrderItemModifierEntity copyWith({
    String? id,
    String? orderItemId,
    String? modifierId,
    String? modifierName,
    int? priceDelta,
  }) {
    return OrderItemModifierEntity(
      id: id ?? this.id,
      orderItemId: orderItemId ?? this.orderItemId,
      modifierId: modifierId ?? this.modifierId,
      modifierName: modifierName ?? this.modifierName,
      priceDelta: priceDelta ?? this.priceDelta,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrderItemModifierEntity &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          orderItemId == other.orderItemId &&
          modifierId == other.modifierId &&
          modifierName == other.modifierName &&
          priceDelta == other.priceDelta;

  @override
  int get hashCode =>
      Object.hash(id, orderItemId, modifierId, modifierName, priceDelta);

  @override
  String toString() =>
      'OrderItemModifierEntity(id: $id, name: $modifierName, delta: $priceDelta)';
}

// ---------------------------------------------------------------------------
// OrderItemEntity
// ---------------------------------------------------------------------------

/// A single line item on a ticket.
class OrderItemEntity {
  final String id;
  final String tenantId;
  final String ticketId;
  final String productId;

  /// Product name captured at order time (snapshot).
  final String productName;

  /// Quantity (double to support weight-based items).
  final double quantity;

  /// Unit price in cents at the time of ordering.
  final int unitPrice;

  /// Line subtotal in cents (unitPrice * quantity + modifier deltas).
  final int subtotal;

  /// Tax amount in cents for this line item.
  final int taxAmount;

  /// Discount amount in cents applied to this line item.
  final int discountAmount;

  final OrderItemStatus status;
  final bool sentToKitchen;
  final String? notes;

  /// Course number for multi-course service (1 = first course).
  final int course;

  final List<OrderItemModifierEntity> modifiers;
  final bool isTaxFree;
  final bool isOpenPrice;
  final bool isWeightBased;
  final double? weight;
  final String? weightUnit;
  final int specialDiscountAmount;

  /// Tax group name (snapshot from product at order time).
  final String taxGroup;

  const OrderItemEntity({
    required this.id,
    required this.tenantId,
    required this.ticketId,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.subtotal,
    this.taxAmount = 0,
    this.discountAmount = 0,
    this.status = OrderItemStatus.ordered,
    this.sentToKitchen = false,
    this.notes,
    this.course = 1,
    this.modifiers = const [],
    this.isTaxFree = false,
    this.isOpenPrice = false,
    this.isWeightBased = false,
    this.weight,
    this.weightUnit,
    this.specialDiscountAmount = 0,
    this.taxGroup = 'food',
  });

  /// Recalculate the subtotal from unit price, quantity, and modifiers.
  int calculateSubtotal() {
    final modifierTotal =
        modifiers.fold<int>(0, (sum, m) => sum + m.priceDelta);
    return ((unitPrice + modifierTotal) * quantity).round();
  }

  factory OrderItemEntity.fromJson(Map<String, dynamic> json) =>
      OrderItemEntity(
        id: json['id'] as String,
        tenantId: json['tenant_id'] as String,
        ticketId: json['ticket_id'] as String,
        productId: json['product_id'] as String,
        productName: json['product_name'] as String,
        quantity: (json['quantity'] as num).toDouble(),
        unitPrice: (json['unit_price'] as num).toInt(),
        subtotal: (json['subtotal'] as num).toInt(),
        taxAmount: (json['tax_amount'] as num?)?.toInt() ?? 0,
        discountAmount: (json['discount_amount'] as num?)?.toInt() ?? 0,
        status: OrderItemStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => OrderItemStatus.ordered,
        ),
        sentToKitchen: json['sent_to_kitchen'] as bool? ?? false,
        notes: json['notes'] as String?,
        course: json['course'] as int? ?? 1,
        modifiers: (json['modifiers'] as List<dynamic>? ?? [])
            .map((m) =>
                OrderItemModifierEntity.fromJson(m as Map<String, dynamic>))
            .toList(),
        isTaxFree: json['is_tax_free'] as bool? ?? false,
        isOpenPrice: json['is_open_price'] as bool? ?? false,
        isWeightBased: json['is_weight_based'] as bool? ?? false,
        weight: (json['weight'] as num?)?.toDouble(),
        weightUnit: json['weight_unit'] as String?,
        specialDiscountAmount:
            (json['special_discount_amount'] as num?)?.toInt() ?? 0,
        taxGroup: json['tax_group'] as String? ?? 'food',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenant_id': tenantId,
        'ticket_id': ticketId,
        'product_id': productId,
        'product_name': productName,
        'quantity': quantity,
        'unit_price': unitPrice,
        'subtotal': subtotal,
        'tax_amount': taxAmount,
        'discount_amount': discountAmount,
        'status': status.name,
        'sent_to_kitchen': sentToKitchen,
        if (notes != null) 'notes': notes,
        'course': course,
        'modifiers': modifiers.map((m) => m.toJson()).toList(),
        'is_tax_free': isTaxFree,
        'is_open_price': isOpenPrice,
        'is_weight_based': isWeightBased,
        if (weight != null) 'weight': weight,
        if (weightUnit != null) 'weight_unit': weightUnit,
        'special_discount_amount': specialDiscountAmount,
        'tax_group': taxGroup,
      };

  OrderItemEntity copyWith({
    String? id,
    String? tenantId,
    String? ticketId,
    String? productId,
    String? productName,
    double? quantity,
    int? unitPrice,
    int? subtotal,
    int? taxAmount,
    int? discountAmount,
    OrderItemStatus? status,
    bool? sentToKitchen,
    String? Function()? notes,
    int? course,
    List<OrderItemModifierEntity>? modifiers,
    bool? isTaxFree,
    bool? isOpenPrice,
    bool? isWeightBased,
    double? Function()? weight,
    String? Function()? weightUnit,
    int? specialDiscountAmount,
    String? taxGroup,
  }) {
    return OrderItemEntity(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      ticketId: ticketId ?? this.ticketId,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      subtotal: subtotal ?? this.subtotal,
      taxAmount: taxAmount ?? this.taxAmount,
      discountAmount: discountAmount ?? this.discountAmount,
      status: status ?? this.status,
      sentToKitchen: sentToKitchen ?? this.sentToKitchen,
      notes: notes != null ? notes() : this.notes,
      course: course ?? this.course,
      modifiers: modifiers ?? this.modifiers,
      isTaxFree: isTaxFree ?? this.isTaxFree,
      isOpenPrice: isOpenPrice ?? this.isOpenPrice,
      isWeightBased: isWeightBased ?? this.isWeightBased,
      weight: weight != null ? weight() : this.weight,
      weightUnit: weightUnit != null ? weightUnit() : this.weightUnit,
      specialDiscountAmount:
          specialDiscountAmount ?? this.specialDiscountAmount,
      taxGroup: taxGroup ?? this.taxGroup,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrderItemEntity &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          tenantId == other.tenantId &&
          ticketId == other.ticketId &&
          productId == other.productId &&
          productName == other.productName &&
          quantity == other.quantity &&
          unitPrice == other.unitPrice &&
          subtotal == other.subtotal &&
          taxAmount == other.taxAmount &&
          discountAmount == other.discountAmount &&
          status == other.status &&
          sentToKitchen == other.sentToKitchen &&
          notes == other.notes &&
          course == other.course &&
          isTaxFree == other.isTaxFree &&
          isOpenPrice == other.isOpenPrice &&
          isWeightBased == other.isWeightBased &&
          weight == other.weight &&
          weightUnit == other.weightUnit &&
          specialDiscountAmount == other.specialDiscountAmount &&
          taxGroup == other.taxGroup;

  @override
  int get hashCode => Object.hash(
        id,
        tenantId,
        ticketId,
        productId,
        productName,
        quantity,
        unitPrice,
        subtotal,
        taxAmount,
        discountAmount,
        status,
        sentToKitchen,
        notes,
        course,
        isTaxFree,
        isWeightBased,
        specialDiscountAmount,
        taxGroup,
      );

  @override
  String toString() =>
      'OrderItemEntity(id: $id, product: $productName, qty: $quantity, subtotal: $subtotal)';
}
