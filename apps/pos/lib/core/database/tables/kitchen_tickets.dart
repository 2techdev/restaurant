import 'package:drift/drift.dart';

@DataClassName('KitchenTicket')
class KitchenTickets extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  TextColumn get ticketId => text()();
  TextColumn get kitchenTableName => text().nullable()(); // denormalized table name
  TextColumn get waiterName => text().nullable()(); // denormalized waiter name
  IntColumn get orderNumber => integer()();
  TextColumn get printerGroup => text().withDefault(const Constant('kitchen'))();
  TextColumn get status => text().withDefault(const Constant('pending'))(); // pending, acknowledged, preparing, ready, served, void
  DateTimeColumn get sentAt => dateTime()();
  DateTimeColumn get startedAt => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
