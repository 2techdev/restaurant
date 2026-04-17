/// Order line item and order-item-modifier entities.
///
/// An [OrderItemEntity] is a snapshot of a product added to a ticket.
/// Product name and price are captured at the time of ordering so that
/// subsequent menu changes do not alter historical data.
library;

// ---------------------------------------------------------------------------
// OrderItemStatus enum
// ---------------------------------------------------------------------------

/// Lifecycle status of a single order line item.
enum OrderItemStatus {
  /// Item added to the ticket but not yet sent to kitchen.
  ordered,

  /// Sent to kitchen / bar printer.
  sent,

  /// Kitchen has started preparing.
  preparing,

  /// Ready for pickup / serving.
  ready,

  /// Served to the guest.
  served,

  /// Voided (cancelled after sending).
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

  /// Snapshot of the modifier name at order time.
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

  /// Create a copy with selectively overridden fields.
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
  int get hashCode => Object.hash(
        id,
        orderItemId,
        modifierId,
        modifierName,
        priceDelta,
      );

  @override
  String toString() =>
      'OrderItemModifierEntity(id: $id, name: $modifierName, delta: $priceDelta)';
}

// ---------------------------------------------------------------------------
// OrderItemEntity
// ---------------------------------------------------------------------------

/// A single line item on a [TicketEntity].
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

  /// Current preparation status.
  final OrderItemStatus status;

  /// Whether this item has been transmitted to the kitchen printer.
  final bool sentToKitchen;

  /// Free-text notes (e.g. "no onions", "extra spicy").
  final String? notes;

  /// Course number for multi-course service (1 = first course, etc.).
  final int course;

  /// Gang (course group) ID assigned to this item.
  /// References GangTemplate.id. Null = no Gang assigned.
  final String? gangId;

  /// Seat number this item is assigned to (1-based). Null = unassigned.
  ///
  /// Drives seat-based split billing. Kept nullable so single-cover tickets
  /// and walk-ups don't need to pick a seat.
  final int? seatNumber;

  /// Modifiers applied to this item.
  final List<OrderItemModifierEntity> modifiers;

  // -------------------------------------------------------------------------
  // Expanded fields (OrderPin-compatible)
  // -------------------------------------------------------------------------

  /// Whether this item is tax-exempt.
  final bool isTaxFree;

  /// Whether the price was manually entered (open price).
  final bool isOpenPrice;

  /// Whether this item uses weight-based pricing.
  final bool isWeightBased;

  /// Weight value for weight-based items (in [weightUnit]).
  final double? weight;

  /// Unit of weight measurement ('kg', 'g', 'lb').
  final String? weightUnit;

  /// Per-item special discount amount in cents.
  final int specialDiscountAmount;

  /// Tax group name (snapshot from product at order time).
  ///
  /// Drives Swiss MWST code resolution:
  /// - 'food'          → A (8.1% dine-in) or B (2.6% takeaway)
  /// - 'beverage'      → A (8.1% always)
  /// - 'alcohol'       → A (8.1% always)
  /// - 'accommodation' → C (3.8% always)
  /// - 'standard'      → A (8.1% default)
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
    this.gangId,
    this.seatNumber,
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

  /// Create a copy with selectively overridden fields.
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
    String? Function()? gangId,
    int? Function()? seatNumber,
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
      gangId: gangId != null ? gangId() : this.gangId,
      seatNumber: seatNumber != null ? seatNumber() : this.seatNumber,
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
          seatNumber == other.seatNumber &&
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
        seatNumber,
        isTaxFree,
        isWeightBased,
        specialDiscountAmount,
        taxGroup,
      );

  @override
  String toString() =>
      'OrderItemEntity(id: $id, product: $productName, qty: $quantity, subtotal: $subtotal)';
}
