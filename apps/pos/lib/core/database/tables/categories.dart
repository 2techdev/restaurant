import 'package:drift/drift.dart';

@DataClassName('Category')
class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  TextColumn get name => text()();
  IntColumn get displayOrder => integer().withDefault(const Constant(0))();
  TextColumn get color => text().nullable()(); // hex string e.g. '#FF5733'
  TextColumn get icon => text().nullable()(); // icon name or emoji
  TextColumn get parentId => text().nullable()(); // self-reference for subcategories

  /// Default Gang for products in this category (references gang_templates.id).
  /// Used as fallback when a product has no explicit defaultGangId.
  TextColumn get defaultGangId => text().nullable()();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
