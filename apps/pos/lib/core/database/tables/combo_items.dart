import 'package:drift/drift.dart';

@DataClassName('ComboItem')
class ComboItems extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  TextColumn get comboProductId => text()(); // The combo product
  TextColumn get itemProductId => text()(); // Product included in combo
  IntColumn get quantity => integer().withDefault(const Constant(1))();
  TextColumn get groupName =>
      text().nullable()(); // "Choose your drink", null = fixed item
  BoolColumn get isRequired =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get canSubstitute =>
      boolean().withDefault(const Constant(false))();
  IntColumn get displayOrder =>
      integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
