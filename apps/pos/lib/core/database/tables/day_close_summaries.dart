/// Drift table definition for day-close (shift-close) summaries.
///
/// One record is written per closed shift, capturing the denomination
/// breakdown entered by the cashier, expected vs actual cash, and a
/// snapshot of revenue / payment breakdown for historical reporting.
library;

import 'package:drift/drift.dart';

@DataClassName('DayCloseSummaryRecord')
class DayCloseSummaries extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();

  /// Foreign-key reference to the closed shift.
  TextColumn get shiftId => text()();

  /// Terminal / register identifier.
  TextColumn get deviceId => text()();

  /// Name of the cashier who closed the shift.
  TextColumn get cashierName => text()();

  // ---------------------------------------------------------------------------
  // Revenue snapshot
  // ---------------------------------------------------------------------------

  /// Total revenue processed during the shift, in cents.
  IntColumn get totalRevenueCents => integer()();

  /// Number of completed orders (covers) during the shift.
  IntColumn get totalOrders => integer()();

  /// Average order value in cents.
  IntColumn get avgOrderCents => integer()();

  // ---------------------------------------------------------------------------
  // Cash reconciliation
  // ---------------------------------------------------------------------------

  /// Cash counted by the cashier from the denomination breakdown, in cents.
  IntColumn get countedCashCents => integer()();

  /// System-calculated expected cash (opening + cash sales + pay-ins - pay-outs), in cents.
  IntColumn get expectedCashCents => integer()();

  /// Discrepancy = counted - expected (positive = over, negative = short), in cents.
  IntColumn get discrepancyCents => integer()();

  // ---------------------------------------------------------------------------
  // JSON blobs
  // ---------------------------------------------------------------------------

  /// JSON-encoded denomination breakdown.
  /// Key = denomination in cents (int), value = piece count.
  /// Example: {"5":3,"10":5,"50":2,"100":4,"2000":1}
  TextColumn get denominationBreakdownJson => text()();

  /// JSON-encoded payment breakdown.
  /// Key = raw DB payment method string, value = total cents.
  /// Example: {"cash":12500,"credit_card":8750}
  TextColumn get paymentBreakdownJson => text()();

  // ---------------------------------------------------------------------------
  // Timestamps
  // ---------------------------------------------------------------------------

  /// When the shift was closed.
  DateTimeColumn get closedAt => dateTime()();

  /// When this record was inserted.
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
