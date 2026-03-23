import 'package:drift/drift.dart';

/// Records manager PIN override events for audit purposes.
///
/// When a manager enters their PIN to approve a restricted action (void,
/// discount, refund, etc.) a row is written here so the event appears in
/// the audit trail independently of the entity it authorised.
@DataClassName('ManagerPinEntry')
class ManagerPins extends Table {
  /// UUID generated at override time.
  TextColumn get id => text()();

  /// Tenant this event belongs to.
  TextColumn get tenantId => text()();

  /// The manager's user ID (references Users.id).
  TextColumn get managerId => text()();

  /// The manager's display name at the time of the override.
  TextColumn get managerName => text()();

  /// The action being authorised (e.g. 'void_ticket', 'apply_discount').
  TextColumn get action => text()();

  /// Entity type the action targets (e.g. 'ticket', 'order_item').
  TextColumn get entityType => text().nullable()();

  /// ID of the specific entity being acted upon.
  TextColumn get entityId => text().nullable()();

  /// Optional reason entered by the manager.
  TextColumn get reason => text().nullable()();

  /// Device from which the override was triggered.
  TextColumn get deviceId => text()();

  /// When the PIN was entered and the override granted.
  DateTimeColumn get authorisedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
