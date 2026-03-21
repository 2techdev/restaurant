import 'package:drift/drift.dart';

@DataClassName('LoyaltyTransactionRow')
class LoyaltyTransactions extends Table {
  TextColumn get id => text()();
  TextColumn get customerId => text()();
  IntColumn get points => integer()(); // positive = earn, negative = redeem
  TextColumn get type => text()(); // 'earn' | 'redeem' | 'adjust' | 'expire'
  TextColumn get orderId => text().nullable()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
