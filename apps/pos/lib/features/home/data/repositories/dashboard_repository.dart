/// Dashboard repository – aggregates all data shown on the Home screen.
///
/// Queries the Drift database directly without going through other feature
/// repositories, to keep the read-side logic self-contained and avoid
/// loading unnecessary data (e.g. full order-item lists).
library;

import 'package:drift/drift.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/features/home/domain/entities/dashboard_summary.dart';
import 'package:gastrocore_pos/features/shifts/domain/entities/shift_entity.dart';

class DashboardRepository {
  final AppDatabase _db;

  DashboardRepository(this._db);

  // =========================================================================
  // Public API
  // =========================================================================

  /// Build the full [DashboardSummaryEntity] for [tenantId].
  ///
  /// All sub-queries run concurrently via [Future.wait].
  Future<DashboardSummaryEntity> getDashboardSummary(String tenantId) async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final results = await Future.wait([
      _getDailyRevenue(tenantId, startOfDay, endOfDay),
      _getPaymentBreakdown(tenantId, startOfDay, endOfDay),
      _getTableCounts(tenantId),
      _getCurrentShift(tenantId),
      _getRecentOrders(tenantId),
      _getHourlySales(tenantId, startOfDay, endOfDay),
    ]);

    final revenue = results[0] as _RevenueData;
    final payments = results[1] as _PaymentBreakdown;
    final tables = results[2] as _TableCounts;
    final shift = results[3] as ShiftEntity?;
    final recent = results[4] as List<RecentOrderRow>;
    final hourly = results[5] as List<HourlySalesPoint>;

    return DashboardSummaryEntity(
      dailyRevenueCents: revenue.totalCents,
      dailyOrderCount: revenue.orderCount,
      cashRevenueCents: payments.cashCents,
      cardRevenueCents: payments.cardCents,
      otherRevenueCents: payments.otherCents,
      occupiedTableCount: tables.occupied,
      totalTableCount: tables.total,
      currentShift: shift,
      recentOrders: recent,
      hourlySales: hourly,
    );
  }

  // =========================================================================
  // Sub-queries
  // =========================================================================

  /// Today's completed-ticket revenue and order count.
  Future<_RevenueData> _getDailyRevenue(
    String tenantId,
    DateTime startOfDay,
    DateTime endOfDay,
  ) async {
    final query = _db.select(_db.tickets)
      ..where(
        (t) =>
            t.tenantId.equals(tenantId) &
            t.isDeleted.equals(false) &
            t.status.equals('completed') &
            t.openedAt.isBiggerOrEqualValue(startOfDay) &
            t.openedAt.isSmallerThanValue(endOfDay),
      );
    final rows = await query.get();
    final total = rows.fold<int>(0, (s, t) => s + t.total);
    return _RevenueData(totalCents: total, orderCount: rows.length);
  }

  /// Today's payment totals grouped by method.
  ///
  /// - `cash`                          → cashCents
  /// - `credit_card` / `debit_card`   → cardCents
  /// - everything else                 → otherCents  (TWINT, vouchers…)
  Future<_PaymentBreakdown> _getPaymentBreakdown(
    String tenantId,
    DateTime startOfDay,
    DateTime endOfDay,
  ) async {
    final query = _db.select(_db.payments)
      ..where(
        (p) =>
            p.tenantId.equals(tenantId) &
            p.isDeleted.equals(false) &
            p.paidAt.isBiggerOrEqualValue(startOfDay) &
            p.paidAt.isSmallerThanValue(endOfDay),
      );
    final rows = await query.get();

    int cash = 0, card = 0, other = 0;
    for (final p in rows) {
      switch (p.paymentMethod) {
        case 'cash':
          cash += p.amount;
        case 'credit_card' || 'debit_card':
          card += p.amount;
        default:
          other += p.amount;
      }
    }
    return _PaymentBreakdown(cashCents: cash, cardCents: card, otherCents: other);
  }

  /// Occupied vs total table count for [tenantId].
  Future<_TableCounts> _getTableCounts(String tenantId) async {
    final query = _db.select(_db.restaurantTables)
      ..where(
        (t) => t.tenantId.equals(tenantId) & t.isDeleted.equals(false),
      );
    final rows = await query.get();
    final occupied = rows.where((t) => t.status == 'occupied').length;
    return _TableCounts(occupied: occupied, total: rows.length);
  }

  /// Most recently opened shift with status 'open', or null.
  Future<ShiftEntity?> _getCurrentShift(String tenantId) async {
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
    if (row == null) return null;

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

  /// Last [limit] tickets ordered by openedAt descending.
  Future<List<RecentOrderRow>> _getRecentOrders(
    String tenantId, {
    int limit = 10,
  }) async {
    final query = _db.select(_db.tickets)
      ..where(
        (t) => t.tenantId.equals(tenantId) & t.isDeleted.equals(false),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.openedAt)])
      ..limit(limit);
    final rows = await query.get();

    return rows
        .map(
          (r) => RecentOrderRow(
            id: r.id,
            orderNumber: r.orderNumber.toString().padLeft(4, '0'),
            status: r.status,
            totalCents: r.total,
            openedAt: r.openedAt,
            tableId: r.tableId,
            orderType: r.orderType,
          ),
        )
        .toList();
  }

  /// 24-element list of [HourlySalesPoint] for completed tickets today.
  Future<List<HourlySalesPoint>> _getHourlySales(
    String tenantId,
    DateTime startOfDay,
    DateTime endOfDay,
  ) async {
    final query = _db.select(_db.tickets)
      ..where(
        (t) =>
            t.tenantId.equals(tenantId) &
            t.isDeleted.equals(false) &
            t.status.equals('completed') &
            t.openedAt.isBiggerOrEqualValue(startOfDay) &
            t.openedAt.isSmallerThanValue(endOfDay),
      );
    final rows = await query.get();

    final amountByHour = <int, int>{};
    final countByHour = <int, int>{};
    for (final t in rows) {
      final h = t.openedAt.hour;
      amountByHour[h] = (amountByHour[h] ?? 0) + t.total;
      countByHour[h] = (countByHour[h] ?? 0) + 1;
    }

    return List.generate(
      24,
      (h) => HourlySalesPoint(
        hour: h,
        amountCents: amountByHour[h] ?? 0,
        orderCount: countByHour[h] ?? 0,
      ),
    );
  }

  // =========================================================================
  // Helpers
  // =========================================================================

  static ShiftStatus _parseShiftStatus(String value) {
    return switch (value) {
      'open' => ShiftStatus.open,
      'closing' => ShiftStatus.closing,
      'closed' => ShiftStatus.closed,
      _ => ShiftStatus.open,
    };
  }
}

// ---------------------------------------------------------------------------
// Private data transfer objects
// ---------------------------------------------------------------------------

class _RevenueData {
  final int totalCents;
  final int orderCount;

  const _RevenueData({required this.totalCents, required this.orderCount});
}

class _PaymentBreakdown {
  final int cashCents;
  final int cardCents;
  final int otherCents;

  const _PaymentBreakdown({
    required this.cashCents,
    required this.cardCents,
    required this.otherCents,
  });
}

class _TableCounts {
  final int occupied;
  final int total;

  const _TableCounts({required this.occupied, required this.total});
}
