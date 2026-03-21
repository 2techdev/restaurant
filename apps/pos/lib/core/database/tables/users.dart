import 'package:drift/drift.dart';

@DataClassName('User')
class Users extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  TextColumn get name => text()();
  TextColumn get pinHash => text()();

  /// Optional separate PIN used exclusively for manager override authorisation.
  ///
  /// When set, this PIN is accepted in [ManagerPinDialog] in addition to the
  /// regular [pinHash].  Allows a manager to have a short login PIN (4 digits)
  /// and a separate, more secure override PIN.  If null, [pinHash] is used for
  /// both login and override.
  TextColumn get managerPinHash => text().nullable()();

  TextColumn get role => text()(); // admin, manager, waiter, cashier, kitchen
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get permissionsJson => text().nullable()();
  TextColumn get avatarPath => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
