import 'package:drift/drift.dart';

@DataClassName('Payment')
class Payments extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  TextColumn get billId => text()();
  TextColumn get ticketId => text()();
  TextColumn get paymentMethod => text()(); // cash, credit_card, debit_card, other
  IntColumn get amount => integer()(); // cents
  IntColumn get tipAmount => integer().withDefault(const Constant(0))(); // cents
  IntColumn get tenderedAmount => integer().withDefault(const Constant(0))(); // cents
  IntColumn get changeAmount => integer().withDefault(const Constant(0))(); // cents
  TextColumn get reference => text().nullable()();
  TextColumn get receivedBy => text()(); // userId
  DateTimeColumn get paidAt => dateTime()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
