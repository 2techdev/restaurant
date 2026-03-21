import 'package:drift/drift.dart';

@DataClassName('ModifierGroup')
class ModifierGroups extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  TextColumn get name => text()();
  TextColumn get selectionType => text().withDefault(const Constant('single'))(); // single, multiple
  IntColumn get minSelections => integer().withDefault(const Constant(0))();
  IntColumn get maxSelections => integer().withDefault(const Constant(1))();
  BoolColumn get isRequired => boolean().withDefault(const Constant(false))();
  IntColumn get displayOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
