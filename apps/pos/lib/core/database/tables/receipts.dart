import 'package:drift/drift.dart';

@DataClassName('Receipt')
class Receipts extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  TextColumn get ticketId => text()();
  TextColumn get billId => text()();
  TextColumn get receiptNumber => text()();
  TextColumn get receiptType => text().withDefault(const Constant('sale'))(); // sale, refund, void
  TextColumn get content => text()(); // JSON of receipt data
  DateTimeColumn get printedAt => dateTime().nullable()();
  IntColumn get printCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
