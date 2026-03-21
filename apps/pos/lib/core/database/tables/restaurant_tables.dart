import 'package:drift/drift.dart';

@DataClassName('RestaurantTable')
class RestaurantTables extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  TextColumn get floorId => text()();
  TextColumn get name => text()();
  IntColumn get capacity => integer().withDefault(const Constant(4))();
  TextColumn get shape => text().withDefault(const Constant('rectangle'))(); // rectangle, circle, square
  RealColumn get posX => real().withDefault(const Constant(0.0))();
  RealColumn get posY => real().withDefault(const Constant(0.0))();
  RealColumn get width => real().withDefault(const Constant(100.0))();
  RealColumn get height => real().withDefault(const Constant(100.0))();
  TextColumn get status => text().withDefault(const Constant('available'))(); // available, occupied, reserved, dirty
  TextColumn get currentOrderId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
