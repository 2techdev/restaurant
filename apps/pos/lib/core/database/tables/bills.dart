import 'package:drift/drift.dart';

@DataClassName('Bill')
class Bills extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  TextColumn get ticketId => text()();
  IntColumn get billNumber => integer()();
  IntColumn get subtotal => integer()(); // cents
  IntColumn get taxAmount => integer().withDefault(const Constant(0))(); // cents
  IntColumn get discountAmount => integer().withDefault(const Constant(0))(); // cents
  IntColumn get total => integer()(); // cents
  TextColumn get status => text().withDefault(const Constant('open'))(); // open, partially_paid, fully_paid, void
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
