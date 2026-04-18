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
///
/// This is the table's *primary* state — one value drives the tile's
/// main colour on the floor plan. Concurrent signals (e.g. bill has
/// been requested while the table is still occupied, or a
/// reservation is approaching while the table is currently dirty)
/// live on [TableFlag] so that multiple states can coexist without
/// overwriting each other.
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
// TableFlag enum
// ---------------------------------------------------------------------------

/// Orthogonal state signals that can stack on top of [TableStatus].
///
/// Modelled after SambaPOS-3's Entity State groups: a table can be
/// `occupied` AND have `billRequested` AND have `reservationSoon`
/// simultaneously. Flags are rendered as small badges overlaid on
/// the table tile.
enum TableFlag {
  /// Waiter / guest has requested the bill — cashier should prepare
  /// payment without the guest asking again.
  billRequested,

  /// An upcoming reservation is within the "warning" window
  /// (typically < 30 min). The table tile should alert staff that
  /// the current party may need to be moved along.
  reservationSoon,

  /// Service has been flagged — e.g. guest pressed a call button,
  /// or a manager escalated the table.
  needsAttention,

  /// VIP guest marker — surfaces preferred service and often
  /// guides seating choices.
  vip,
}

/// Canonical wire form for [TableFlag.name] → enum. Used by the
/// Drift mapper and by LAN sync payloads.
TableFlag? _parseTableFlag(String name) {
  for (final flag in TableFlag.values) {
    if (flag.name == name) return flag;
  }
  return null;
}

/// Decode the persisted CSV blob into a deterministic flag set.
///
/// Unknown tokens are silently dropped so a new app version can roll
/// back without breaking existing rows.
Set<TableFlag> decodeTableFlags(String? csv) {
  if (csv == null || csv.isEmpty) return const <TableFlag>{};
  final out = <TableFlag>{};
  for (final raw in csv.split(',')) {
    final token = raw.trim();
    if (token.isEmpty) continue;
    final parsed = _parseTableFlag(token);
    if (parsed != null) out.add(parsed);
  }
  return out;
}

/// Encode a flag set for persistence. Order is deterministic (enum
/// declaration order) so round-trips are byte-stable — useful for
/// sync conflict detection.
String encodeTableFlags(Set<TableFlag> flags) {
  if (flags.isEmpty) return '';
  return TableFlag.values
      .where(flags.contains)
      .map((f) => f.name)
      .join(',');
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

  /// Orthogonal state signals layered on top of [status]. Any number
  /// of flags can be set simultaneously — e.g. occupied + bill
  /// requested + VIP.
  final Set<TableFlag> flags;

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
    this.flags = const <TableFlag>{},
  });

  /// Whether the table is free to seat new guests.
  bool get isAvailable => status == TableStatus.available;

  /// Convenience: is the [flag] currently active on this table?
  bool hasFlag(TableFlag flag) => flags.contains(flag);

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
    Set<TableFlag>? flags,
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
      flags: flags ?? this.flags,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! RestaurantTableEntity) return false;
    if (flags.length != other.flags.length) return false;
    for (final flag in flags) {
      if (!other.flags.contains(flag)) return false;
    }
    return runtimeType == other.runtimeType &&
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
  }

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
        Object.hashAllUnordered(flags),
      );

  @override
  String toString() =>
      'RestaurantTableEntity(id: $id, name: $name, status: ${status.name}, '
      'flags: ${flags.map((f) => f.name).join(",")})';
}
