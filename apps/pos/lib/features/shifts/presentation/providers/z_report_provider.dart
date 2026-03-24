/// Riverpod providers for the Z-Report screen.
///
/// Fetches detailed shift statistics by querying tickets, order_items,
/// and payments for the current shift's time window.
library;

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/features/shifts/domain/entities/shift_entity.dart';
import 'package:gastrocore_pos/features/shifts/presentation/providers/shift_provider.dart';

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// Top-selling item for the Z-Report.
class ZReportTopItem {
  const ZReportTopItem({
    required this.name,
    required this.quantity,
    required this.revenueCents,
  });

  final String name;
  final double quantity;
  final int revenueCents;
}

/// MWST summary entry for the Z-Report.
class ZReportMwstEntry {
  const ZReportMwstEntry({
    required this.code,
    required this.rate,
    required this.grossCents,
    required this.taxCents,
  });

  /// 'A', 'B', 'C'
  final String code;
  final double rate;
  final int grossCents;
  final int taxCents;
  int get netCents => grossCents - taxCents;
}

/// Aggregated statistics for the Z-Report screen.
class ZReportStats {
  const ZReportStats({
    required this.shift,
    required this.totalRevenueCents,
    required this.totalOrders,
    required this.paymentBreakdown,
    required this.taxTotalCents,
    required this.discountTotalCents,
    required this.voidCount,
    required this.topItems,
    required this.mwstEntries,
    required this.generatedAt,
  });

  final ShiftEntity shift;

  /// Gross revenue for the shift (cents).
  final int totalRevenueCents;

  /// Number of completed orders.
  final int totalOrders;

  /// Payment method → total amount (cents).
  final Map<String, int> paymentBreakdown;

  /// Total MWST (tax) collected (cents).
  final int taxTotalCents;

  /// Total discounts given (cents).
  final int discountTotalCents;

  /// Number of voided tickets.
  final int voidCount;

  /// Top 5 selling items by revenue.
  final List<ZReportTopItem> topItems;

  /// MWST breakdown (A=8.1% dine-in, B=2.6% takeaway).
  final List<ZReportMwstEntry> mwstEntries;

  final DateTime generatedAt;

  // ---- Computed ----

  /// Cash payments (cents).
  int get cashTotal =>
      paymentBreakdown.entries
          .where((e) => e.key == 'cash')
          .fold(0, (s, e) => s + e.value);

  /// Card / digital payments (cents).
  int get cardTotal => totalRevenueCents - cashTotal;

  /// Average order value (cents).
  int get avgOrderCents =>
      totalOrders > 0 ? (totalRevenueCents / totalOrders).round() : 0;

  /// Net revenue = gross - discounts.
  int get netRevenueCents => totalRevenueCents - discountTotalCents;
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Loads [ZReportStats] for the currently active shift.
///
/// Returns `null` when no shift is open.
final zReportStatsProvider = FutureProvider<ZReportStats?>((ref) async {
  final shift = ref.watch(currentShiftProvider);
  if (shift == null) return null;

  final db = ref.watch(databaseProvider);
  final tenantId = ref.watch(tenantIdProvider);
  final shiftStart = shift.openedAt;

  // ----- Tickets in shift window -----
  final ticketQuery = db.select(db.tickets)
    ..where(
      (t) =>
          t.tenantId.equals(tenantId) &
          t.isDeleted.equals(false) &
          t.openedAt.isBiggerOrEqualValue(shiftStart),
    );
  final allTickets = await ticketQuery.get();

  final completedTickets = allTickets
      .where(
        (t) => ['completed', 'fully_paid', 'closed'].contains(t.status),
      )
      .toList();

  final voidedTickets =
      allTickets.where((t) => t.status == 'voided').toList();

  // ----- Revenue & tax totals -----
  final totalRevenue =
      completedTickets.fold<int>(0, (s, t) => s + t.total);
  final taxTotal =
      completedTickets.fold<int>(0, (s, t) => s + t.taxAmount);
  final discountTotal =
      completedTickets.fold<int>(0, (s, t) => s + t.discountAmount);

  // ----- MWST breakdown (A=8.1% dine-in, B=2.6% takeaway) -----
  final dineInTickets = completedTickets
      .where((t) => t.orderType != 'takeaway' && t.orderType != 'delivery')
      .toList();
  final takeawayTickets = completedTickets
      .where((t) => t.orderType == 'takeaway' || t.orderType == 'delivery')
      .toList();

  final dineInGross = dineInTickets.fold<int>(0, (s, t) => s + t.total);
  final dineInTax = dineInTickets.fold<int>(0, (s, t) => s + t.taxAmount);
  final takeawayGross =
      takeawayTickets.fold<int>(0, (s, t) => s + t.total);
  final takeawayTax =
      takeawayTickets.fold<int>(0, (s, t) => s + t.taxAmount);

  final mwstEntries = <ZReportMwstEntry>[
    if (dineInGross > 0)
      ZReportMwstEntry(
        code: 'A',
        rate: 8.1,
        grossCents: dineInGross,
        taxCents: dineInTax,
      ),
    if (takeawayGross > 0)
      ZReportMwstEntry(
        code: 'B',
        rate: 2.6,
        grossCents: takeawayGross,
        taxCents: takeawayTax,
      ),
  ];

  // ----- Payment breakdown -----
  final paymentQuery = db.select(db.payments)
    ..where(
      (p) =>
          p.tenantId.equals(tenantId) &
          p.isDeleted.equals(false) &
          p.paidAt.isBiggerOrEqualValue(shiftStart),
    );
  final payments = await paymentQuery.get();
  final paymentBreakdown = <String, int>{};
  for (final p in payments) {
    paymentBreakdown[p.paymentMethod] =
        (paymentBreakdown[p.paymentMethod] ?? 0) + p.amount;
  }

  // ----- Top selling items -----
  final completedIds = completedTickets.map((t) => t.id).toSet();
  final List<ZReportTopItem> topItems;

  if (completedIds.isNotEmpty) {
    final itemQuery = db.select(db.orderItems)
      ..where(
        (i) =>
            i.tenantId.equals(tenantId) &
            i.isDeleted.equals(false) &
            i.ticketId.isIn(completedIds),
      );
    final orderItems = await itemQuery.get();

    // Group by productName
    final grouped = <String, ({double qty, int revenue})>{};
    for (final item in orderItems) {
      final existing = grouped[item.productName];
      if (existing == null) {
        grouped[item.productName] =
            (qty: item.quantity, revenue: item.subtotal);
      } else {
        grouped[item.productName] = (
          qty: existing.qty + item.quantity,
          revenue: existing.revenue + item.subtotal,
        );
      }
    }

    final sorted = grouped.entries.toList()
      ..sort((a, b) => b.value.revenue.compareTo(a.value.revenue));

    topItems = sorted
        .take(5)
        .map(
          (e) => ZReportTopItem(
            name: e.key,
            quantity: e.value.qty,
            revenueCents: e.value.revenue,
          ),
        )
        .toList();
  } else {
    topItems = [];
  }

  return ZReportStats(
    shift: shift,
    totalRevenueCents: totalRevenue,
    totalOrders: completedTickets.length,
    paymentBreakdown: paymentBreakdown,
    taxTotalCents: taxTotal,
    discountTotalCents: discountTotal,
    voidCount: voidedTickets.length,
    topItems: topItems,
    mwstEntries: mwstEntries,
    generatedAt: DateTime.now(),
  );
});
