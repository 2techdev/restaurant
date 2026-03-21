/// Floor and restaurant table entities.
library;

enum TableShape { rectangle, circle, square }

enum TableStatus { available, occupied, reserved, dirty }

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

  factory FloorEntity.fromJson(Map<String, dynamic> json) => FloorEntity(
        id: json['id'] as String,
        tenantId: json['tenant_id'] as String,
        name: json['name'] as String,
        displayOrder: json['display_order'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenant_id': tenantId,
        'name': name,
        'display_order': displayOrder,
      };

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

/// A physical table positioned on a floor plan canvas.
class RestaurantTableEntity {
  final String id;
  final String tenantId;
  final String floorId;
  final String name;
  final int capacity;
  final TableShape shape;
  final double posX;
  final double posY;
  final double width;
  final double height;
  final TableStatus status;
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

  bool get isAvailable => status == TableStatus.available;

  factory RestaurantTableEntity.fromJson(Map<String, dynamic> json) =>
      RestaurantTableEntity(
        id: json['id'] as String,
        tenantId: json['tenant_id'] as String,
        floorId: json['floor_id'] as String,
        name: json['name'] as String,
        capacity: json['capacity'] as int? ?? 4,
        shape: TableShape.values.firstWhere(
          (e) => e.name == json['shape'],
          orElse: () => TableShape.rectangle,
        ),
        posX: (json['pos_x'] as num?)?.toDouble() ?? 0,
        posY: (json['pos_y'] as num?)?.toDouble() ?? 0,
        width: (json['width'] as num?)?.toDouble() ?? 100,
        height: (json['height'] as num?)?.toDouble() ?? 80,
        status: TableStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => TableStatus.available,
        ),
        currentOrderId: json['current_order_id'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenant_id': tenantId,
        'floor_id': floorId,
        'name': name,
        'capacity': capacity,
        'shape': shape.name,
        'pos_x': posX,
        'pos_y': posY,
        'width': width,
        'height': height,
        'status': status.name,
        if (currentOrderId != null) 'current_order_id': currentOrderId,
      };

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
          status == other.status;

  @override
  int get hashCode =>
      Object.hash(id, tenantId, floorId, name, status);

  @override
  String toString() =>
      'RestaurantTableEntity(id: $id, name: $name, status: ${status.name})';
}
