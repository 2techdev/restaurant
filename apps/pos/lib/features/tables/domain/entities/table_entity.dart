/// Floor and restaurant table entities.
///
/// [FloorEntity] represents a physical section of the restaurant
/// (e.g. "Main Hall", "Terrace", "Bar Area"). Each floor contains
/// [RestaurantTableEntity] objects positioned on a 2D canvas for the
/// floor-plan view.
library;

// ---------------------------------------------------------------------------
// TableShape enum
// ---------------------------------------------------------------------------

/// Visual shape of a table on the floor plan.
enum TableShape {
  rectangle,
  circle,
  square,
}

// ---------------------------------------------------------------------------
// TableStatus enum
// ---------------------------------------------------------------------------

/// Current status of a restaurant table.
enum TableStatus {
  /// Ready for seating.
  available,

  /// Guests seated, active order.
  occupied,

  /// Reserved for a future seating.
  reserved,

  /// Needs clearing / cleaning.
  dirty,
}

// ---------------------------------------------------------------------------
// FloorEntity
// ---------------------------------------------------------------------------

/// A named section / zone of the restaurant.
class FloorEntity {
  final String id;
  final String tenantId;
  final String name;
  final int displayOrder;

  const FloorEntity({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.displayOrder,
  });

  /// Create a copy with selectively overridden fields.
  FloorEntity copyWith({
    String? id,
    String? tenantId,
    String? name,
    int? displayOrder,
  }) {
    return FloorEntity(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      name: name ?? this.name,
      displayOrder: displayOrder ?? this.displayOrder,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FloorEntity &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          tenantId == other.tenantId &&
          name == other.name &&
          displayOrder == other.displayOrder;

  @override
  int get hashCode => Object.hash(id, tenantId, name, displayOrder);

  @override
  String toString() =>
      'FloorEntity(id: $id, name: $name, order: $displayOrder)';
}

// ---------------------------------------------------------------------------
// RestaurantTableEntity
// ---------------------------------------------------------------------------

/// A physical table positioned on a floor plan canvas.
class RestaurantTableEntity {
  final String id;
  final String tenantId;

  /// The floor / zone this table belongs to.
  final String floorId;

  /// Display name (e.g. "T1", "Bar 3", "Terrace 12").
  final String name;

  /// Maximum number of guests.
  final int capacity;

  /// Visual shape for rendering.
  final TableShape shape;

  /// Horizontal position on the floor plan canvas.
  final double posX;

  /// Vertical position on the floor plan canvas.
  final double posY;

  /// Width of the table on the canvas.
  final double width;

  /// Height of the table on the canvas.
  final double height;

  /// Current status.
  final TableStatus status;

  /// ID of the currently active order, if any.
  final String? currentOrderId;

  const RestaurantTableEntity({
    required this.id,
    required this.tenantId,
    required this.floorId,
    required this.name,
    required this.capacity,
    this.shape = TableShape.rectangle,
    required this.posX,
    required this.posY,
    required this.width,
    required this.height,
    this.status = TableStatus.available,
    this.currentOrderId,
  });

  /// Whether the table is free to seat new guests.
  bool get isAvailable => status == TableStatus.available;

  /// Create a copy with selectively overridden fields.
  RestaurantTableEntity copyWith({
    String? id,
    String? tenantId,
    String? floorId,
    String? name,
    int? capacity,
    TableShape? shape,
    double? posX,
    double? posY,
    double? width,
    double? height,
    TableStatus? status,
    String? Function()? currentOrderId,
  }) {
    return RestaurantTableEntity(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      floorId: floorId ?? this.floorId,
      name: name ?? this.name,
      capacity: capacity ?? this.capacity,
      shape: shape ?? this.shape,
      posX: posX ?? this.posX,
      posY: posY ?? this.posY,
      width: width ?? this.width,
      height: height ?? this.height,
      status: status ?? this.status,
      currentOrderId:
          currentOrderId != null ? currentOrderId() : this.currentOrderId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RestaurantTableEntity &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          tenantId == other.tenantId &&
          floorId == other.floorId &&
          name == other.name &&
          capacity == other.capacity &&
          shape == other.shape &&
          posX == other.posX &&
          posY == other.posY &&
          width == other.width &&
          height == other.height &&
          status == other.status &&
          currentOrderId == other.currentOrderId;

  @override
  int get hashCode => Object.hash(
        id,
        tenantId,
        floorId,
        name,
        capacity,
        shape,
        posX,
        posY,
        width,
        height,
        status,
        currentOrderId,
      );

  @override
  String toString() =>
      'RestaurantTableEntity(id: $id, name: $name, status: ${status.name})';
}
