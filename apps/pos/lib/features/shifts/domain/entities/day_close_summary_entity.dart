/// Day-close summary entity.
///
/// One [DayCloseSummaryEntity] is created per closed shift. It captures
/// the cashier's denomination count, expected vs actual cash, and a
/// revenue / payment snapshot for historical reporting.
library;

// ---------------------------------------------------------------------------
// CHF denominations
// ---------------------------------------------------------------------------

/// All valid Swiss Franc denominations used in a POS cash count.
///
/// Values are in cents. Coins: 0.05–5.00. Notes: 10–1000.
abstract final class ChfDenomination {
  /// Coin denominations in cents, lowest to highest.
  static const List<int> coins = [5, 10, 20, 50, 100, 200, 500];

  /// Note denominations in cents, lowest to highest.
  static const List<int> notes = [1000, 2000, 5000, 10000, 20000, 100000];

  /// All denominations: coins first, then notes.
  static const List<int> all = [...coins, ...notes];

  /// Human-readable label for a denomination given in cents.
  ///
  /// Examples:
  /// - 5 → "CHF 0.05"
  /// - 100 → "CHF 1.00"
  /// - 1000 → "CHF 10.00"
  static String label(int cents) {
    final isNeg = cents < 0;
    final abs = cents.abs();
    final whole = abs ~/ 100;
    final frac = (abs % 100).toString().padLeft(2, '0');
    return '${isNeg ? '-' : ''}CHF $whole.$frac';
  }
}

// ---------------------------------------------------------------------------
// DayCloseSummaryEntity
// ---------------------------------------------------------------------------

/// Immutable snapshot of a closed shift used for historical reporting.
class DayCloseSummaryEntity {
  final String id;
  final String tenantId;

  /// The shift that was closed.
  final String shiftId;

  /// Device / terminal identifier.
  final String deviceId;

  /// Cashier name at the time of close.
  final String cashierName;

  // -------------------------------------------------------------------------
  // Revenue snapshot
  // -------------------------------------------------------------------------

  /// Total revenue processed during the shift, in cents.
  final int totalRevenueCents;

  /// Number of completed orders (covers) during the shift.
  final int totalOrders;

  /// Average order value in cents.
  final int avgOrderCents;

  // -------------------------------------------------------------------------
  // Cash reconciliation
  // -------------------------------------------------------------------------

  /// Cash counted by the cashier from the denomination breakdown, in cents.
  final int countedCashCents;

  /// System-calculated expected cash, in cents.
  final int expectedCashCents;

  /// Discrepancy = counted − expected (positive = over, negative = short).
  final int discrepancyCents;

  // -------------------------------------------------------------------------
  // Breakdowns
  // -------------------------------------------------------------------------

  /// Denomination breakdown entered by the cashier.
  /// Key = denomination in cents, value = piece count.
  final Map<int, int> denominationBreakdown;

  /// Payment method breakdown for this shift.
  /// Key = raw DB payment method (e.g. 'cash', 'credit_card'), value = total cents.
  final Map<String, int> paymentBreakdown;

  // -------------------------------------------------------------------------
  // Timestamps
  // -------------------------------------------------------------------------

  final DateTime closedAt;
  final DateTime createdAt;

  const DayCloseSummaryEntity({
    required this.id,
    required this.tenantId,
    required this.shiftId,
    required this.deviceId,
    required this.cashierName,
    required this.totalRevenueCents,
    required this.totalOrders,
    required this.avgOrderCents,
    required this.countedCashCents,
    required this.expectedCashCents,
    required this.discrepancyCents,
    required this.denominationBreakdown,
    required this.paymentBreakdown,
    required this.closedAt,
    required this.createdAt,
  });

  // -------------------------------------------------------------------------
  // Derived helpers
  // -------------------------------------------------------------------------

  /// Whether the discrepancy is within the acceptable CHF 5.00 threshold.
  bool get isWithinThreshold => discrepancyCents.abs() <= 500;

  /// Formatted discrepancy label, e.g. "+CHF 3.20" or "-CHF 12.50".
  String get discrepancyLabel {
    final isNeg = discrepancyCents < 0;
    final abs = discrepancyCents.abs();
    final whole = abs ~/ 100;
    final frac = (abs % 100).toString().padLeft(2, '0');
    return '${isNeg ? '-' : '+'}CHF $whole.$frac';
  }

  // -------------------------------------------------------------------------
  // Equality
  // -------------------------------------------------------------------------

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DayCloseSummaryEntity &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          tenantId == other.tenantId &&
          shiftId == other.shiftId;

  @override
  int get hashCode => Object.hash(id, tenantId, shiftId);

  @override
  String toString() =>
      'DayCloseSummaryEntity(shiftId: $shiftId, revenue: $totalRevenueCents¢, '
      'discrepancy: $discrepancyCents¢)';
}
