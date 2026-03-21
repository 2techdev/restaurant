import 'package:drift/drift.dart';

@DataClassName('CashMovement')
class CashMovements extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  TextColumn get shiftId => text()();
  TextColumn get type => text()(); // pay_in, pay_out, tip, expense
  IntColumn get amount => integer()(); // cents
  TextColumn get description => text().nullable()();
  TextColumn get performedBy => text()(); // userId
  DateTimeColumn get performedAt => dateTime()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
