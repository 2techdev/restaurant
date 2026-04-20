/// Tamper-evident daily Z-report seals.
///
/// Each row records a closed business day (or shift close) with a
/// per-tenant sequence number that only goes up. The row includes the
/// sealed totals and MWST breakdown so repeat runs can't re-aggregate
/// transactions into a new Z number — the legal requirement for Swiss
/// register tape parity.
library;

import 'package:drift/drift.dart';

@DataClassName('ZReport')
class ZReports extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();

  /// Monotonic sequence number within the tenant. Unique via the
  /// `(tenantId, sequenceNumber)` guard the repository enforces at
  /// write time; SQLite lacks a portable AUTOINCREMENT-within-group.
  IntColumn get sequenceNumber => integer()();

  /// Inclusive window covered by the report (both in local time).
  DateTimeColumn get fromTs => dateTime()();
  DateTimeColumn get toTs => dateTime()();

  /// When the operator sealed the report. Monotonic — repeat closes
  /// in the same window are allowed but get a new seal.
  DateTimeColumn get closedAt => dateTime()();

  TextColumn get closedBy => text()();

  /// Number of paid tickets covered by this seal.
  IntColumn get ticketCount => integer().withDefault(const Constant(0))();

  IntColumn get grossTotalCents => integer().withDefault(const Constant(0))();
  IntColumn get netTotalCents => integer().withDefault(const Constant(0))();
  IntColumn get taxTotalCents => integer().withDefault(const Constant(0))();
  IntColumn get discountTotalCents =>
      integer().withDefault(const Constant(0))();
  IntColumn get tipTotalCents => integer().withDefault(const Constant(0))();
  IntColumn get voidCount => integer().withDefault(const Constant(0))();

  /// JSON blob — stable serialization of the full report payload so the
  /// PDF export can reproduce the seal byte-for-byte without re-querying.
  TextColumn get payloadJson => text()();

  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
