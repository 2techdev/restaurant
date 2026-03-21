import 'package:drift/drift.dart';

@DataClassName('User')
class Users extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  TextColumn get name => text()();
  TextColumn get pinHash => text()();
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
