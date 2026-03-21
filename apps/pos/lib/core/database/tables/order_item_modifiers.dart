import 'package:drift/drift.dart';

@DataClassName('OrderItemModifier')
class OrderItemModifiers extends Table {
  TextColumn get id => text()();
  TextColumn get orderItemId => text()();
  TextColumn get modifierId => text()();
  TextColumn get modifierName => text()(); // denormalized
  IntColumn get priceDelta => integer().withDefault(const Constant(0))(); // cents
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
