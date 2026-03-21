import 'package:drift/drift.dart';

/// Order-type-based price adjustment rules.
/// E.g., "takeaway gets 10% discount" or "delivery gets CHF 2.00 surcharge".
@DataClassName('OrderTypeRule')
class OrderTypeRules extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  TextColumn get orderType => text()(); // 'takeaway', 'delivery'
  TextColumn get adjustmentType => text()(); // 'percentage_discount', 'fixed_discount', 'percentage_surcharge', 'fixed_surcharge'
  IntColumn get adjustmentValue => integer()(); // percentage * 100 (1000 = 10%) or fixed cents
  BoolColumn get isActive =>
      boolean().withDefault(const Constant(true))();
  TextColumn get description => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
