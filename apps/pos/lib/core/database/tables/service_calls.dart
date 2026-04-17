import 'package:drift/drift.dart';

/// Waiter-raised service calls: "needs water", "needs bread", "call manager", …
///
/// Rows flow through the sync queue to the boss/KDS dashboards so staff see
/// pending requests in real time. Acknowledged calls stay in the table for
/// day-close reporting (response-time stats).
@DataClassName('ServiceCall')
class ServiceCalls extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();

  /// Table the call was raised at. Nullable so a waiter can raise an ad-hoc
  /// call not bound to a seated party (e.g. clean spill at front).
  TextColumn get tableId => text().nullable()();

  /// Ticket tied to the call, if any. Lets dashboards surface the order.
  TextColumn get ticketId => text().nullable()();

  /// Waiter who raised the call.
  TextColumn get waiterId => text()();
  TextColumn get waiterName => text()();

  /// Canonical kind: water, bread, manager, cleanup, other.
  TextColumn get kind => text()();

  /// Freeform note from the waiter (optional, e.g. "table 7 extra napkins").
  TextColumn get note => text().nullable()();

  /// Status: pending → acknowledged → resolved.
  TextColumn get status => text().withDefault(const Constant('pending'))();

  /// When the call was raised (waiter side).
  DateTimeColumn get createdAt => dateTime()();

  /// When a user on the receiving end acknowledged the call.
  DateTimeColumn get acknowledgedAt => dateTime().nullable()();

  /// Who acknowledged it (dashboard / manager user id).
  TextColumn get acknowledgedBy => text().nullable()();

  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
