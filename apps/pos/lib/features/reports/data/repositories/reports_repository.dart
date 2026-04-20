/// Drift-backed reports repository.
///
/// Generates Z / daily / monthly / period snapshots and seals the Z report
/// into the ZReports table with a per-tenant monotonic sequence number.
library;

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/features/reports/domain/entities/report_entities.dart';

class ReportsRepository {
  ReportsRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  // ---------------------------------------------------------------------------
  // Snapshot generation
  // ---------------------------------------------------------------------------

  /// Build an aggregate snapshot for [from, to). Callers pick the window;
  /// the same code path powers "Z today", "monthly", and "period".
  Future<ReportSnapshot> generateSnapshot({
    required String tenantId,
    required DateTime from,
    required DateTime to,
  }) async {
    // Tickets closed inside the window.
    final ticketQuery = _db.select(_db.tickets)
      ..where(
        (t) =>
            t.tenantId.equals(tenantId) &
            t.isDeleted.equals(false) &
            t.closedAt.isBiggerOrEqualValue(from) &
            t.closedAt.isSmallerThanValue(to),
      );
    final tickets = await ticketQuery.get();

    final paidTickets = tickets.where((t) =>
        t.status == 'fully_paid' || t.status == 'closed' || t.status == 'paid');
    final voidedTickets = tickets.where((t) => t.status == 'void');

    final ticketIds = paidTickets.map((t) => t.id).toSet();

    int grossTotal = 0;
    int taxTotal = 0;
    int discountTotal = 0;
    int giftTotal = 0;
    for (final t in paidTickets) {
      grossTotal += t.total;
      taxTotal += t.taxAmount;
      discountTotal += t.discountAmount;
      // A gift is modelled as a 100% percentage discount at the ticket
      // level — the reports screen surfaces it as a distinct line so the
      // operator can see how much was given away.
      if (t.discountType == 'percent' &&
          (t.discountValue ?? 0) >= 100 &&
          t.subtotal > 0) {
        giftTotal += t.subtotal;
      }
    }
    final netTotal = grossTotal - taxTotal;

    // Payments — join by ticketId, group by method + sum tips.
    int tipTotal = 0;
    final payments = <String, List<int>>{};
    if (ticketIds.isNotEmpty) {
      final payQuery = _db.select(_db.payments)
        ..where(
          (p) =>
              p.tenantId.equals(tenantId) &
              p.isDeleted.equals(false) &
              p.ticketId.isIn(ticketIds),
        );
      final payRows = await payQuery.get();
      for (final p in payRows) {
        tipTotal += p.tipAmount;
        payments.putIfAbsent(p.paymentMethod, () => <int>[]).add(p.amount);
      }
    }
    final paymentEntries = payments.entries
        .map((e) => PaymentBreakdownEntry(
              method: e.key,
              totalCents: e.value.fold<int>(0, (a, b) => a + b),
              count: e.value.length,
            ))
        .toList()
      ..sort((a, b) => b.totalCents.compareTo(a.totalCents));

    // Line items — MWST buckets + top products + category breakdown.
    final mwstBuckets = <int, ({int gross, int net, int tax})>{};
    final productAgg = <String, ({String name, double qty, int revenue})>{};
    final categoryAgg =
        <String, ({String name, int revenue, double qty})>{};

    if (ticketIds.isNotEmpty) {
      final itemsQuery = _db.select(_db.orderItems)
        ..where(
          (i) =>
              i.tenantId.equals(tenantId) &
              i.isDeleted.equals(false) &
              i.ticketId.isIn(ticketIds) &
              i.status.isNotValue('void'),
        );
      final items = await itemsQuery.get();

      // Preload product→category for the items in play so we can label
      // the category breakdown without an N+1 query.
      final productIds = items.map((i) => i.productId).toSet();
      final categoryByProduct = <String, String?>{};
      if (productIds.isNotEmpty) {
        final prodQuery = _db.select(_db.products)
          ..where((p) => p.id.isIn(productIds));
        for (final p in await prodQuery.get()) {
          categoryByProduct[p.id] = p.categoryId;
        }
      }
      final catIds = categoryByProduct.values
          .whereType<String>()
          .toSet();
      final catNameById = <String, String>{};
      if (catIds.isNotEmpty) {
        final catQuery = _db.select(_db.categories)
          ..where((c) => c.id.isIn(catIds));
        for (final c in await catQuery.get()) {
          catNameById[c.id] = c.name;
        }
      }

      for (final item in items) {
        final sub = item.subtotal;
        final tax = item.taxAmount;
        final gross = sub + tax;

        // Derive MWST rate in basis points from the item totals themselves
        // (subtotal is pre-tax). Line items with no tax just skip the
        // bucket — they're already counted in grossTotal.
        if (sub > 0 && tax > 0) {
          final rateBps = ((tax * 10000) / sub).round();
          final rounded = _snapToStandardRate(rateBps);
          final entry = mwstBuckets[rounded];
          if (entry == null) {
            mwstBuckets[rounded] =
                (gross: gross, net: sub, tax: tax);
          } else {
            mwstBuckets[rounded] = (
              gross: entry.gross + gross,
              net: entry.net + sub,
              tax: entry.tax + tax,
            );
          }
        }

        final existing = productAgg[item.productId];
        productAgg[item.productId] = (
          name: item.productName,
          qty: (existing?.qty ?? 0) + item.quantity,
          revenue: (existing?.revenue ?? 0) + gross,
        );

        final catId = categoryByProduct[item.productId];
        final catKey = catId ?? '__uncat__';
        final catName = catId == null
            ? 'Kategorisiz'
            : (catNameById[catId] ?? 'Kategorisiz');
        final c = categoryAgg[catKey];
        categoryAgg[catKey] = (
          name: catName,
          revenue: (c?.revenue ?? 0) + gross,
          qty: (c?.qty ?? 0) + item.quantity,
        );
      }
    }

    final mwstList = mwstBuckets.entries
        .map((e) => MwstBucket(
              rateBps: e.key,
              grossCents: e.value.gross,
              netCents: e.value.net,
              taxCents: e.value.tax,
            ))
        .toList()
      ..sort((a, b) => a.rateBps.compareTo(b.rateBps));

    final topProducts = productAgg.entries
        .map((e) => TopProductEntry(
              productId: e.key,
              productName: e.value.name,
              quantity: e.value.qty,
              revenueCents: e.value.revenue,
            ))
        .toList()
      ..sort((a, b) => b.revenueCents.compareTo(a.revenueCents));
    final top10 = topProducts.take(10).toList();

    final categoryList = categoryAgg.entries
        .map((e) => CategoryBreakdownEntry(
              categoryId: e.key == '__uncat__' ? null : e.key,
              categoryName: e.value.name,
              revenueCents: e.value.revenue,
              quantity: e.value.qty,
            ))
        .toList()
      ..sort((a, b) => b.revenueCents.compareTo(a.revenueCents));

    // Hourly breakdown — bucket closed tickets by hour-of-day.
    final hourlyAgg =
        <int, ({int count, int revenue})>{};
    for (final t in paidTickets) {
      final closed = t.closedAt;
      if (closed == null) continue;
      final hour = closed.hour;
      final existing = hourlyAgg[hour];
      hourlyAgg[hour] = (
        count: (existing?.count ?? 0) + 1,
        revenue: (existing?.revenue ?? 0) + t.total,
      );
    }
    final hourly = hourlyAgg.entries
        .map((e) => HourlyBreakdownEntry(
              hour: e.key,
              ticketCount: e.value.count,
              revenueCents: e.value.revenue,
            ))
        .toList()
      ..sort((a, b) => a.hour.compareTo(b.hour));

    return ReportSnapshot(
      fromTs: from,
      toTs: to,
      ticketCount: paidTickets.length,
      grossTotalCents: grossTotal,
      netTotalCents: netTotal,
      taxTotalCents: taxTotal,
      discountTotalCents: discountTotal,
      giftTotalCents: giftTotal,
      tipTotalCents: tipTotal,
      voidCount: voidedTickets.length,
      mwstBuckets: mwstList,
      payments: paymentEntries,
      topProducts: top10,
      categories: categoryList,
      hourly: hourly,
    );
  }

  /// Snap a computed rate-in-basis-points to the nearest Swiss MWST rate
  /// if the input is within 5 bps (0.05%) of one. Otherwise return as-is
  /// so odd product configurations still show up.
  int _snapToStandardRate(int rateBps) {
    const standard = <int>[260, 380, 810];
    for (final r in standard) {
      if ((rateBps - r).abs() <= 5) return r;
    }
    return rateBps;
  }

  // ---------------------------------------------------------------------------
  // Z seal — monotonic, sequence-numbered, tamper-evident snapshots
  // ---------------------------------------------------------------------------

  /// Persist [snapshot] as a sealed Z report. Returns the entity with its
  /// freshly-assigned sequence number.
  Future<ZSealEntity> sealZReport({
    required String tenantId,
    required String closedBy,
    required ReportSnapshot snapshot,
  }) async {
    return _db.transaction<ZSealEntity>(() async {
      final nextSeq = await _nextSequenceNumber(tenantId);
      final id = 'zrep-${_uuid.v4()}';
      final now = DateTime.now();
      await _db.into(_db.zReports).insert(ZReportsCompanion(
            id: Value(id),
            tenantId: Value(tenantId),
            sequenceNumber: Value(nextSeq),
            fromTs: Value(snapshot.fromTs),
            toTs: Value(snapshot.toTs),
            closedAt: Value(now),
            closedBy: Value(closedBy),
            ticketCount: Value(snapshot.ticketCount),
            grossTotalCents: Value(snapshot.grossTotalCents),
            netTotalCents: Value(snapshot.netTotalCents),
            taxTotalCents: Value(snapshot.taxTotalCents),
            discountTotalCents: Value(snapshot.discountTotalCents),
            tipTotalCents: Value(snapshot.tipTotalCents),
            voidCount: Value(snapshot.voidCount),
            payloadJson: Value(snapshot.toJsonString()),
            createdAt: Value(now),
          ));
      return ZSealEntity(
        id: id,
        tenantId: tenantId,
        sequenceNumber: nextSeq,
        fromTs: snapshot.fromTs,
        toTs: snapshot.toTs,
        closedAt: now,
        closedBy: closedBy,
        snapshot: snapshot,
      );
    });
  }

  /// List previously-sealed Z reports for [tenantId], newest first.
  Future<List<ZSealEntity>> listZSeals(String tenantId, {int limit = 60}) async {
    final query = _db.select(_db.zReports)
      ..where((z) => z.tenantId.equals(tenantId))
      ..orderBy([(z) => OrderingTerm.desc(z.sequenceNumber)])
      ..limit(limit);
    final rows = await query.get();
    return rows
        .map((row) => ZSealEntity(
              id: row.id,
              tenantId: row.tenantId,
              sequenceNumber: row.sequenceNumber,
              fromTs: row.fromTs,
              toTs: row.toTs,
              closedAt: row.closedAt,
              closedBy: row.closedBy,
              snapshot: ReportSnapshot.fromJsonString(row.payloadJson),
            ))
        .toList();
  }

  Future<int> _nextSequenceNumber(String tenantId) async {
    final query = _db.select(_db.zReports)
      ..where((z) => z.tenantId.equals(tenantId))
      ..orderBy([(z) => OrderingTerm.desc(z.sequenceNumber)])
      ..limit(1);
    final row = await query.getSingleOrNull();
    return (row?.sequenceNumber ?? 0) + 1;
  }
}
