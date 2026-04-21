import 'package:drift/drift.dart';

@DataClassName('Product')
class Products extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  TextColumn get categoryId => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  IntColumn get price => integer()(); // cents: 1500 = CHF 15.00
  IntColumn get costPrice => integer().withDefault(const Constant(0))(); // cents
  TextColumn get taxGroup => text().withDefault(const Constant('default'))();
  TextColumn get imagePath => text().nullable()();
  TextColumn get barcode => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// Operator-facing "sold out / 86'd" flag. When false the product is
  /// still listed on the menu (isActive), but temporarily cannot be
  /// ordered — the POS grid greys it out and blocks taps. Default true
  /// so existing rows behave as before.
  BoolColumn get isAvailable => boolean().withDefault(const Constant(true))();

  IntColumn get displayOrder => integer().withDefault(const Constant(0))();
  IntColumn get prepTimeMinutes => integer().nullable()();
  TextColumn get printerGroup => text().withDefault(const Constant('kitchen'))();

  /// Default Gang assignment for this product (references gang_templates.id).
  /// Null means fall back to category default or no Gang.
  TextColumn get defaultGangId => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
