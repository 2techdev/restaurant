/// Shift and cash movement entities.
///
/// A [ShiftEntity] tracks a cashier's working session from open to close,
/// including opening/closing cash counts and aggregate sales figures.
/// [CashMovementEntity] records pay-ins, pay-outs, tips, and expenses
/// during the shift.
library;

// ---------------------------------------------------------------------------
// ShiftStatus enum
// ---------------------------------------------------------------------------

/// Lifecycle status of a shift.
enum ShiftStatus {
  /// Shift is active, accepting orders and payments.
  open,

  /// Cash count in progress, no new orders.
  closing,

  /// Shift fully closed and reconciled.
  closed,
}

// ---------------------------------------------------------------------------
// CashMovementType enum
// ---------------------------------------------------------------------------

/// Type of non-sale cash movement within a shift.
enum CashMovementType {
  /// Cash added to the drawer (e.g. change float top-up).
  payIn,

  /// Cash removed from the drawer (e.g. bank deposit).
  payOut,

  /// Tip received in cash.
  tip,

  /// Minor expense paid from the drawer.
  expense,
}

// ---------------------------------------------------------------------------
// ShiftEntity
// ---------------------------------------------------------------------------

/// Immutable representation of a cashier shift.
class ShiftEntity {
  final String id;
  final String tenantId;

  /// User who owns this shift.
  final String userId;

  /// Device on which the shift was opened.
  final String deviceId;

  /// Cash counted in the drawer at shift start (cents).
  final int openingCash;

  /// Cash counted at shift close (cents). Null while shift is open.
  final int? closingCash;

  /// System-calculated expected cash (opening + sales - payouts, in cents).
  final int? expectedCash;

  /// Difference between actual and expected cash (cents). Positive = over.
  final int? difference;

  /// Total sales processed during this shift (cents).
  final int totalSales;

  /// Total number of orders completed during this shift.
  final int totalOrders;

  final ShiftStatus status;

  /// When the shift was opened.
  final DateTime openedAt;

  /// When the shift was closed. Null while open.
  final DateTime? closedAt;

  /// Optional closing notes from the cashier.
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

  /// Whether the shift is currently active.
  bool get isOpen => status == ShiftStatus.open;

  /// Create a copy with selectively overridden fields.
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
          openingCash == other.openingCash &&
          closingCash == other.closingCash &&
          expectedCash == other.expectedCash &&
          difference == other.difference &&
          totalSales == other.totalSales &&
          totalOrders == other.totalOrders &&
          status == other.status &&
          openedAt == other.openedAt &&
          closedAt == other.closedAt &&
          notes == other.notes;

  @override
  int get hashCode => Object.hash(
        id,
        tenantId,
        userId,
        deviceId,
        openingCash,
        closingCash,
        expectedCash,
        difference,
        totalSales,
        totalOrders,
        status,
        openedAt,
        closedAt,
        notes,
      );

  @override
  String toString() =>
      'ShiftEntity(id: $id, user: $userId, status: ${status.name})';
}

// ---------------------------------------------------------------------------
// CashMovementEntity
// ---------------------------------------------------------------------------

/// A non-sale cash movement within a shift.
class CashMovementEntity {
  final String id;
  final String tenantId;

  /// The shift this movement belongs to.
  final String shiftId;

  final CashMovementType type;

  /// Amount in cents (always positive; direction determined by [type]).
  final int amount;

  /// Optional description of the movement.
  final String? description;

  /// User who performed the movement.
  final String performedBy;

  /// When the movement was recorded.
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

  /// Create a copy with selectively overridden fields.
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
          amount == other.amount &&
          description == other.description &&
          performedBy == other.performedBy &&
          performedAt == other.performedAt;

  @override
  int get hashCode => Object.hash(
        id,
        tenantId,
        shiftId,
        type,
        amount,
        description,
        performedBy,
        performedAt,
      );

  @override
  String toString() =>
      'CashMovementEntity(id: $id, type: ${type.name}, amount: $amount)';
}
