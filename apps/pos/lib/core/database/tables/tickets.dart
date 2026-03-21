import 'package:drift/drift.dart';

@DataClassName('Ticket')
class Tickets extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  IntColumn get orderNumber => integer()();
  TextColumn get orderType => text().withDefault(const Constant('dine_in'))(); // dine_in, takeaway, delivery, online
  TextColumn get tableId => text().nullable()();
  TextColumn get waiterId => text().nullable()();
  TextColumn get customerName => text().nullable()();
  IntColumn get guestCount => integer().withDefault(const Constant(1))();
  TextColumn get status => text().withDefault(const Constant('open'))(); // open, items_added, sent_to_kitchen, partially_served, fully_served, bill_requested, partially_paid, fully_paid, closed, void
  TextColumn get channel => text().withDefault(const Constant('pos'))(); // pos, waiter, qr, kiosk, web
  IntColumn get subtotal => integer().withDefault(const Constant(0))(); // cents
  IntColumn get taxAmount => integer().withDefault(const Constant(0))(); // cents
  IntColumn get discountAmount => integer().withDefault(const Constant(0))(); // cents
  TextColumn get discountType => text().nullable()(); // percent, fixed
  RealColumn get discountValue => real().nullable()();
  IntColumn get total => integer().withDefault(const Constant(0))(); // cents
  TextColumn get notes => text().nullable()();
  DateTimeColumn get openedAt => dateTime()();
  DateTimeColumn get closedAt => dateTime().nullable()();
  TextColumn get deviceId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
