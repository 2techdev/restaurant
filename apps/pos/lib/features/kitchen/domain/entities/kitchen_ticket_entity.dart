/// Kitchen display ticket and item entities.
///
/// A [KitchenTicketEntity] is a projection of an order ticket filtered
/// by printer group. The kitchen sees only the items routed to its station,
/// with timestamps for SLA tracking.
library;

// ---------------------------------------------------------------------------
// KitchenTicketStatus enum
// ---------------------------------------------------------------------------

/// Lifecycle status of a kitchen ticket or individual item.
enum KitchenTicketStatus {
  /// Waiting to be seen by kitchen staff.
  pending,

  /// Kitchen staff has acknowledged the ticket.
  acknowledged,

  /// Preparation in progress.
  preparing,

  /// Ready for pickup / serving.
  ready,

  /// Served to the guest.
  served,

  /// Voided / cancelled.
  voidStatus,
}

// ---------------------------------------------------------------------------
// KitchenTicketItemEntity
// ---------------------------------------------------------------------------

/// A single item on a kitchen ticket.
class KitchenTicketItemEntity {
  final String id;

  /// Parent kitchen ticket.
  final String kitchenTicketId;

  /// Reference to the original order item.
  final String orderItemId;

  /// Product name (snapshot).
  final String productName;

  /// Quantity to prepare.
  final double quantity;

  /// Comma-separated modifier descriptions for display.
  final String? modifiersText;

  /// Special preparation notes.
  final String? notes;

  /// Current preparation status of this individual item.
  final KitchenTicketStatus status;

  /// Gang (course group) ID for this item. Null = no Gang assigned.
  final String? gangId;

  const KitchenTicketItemEntity({
    required this.id,
    required this.kitchenTicketId,
    required this.orderItemId,
    required this.productName,
    required this.quantity,
    this.modifiersText,
    this.notes,
    this.status = KitchenTicketStatus.pending,
    this.gangId,
  });

  /// Create a copy with selectively overridden fields.
  KitchenTicketItemEntity copyWith({
    String? id,
    String? kitchenTicketId,
    String? orderItemId,
    String? productName,
    double? quantity,
    String? Function()? modifiersText,
    String? Function()? notes,
    KitchenTicketStatus? status,
    String? Function()? gangId,
  }) {
    return KitchenTicketItemEntity(
      id: id ?? this.id,
      kitchenTicketId: kitchenTicketId ?? this.kitchenTicketId,
      orderItemId: orderItemId ?? this.orderItemId,
      productName: productName ?? this.productName,
      quantity: quantity ?? this.quantity,
      modifiersText:
          modifiersText != null ? modifiersText() : this.modifiersText,
      notes: notes != null ? notes() : this.notes,
      status: status ?? this.status,
      gangId: gangId != null ? gangId() : this.gangId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KitchenTicketItemEntity &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          kitchenTicketId == other.kitchenTicketId &&
          orderItemId == other.orderItemId &&
          productName == other.productName &&
          quantity == other.quantity &&
          modifiersText == other.modifiersText &&
          notes == other.notes &&
          status == other.status;

  @override
  int get hashCode => Object.hash(
        id,
        kitchenTicketId,
        orderItemId,
        productName,
        quantity,
        modifiersText,
        notes,
        status,
      );

  @override
  String toString() =>
      'KitchenTicketItemEntity(id: $id, product: $productName, qty: $quantity)';
}

// ---------------------------------------------------------------------------
// KitchenTicketEntity
// ---------------------------------------------------------------------------

/// A ticket as seen on the kitchen display system.
class KitchenTicketEntity {
  final String id;
  final String tenantId;

  /// Reference to the parent order ticket.
  final String ticketId;

  /// Table name for display (null for takeaway / delivery).
  final String? tableName;

  /// Waiter / server name (denormalized snapshot).
  final String? waiterName;

  /// Human-readable order number.
  final String orderNumber;

  /// Printer group this ticket was routed to (e.g. "kitchen", "bar").
  final String printerGroup;

  /// Aggregate status of the kitchen ticket.
  final KitchenTicketStatus status;

  /// Items to prepare.
  final List<KitchenTicketItemEntity> items;

  /// When the ticket was sent to the kitchen.
  final DateTime sentAt;

  /// When preparation was started.
  final DateTime? startedAt;

  /// When all items were marked ready.
  final DateTime? completedAt;

  const KitchenTicketEntity({
    required this.id,
    required this.tenantId,
    required this.ticketId,
    this.tableName,
    this.waiterName,
    required this.orderNumber,
    required this.printerGroup,
    this.status = KitchenTicketStatus.pending,
    this.items = const [],
    required this.sentAt,
    this.startedAt,
    this.completedAt,
  });

  /// Elapsed time since the ticket was sent to the kitchen.
  Duration get elapsedTime => DateTime.now().difference(sentAt);

  /// Whether the ticket is overdue based on a target duration.
  bool isOverdue(Duration target) => elapsedTime > target;

  /// Create a copy with selectively overridden fields.
  KitchenTicketEntity copyWith({
    String? id,
    String? tenantId,
    String? ticketId,
    String? Function()? tableName,
    String? Function()? waiterName,
    String? orderNumber,
    String? printerGroup,
    KitchenTicketStatus? status,
    List<KitchenTicketItemEntity>? items,
    DateTime? sentAt,
    DateTime? Function()? startedAt,
    DateTime? Function()? completedAt,
  }) {
    return KitchenTicketEntity(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      ticketId: ticketId ?? this.ticketId,
      tableName: tableName != null ? tableName() : this.tableName,
      waiterName: waiterName != null ? waiterName() : this.waiterName,
      orderNumber: orderNumber ?? this.orderNumber,
      printerGroup: printerGroup ?? this.printerGroup,
      status: status ?? this.status,
      items: items ?? this.items,
      sentAt: sentAt ?? this.sentAt,
      startedAt: startedAt != null ? startedAt() : this.startedAt,
      completedAt: completedAt != null ? completedAt() : this.completedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KitchenTicketEntity &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          tenantId == other.tenantId &&
          ticketId == other.ticketId &&
          tableName == other.tableName &&
          waiterName == other.waiterName &&
          orderNumber == other.orderNumber &&
          printerGroup == other.printerGroup &&
          status == other.status &&
          sentAt == other.sentAt &&
          startedAt == other.startedAt &&
          completedAt == other.completedAt;

  @override
  int get hashCode => Object.hash(
        id,
        tenantId,
        ticketId,
        tableName,
        waiterName,
        orderNumber,
        printerGroup,
        status,
        sentAt,
        startedAt,
        completedAt,
      );

  @override
  String toString() =>
      'KitchenTicketEntity(id: $id, order: $orderNumber, status: ${status.name})';
}
