/// Drift-backed implementation of the shift repository.
///
/// Manages cashier shift lifecycle (open / close) and cash movements
/// (pay-in, pay-out, tips, expenses). Shift totals are recalculated
/// from completed tickets that fall within the shift time window.
library;

import 'package:drift/drift.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/shifts/domain/entities/shift_entity.dart';

class ShiftRepositoryImpl {
  final AppDatabase _db;

  ShiftRepositoryImpl(this._db);

  // =========================================================================
  // Shift lifecycle
  // =========================================================================

  /// Open a new cashier shift and return the persisted [ShiftEntity].
  Future<ShiftEntity> openShift({
    required String tenantId,
    required String userId,
    required String deviceId,
    required int openingCash,
  }) async {
    final id = IdGenerator.generateId();
    final now = DateTime.now();

    await _db.into(_db.shifts).insert(
          ShiftsCompanion(
            id: Value(id),
            tenantId: Value(tenantId),
            userId: Value(userId),
            deviceId: Value(deviceId),
            openingCash: Value(openingCash),
            totalSales: const Value(0),
            totalOrders: const Value(0),
            status: const Value('open'),
            openedAt: Value(now),
            createdAt: Value(now),
            updatedAt: Value(now),
            isDeleted: const Value(false),
            syncStatus: const Value(0),
          ),
        );

    return (await getShiftById(id))!;
  }

  /// Return the currently open shift for [tenantId], or `null` if none.
  Future<ShiftEntity?> getOpenShift(String tenantId) async {
    final query = _db.select(_db.shifts)
      ..where(
        (s) =>
            s.tenantId.equals(tenantId) &
            s.status.equals('open') &
            s.isDeleted.equals(false),
      )
      ..orderBy([(s) => OrderingTerm.desc(s.openedAt)])
      ..limit(1);
    final row = await query.getSingleOrNull();
    return row == null ? null : _shiftToEntity(row);
  }

  /// Close a shift: record the closing cash count, calculate the expected
  /// value and difference, then transition the status to "closed".
  Future<ShiftEntity> closeShift({
    required String shiftId,
    required int closingCash,
    String? notes,
  }) async {
    // Recalculate totals before closing.
    await calculateShiftTotals(shiftId);

    // Read the refreshed shift row.
    final shift = await (_db.select(_db.shifts)
          ..where((s) => s.id.equals(shiftId)))
        .getSingle();

    // Expected = opening + cash sales + pay-ins - pay-outs.
    final movements = await getCashMovements(shiftId);
    int payIns = 0;
    int payOuts = 0;
    for (final m in movements) {
      if (m.type == CashMovementType.payIn || m.type == CashMovementType.tip) {
        payIns += m.amount;
      } else {
        payOuts += m.amount;
      }
    }

    // Cash sales: sum of cash payments during this shift.
    final cashPayments = await _getCashPaymentsDuringShift(shift);
    final cashSales = cashPayments.fold<int>(0, (s, p) => s + p.amount);

    final expectedCash = shift.openingCash + cashSales + payIns - payOuts;
    final difference = closingCash - expectedCash;
    final now = DateTime.now();

    await (_db.update(_db.shifts)..where((s) => s.id.equals(shiftId))).write(
      ShiftsCompanion(
        closingCash: Value(closingCash),
        expectedCash: Value(expectedCash),
        difference: Value(difference),
        status: const Value('closed'),
        closedAt: Value(now),
        notes: Value(notes),
        updatedAt: Value(now),
      ),
    );

    return (await getShiftById(shiftId))!;
  }

  /// Fetch a shift by [id].
  Future<ShiftEntity?> getShiftById(String id) async {
    final query = _db.select(_db.shifts)
      ..where((s) => s.id.equals(id) & s.isDeleted.equals(false));
    final row = await query.getSingleOrNull();
    return row == null ? null : _shiftToEntity(row);
  }

  // =========================================================================
  // Cash movements
  // =========================================================================

  /// Record a cash movement (pay-in, pay-out, tip, expense).
  Future<void> addCashMovement(CashMovementEntity entity) async {
    await _db.into(_db.cashMovements).insert(
          CashMovementsCompanion(
            id: Value(entity.id),
            tenantId: Value(entity.tenantId),
            shiftId: Value(entity.shiftId),
            type: Value(_cashMovementTypeToString(entity.type)),
            amount: Value(entity.amount),
            description: Value(entity.description),
            performedBy: Value(entity.performedBy),
            performedAt: Value(entity.performedAt),
            createdAt: Value(DateTime.now()),
            isDeleted: const Value(false),
            syncStatus: const Value(0),
          ),
        );
  }

  /// Return all cash movements for [shiftId], ordered chronologically.
  Future<List<CashMovementEntity>> getCashMovements(String shiftId) async {
    final query = _db.select(_db.cashMovements)
      ..where(
        (m) => m.shiftId.equals(shiftId) & m.isDeleted.equals(false),
      )
      ..orderBy([(m) => OrderingTerm.asc(m.performedAt)]);
    final rows = await query.get();
    return rows.map(_cashMovementToEntity).toList();
  }

  // =========================================================================
  // Totals recalculation
  // =========================================================================

  /// Recalculate totalSales and totalOrders for a shift from the
  /// completed tickets within the shift window.
  Future<void> calculateShiftTotals(String shiftId) async {
    final shift = await (_db.select(_db.shifts)
          ..where((s) => s.id.equals(shiftId)))
        .getSingle();

    // Tickets completed during the shift.
    var ticketQuery = _db.select(_db.tickets)
      ..where(
        (t) =>
            t.tenantId.equals(shift.tenantId) &
            t.isDeleted.equals(false) &
            t.openedAt.isBiggerOrEqualValue(shift.openedAt) &
            t.status.isIn(['completed', 'fully_paid', 'closed']),
      );

    if (shift.closedAt != null) {
      ticketQuery = _db.select(_db.tickets)
        ..where(
          (t) =>
              t.tenantId.equals(shift.tenantId) &
              t.isDeleted.equals(false) &
              t.openedAt.isBiggerOrEqualValue(shift.openedAt) &
              t.openedAt.isSmallerOrEqualValue(shift.closedAt!) &
              t.status.isIn(['completed', 'fully_paid', 'closed']),
        );
    }

    final tickets = await ticketQuery.get();

    final totalSales = tickets.fold<int>(0, (s, t) => s + t.total);
    final totalOrders = tickets.length;

    await (_db.update(_db.shifts)..where((s) => s.id.equals(shiftId))).write(
      ShiftsCompanion(
        totalSales: Value(totalSales),
        totalOrders: Value(totalOrders),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  // =========================================================================
  // History & breakdown
  // =========================================================================

  /// Return all shifts for [tenantId], newest first, up to [limit].
  Future<List<ShiftEntity>> getShiftHistory(
    String tenantId, {
    int limit = 50,
  }) async {
    final query = _db.select(_db.shifts)
      ..where((s) => s.tenantId.equals(tenantId) & s.isDeleted.equals(false))
      ..orderBy([
        (s) => OrderingTerm.desc(s.openedAt),
        (s) => OrderingTerm(expression: s.rowId, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    final rows = await query.get();
    return rows.map(_shiftToEntity).toList();
  }

  /// Return a map of `paymentMethod → totalCents` for all payments
  /// made during the given shift's time window.
  Future<Map<String, int>> getPaymentBreakdown(
    String shiftId,
    String tenantId,
  ) async {
    final shift = await (_db.select(_db.shifts)
          ..where((s) => s.id.equals(shiftId)))
        .getSingle();

    var query = _db.select(_db.payments)
      ..where(
        (p) =>
            p.tenantId.equals(tenantId) &
            p.isDeleted.equals(false) &
            p.paidAt.isBiggerOrEqualValue(shift.openedAt),
      );

    if (shift.closedAt != null) {
      query = _db.select(_db.payments)
        ..where(
          (p) =>
              p.tenantId.equals(tenantId) &
              p.isDeleted.equals(false) &
              p.paidAt.isBiggerOrEqualValue(shift.openedAt) &
              p.paidAt.isSmallerOrEqualValue(shift.closedAt!),
        );
    }

    final payments = await query.get();
    final breakdown = <String, int>{};
    for (final p in payments) {
      breakdown[p.paymentMethod] =
          (breakdown[p.paymentMethod] ?? 0) + p.amount;
    }
    return breakdown;
  }

  /// Return all shifts for a specific device, newest first.
  Future<List<ShiftEntity>> getShiftsForDevice(
    String tenantId,
    String deviceId, {
    int limit = 20,
  }) async {
    final query = _db.select(_db.shifts)
      ..where(
        (s) =>
            s.tenantId.equals(tenantId) &
            s.deviceId.equals(deviceId) &
            s.isDeleted.equals(false),
      )
      ..orderBy([(s) => OrderingTerm.desc(s.openedAt)])
      ..limit(limit);
    final rows = await query.get();
    return rows.map(_shiftToEntity).toList();
  }

  // =========================================================================
  // Private helpers
  // =========================================================================

  /// Fetch all cash-method payments made during a shift time window.
  Future<List<Payment>> _getCashPaymentsDuringShift(Shift shift) async {
    var query = _db.select(_db.payments)
      ..where(
        (p) =>
            p.tenantId.equals(shift.tenantId) &
            p.isDeleted.equals(false) &
            p.paymentMethod.equals('cash') &
            p.paidAt.isBiggerOrEqualValue(shift.openedAt),
      );

    if (shift.closedAt != null) {
      query = _db.select(_db.payments)
        ..where(
          (p) =>
              p.tenantId.equals(shift.tenantId) &
              p.isDeleted.equals(false) &
              p.paymentMethod.equals('cash') &
              p.paidAt.isBiggerOrEqualValue(shift.openedAt) &
              p.paidAt.isSmallerOrEqualValue(shift.closedAt!),
        );
    }

    return query.get();
  }

  // =========================================================================
  // Mappers – Shift
  // =========================================================================

  ShiftEntity _shiftToEntity(Shift row) {
    return ShiftEntity(
      id: row.id,
      tenantId: row.tenantId,
      userId: row.userId,
      deviceId: row.deviceId,
      openingCash: row.openingCash,
      closingCash: row.closingCash,
      expectedCash: row.expectedCash,
      difference: row.difference,
      totalSales: row.totalSales,
      totalOrders: row.totalOrders,
      status: _parseShiftStatus(row.status),
      openedAt: row.openedAt,
      closedAt: row.closedAt,
      notes: row.notes,
    );
  }

  // =========================================================================
  // Mappers – Cash movement
  // =========================================================================

  CashMovementEntity _cashMovementToEntity(CashMovement row) {
    return CashMovementEntity(
      id: row.id,
      tenantId: row.tenantId,
      shiftId: row.shiftId,
      type: _parseCashMovementType(row.type),
      amount: row.amount,
      description: row.description,
      performedBy: row.performedBy,
      performedAt: row.performedAt,
    );
  }

  // =========================================================================
  // Enum serialisation
  // =========================================================================

  static ShiftStatus _parseShiftStatus(String value) {
    return switch (value) {
      'open' => ShiftStatus.open,
      'closing' => ShiftStatus.closing,
      'closed' => ShiftStatus.closed,
      _ => ShiftStatus.open,
    };
  }

  static CashMovementType _parseCashMovementType(String value) {
    return switch (value) {
      'pay_in' => CashMovementType.payIn,
      'pay_out' => CashMovementType.payOut,
      'tip' => CashMovementType.tip,
      'expense' => CashMovementType.expense,
      _ => CashMovementType.payIn,
    };
  }

  static String _cashMovementTypeToString(CashMovementType type) {
    return switch (type) {
      CashMovementType.payIn => 'pay_in',
      CashMovementType.payOut => 'pay_out',
      CashMovementType.tip => 'tip',
      CashMovementType.expense => 'expense',
    };
  }
}
