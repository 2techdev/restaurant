/// Drift-backed repository for [DayCloseSummaryEntity] persistence.
///
/// Writes one record per closed shift (called from [DayCloseNotifier]) and
/// exposes history queries for back-office reporting.
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/shifts/domain/entities/day_close_summary_entity.dart';

class DayCloseRepositoryImpl {
  final AppDatabase _db;

  DayCloseRepositoryImpl(this._db);

  // =========================================================================
  // Write
  // =========================================================================

  /// Persist a new day-close summary and return the stored entity.
  Future<DayCloseSummaryEntity> saveSummary({
    required String tenantId,
    required String shiftId,
    required String deviceId,
    required String cashierName,
    required int totalRevenueCents,
    required int totalOrders,
    required int avgOrderCents,
    required int countedCashCents,
    required int expectedCashCents,
    required int discrepancyCents,
    required Map<int, int> denominationBreakdown,
    required Map<String, int> paymentBreakdown,
    required DateTime closedAt,
  }) async {
    final id = IdGenerator.generateId();
    final now = DateTime.now();

    // Encode maps as JSON (keys must be strings in JSON).
    final denomJson = jsonEncode(
      denominationBreakdown.map((k, v) => MapEntry(k.toString(), v)),
    );
    final paymentJson = jsonEncode(paymentBreakdown);

    await _db.into(_db.dayCloseSummaries).insert(
          DayCloseSummariesCompanion(
            id: Value(id),
            tenantId: Value(tenantId),
            shiftId: Value(shiftId),
            deviceId: Value(deviceId),
            cashierName: Value(cashierName),
            totalRevenueCents: Value(totalRevenueCents),
            totalOrders: Value(totalOrders),
            avgOrderCents: Value(avgOrderCents),
            countedCashCents: Value(countedCashCents),
            expectedCashCents: Value(expectedCashCents),
            discrepancyCents: Value(discrepancyCents),
            denominationBreakdownJson: Value(denomJson),
            paymentBreakdownJson: Value(paymentJson),
            closedAt: Value(closedAt),
            createdAt: Value(now),
          ),
        );

    return (await getById(id))!;
  }

  // =========================================================================
  // Read
  // =========================================================================

  /// Fetch a single summary by [id], or `null` if not found.
  Future<DayCloseSummaryEntity?> getById(String id) async {
    final query = _db.select(_db.dayCloseSummaries)
      ..where((t) => t.id.equals(id));
    final row = await query.getSingleOrNull();
    return row == null ? null : _toEntity(row);
  }

  /// Fetch the summary for a specific [shiftId], or `null` if none exists.
  Future<DayCloseSummaryEntity?> getByShiftId(String shiftId) async {
    final query = _db.select(_db.dayCloseSummaries)
      ..where((t) => t.shiftId.equals(shiftId));
    final row = await query.getSingleOrNull();
    return row == null ? null : _toEntity(row);
  }

  /// Return all summaries for [tenantId], newest first, up to [limit].
  Future<List<DayCloseSummaryEntity>> getHistory(
    String tenantId, {
    int limit = 50,
  }) async {
    final query = _db.select(_db.dayCloseSummaries)
      ..where((t) => t.tenantId.equals(tenantId))
      ..orderBy([(t) => OrderingTerm.desc(t.closedAt)])
      ..limit(limit);
    final rows = await query.get();
    return rows.map(_toEntity).toList();
  }

  // =========================================================================
  // Mapper
  // =========================================================================

  DayCloseSummaryEntity _toEntity(DayCloseSummaryRecord row) {
    // Decode denomination breakdown: JSON keys are strings → convert to int.
    final rawDenom =
        jsonDecode(row.denominationBreakdownJson) as Map<String, dynamic>;
    final denomBreakdown = rawDenom.map(
      (k, v) => MapEntry(int.parse(k), (v as num).toInt()),
    );

    // Decode payment breakdown.
    final rawPayment =
        jsonDecode(row.paymentBreakdownJson) as Map<String, dynamic>;
    final paymentBreakdown = rawPayment.map(
      (k, v) => MapEntry(k, (v as num).toInt()),
    );

    return DayCloseSummaryEntity(
      id: row.id,
      tenantId: row.tenantId,
      shiftId: row.shiftId,
      deviceId: row.deviceId,
      cashierName: row.cashierName,
      totalRevenueCents: row.totalRevenueCents,
      totalOrders: row.totalOrders,
      avgOrderCents: row.avgOrderCents,
      countedCashCents: row.countedCashCents,
      expectedCashCents: row.expectedCashCents,
      discrepancyCents: row.discrepancyCents,
      denominationBreakdown: denomBreakdown,
      paymentBreakdown: paymentBreakdown,
      closedAt: row.closedAt,
      createdAt: row.createdAt,
    );
  }
}
