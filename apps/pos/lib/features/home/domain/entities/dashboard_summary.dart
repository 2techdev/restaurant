/// Dashboard / Home screen data aggregates.
///
/// [DashboardSummaryEntity] is a read-only snapshot built once per screen load
/// (or periodic refresh). All monetary values are in cents (CHF).
library;

import 'package:gastrocore_pos/features/shifts/domain/entities/shift_entity.dart';

// ---------------------------------------------------------------------------
// HourlySalesPoint
// ---------------------------------------------------------------------------

/// Revenue and order count for a single hour of the day.
class HourlySalesPoint {
  /// Hour of the day (0–23).
  final int hour;

  /// Total completed-ticket revenue for this hour, in cents.
  final int amountCents;

  /// Number of completed orders in this hour.
  final int orderCount;

  const HourlySalesPoint({
    required this.hour,
    required this.amountCents,
    required this.orderCount,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HourlySalesPoint &&
          hour == other.hour &&
          amountCents == other.amountCents &&
          orderCount == other.orderCount;

  @override
  int get hashCode => Object.hash(hour, amountCents, orderCount);
}

// ---------------------------------------------------------------------------
// RecentOrderRow
// ---------------------------------------------------------------------------

/// Lightweight order row used by the Recent Orders list on the dashboard.
///
/// Contains only the fields needed for display — no line-item details.
class RecentOrderRow {
  final String id;
  final String orderNumber;

  /// Raw DB status string (e.g. 'completed', 'open', 'sent').
  final String status;

  /// Grand total in cents.
  final int totalCents;

  final DateTime openedAt;

  /// Table ID – null for takeaway / delivery.
  final String? tableId;

  /// Raw DB order-type string (e.g. 'dine_in', 'takeaway').
  final String orderType;

  const RecentOrderRow({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.totalCents,
    required this.openedAt,
    this.tableId,
    required this.orderType,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecentOrderRow &&
          id == other.id &&
          orderNumber == other.orderNumber &&
          status == other.status &&
          totalCents == other.totalCents &&
          openedAt == other.openedAt &&
          tableId == other.tableId &&
          orderType == other.orderType;

  @override
  int get hashCode => Object.hash(
        id,
        orderNumber,
        status,
        totalCents,
        openedAt,
        tableId,
        orderType,
      );
}

// ---------------------------------------------------------------------------
// DashboardSummaryEntity
// ---------------------------------------------------------------------------

/// Immutable snapshot of all data shown on the home / dashboard screen.
class DashboardSummaryEntity {
  // ---- Revenue ----

  /// Sum of all completed-ticket totals for today, in cents.
  final int dailyRevenueCents;

  /// Number of completed orders today.
  final int dailyOrderCount;

  // ---- Payment breakdown (today) ----

  /// Total cash payments today, in cents.
  final int cashRevenueCents;

  /// Total card payments (credit + debit) today, in cents.
  final int cardRevenueCents;

  /// Total "other" payments (TWINT, vouchers, etc.) today, in cents.
  final int otherRevenueCents;

  // ---- Tables ----

  /// Number of tables currently in 'occupied' status.
  final int occupiedTableCount;

  /// Total table count (non-deleted).
  final int totalTableCount;

  // ---- Shift ----

  /// Currently open shift, or null when no shift is active.
  final ShiftEntity? currentShift;

  // ---- Recent orders ----

  /// The 10 most recently opened tickets, newest first.
  final List<RecentOrderRow> recentOrders;

  // ---- Hourly sales ----

  /// 24-element list (index == hour) with revenue + order count per hour.
  final List<HourlySalesPoint> hourlySales;

  const DashboardSummaryEntity({
    required this.dailyRevenueCents,
    required this.dailyOrderCount,
    required this.cashRevenueCents,
    required this.cardRevenueCents,
    required this.otherRevenueCents,
    required this.occupiedTableCount,
    required this.totalTableCount,
    this.currentShift,
    required this.recentOrders,
    required this.hourlySales,
  });

  // ---- Computed ----

  /// Average order value today in cents (0 when no orders).
  int get dailyAverageOrderCents =>
      dailyOrderCount > 0
          ? (dailyRevenueCents / dailyOrderCount).round()
          : 0;

  /// Table occupancy rate 0.0–1.0 (0 when no tables configured).
  double get tableOccupancyRate =>
      totalTableCount > 0 ? occupiedTableCount / totalTableCount : 0.0;

  /// True when there is an open shift.
  bool get hasActiveShift =>
      currentShift != null && currentShift!.isOpen;

  /// Total payment volume processed today in cents.
  int get totalPaymentsCents =>
      cashRevenueCents + cardRevenueCents + otherRevenueCents;

  /// Peak hourly revenue in cents (used to scale the chart).
  int get peakHourlyRevenueCents =>
      hourlySales.fold<int>(0, (max, h) => h.amountCents > max ? h.amountCents : max);

  // ---- Factory ----

  /// Empty snapshot – used while loading or on first paint.
  static DashboardSummaryEntity empty() {
    return DashboardSummaryEntity(
      dailyRevenueCents: 0,
      dailyOrderCount: 0,
      cashRevenueCents: 0,
      cardRevenueCents: 0,
      otherRevenueCents: 0,
      occupiedTableCount: 0,
      totalTableCount: 0,
      recentOrders: const [],
      hourlySales: List.generate(
        24,
        (h) => HourlySalesPoint(hour: h, amountCents: 0, orderCount: 0),
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DashboardSummaryEntity &&
          dailyRevenueCents == other.dailyRevenueCents &&
          dailyOrderCount == other.dailyOrderCount &&
          cashRevenueCents == other.cashRevenueCents &&
          cardRevenueCents == other.cardRevenueCents &&
          otherRevenueCents == other.otherRevenueCents &&
          occupiedTableCount == other.occupiedTableCount &&
          totalTableCount == other.totalTableCount &&
          currentShift == other.currentShift;

  @override
  int get hashCode => Object.hash(
        dailyRevenueCents,
        dailyOrderCount,
        cashRevenueCents,
        cardRevenueCents,
        otherRevenueCents,
        occupiedTableCount,
        totalTableCount,
        currentShift,
      );
}
