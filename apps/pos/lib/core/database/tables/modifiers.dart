import 'package:drift/drift.dart';

@DataClassName('Modifier')
class Modifiers extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  TextColumn get groupId => text()();
  TextColumn get name => text()();
  IntColumn get priceDelta => integer().withDefault(const Constant(0))(); // cents
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  IntColumn get displayOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
