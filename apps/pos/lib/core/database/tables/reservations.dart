import 'package:drift/drift.dart';

@DataClassName('Reservation')
class Reservations extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  TextColumn get customerName => text()();
  TextColumn get customerPhone => text().nullable()();
  TextColumn get customerEmail => text().nullable()();
  TextColumn get tableId => text().nullable()();
  DateTimeColumn get date => dateTime()();
  DateTimeColumn get timeStart => dateTime()();
  DateTimeColumn get timeEnd => dateTime()();
  IntColumn get partySize => integer().withDefault(const Constant(2))();
  // status: pending, confirmed, seated, cancelled, no_show
  TextColumn get status => text().withDefault(const Constant('pending'))();
  TextColumn get notes => text().nullable()();
  TextColumn get channel => text().withDefault(const Constant('walk_in'))(); // walk_in, online, phone
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get createdBy => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
