import 'package:drift/drift.dart';

/// Tax profiles: maps country + order_type + product_tax_group to VAT rate.
/// Supports date ranges for rate changes (e.g., Germany changed rates Jan 2026).
@DataClassName('TaxProfile')
class TaxProfiles extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  TextColumn get countryCode => text()(); // 'CH', 'DE'
  TextColumn get orderType => text()(); // 'dine_in', 'takeaway', 'delivery', '*' (all)
  TextColumn get productTaxGroup => text()(); // 'food', 'beverage', 'alcohol', 'standard'
  RealColumn get taxRate => real()(); // percentage e.g. 8.1
  TextColumn get taxName => text()(); // 'MwSt 8.1%', 'USt 7%'
  BoolColumn get isDefault =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get validFrom => dateTime().nullable()();
  DateTimeColumn get validUntil => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
