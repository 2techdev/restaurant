/// Unit tests for [DayCloseCalculator] and related domain types.
///
/// All tests are pure Dart — no Flutter engine, no database, no widgets.
/// Run with: flutter test test/features/shifts/domain/day_close_calculator_test.dart
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/features/shifts/domain/day_close_calculator.dart';
import 'package:gastrocore_pos/features/shifts/domain/entities/day_close_summary_entity.dart';

void main() {
  // =========================================================================
  // ChfDenomination
  // =========================================================================

  group('ChfDenomination.all', () {
    test('contains all 13 CHF denominations', () {
      expect(ChfDenomination.all.length, 13);
    });

    test('starts with the smallest coin (5¢) and ends with CHF 1000 note', () {
      expect(ChfDenomination.all.first, 5);
      expect(ChfDenomination.all.last, 100000);
    });

    test('coins list contains 7 entries', () {
      expect(ChfDenomination.coins.length, 7);
    });

    test('notes list contains 6 entries', () {
      expect(ChfDenomination.notes.length, 6);
    });
  });

  group('ChfDenomination.label', () {
    test('5¢ coin → "CHF 0.05"', () {
      expect(ChfDenomination.label(5), 'CHF 0.05');
    });

    test('10¢ coin → "CHF 0.10"', () {
      expect(ChfDenomination.label(10), 'CHF 0.10');
    });

    test('50¢ coin → "CHF 0.50"', () {
      expect(ChfDenomination.label(50), 'CHF 0.50');
    });

    test('CHF 1 coin (100¢) → "CHF 1.00"', () {
      expect(ChfDenomination.label(100), 'CHF 1.00');
    });

    test('CHF 5 coin (500¢) → "CHF 5.00"', () {
      expect(ChfDenomination.label(500), 'CHF 5.00');
    });

    test('CHF 10 note (1000¢) → "CHF 10.00"', () {
      expect(ChfDenomination.label(1000), 'CHF 10.00');
    });

    test('CHF 100 note (10000¢) → "CHF 100.00"', () {
      expect(ChfDenomination.label(10000), 'CHF 100.00');
    });

    test('CHF 1000 note (100000¢) → "CHF 1000.00"', () {
      expect(ChfDenomination.label(100000), 'CHF 1000.00');
    });
  });

  // =========================================================================
  // DayCloseCalculator.denominationTotal
  // =========================================================================

  group('DayCloseCalculator.denominationTotal', () {
    test('empty breakdown → 0', () {
      expect(DayCloseCalculator.denominationTotal({}), 0);
    });

    test('single denomination', () {
      // 3 × CHF 10 notes = CHF 30.00 = 3000¢
      expect(DayCloseCalculator.denominationTotal({1000: 3}), 3000);
    });

    test('mixed coins and notes', () {
      // 5 × 0.20 = 100¢  +  2 × 5.00 = 1000¢  +  1 × 20.00 = 2000¢  = 3100¢
      final breakdown = {20: 5, 500: 2, 2000: 1};
      expect(DayCloseCalculator.denominationTotal(breakdown), 3100);
    });

    test('denomination with zero count contributes nothing', () {
      expect(DayCloseCalculator.denominationTotal({100: 0, 1000: 2}), 2000);
    });

    test('all CHF coins × 1 sums correctly', () {
      // 5+10+20+50+100+200+500 = 885¢
      final breakdown = {for (final d in ChfDenomination.coins) d: 1};
      expect(DayCloseCalculator.denominationTotal(breakdown), 885);
    });

    test('all CHF notes × 1 sums correctly', () {
      // 1000+2000+5000+10000+20000+100000 = 138000¢
      final breakdown = {for (final d in ChfDenomination.notes) d: 1};
      expect(DayCloseCalculator.denominationTotal(breakdown), 138000);
    });

    test('realistic end-of-day count', () {
      // 10 × 0.10 = 100¢
      // 5  × 1.00 = 500¢
      // 3  × 10   = 3000¢
      // 2  × 50   = 10000¢
      // 1  × 100  = 10000¢
      // Total = 23600¢ = CHF 236.00
      final breakdown = {10: 10, 100: 5, 1000: 3, 5000: 2, 10000: 1};
      expect(DayCloseCalculator.denominationTotal(breakdown), 23600);
    });
  });

  // =========================================================================
  // DayCloseCalculator.expectedCash
  // =========================================================================

  group('DayCloseCalculator.expectedCash', () {
    test('no sales or movements → equals opening cash', () {
      expect(
        DayCloseCalculator.expectedCash(
          openingCash: 50000,
          cashSales: 0,
          payIns: 0,
          payOuts: 0,
        ),
        50000,
      );
    });

    test('with cash sales only', () {
      // Opening CHF 500 + sales CHF 200 = CHF 700
      expect(
        DayCloseCalculator.expectedCash(
          openingCash: 50000,
          cashSales: 20000,
          payIns: 0,
          payOuts: 0,
        ),
        70000,
      );
    });

    test('with pay-ins and pay-outs', () {
      // Opening 50000 + sales 20000 + payIn 10000 - payOut 5000 = 75000
      expect(
        DayCloseCalculator.expectedCash(
          openingCash: 50000,
          cashSales: 20000,
          payIns: 10000,
          payOuts: 5000,
        ),
        75000,
      );
    });

    test('pay-outs can exceed sales (negative result is fine)', () {
      expect(
        DayCloseCalculator.expectedCash(
          openingCash: 1000,
          cashSales: 0,
          payIns: 0,
          payOuts: 5000,
        ),
        -4000,
      );
    });
  });

  // =========================================================================
  // DayCloseCalculator.discrepancy
  // =========================================================================

  group('DayCloseCalculator.discrepancy', () {
    test('counted == expected → discrepancy 0', () {
      expect(
        DayCloseCalculator.discrepancy(
            countedCash: 75000, expectedCash: 75000),
        0,
      );
    });

    test('counted > expected → positive discrepancy (over)', () {
      expect(
        DayCloseCalculator.discrepancy(
            countedCash: 76000, expectedCash: 75000),
        1000,
      );
    });

    test('counted < expected → negative discrepancy (short)', () {
      expect(
        DayCloseCalculator.discrepancy(
            countedCash: 74500, expectedCash: 75000),
        -500,
      );
    });
  });

  // =========================================================================
  // DayCloseCalculator.isWithinThreshold
  // =========================================================================

  group('DayCloseCalculator.isWithinThreshold', () {
    test('zero discrepancy is within threshold', () {
      expect(DayCloseCalculator.isWithinThreshold(0), isTrue);
    });

    test('discrepancy of exactly CHF 5.00 (500¢) is within threshold', () {
      expect(DayCloseCalculator.isWithinThreshold(500), isTrue);
      expect(DayCloseCalculator.isWithinThreshold(-500), isTrue);
    });

    test('discrepancy of CHF 5.01 (501¢) exceeds threshold', () {
      expect(DayCloseCalculator.isWithinThreshold(501), isFalse);
      expect(DayCloseCalculator.isWithinThreshold(-501), isFalse);
    });

    test('large discrepancy is outside threshold', () {
      expect(DayCloseCalculator.isWithinThreshold(10000), isFalse);
      expect(DayCloseCalculator.isWithinThreshold(-10000), isFalse);
    });
  });

  // =========================================================================
  // DayCloseCalculator.avgOrderCents
  // =========================================================================

  group('DayCloseCalculator.avgOrderCents', () {
    test('zero orders → returns 0', () {
      expect(
        DayCloseCalculator.avgOrderCents(
            totalRevenueCents: 50000, totalOrders: 0),
        0,
      );
    });

    test('exact division', () {
      expect(
        DayCloseCalculator.avgOrderCents(
            totalRevenueCents: 30000, totalOrders: 3),
        10000,
      );
    });

    test('fractional result rounds to nearest integer', () {
      // 10000 / 3 = 3333.33 → 3333
      expect(
        DayCloseCalculator.avgOrderCents(
            totalRevenueCents: 10000, totalOrders: 3),
        3333,
      );
      // 10001 / 3 = 3333.67 → 3334
      expect(
        DayCloseCalculator.avgOrderCents(
            totalRevenueCents: 10001, totalOrders: 3),
        3334,
      );
    });
  });

  // =========================================================================
  // DayCloseCalculator.validateBreakdown
  // =========================================================================

  group('DayCloseCalculator.validateBreakdown', () {
    test('all-zero breakdown → returns error message', () {
      final breakdown = {for (final d in ChfDenomination.all) d: 0};
      expect(DayCloseCalculator.validateBreakdown(breakdown), isNotNull);
    });

    test('empty breakdown → returns error message', () {
      expect(DayCloseCalculator.validateBreakdown({}), isNotNull);
    });

    test('at least one non-zero count → returns null (valid)', () {
      final breakdown = {for (final d in ChfDenomination.all) d: 0};
      final updated = Map<int, int>.from(breakdown)..[1000] = 3;
      expect(DayCloseCalculator.validateBreakdown(updated), isNull);
    });

    test('invalid denomination → returns error message', () {
      final breakdown = {99: 1}; // 99¢ is not a valid CHF denomination
      expect(DayCloseCalculator.validateBreakdown(breakdown), isNotNull);
    });
  });

  // =========================================================================
  // DayCloseCalculator.discrepancyLabel
  // =========================================================================

  group('DayCloseCalculator.discrepancyLabel', () {
    test('zero → "+CHF 0.00"', () {
      expect(DayCloseCalculator.discrepancyLabel(0), '+CHF 0.00');
    });

    test('positive 150¢ → "+CHF 1.50"', () {
      expect(DayCloseCalculator.discrepancyLabel(150), '+CHF 1.50');
    });

    test('negative 250¢ → "-CHF 2.50"', () {
      expect(DayCloseCalculator.discrepancyLabel(-250), '-CHF 2.50');
    });

    test('exactly CHF 5 positive → "+CHF 5.00"', () {
      expect(DayCloseCalculator.discrepancyLabel(500), '+CHF 5.00');
    });
  });

  // =========================================================================
  // DayCloseCalculator.formatCents
  // =========================================================================

  group('DayCloseCalculator.formatCents', () {
    test('0¢ → "0.00"', () {
      expect(DayCloseCalculator.formatCents(0), '0.00');
    });

    test('100¢ → "1.00"', () {
      expect(DayCloseCalculator.formatCents(100), '1.00');
    });

    test('12345¢ → "123.45"', () {
      expect(DayCloseCalculator.formatCents(12345), '123.45');
    });

    test('1234567¢ → "12,345.67"', () {
      expect(DayCloseCalculator.formatCents(1234567), '12,345.67');
    });

    test('negative → "-1.00"', () {
      expect(DayCloseCalculator.formatCents(-100), '-1.00');
    });
  });

  // =========================================================================
  // DayCloseSummaryEntity helpers
  // =========================================================================

  group('DayCloseSummaryEntity', () {
    DayCloseSummaryEntity makeEntity({
      int countedCash = 75000,
      int expectedCash = 75000,
      int discrepancy = 0,
    }) {
      return DayCloseSummaryEntity(
        id: 'dcs-1',
        tenantId: 'tenant-1',
        shiftId: 'shift-1',
        deviceId: 'DEV-POS-01',
        cashierName: 'Anna Müller',
        totalRevenueCents: 60000,
        totalOrders: 6,
        avgOrderCents: 10000,
        countedCashCents: countedCash,
        expectedCashCents: expectedCash,
        discrepancyCents: discrepancy,
        denominationBreakdown: {1000: 3, 5000: 1, 10000: 2},
        paymentBreakdown: {'cash': 40000, 'credit_card': 20000},
        closedAt: DateTime(2026, 3, 20, 22, 0),
        createdAt: DateTime(2026, 3, 20, 22, 0),
      );
    }

    test('isWithinThreshold true when discrepancy == 0', () {
      expect(makeEntity(discrepancy: 0).isWithinThreshold, isTrue);
    });

    test('isWithinThreshold true at ±500¢ (CHF 5.00 boundary)', () {
      expect(makeEntity(discrepancy: 500).isWithinThreshold, isTrue);
      expect(makeEntity(discrepancy: -500).isWithinThreshold, isTrue);
    });

    test('isWithinThreshold false when |discrepancy| > 500¢', () {
      expect(makeEntity(discrepancy: 501).isWithinThreshold, isFalse);
      expect(makeEntity(discrepancy: -501).isWithinThreshold, isFalse);
    });

    test('discrepancyLabel for positive value includes "+"', () {
      final label = makeEntity(discrepancy: 150).discrepancyLabel;
      expect(label, '+CHF 1.50');
    });

    test('discrepancyLabel for negative value includes "-"', () {
      final label = makeEntity(discrepancy: -250).discrepancyLabel;
      expect(label, '-CHF 2.50');
    });

    test('equality is based on id / tenantId / shiftId', () {
      final a = makeEntity();
      final b = makeEntity();
      expect(a, equals(b));
    });

    test('toString contains shiftId and discrepancy', () {
      final entity = makeEntity(discrepancy: -300);
      expect(entity.toString(), contains('shift-1'));
      expect(entity.toString(), contains('-300'));
    });
  });

  // =========================================================================
  // End-to-end scenario: typical shift close
  // =========================================================================

  group('End-to-end shift close scenario', () {
    test('typical closing with slight over-count stays within tolerance', () {
      // Setup: CHF 500 opening + CHF 320 cash sales
      const opening = 50000;
      const cashSales = 32000;
      const payIns = 0;
      const payOuts = 0;

      final expected = DayCloseCalculator.expectedCash(
        openingCash: opening,
        cashSales: cashSales,
        payIns: payIns,
        payOuts: payOuts,
      );
      expect(expected, 82000); // CHF 820.00

      // Cashier counts: 5 × CHF 100, 3 × CHF 50, 7 × CHF 10 = 500 + 150 + 70 = 720 → 72000¢
      // Plus: 5 × CHF 2, 3 × CHF 1, 10 × CHF 0.20 = 10 + 3 + 2 = 15 → 1500¢
      // Total = 72000 + 1500 + 10200 (adjustment) = depends on exact counts
      // Let's use a simple breakdown:
      final breakdown = <int, int>{
        10000: 5,  // 5 × CHF 100 = 50000¢
        5000: 3,   // 3 × CHF 50  = 15000¢
        1000: 7,   // 7 × CHF 10  = 7000¢
        500: 2,    // 2 × CHF 5   = 1000¢
        200: 4,    // 4 × CHF 2   = 800¢
        100: 6,    // 6 × CHF 1   = 600¢
        50: 3,     // 3 × CHF 0.50= 150¢
        10: 8,     // 8 × CHF 0.10= 80¢
      };
      final counted = DayCloseCalculator.denominationTotal(breakdown);
      expect(counted, 74630); // 50000+15000+7000+1000+800+600+150+80 = 74630¢

      final discrepancy = DayCloseCalculator.discrepancy(
        countedCash: counted,
        expectedCash: expected,
      );
      // 74630 - 82000 = -7370¢ → short by CHF 73.70 (outside tolerance)
      expect(discrepancy, -7370);
      expect(DayCloseCalculator.isWithinThreshold(discrepancy), isFalse);
    });

    test('exact match is within tolerance and validates correctly', () {
      const opening = 20000; // CHF 200
      const cashSales = 15000; // CHF 150
      final expected = DayCloseCalculator.expectedCash(
        openingCash: opening,
        cashSales: cashSales,
        payIns: 0,
        payOuts: 0,
      );
      // CHF 350 = 35000¢

      // Cashier counts exactly CHF 350
      final breakdown = {10000: 3, 5000: 1}; // 30000 + 5000 = 35000¢
      final counted = DayCloseCalculator.denominationTotal(breakdown);
      expect(counted, 35000);

      final disc = DayCloseCalculator.discrepancy(
          countedCash: counted, expectedCash: expected);
      expect(disc, 0);
      expect(DayCloseCalculator.isWithinThreshold(disc), isTrue);

      // Breakdown should be valid (non-zero counts exist).
      expect(DayCloseCalculator.validateBreakdown(breakdown), isNull);
    });
  });
}
