import 'package:drift/drift.dart';

@DataClassName('KitchenTicketItem')
class KitchenTicketItems extends Table {
  TextColumn get id => text()();
  TextColumn get kitchenTicketId => text()();
  TextColumn get orderItemId => text()();
  TextColumn get productName => text()();
  RealColumn get quantity => real()();
  TextColumn get modifiersText => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('pending'))(); // pending, preparing, ready, served, void
  TextColumn get gangId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
