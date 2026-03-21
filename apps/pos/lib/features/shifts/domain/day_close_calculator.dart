/// Pure-logic day-close calculation utilities.
///
/// All methods are static and free of Flutter / Riverpod dependencies so
/// they can be exercised in plain Dart unit tests without a test harness.
library;

import 'package:gastrocore_pos/features/shifts/domain/entities/day_close_summary_entity.dart';

// ---------------------------------------------------------------------------
// DayCloseCalculator
// ---------------------------------------------------------------------------

/// Stateless calculator for shift-close reconciliation.
abstract final class DayCloseCalculator {
  /// CHF 5.00 in cents — the maximum acceptable cash discrepancy.
  static const int discrepancyThresholdCents = 500;

  // -------------------------------------------------------------------------
  // Denomination total
  // -------------------------------------------------------------------------

  /// Sum of all denominations × counts in [breakdown].
  ///
  /// [breakdown] maps denomination-in-cents → piece count.
  /// All counts and denominations must be non-negative.
  static int denominationTotal(Map<int, int> breakdown) {
    var total = 0;
    for (final entry in breakdown.entries) {
      assert(entry.key >= 0, 'Denomination must be non-negative');
      assert(entry.value >= 0, 'Count must be non-negative');
      total += entry.key * entry.value;
    }
    return total;
  }

  // -------------------------------------------------------------------------
  // Expected cash
  // -------------------------------------------------------------------------

  /// Calculate expected cash at shift close.
  ///
  /// Formula:
  ///   expected = openingCash + cashSales + payIns − payOuts
  ///
  /// All values in cents.
  static int expectedCash({
    required int openingCash,
    required int cashSales,
    required int payIns,
    required int payOuts,
  }) {
    assert(openingCash >= 0, 'Opening cash must be non-negative');
    assert(cashSales >= 0, 'Cash sales must be non-negative');
    assert(payIns >= 0, 'Pay-ins must be non-negative');
    assert(payOuts >= 0, 'Pay-outs must be non-negative');
    return openingCash + cashSales + payIns - payOuts;
  }

  // -------------------------------------------------------------------------
  // Discrepancy
  // -------------------------------------------------------------------------

  /// Calculate the cash discrepancy.
  ///
  /// Result = countedCash − expectedCash.
  /// Positive value → cash over; negative value → cash short.
  static int discrepancy({
    required int countedCash,
    required int expectedCash,
  }) =>
      countedCash - expectedCash;

  // -------------------------------------------------------------------------
  // Threshold check
  // -------------------------------------------------------------------------

  /// Returns `true` if |[discrepancyCents]| ≤ [discrepancyThresholdCents].
  static bool isWithinThreshold(int discrepancyCents) =>
      discrepancyCents.abs() <= discrepancyThresholdCents;

  // -------------------------------------------------------------------------
  // Average order value
  // -------------------------------------------------------------------------

  /// Average order value in cents; 0 if [totalOrders] == 0.
  static int avgOrderCents({
    required int totalRevenueCents,
    required int totalOrders,
  }) {
    if (totalOrders <= 0) return 0;
    return (totalRevenueCents / totalOrders).round();
  }

  // -------------------------------------------------------------------------
  // Validation
  // -------------------------------------------------------------------------

  /// Returns a non-null error message if the denomination breakdown is invalid,
  /// or `null` if the breakdown is ready to submit.
  ///
  /// Rules:
  /// - At least one denomination must have a count > 0.
  /// - Every denomination in [breakdown] must be a recognised CHF denomination.
  static String? validateBreakdown(Map<int, int> breakdown) {
    if (breakdown.isEmpty || breakdown.values.every((c) => c == 0)) {
      return 'Please count the cash before closing.';
    }
    for (final denom in breakdown.keys) {
      if (!ChfDenomination.all.contains(denom)) {
        return 'Invalid denomination: $denom¢';
      }
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Discrepancy label
  // -------------------------------------------------------------------------

  /// Human-readable discrepancy label, e.g. "+CHF 3.20" or "-CHF 12.50".
  static String discrepancyLabel(int cents) {
    final isNeg = cents < 0;
    final abs = cents.abs();
    final whole = abs ~/ 100;
    final frac = (abs % 100).toString().padLeft(2, '0');
    return '${isNeg ? '-' : '+'}CHF $whole.$frac';
  }

  // -------------------------------------------------------------------------
  // Currency formatting
  // -------------------------------------------------------------------------

  /// Format [cents] as a CHF amount string, e.g. "1,234.50".
  static String formatCents(int cents) {
    final isNeg = cents < 0;
    final abs = cents.abs();
    final whole = abs ~/ 100;
    final frac = (abs % 100).toString().padLeft(2, '0');
    final s = whole.toString();
    final parts = <String>[];
    for (var i = s.length; i > 0; i -= 3) {
      final start = i - 3 < 0 ? 0 : i - 3;
      parts.insert(0, s.substring(start, i));
    }
    return '${isNeg ? '-' : ''}${parts.join(',')}.$frac';
  }
}
