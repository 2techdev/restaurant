import 'package:drift/drift.dart';

@DataClassName('Tenant')
class Tenants extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get address => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get taxId => text().nullable()();
  RealColumn get defaultTaxRate => real().withDefault(const Constant(0.0))();
  TextColumn get currencyCode => text().withDefault(const Constant('CHF'))();
  TextColumn get countryCode => text().withDefault(const Constant('CH'))();
  TextColumn get settingsJson => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
