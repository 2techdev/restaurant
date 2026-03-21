/// Unit tests for ShiftEntity, CashMovementEntity, and ShiftSummaryEntity.
///
/// All tests are pure domain-logic tests with no database or widget
/// dependencies. They cover:
///   - ShiftEntity lifecycle helpers (isOpen, copyWith, equality)
///   - CashMovementEntity construction and equality
///   - ShiftSummaryEntity derived properties (cashSales, avgOrderCents,
///     durationLabel, reportPaymentBreakdown)
///   - PaymentBreakdownLine.labelFor mapping
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/features/shifts/domain/entities/shift_entity.dart';
import 'package:gastrocore_pos/features/shifts/domain/entities/shift_summary_entity.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ShiftEntity openShift({
  String id = 'shift-1',
  String userId = 'user-1',
  String deviceId = 'DEV-POS-01',
  int openingCash = 50000, // CHF 500.00
  int totalSales = 0,
  int totalOrders = 0,
  ShiftStatus status = ShiftStatus.open,
  DateTime? openedAt,
  DateTime? closedAt,
}) {
  return ShiftEntity(
    id: id,
    tenantId: 'tenant-1',
    userId: userId,
    deviceId: deviceId,
    openingCash: openingCash,
    totalSales: totalSales,
    totalOrders: totalOrders,
    status: status,
    openedAt: openedAt ?? DateTime(2026, 3, 20, 8, 0),
    closedAt: closedAt,
  );
}

ShiftSummaryEntity summaryWith({
  int totalSalesCents = 0,
  int totalOrders = 0,
  int openingCashCents = 50000,
  List<PaymentBreakdownLine> breakdown = const [],
  DateTime? openedAt,
  DateTime? closedAt,
}) {
  return ShiftSummaryEntity(
    shiftId: 'shift-1',
    cashierName: 'Anna Müller',
    deviceId: 'DEV-POS-01',
    totalSalesCents: totalSalesCents,
    totalOrders: totalOrders,
    openingCashCents: openingCashCents,
    paymentBreakdown: breakdown,
    openedAt: openedAt ?? DateTime(2026, 3, 20, 8, 0),
    closedAt: closedAt,
  );
}

// ---------------------------------------------------------------------------
// ShiftEntity tests
// ---------------------------------------------------------------------------

void main() {
  // =========================================================================
  // ShiftEntity.isOpen
  // =========================================================================

  group('ShiftEntity.isOpen', () {
    test('open status → isOpen is true', () {
      final shift = openShift(status: ShiftStatus.open);
      expect(shift.isOpen, true);
    });

    test('closing status → isOpen is false', () {
      final shift = openShift(status: ShiftStatus.closing);
      expect(shift.isOpen, false);
    });

    test('closed status → isOpen is false', () {
      final shift = openShift(status: ShiftStatus.closed);
      expect(shift.isOpen, false);
    });
  });

  // =========================================================================
  // ShiftEntity.copyWith
  // =========================================================================

  group('ShiftEntity.copyWith', () {
    test('changes only the specified field', () {
      final original = openShift(totalSales: 10000);
      final updated = original.copyWith(totalSales: 25000);

      expect(updated.totalSales, 25000);
      expect(updated.id, original.id);
      expect(updated.userId, original.userId);
      expect(updated.openingCash, original.openingCash);
    });

    test('can set nullable fields to null via lambda', () {
      final withNotes = openShift().copyWith(
        notes: () => 'Some notes',
      );
      expect(withNotes.notes, 'Some notes');

      final cleared = withNotes.copyWith(notes: () => null);
      expect(cleared.notes, isNull);
    });

    test('closing cash and difference can be set', () {
      final shift = openShift(totalSales: 100000);
      final closed = shift.copyWith(
        closingCash: () => 150000,
        expectedCash: () => 150000,
        difference: () => 0,
        status: ShiftStatus.closed,
        closedAt: () => DateTime(2026, 3, 20, 16, 0),
      );

      expect(closed.closingCash, 150000);
      expect(closed.difference, 0);
      expect(closed.status, ShiftStatus.closed);
      expect(closed.isOpen, false);
    });
  });

  // =========================================================================
  // ShiftEntity equality
  // =========================================================================

  group('ShiftEntity equality', () {
    test('identical shifts are equal', () {
      final a = openShift();
      final b = openShift();
      expect(a, equals(b));
    });

    test('shifts with different IDs are not equal', () {
      final a = openShift(id: 'shift-1');
      final b = openShift(id: 'shift-2');
      expect(a == b, false);
    });

    test('shifted status changes equality', () {
      final open = openShift(status: ShiftStatus.open);
      final closed = open.copyWith(status: ShiftStatus.closed);
      expect(open == closed, false);
    });
  });

  // =========================================================================
  // CashMovementEntity
  // =========================================================================

  group('CashMovementEntity', () {
    test('construction stores all fields correctly', () {
      final now = DateTime(2026, 3, 20, 10, 0);
      final m = CashMovementEntity(
        id: 'cm-1',
        tenantId: 'tenant-1',
        shiftId: 'shift-1',
        type: CashMovementType.payIn,
        amount: 20000, // CHF 200
        description: 'Change float top-up',
        performedBy: 'user-1',
        performedAt: now,
      );

      expect(m.type, CashMovementType.payIn);
      expect(m.amount, 20000);
      expect(m.description, 'Change float top-up');
    });

    test('equality holds for identical instances', () {
      final now = DateTime(2026, 3, 20, 10, 0);
      final a = CashMovementEntity(
        id: 'cm-1',
        tenantId: 'tenant-1',
        shiftId: 'shift-1',
        type: CashMovementType.payOut,
        amount: 5000,
        performedBy: 'user-1',
        performedAt: now,
      );
      final b = a.copyWith();
      expect(a, equals(b));
    });

    test('different types are not equal', () {
      final now = DateTime.now();
      final a = CashMovementEntity(
        id: 'cm-1',
        tenantId: 'tenant-1',
        shiftId: 'shift-1',
        type: CashMovementType.tip,
        amount: 500,
        performedBy: 'user-1',
        performedAt: now,
      );
      final b = a.copyWith(type: CashMovementType.expense);
      expect(a == b, false);
    });
  });

  // =========================================================================
  // ShiftSummaryEntity derived properties
  // =========================================================================

  group('ShiftSummaryEntity.cashSales', () {
    test('sums only cash payment lines', () {
      final summary = summaryWith(
        totalSalesCents: 30000,
        breakdown: [
          const PaymentBreakdownLine(
              method: 'cash', label: 'Bar', amount: 20000, count: 3),
          const PaymentBreakdownLine(
              method: 'credit_card', label: 'Kreditkarte', amount: 10000, count: 1),
        ],
      );
      expect(summary.cashSales, 20000);
      expect(summary.cardSales, 10000);
    });

    test('returns zero when no payments', () {
      final summary = summaryWith(totalSalesCents: 0);
      expect(summary.cashSales, 0);
      expect(summary.cardSales, 0);
    });
  });

  group('ShiftSummaryEntity.avgOrderCents', () {
    test('calculates average correctly', () {
      final summary = summaryWith(
        totalSalesCents: 30000,
        totalOrders: 3,
      );
      expect(summary.avgOrderCents, 10000); // CHF 100.00 average
    });

    test('returns zero when no orders', () {
      final summary = summaryWith(totalSalesCents: 0, totalOrders: 0);
      expect(summary.avgOrderCents, 0);
    });

    test('rounds fractional averages', () {
      // 10000 / 3 = 3333.33... → 3333
      final summary =
          summaryWith(totalSalesCents: 10000, totalOrders: 3);
      expect(summary.avgOrderCents, 3333);
    });
  });

  group('ShiftSummaryEntity.durationLabel', () {
    test('shows hours and minutes when >= 1 hour', () {
      final summary = summaryWith(
        openedAt: DateTime(2026, 3, 20, 8, 0),
        closedAt: DateTime(2026, 3, 20, 15, 32),
      );
      expect(summary.durationLabel, '7h 32m');
    });

    test('shows only minutes when < 1 hour', () {
      final summary = summaryWith(
        openedAt: DateTime(2026, 3, 20, 8, 0),
        closedAt: DateTime(2026, 3, 20, 8, 45),
      );
      expect(summary.durationLabel, '45m');
    });

    test('uses now when shift is still open (closedAt is null)', () {
      // The shift was opened 0 seconds ago — duration < 1 minute.
      final now = DateTime.now();
      final summary = summaryWith(openedAt: now);
      // Duration label should be '0m' since just opened.
      expect(summary.durationLabel, '0m');
    });
  });

  group('ShiftSummaryEntity.reportPaymentBreakdown', () {
    test('maps raw methods to report labels', () {
      final summary = summaryWith(
        breakdown: [
          const PaymentBreakdownLine(
              method: 'cash', label: 'Bar', amount: 15000, count: 2),
          const PaymentBreakdownLine(
              method: 'credit_card', label: 'Kreditkarte', amount: 5000, count: 1),
          const PaymentBreakdownLine(
              method: 'twint', label: 'TWINT', amount: 3000, count: 1),
        ],
      );

      final report = summary.reportPaymentBreakdown;
      expect(report['Bar'], 15000);
      expect(report['Kreditkarte'], 5000);
      expect(report['TWINT'], 3000);
    });

    test('merges duplicate method labels', () {
      // Two cash entries (shouldn't happen in practice but must be safe).
      final summary = summaryWith(
        breakdown: [
          const PaymentBreakdownLine(
              method: 'cash', label: 'Bar', amount: 10000, count: 1),
          const PaymentBreakdownLine(
              method: 'cash', label: 'Bar', amount: 5000, count: 1),
        ],
      );

      expect(summary.reportPaymentBreakdown['Bar'], 15000);
    });
  });

  // =========================================================================
  // PaymentBreakdownLine.labelFor
  // =========================================================================

  group('PaymentBreakdownLine.labelFor', () {
    test('maps cash to Bar', () {
      expect(PaymentBreakdownLine.labelFor('cash'), 'Bar');
    });

    test('maps credit_card to Kreditkarte', () {
      expect(PaymentBreakdownLine.labelFor('credit_card'), 'Kreditkarte');
    });

    test('maps debit_card to Debitkarte', () {
      expect(PaymentBreakdownLine.labelFor('debit_card'), 'Debitkarte');
    });

    test('maps twint to TWINT', () {
      expect(PaymentBreakdownLine.labelFor('twint'), 'TWINT');
    });

    test('unknown methods fall back to Sonstiges', () {
      expect(PaymentBreakdownLine.labelFor('crypto'), 'Sonstiges');
      expect(PaymentBreakdownLine.labelFor(''), 'Sonstiges');
    });
  });
}
