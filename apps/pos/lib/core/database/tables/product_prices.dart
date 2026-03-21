import 'package:drift/drift.dart';

/// Per-order-type price overrides for products.
/// If no override exists for an order type, use the product's base price.
@DataClassName('ProductPrice')
class ProductPrices extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  TextColumn get productId => text()();
  TextColumn get orderType => text()(); // 'dine_in', 'takeaway', 'delivery'
  IntColumn get price => integer()(); // cents - the override price
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
