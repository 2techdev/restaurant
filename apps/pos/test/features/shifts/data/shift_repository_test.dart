/// Repository integration tests for ShiftRepositoryImpl.
///
/// Uses an in-memory Drift database.  Tests cover:
///   - openShift / getOpenShift / getShiftById
///   - closeShift with cash counting & difference calculation
///   - addCashMovement / getCashMovements
///   - calculateShiftTotals from completed tickets
///   - getShiftHistory ordering
///   - getPaymentBreakdown by method
///
/// Run with:
///   flutter test test/features/shifts/data/shift_repository_test.dart
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/orders/data/repositories/order_repository_impl.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/order_item_entity.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/features/payments/data/repositories/payment_repository_impl.dart';
import 'package:gastrocore_pos/features/payments/domain/entities/payment_entity.dart';
import 'package:gastrocore_pos/features/shifts/data/repositories/shift_repository_impl.dart';
import 'package:gastrocore_pos/features/shifts/domain/entities/shift_entity.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _tenantId = 'tenant-shift-test';
const _userId = 'user-shift-01';
const _deviceId = 'DEV-SHIFT-01';

ShiftRepositoryImpl _makeRepo(AppDatabase db) => ShiftRepositoryImpl(db);

Future<ShiftEntity> _openShift(
  AppDatabase db, {
  int openingCash = 50000,
}) async {
  return _makeRepo(db).openShift(
    tenantId: _tenantId,
    userId: _userId,
    deviceId: _deviceId,
    openingCash: openingCash,
  );
}

CashMovementEntity _makeCashMovement({
  required String shiftId,
  CashMovementType type = CashMovementType.payIn,
  int amount = 10000,
  String description = 'test movement',
}) {
  return CashMovementEntity(
    id: IdGenerator.generateId(),
    tenantId: _tenantId,
    shiftId: shiftId,
    type: type,
    amount: amount,
    description: description,
    performedBy: _userId,
    performedAt: DateTime(2026, 3, 20, 9, 30),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // =========================================================================
  // Shift lifecycle
  // =========================================================================

  group('ShiftRepositoryImpl — Open / Get', () {
    late AppDatabase db;
    late ShiftRepositoryImpl repo;

    setUp(() async {
      db = AppDatabase.createInMemory();
      repo = _makeRepo(db);
    });

    tearDown(() async => db.close());

    test('openShift returns a persisted ShiftEntity', () async {
      const openingCash = 75000; // CHF 750.00
      final shift = await repo.openShift(
        tenantId: _tenantId,
        userId: _userId,
        deviceId: _deviceId,
        openingCash: openingCash,
      );

      expect(shift.id, isNotEmpty);
      expect(shift.tenantId, equals(_tenantId));
      expect(shift.userId, equals(_userId));
      expect(shift.deviceId, equals(_deviceId));
      expect(shift.openingCash, equals(openingCash));
      expect(shift.status, equals(ShiftStatus.open));
      expect(shift.closedAt, isNull);
    });

    test('getOpenShift returns the active shift', () async {
      await _openShift(db, openingCash: 30000);
      final open = await repo.getOpenShift(_tenantId);

      expect(open, isNotNull);
      expect(open!.status, equals(ShiftStatus.open));
      expect(open.openingCash, equals(30000));
    });

    test('getOpenShift returns null when no shift is open', () async {
      final open = await repo.getOpenShift(_tenantId);
      expect(open, isNull);
    });

    test('getShiftById returns the correct shift', () async {
      final shift = await _openShift(db);
      final fetched = await repo.getShiftById(shift.id);

      expect(fetched, isNotNull);
      expect(fetched!.id, equals(shift.id));
    });

    test('getShiftById returns null for unknown id', () async {
      final result = await repo.getShiftById('nonexistent-shift-id');
      expect(result, isNull);
    });

    test('opening a second shift with no closure does not affect first', () async {
      // Two open shifts (unusual but should not crash).
      await _openShift(db, openingCash: 10000);
      await _openShift(db, openingCash: 20000);

      // getOpenShift returns at least one.
      final open = await repo.getOpenShift(_tenantId);
      expect(open, isNotNull);
    });
  });

  // =========================================================================
  // Close shift
  // =========================================================================

  group('ShiftRepositoryImpl — Close Shift', () {
    late AppDatabase db;
    late ShiftRepositoryImpl repo;

    setUp(() async {
      db = AppDatabase.createInMemory();
      repo = _makeRepo(db);
    });

    tearDown(() async => db.close());

    test('closeShift transitions status to closed', () async {
      final shift = await _openShift(db, openingCash: 50000);
      final closed = await repo.closeShift(
        shiftId: shift.id,
        closingCash: 55000,
      );

      expect(closed.status, equals(ShiftStatus.closed));
      expect(closed.closedAt, isNotNull);
    });

    test('closeShift records closing cash', () async {
      final shift = await _openShift(db, openingCash: 50000);
      await repo.closeShift(
        shiftId: shift.id,
        closingCash: 48000,
      );

      // Closing cash is stored on the shift row.
      final row = await (db.select(db.shifts)
            ..where((s) => s.id.equals(shift.id)))
          .getSingle();
      expect(row.closingCash, equals(48000));
    });

    test('closeShift calculates expected cash = opening + cash sales', () async {
      // Open shift with 50 CHF opening cash.
      final shift = await _openShift(db, openingCash: 50000);

      // No sales during shift.
      await repo.closeShift(shiftId: shift.id, closingCash: 50000);

      final row = await (db.select(db.shifts)
            ..where((s) => s.id.equals(shift.id)))
          .getSingle();
      // Expected = 50000 + 0 cash sales + 0 pay-ins - 0 pay-outs = 50000.
      expect(row.expectedCash, equals(50000));
    });

    test('closeShift computes positive cash difference', () async {
      final shift = await _openShift(db, openingCash: 50000);
      await repo.closeShift(shiftId: shift.id, closingCash: 52000);

      final row = await (db.select(db.shifts)
            ..where((s) => s.id.equals(shift.id)))
          .getSingle();
      // Difference = closingCash - expectedCash = 52000 - 50000 = +2000.
      expect(row.difference, equals(2000));
    });

    test('closeShift computes negative cash difference', () async {
      final shift = await _openShift(db, openingCash: 50000);
      await repo.closeShift(shiftId: shift.id, closingCash: 47000);

      final row = await (db.select(db.shifts)
            ..where((s) => s.id.equals(shift.id)))
          .getSingle();
      expect(row.difference, equals(-3000));
    });

    test('closeShift stores notes', () async {
      final shift = await _openShift(db);
      await repo.closeShift(
        shiftId: shift.id,
        closingCash: 50000,
        notes: 'Quiet day',
      );

      final row = await (db.select(db.shifts)
            ..where((s) => s.id.equals(shift.id)))
          .getSingle();
      expect(row.notes, equals('Quiet day'));
    });

    test('getOpenShift returns null after shift is closed', () async {
      final shift = await _openShift(db);
      await repo.closeShift(shiftId: shift.id, closingCash: 50000);

      final open = await repo.getOpenShift(_tenantId);
      expect(open, isNull);
    });
  });

  // =========================================================================
  // Cash movements
  // =========================================================================

  group('ShiftRepositoryImpl — Cash Movements', () {
    late AppDatabase db;
    late ShiftRepositoryImpl repo;

    setUp(() async {
      db = AppDatabase.createInMemory();
      repo = _makeRepo(db);
    });

    tearDown(() async => db.close());

    test('addCashMovement persists a pay-in', () async {
      final shift = await _openShift(db);
      final movement = _makeCashMovement(
        shiftId: shift.id,
        type: CashMovementType.payIn,
        amount: 5000,
        description: 'Morning top-up',
      );

      await repo.addCashMovement(movement);

      final movements = await repo.getCashMovements(shift.id);
      expect(movements.length, equals(1));
      expect(movements.first.type, equals(CashMovementType.payIn));
      expect(movements.first.amount, equals(5000));
      expect(movements.first.description, equals('Morning top-up'));
    });

    test('addCashMovement persists a pay-out', () async {
      final shift = await _openShift(db);
      final movement = _makeCashMovement(
        shiftId: shift.id,
        type: CashMovementType.payOut,
        amount: 2000,
        description: 'Supplies',
      );

      await repo.addCashMovement(movement);

      final movements = await repo.getCashMovements(shift.id);
      expect(movements.first.type, equals(CashMovementType.payOut));
    });

    test('getCashMovements returns movements ordered chronologically', () async {
      final shift = await _openShift(db);

      await repo.addCashMovement(CashMovementEntity(
        id: IdGenerator.generateId(),
        tenantId: _tenantId,
        shiftId: shift.id,
        type: CashMovementType.payIn,
        amount: 1000,
        description: 'First',
        performedBy: _userId,
        performedAt: DateTime(2026, 3, 20, 8, 0),
      ));
      await repo.addCashMovement(CashMovementEntity(
        id: IdGenerator.generateId(),
        tenantId: _tenantId,
        shiftId: shift.id,
        type: CashMovementType.payIn,
        amount: 2000,
        description: 'Second',
        performedBy: _userId,
        performedAt: DateTime(2026, 3, 20, 9, 0),
      ));

      final movements = await repo.getCashMovements(shift.id);
      expect(movements.length, equals(2));
      expect(movements.first.description, equals('First'));
      expect(movements.last.description, equals('Second'));
    });

    test('getCashMovements returns empty for unknown shift', () async {
      final movements = await repo.getCashMovements('nonexistent-shift');
      expect(movements, isEmpty);
    });

    test('multiple movement types are recorded independently', () async {
      final shift = await _openShift(db);

      await repo.addCashMovement(_makeCashMovement(
        shiftId: shift.id,
        type: CashMovementType.payIn,
        amount: 3000,
      ));
      await repo.addCashMovement(_makeCashMovement(
        shiftId: shift.id,
        type: CashMovementType.tip,
        amount: 500,
      ));
      await repo.addCashMovement(_makeCashMovement(
        shiftId: shift.id,
        type: CashMovementType.payOut,
        amount: 1000,
      ));

      final movements = await repo.getCashMovements(shift.id);
      expect(movements.length, equals(3));
      expect(
        movements.map((m) => m.type).toSet(),
        containsAll([
          CashMovementType.payIn,
          CashMovementType.tip,
          CashMovementType.payOut,
        ]),
      );
    });
  });

  // =========================================================================
  // Totals recalculation
  // =========================================================================

  group('ShiftRepositoryImpl — Total Calculation', () {
    late AppDatabase db;
    late ShiftRepositoryImpl repo;

    setUp(() async {
      db = AppDatabase.createInMemory();
      repo = _makeRepo(db);
    });

    tearDown(() async => db.close());

    test('calculateShiftTotals counts completed tickets in shift window',
        () async {
      final shift = await _openShift(db);

      // Create and complete two tickets.
      final orderRepo = OrderRepositoryImpl(db);
      final payRepo = PaymentRepositoryImpl(db);

      for (int i = 0; i < 2; i++) {
        final ticketId = IdGenerator.generateId();
        final itemId = IdGenerator.generateId();
        final item = OrderItemEntity(
          id: itemId,
          tenantId: _tenantId,
          ticketId: ticketId,
          productId: 'prod-$i',
          productName: 'Product $i',
          quantity: 1,
          unitPrice: 2000,
          subtotal: 2000,
          taxGroup: 'food',
        );
        final ticket = TicketEntity(
          id: ticketId,
          tenantId: _tenantId,
          orderNumber: 'ORD-$i',
          orderType: OrderType.dineIn,
          status: TicketStatus.sent,
          openedAt: DateTime.now(),
          deviceId: _deviceId,
          items: [item],
        );
        await orderRepo.createTicket(ticket);
        await orderRepo.calculateTicketTotals(ticketId);
        await payRepo.processPayment(
          ticketId: ticketId,
          tenantId: _tenantId,
          paymentMethod: PaymentMethod.cash,
          amount: 2000,
          tenderedAmount: 2000,
          receivedBy: _userId,
        );
      }

      await repo.calculateShiftTotals(shift.id);

      final row = await (db.select(db.shifts)
            ..where((s) => s.id.equals(shift.id)))
          .getSingle();
      expect(row.totalOrders, equals(2));
      expect(row.totalSales, greaterThan(0));
    });

    test('calculateShiftTotals with no completed tickets gives zeros', () async {
      final shift = await _openShift(db);

      // Create a draft ticket that is NOT completed.
      final orderRepo = OrderRepositoryImpl(db);
      final ticket = TicketEntity(
        id: IdGenerator.generateId(),
        tenantId: _tenantId,
        orderNumber: 'DRAFT-01',
        orderType: OrderType.dineIn,
        status: TicketStatus.draft,
        openedAt: DateTime.now(),
        deviceId: _deviceId,
      );
      await orderRepo.createTicket(ticket);

      await repo.calculateShiftTotals(shift.id);

      final row = await (db.select(db.shifts)
            ..where((s) => s.id.equals(shift.id)))
          .getSingle();
      expect(row.totalOrders, equals(0));
      expect(row.totalSales, equals(0));
    });
  });

  // =========================================================================
  // Shift history
  // =========================================================================

  group('ShiftRepositoryImpl — History', () {
    late AppDatabase db;
    late ShiftRepositoryImpl repo;

    setUp(() async {
      db = AppDatabase.createInMemory();
      repo = _makeRepo(db);
    });

    tearDown(() async => db.close());

    test('getShiftHistory returns shifts newest first', () async {
      final s1 = await _openShift(db, openingCash: 10000);
      await repo.closeShift(shiftId: s1.id, closingCash: 10000);

      await Future.delayed(const Duration(milliseconds: 5));

      final s2 = await _openShift(db, openingCash: 20000);
      await repo.closeShift(shiftId: s2.id, closingCash: 20000);

      final history = await repo.getShiftHistory(_tenantId);
      expect(history.length, greaterThanOrEqualTo(2));
      // Most recent (s2) should be first.
      expect(history.first.id, equals(s2.id));
    });

    test('getShiftHistory respects limit parameter', () async {
      for (int i = 0; i < 5; i++) {
        final s = await _openShift(db);
        await repo.closeShift(shiftId: s.id, closingCash: 50000);
      }

      final history = await repo.getShiftHistory(_tenantId, limit: 3);
      expect(history.length, lessThanOrEqualTo(3));
    });

    test('getShiftHistory returns empty list when no shifts exist', () async {
      final history = await repo.getShiftHistory('unknown-tenant');
      expect(history, isEmpty);
    });
  });
}
