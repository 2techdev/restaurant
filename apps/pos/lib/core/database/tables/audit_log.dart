import 'package:drift/drift.dart';

@DataClassName('AuditLogEntry')
class AuditLog extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  TextColumn get branchId => text().nullable()();
  TextColumn get deviceId => text()();

  /// The staff member who performed the action.
  TextColumn get userId => text()();
  TextColumn get userName => text()();

  /// The manager / admin who authorised the action (overrides, voids, etc.).
  ///
  /// Null when no authorisation was required.
  TextColumn get managerId => text().nullable()();
  TextColumn get managerName => text().nullable()();

  TextColumn get action => text()(); // AuditAction enum name
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get oldValueJson => text().nullable()();
  TextColumn get newValueJson => text().nullable()();
  TextColumn get reason => text().nullable()();
  TextColumn get ipAddress => text().nullable()();
  DateTimeColumn get timestamp => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
