import 'package:drift/drift.dart';

@DataClassName('ProductModifierGroup')
class ProductModifierGroups extends Table {
  TextColumn get id => text()();
  TextColumn get productId => text()();
  TextColumn get modifierGroupId => text()();
  IntColumn get displayOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}
