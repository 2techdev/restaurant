import 'package:drift/drift.dart';

@DataClassName('Shift')
class Shifts extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  TextColumn get userId => text()();
  TextColumn get deviceId => text()();
  IntColumn get openingCash => integer()(); // cents
  IntColumn get closingCash => integer().nullable()(); // cents
  IntColumn get expectedCash => integer().nullable()(); // cents
  IntColumn get difference => integer().nullable()(); // cents
  IntColumn get totalSales => integer().withDefault(const Constant(0))(); // cents
  IntColumn get totalOrders => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('open'))(); // open, closing, closed
  DateTimeColumn get openedAt => dateTime()();
  DateTimeColumn get closedAt => dateTime().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
