/// Analytics repository – runs all reporting queries against the local DB.
///
/// All queries are scoped to [tenantId] and the supplied [DateRangeFilter].
/// Sub-queries run concurrently via [Future.wait] for maximum throughput.
library;

import 'package:drift/drift.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/features/dashboard/domain/entities/analytics_report.dart';

class AnalyticsRepository {
  final AppDatabase _db;

  AnalyticsRepository(this._db);

  // =========================================================================
  // Public API
  // =========================================================================

  Future<AnalyticsReport> getReport(
    String tenantId,
    DateRangeFilter dateRange,
  ) async {
    final start = dateRange.start;
    final end = dateRange.end;

    final results = await Future.wait([
      _getRevenueCounts(tenantId, start, end),       // 0
      _getCancelVoidCounts(tenantId, start, end),    // 1
      _getTableCounts(tenantId),                     // 2
      _getDailyTrend(tenantId, start, end),          // 3
      _getTopProducts(tenantId, start, end),         // 4
      _getHourlySales(tenantId, start, end),         // 5
      _getStaffPerformance(tenantId, start, end),    // 6
      _getMwstBreakdown(tenantId, start, end),       // 7
      _getPaymentBreakdown(tenantId, start, end),    // 8
    ]);

    final rev = results[0] as _RevenueCounts;
    final cancel = results[1] as _CancelCounts;
    final tables = results[2] as _TableCounts;
    final trend = results[3] as List<TrendPoint>;
    final products = results[4] as List<TopProductRow>;
    final hourly = results[5] as List<HourlySalesPoint>;
    final staff = results[6] as List<StaffPerformanceRow>;
    final mwst = results[7] as List<MwstRow>;
    final payments = results[8] as List<PaymentMethodRow>;

    return AnalyticsReport(
      dateRange: dateRange,
      totalRevenueCents: rev.totalCents,
      completedOrderCount: rev.count,
      cancelledOrderCount: cancel.cancelledCount,
      voidedOrderCount: cancel.voidedCount,
      occupiedTableCount: tables.occupied,
      totalTableCount: tables.total,
      dailyTrend: trend,
      topProducts: products,
      hourlySales: hourly,
      staffPerformance: staff,
      mwstReport: mwst,
      paymentBreakdown: payments,
    );
  }

  // =========================================================================
  // Sub-queries
  // =========================================================================

  Future<_RevenueCounts> _getRevenueCounts(
    String tenantId,
    DateTime start,
    DateTime end,
  ) async {
    final rows = await (_db.select(_db.tickets)
          ..where(
            (t) =>
                t.tenantId.equals(tenantId) &
                t.isDeleted.equals(false) &
                t.status.equals('completed') &
                t.openedAt.isBiggerOrEqualValue(start) &
                t.openedAt.isSmallerThanValue(end),
          ))
        .get();
    final total = rows.fold<int>(0, (s, t) => s + t.total);
    return _RevenueCounts(totalCents: total, count: rows.length);
  }

  Future<_CancelCounts> _getCancelVoidCounts(
    String tenantId,
    DateTime start,
    DateTime end,
  ) async {
    final rows = await (_db.select(_db.tickets)
          ..where(
            (t) =>
                t.tenantId.equals(tenantId) &
                t.isDeleted.equals(false) &
                t.openedAt.isBiggerOrEqualValue(start) &
                t.openedAt.isSmallerThanValue(end),
          ))
        .get();
    int cancelled = 0, voided = 0;
    for (final t in rows) {
      if (t.status == 'cancelled') cancelled++;
      if (t.status == 'voided') voided++;
    }
    return _CancelCounts(cancelledCount: cancelled, voidedCount: voided);
  }

  Future<_TableCounts> _getTableCounts(String tenantId) async {
    final rows = await (_db.select(_db.restaurantTables)
          ..where((t) => t.tenantId.equals(tenantId) & t.isDeleted.equals(false)))
        .get();
    final occupied = rows.where((t) => t.status == 'occupied').length;
    return _TableCounts(occupied: occupied, total: rows.length);
  }

  Future<List<TrendPoint>> _getDailyTrend(
    String tenantId,
    DateTime start,
    DateTime end,
  ) async {
    final rows = await (_db.select(_db.tickets)
          ..where(
            (t) =>
                t.tenantId.equals(tenantId) &
                t.isDeleted.equals(false) &
                t.status.equals('completed') &
                t.openedAt.isBiggerOrEqualValue(start) &
                t.openedAt.isSmallerThanValue(end),
          ))
        .get();

    // Aggregate by calendar day.
    final revenueByDay = <DateTime, int>{};
    final countByDay = <DateTime, int>{};
    for (final t in rows) {
      final day = DateTime(t.openedAt.year, t.openedAt.month, t.openedAt.day);
      revenueByDay[day] = (revenueByDay[day] ?? 0) + t.total;
      countByDay[day] = (countByDay[day] ?? 0) + 1;
    }

    // Build sorted list of every day in range.
    final days = <TrendPoint>[];
    var cursor = DateTime(start.year, start.month, start.day);
    final endDay = DateTime(end.year, end.month, end.day);
    while (!cursor.isAfter(endDay)) {
      days.add(TrendPoint(
        date: cursor,
        revenueCents: revenueByDay[cursor] ?? 0,
        orderCount: countByDay[cursor] ?? 0,
      ));
      cursor = cursor.add(const Duration(days: 1));
    }
    return days;
  }

  Future<List<TopProductRow>> _getTopProducts(
    String tenantId,
    DateTime start,
    DateTime end,
  ) async {
    // Step 1: collect completed ticket IDs in the date range.
    final tickets = await (_db.select(_db.tickets)
          ..where(
            (t) =>
                t.tenantId.equals(tenantId) &
                t.isDeleted.equals(false) &
                t.status.equals('completed') &
                t.openedAt.isBiggerOrEqualValue(start) &
                t.openedAt.isSmallerThanValue(end),
          ))
        .get();
    if (tickets.isEmpty) return [];
    final ticketIds = tickets.map((t) => t.id).toSet();

    // Step 2: load non-voided order items for those tickets.
    final items = await (_db.select(_db.orderItems)
          ..where(
            (i) =>
                i.tenantId.equals(tenantId) &
                i.isDeleted.equals(false) &
                i.status.isNotIn(['void']),
          ))
        .get();

    // Step 3: aggregate in Dart.
    final qtyByName = <String, double>{};
    final revByName = <String, int>{};
    for (final item in items) {
      if (!ticketIds.contains(item.ticketId)) continue;
      qtyByName[item.productName] =
          (qtyByName[item.productName] ?? 0.0) + item.quantity;
      revByName[item.productName] =
          (revByName[item.productName] ?? 0) + item.subtotal;
    }

    final sorted = revByName.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted.take(10).map((e) => TopProductRow(
          productName: e.key,
          quantity: qtyByName[e.key] ?? 0,
          revenueCents: e.value,
        )).toList();
  }

  Future<List<HourlySalesPoint>> _getHourlySales(
    String tenantId,
    DateTime start,
    DateTime end,
  ) async {
    final rows = await (_db.select(_db.tickets)
          ..where(
            (t) =>
                t.tenantId.equals(tenantId) &
                t.isDeleted.equals(false) &
                t.status.equals('completed') &
                t.openedAt.isBiggerOrEqualValue(start) &
                t.openedAt.isSmallerThanValue(end),
          ))
        .get();

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

  Future<List<StaffPerformanceRow>> _getStaffPerformance(
    String tenantId,
    DateTime start,
    DateTime end,
  ) async {
    final tickets = await (_db.select(_db.tickets)
          ..where(
            (t) =>
                t.tenantId.equals(tenantId) &
                t.isDeleted.equals(false) &
                t.status.equals('completed') &
                t.openedAt.isBiggerOrEqualValue(start) &
                t.openedAt.isSmallerThanValue(end),
          ))
        .get();
    if (tickets.isEmpty) return [];

    // Collect unique waiter IDs (non-null).
    final waiterIds =
        tickets.map((t) => t.waiterId).whereType<String>().toSet();

    // Load waiter names.
    final users = await (_db.select(_db.users)
          ..where(
            (u) =>
                u.tenantId.equals(tenantId) &
                u.isDeleted.equals(false),
          ))
        .get();
    final nameById = {for (final u in users) u.id: u.name};

    // Aggregate per waiter.
    final orderCounts = <String, int>{};
    final revenues = <String, int>{};
    final durations = <String, List<int>>{}; // minutes

    for (final t in tickets) {
      final wid = t.waiterId ?? '__unknown__';
      if (!waiterIds.contains(wid) && wid != '__unknown__') continue;
      orderCounts[wid] = (orderCounts[wid] ?? 0) + 1;
      revenues[wid] = (revenues[wid] ?? 0) + t.total;
      if (t.closedAt != null) {
        final mins = t.closedAt!.difference(t.openedAt).inMinutes;
        durations.putIfAbsent(wid, () => []).add(mins);
      }
    }

    final rows = <StaffPerformanceRow>[];
    for (final wid in orderCounts.keys) {
      final count = orderCounts[wid]!;
      final rev = revenues[wid]!;
      final dList = durations[wid] ?? [];
      final avgDur = dList.isEmpty
          ? 0
          : (dList.reduce((a, b) => a + b) / dList.length).round();
      rows.add(StaffPerformanceRow(
        waiterId: wid,
        waiterName: nameById[wid] ?? 'Bilinmiyor',
        orderCount: count,
        revenueCents: rev,
        avgOrderCents: count > 0 ? rev ~/ count : 0,
        avgDurationMinutes: avgDur,
      ));
    }

    rows.sort((a, b) => b.revenueCents.compareTo(a.revenueCents));
    return rows;
  }

  Future<List<MwstRow>> _getMwstBreakdown(
    String tenantId,
    DateTime start,
    DateTime end,
  ) async {
    final rows = await (_db.select(_db.tickets)
          ..where(
            (t) =>
                t.tenantId.equals(tenantId) &
                t.isDeleted.equals(false) &
                t.status.equals('completed') &
                t.openedAt.isBiggerOrEqualValue(start) &
                t.openedAt.isSmallerThanValue(end),
          ))
        .get();

    // Group by orderType.
    final grossByType = <String, int>{};
    final taxByType = <String, int>{};
    for (final t in rows) {
      grossByType[t.orderType] = (grossByType[t.orderType] ?? 0) + t.total;
      taxByType[t.orderType] = (taxByType[t.orderType] ?? 0) + t.taxAmount;
    }

    const labels = {
      'dine_in': 'Yerinde (8.1%)',
      'takeaway': 'Paket (2.6%)',
      'delivery': 'Teslimat (2.6%)',
      'online': 'Online',
    };

    return grossByType.entries
        .map((e) => MwstRow(
              label: labels[e.key] ?? e.key,
              grossRevenueCents: e.value,
              taxCents: taxByType[e.key] ?? 0,
            ))
        .toList()
      ..sort((a, b) => b.grossRevenueCents.compareTo(a.grossRevenueCents));
  }

  Future<List<PaymentMethodRow>> _getPaymentBreakdown(
    String tenantId,
    DateTime start,
    DateTime end,
  ) async {
    final rows = await (_db.select(_db.payments)
          ..where(
            (p) =>
                p.tenantId.equals(tenantId) &
                p.isDeleted.equals(false) &
                p.paidAt.isBiggerOrEqualValue(start) &
                p.paidAt.isSmallerThanValue(end),
          ))
        .get();

    final amountByMethod = <String, int>{};
    final countByMethod = <String, int>{};
    for (final p in rows) {
      amountByMethod[p.paymentMethod] =
          (amountByMethod[p.paymentMethod] ?? 0) + p.amount;
      countByMethod[p.paymentMethod] =
          (countByMethod[p.paymentMethod] ?? 0) + 1;
    }

    return amountByMethod.entries
        .map((e) => PaymentMethodRow(
              method: e.key,
              amountCents: e.value,
              count: countByMethod[e.key] ?? 0,
            ))
        .toList()
      ..sort((a, b) => b.amountCents.compareTo(a.amountCents));
  }
}

// ---------------------------------------------------------------------------
// Private DTOs
// ---------------------------------------------------------------------------

class _RevenueCounts {
  final int totalCents;
  final int count;
  const _RevenueCounts({required this.totalCents, required this.count});
}

class _CancelCounts {
  final int cancelledCount;
  final int voidedCount;
  const _CancelCounts(
      {required this.cancelledCount, required this.voidedCount});
}

class _TableCounts {
  final int occupied;
  final int total;
  const _TableCounts({required this.occupied, required this.total});
}
