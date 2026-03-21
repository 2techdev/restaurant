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
  IntColumn get displayOrder => integer().withDefault(const Constant(0))();
  IntColumn get prepTimeMinutes => integer().nullable()();
  TextColumn get printerGroup => text().withDefault(const Constant('kitchen'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
