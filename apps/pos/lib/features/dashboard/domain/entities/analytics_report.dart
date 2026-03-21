/// Analytics / Reporting domain entities.
///
/// All monetary values are in cents (CHF).
library;

// ---------------------------------------------------------------------------
// DateRangeFilter
// ---------------------------------------------------------------------------

class DateRangeFilter {
  final DateTime start;
  final DateTime end;
  final String label;

  const DateRangeFilter({
    required this.start,
    required this.end,
    required this.label,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DateRangeFilter &&
          start == other.start &&
          end == other.end;

  @override
  int get hashCode => Object.hash(start, end);
}

// ---------------------------------------------------------------------------
// TrendPoint – one data point in the daily revenue trend chart
// ---------------------------------------------------------------------------

class TrendPoint {
  final DateTime date;
  final int revenueCents;
  final int orderCount;

  const TrendPoint({
    required this.date,
    required this.revenueCents,
    required this.orderCount,
  });
}

// ---------------------------------------------------------------------------
// TopProductRow – one entry in the top-10 products list
// ---------------------------------------------------------------------------

class TopProductRow {
  final String productName;
  final double quantity;
  final int revenueCents;

  const TopProductRow({
    required this.productName,
    required this.quantity,
    required this.revenueCents,
  });
}

// ---------------------------------------------------------------------------
// StaffPerformanceRow – per-waiter KPIs
// ---------------------------------------------------------------------------

class StaffPerformanceRow {
  final String waiterId;
  final String waiterName;
  final int orderCount;
  final int revenueCents;
  final int avgOrderCents;

  /// Average ticket duration in minutes (openedAt → closedAt).
  final int avgDurationMinutes;

  const StaffPerformanceRow({
    required this.waiterId,
    required this.waiterName,
    required this.orderCount,
    required this.revenueCents,
    required this.avgOrderCents,
    required this.avgDurationMinutes,
  });
}

// ---------------------------------------------------------------------------
// PaymentMethodRow – breakdown by payment method
// ---------------------------------------------------------------------------

class PaymentMethodRow {
  final String method;
  final int amountCents;
  final int count;

  const PaymentMethodRow({
    required this.method,
    required this.amountCents,
    required this.count,
  });
}

// ---------------------------------------------------------------------------
// HourlySalesPoint – revenue + order count for one hour of the day
// ---------------------------------------------------------------------------

class HourlySalesPoint {
  final int hour; // 0–23
  final int amountCents;
  final int orderCount;

  const HourlySalesPoint({
    required this.hour,
    required this.amountCents,
    required this.orderCount,
  });
}

// ---------------------------------------------------------------------------
// MwstRow – Swiss VAT (MWST) breakdown row
// ---------------------------------------------------------------------------

class MwstRow {
  /// Human-readable label, e.g. 'Dine-in', 'Takeaway'.
  final String label;

  /// Total gross revenue (tax-inclusive) in cents.
  final int grossRevenueCents;

  /// Tax amount embedded in gross revenue, in cents.
  final int taxCents;

  const MwstRow({
    required this.label,
    required this.grossRevenueCents,
    required this.taxCents,
  });

  int get netRevenueCents => grossRevenueCents - taxCents;

  /// Effective tax rate as a percentage (0–100).
  double get effectiveRatePct =>
      netRevenueCents > 0 ? (taxCents / netRevenueCents) * 100 : 0.0;
}

// ---------------------------------------------------------------------------
// AnalyticsReport – full analytics snapshot for a date range
// ---------------------------------------------------------------------------

class AnalyticsReport {
  final DateRangeFilter dateRange;

  // ---- Revenue ----
  final int totalRevenueCents;
  final int completedOrderCount;
  final int cancelledOrderCount;
  final int voidedOrderCount;

  // ---- Tables ----
  final int occupiedTableCount;
  final int totalTableCount;

  // ---- Charts ----
  final List<TrendPoint> dailyTrend;
  final List<TopProductRow> topProducts;
  final List<HourlySalesPoint> hourlySales;
  final List<StaffPerformanceRow> staffPerformance;
  final List<MwstRow> mwstReport;
  final List<PaymentMethodRow> paymentBreakdown;

  const AnalyticsReport({
    required this.dateRange,
    required this.totalRevenueCents,
    required this.completedOrderCount,
    required this.cancelledOrderCount,
    required this.voidedOrderCount,
    required this.occupiedTableCount,
    required this.totalTableCount,
    required this.dailyTrend,
    required this.topProducts,
    required this.hourlySales,
    required this.staffPerformance,
    required this.mwstReport,
    required this.paymentBreakdown,
  });

  // ---- Computed ----

  int get avgOrderCents =>
      completedOrderCount > 0 ? totalRevenueCents ~/ completedOrderCount : 0;

  int get totalOrdersAll =>
      completedOrderCount + cancelledOrderCount + voidedOrderCount;

  double get cancellationRate =>
      totalOrdersAll > 0
          ? (cancelledOrderCount + voidedOrderCount) / totalOrdersAll
          : 0.0;

  double get tableOccupancyRate =>
      totalTableCount > 0 ? occupiedTableCount / totalTableCount : 0.0;

  // ---- Factory ----

  static AnalyticsReport empty(DateRangeFilter dateRange) => AnalyticsReport(
        dateRange: dateRange,
        totalRevenueCents: 0,
        completedOrderCount: 0,
        cancelledOrderCount: 0,
        voidedOrderCount: 0,
        occupiedTableCount: 0,
        totalTableCount: 0,
        dailyTrend: const [],
        topProducts: const [],
        hourlySales: List.generate(
          24,
          (h) => HourlySalesPoint(hour: h, amountCents: 0, orderCount: 0),
        ),
        staffPerformance: const [],
        mwstReport: const [],
        paymentBreakdown: const [],
      );
}
