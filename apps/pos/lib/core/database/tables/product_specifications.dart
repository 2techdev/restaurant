import 'package:drift/drift.dart';

@DataClassName('ProductSpecification')
class ProductSpecifications extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  TextColumn get productId => text()();
  TextColumn get name => text()(); // "Small", "Medium", "Large", "Default"
  IntColumn get price => integer()(); // Price in cents for this spec
  BoolColumn get isDefault =>
      boolean().withDefault(const Constant(false))();
  IntColumn get displayOrder =>
      integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
