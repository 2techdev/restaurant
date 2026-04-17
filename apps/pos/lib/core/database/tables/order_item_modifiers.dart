import 'package:drift/drift.dart';

@DataClassName('OrderItemModifier')
class OrderItemModifiers extends Table {
  TextColumn get id => text()();
  TextColumn get orderItemId => text()();
  TextColumn get modifierId => text()();
  TextColumn get modifierName => text()(); // denormalized
  IntColumn get priceDelta => integer().withDefault(const Constant(0))(); // cents
  // SambaPOS askQuantity richness (v12): each applied modifier can carry
  // a per-unit multiplier (e.g. "3× Extra Cheese"). Default 1 keeps legacy
  // rows single-quantity.
  IntColumn get quantity => integer().withDefault(const Constant(1))();
  // SambaPOS freeTagging richness (v12): operator-entered free-form note
  // attached to this specific modifier ("less salt", "extra crispy").
  // Nullable because only a small fraction of selections carry one.
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
