/// Shift and cash movement entities.
library;

enum ShiftStatus { open, closing, closed }

enum CashMovementType { payIn, payOut, tip, expense }

/// Immutable representation of a cashier shift.
class ShiftEntity {
  final String id;
  final String tenantId;
  final String userId;
  final String deviceId;
  final int openingCash;
  final int? closingCash;
  final int? expectedCash;
  final int? difference;
  final int totalSales;
  final int totalOrders;
  final ShiftStatus status;
  final DateTime openedAt;
  final DateTime? closedAt;
  final String? notes;

  const ShiftEntity({
    required this.id,
    required this.tenantId,
    required this.userId,
    required this.deviceId,
    required this.openingCash,
    this.closingCash,
    this.expectedCash,
    this.difference,
    this.totalSales = 0,
    this.totalOrders = 0,
    this.status = ShiftStatus.open,
    required this.openedAt,
    this.closedAt,
    this.notes,
  });

  bool get isOpen => status == ShiftStatus.open;

  factory ShiftEntity.fromJson(Map<String, dynamic> json) => ShiftEntity(
        id: json['id'] as String,
        tenantId: json['tenant_id'] as String,
        userId: json['user_id'] as String,
        deviceId: json['device_id'] as String,
        openingCash: (json['opening_cash'] as num).toInt(),
        closingCash: (json['closing_cash'] as num?)?.toInt(),
        expectedCash: (json['expected_cash'] as num?)?.toInt(),
        difference: (json['difference'] as num?)?.toInt(),
        totalSales: (json['total_sales'] as num?)?.toInt() ?? 0,
        totalOrders: (json['total_orders'] as num?)?.toInt() ?? 0,
        status: ShiftStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => ShiftStatus.open,
        ),
        openedAt: DateTime.parse(json['opened_at'] as String),
        closedAt: json['closed_at'] != null
            ? DateTime.parse(json['closed_at'] as String)
            : null,
        notes: json['notes'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenant_id': tenantId,
        'user_id': userId,
        'device_id': deviceId,
        'opening_cash': openingCash,
        if (closingCash != null) 'closing_cash': closingCash,
        if (expectedCash != null) 'expected_cash': expectedCash,
        if (difference != null) 'difference': difference,
        'total_sales': totalSales,
        'total_orders': totalOrders,
        'status': status.name,
        'opened_at': openedAt.toIso8601String(),
        if (closedAt != null) 'closed_at': closedAt!.toIso8601String(),
        if (notes != null) 'notes': notes,
      };

  ShiftEntity copyWith({
    String? id,
    String? tenantId,
    String? userId,
    String? deviceId,
    int? openingCash,
    int? Function()? closingCash,
    int? Function()? expectedCash,
    int? Function()? difference,
    int? totalSales,
    int? totalOrders,
    ShiftStatus? status,
    DateTime? openedAt,
    DateTime? Function()? closedAt,
    String? Function()? notes,
  }) {
    return ShiftEntity(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      userId: userId ?? this.userId,
      deviceId: deviceId ?? this.deviceId,
      openingCash: openingCash ?? this.openingCash,
      closingCash: closingCash != null ? closingCash() : this.closingCash,
      expectedCash:
          expectedCash != null ? expectedCash() : this.expectedCash,
      difference: difference != null ? difference() : this.difference,
      totalSales: totalSales ?? this.totalSales,
      totalOrders: totalOrders ?? this.totalOrders,
      status: status ?? this.status,
      openedAt: openedAt ?? this.openedAt,
      closedAt: closedAt != null ? closedAt() : this.closedAt,
      notes: notes != null ? notes() : this.notes,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShiftEntity &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          tenantId == other.tenantId &&
          userId == other.userId &&
          deviceId == other.deviceId &&
          status == other.status;

  @override
  int get hashCode =>
      Object.hash(id, tenantId, userId, deviceId, status);

  @override
  String toString() =>
      'ShiftEntity(id: $id, user: $userId, status: ${status.name})';
}

/// A non-sale cash movement within a shift.
class CashMovementEntity {
  final String id;
  final String tenantId;
  final String shiftId;
  final CashMovementType type;
  final int amount;
  final String? description;
  final String performedBy;
  final DateTime performedAt;

  const CashMovementEntity({
    required this.id,
    required this.tenantId,
    required this.shiftId,
    required this.type,
    required this.amount,
    this.description,
    required this.performedBy,
    required this.performedAt,
  });

  factory CashMovementEntity.fromJson(Map<String, dynamic> json) =>
      CashMovementEntity(
        id: json['id'] as String,
        tenantId: json['tenant_id'] as String,
        shiftId: json['shift_id'] as String,
        type: CashMovementType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => CashMovementType.payIn,
        ),
        amount: (json['amount'] as num).toInt(),
        description: json['description'] as String?,
        performedBy: json['performed_by'] as String,
        performedAt: DateTime.parse(json['performed_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenant_id': tenantId,
        'shift_id': shiftId,
        'type': type.name,
        'amount': amount,
        if (description != null) 'description': description,
        'performed_by': performedBy,
        'performed_at': performedAt.toIso8601String(),
      };

  CashMovementEntity copyWith({
    String? id,
    String? tenantId,
    String? shiftId,
    CashMovementType? type,
    int? amount,
    String? Function()? description,
    String? performedBy,
    DateTime? performedAt,
  }) {
    return CashMovementEntity(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      shiftId: shiftId ?? this.shiftId,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      description: description != null ? description() : this.description,
      performedBy: performedBy ?? this.performedBy,
      performedAt: performedAt ?? this.performedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CashMovementEntity &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          tenantId == other.tenantId &&
          shiftId == other.shiftId &&
          type == other.type &&
          amount == other.amount;

  @override
  int get hashCode =>
      Object.hash(id, tenantId, shiftId, type, amount);

  @override
  String toString() =>
      'CashMovementEntity(id: $id, type: ${type.name}, amount: $amount)';
}
