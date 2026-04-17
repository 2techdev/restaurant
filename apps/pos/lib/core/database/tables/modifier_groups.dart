import 'package:drift/drift.dart';

@DataClassName('ModifierGroup')
class ModifierGroups extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  TextColumn get name => text()();
  TextColumn get selectionType => text().withDefault(const Constant('single'))(); // single, multiple
  IntColumn get minSelections => integer().withDefault(const Constant(0))();
  // maxSelections: 0 = unlimited (SambaPOS convention). Default 1 keeps
  // legacy rows single-select until explicitly widened.
  IntColumn get maxSelections => integer().withDefault(const Constant(1))();
  BoolColumn get isRequired => boolean().withDefault(const Constant(false))();
  // Order-tag richness (added v11; see app_database.dart migration).
  BoolColumn get askQuantity =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get freeTagging =>
      boolean().withDefault(const Constant(false))();
  IntColumn get columnCount => integer().withDefault(const Constant(1))();
  TextColumn get prefix => text().withDefault(const Constant(''))();
  IntColumn get displayOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
