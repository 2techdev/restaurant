/// Shift summary entity with payment method breakdown.
///
/// Used in the shift close screen, history list, and Z-report printing to
/// display how sales were distributed across payment methods (cash, card, etc.)
library;

// ---------------------------------------------------------------------------
// PaymentBreakdownLine
// ---------------------------------------------------------------------------

/// A single payment method contribution within a shift.
class PaymentBreakdownLine {
  /// Raw DB payment method key (e.g. 'cash', 'credit_card', 'debit_card').
  final String method;

  /// Display label suitable for the UI and receipt (e.g. 'Bar', 'Karte').
  final String label;

  /// Total amount collected via this method, in cents.
  final int amount;

  /// Number of transactions using this method.
  final int count;

  const PaymentBreakdownLine({
    required this.method,
    required this.label,
    required this.amount,
    required this.count,
  });

  /// Maps a raw DB payment method string to a human-readable Swiss German label.
  static String labelFor(String method) {
    return switch (method) {
      'cash' => 'Bar',
      'credit_card' => 'Kreditkarte',
      'debit_card' => 'Debitkarte',
      'twint' => 'TWINT',
      'voucher' => 'Gutschein',
      _ => 'Sonstiges',
    };
  }

  /// Maps a raw DB payment method string to its Z-report key.
  ///
  /// The [ReportBuilder] uses the label as the map key in [ShiftReportData.paymentBreakdown].
  static String reportKeyFor(String method) => labelFor(method);

  @override
  String toString() => 'PaymentBreakdownLine($label: $amount¢ ×$count)';
}

// ---------------------------------------------------------------------------
// ShiftSummaryEntity
// ---------------------------------------------------------------------------

/// Full shift summary used in the close dialog, history list, and printing.
class ShiftSummaryEntity {
  final String shiftId;

  /// Name of the cashier who owned this shift.
  final String cashierName;

  /// Device identifier (terminal / register).
  final String deviceId;

  /// Total sales processed during the shift, in cents.
  final int totalSalesCents;

  /// Total number of completed orders.
  final int totalOrders;

  /// Cash in drawer at shift open, in cents.
  final int openingCashCents;

  /// Cash counted at shift close, in cents. Null while shift is open.
  final int? closingCashCents;

  /// System-expected cash (opening + cash sales + pay-ins - pay-outs), in cents.
  final int? expectedCashCents;

  /// Difference between counted and expected cash, in cents.
  /// Positive = over; negative = short.
  final int? differenceCents;

  /// Breakdown of sales by payment method.
  final List<PaymentBreakdownLine> paymentBreakdown;

  final DateTime openedAt;
  final DateTime? closedAt;

  const ShiftSummaryEntity({
    required this.shiftId,
    required this.cashierName,
    required this.deviceId,
    required this.totalSalesCents,
    required this.totalOrders,
    required this.openingCashCents,
    this.closingCashCents,
    this.expectedCashCents,
    this.differenceCents,
    required this.paymentBreakdown,
    required this.openedAt,
    this.closedAt,
  });

  /// Total cash payments in cents.
  int get cashSales => paymentBreakdown
      .where((l) => l.method == 'cash')
      .fold(0, (s, l) => s + l.amount);

  /// Total non-cash (card, digital) payments in cents.
  int get cardSales => totalSalesCents - cashSales;

  /// Average order value in cents.
  int get avgOrderCents =>
      totalOrders > 0 ? (totalSalesCents / totalOrders).round() : 0;

  /// How long the shift has been (or was) open.
  Duration get duration {
    final end = closedAt ?? DateTime.now();
    return end.difference(openedAt);
  }

  /// Human-readable duration label, e.g. "7h 32m" or "45m".
  String get durationLabel {
    final d = duration;
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  /// Build the [paymentBreakdown] map required by [ShiftReportData].
  Map<String, int> get reportPaymentBreakdown {
    final map = <String, int>{};
    for (final line in paymentBreakdown) {
      final key = PaymentBreakdownLine.reportKeyFor(line.method);
      map[key] = (map[key] ?? 0) + line.amount;
    }
    return map;
  }

  @override
  String toString() =>
      'ShiftSummaryEntity(shiftId: $shiftId, cashier: $cashierName, '
      'sales: $totalSalesCents¢, orders: $totalOrders)';
}
