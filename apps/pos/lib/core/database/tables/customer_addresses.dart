import 'package:drift/drift.dart';

@DataClassName('CustomerAddressRow')
class CustomerAddresses extends Table {
  TextColumn get id => text()();
  TextColumn get customerId => text()();
  TextColumn get label => text().withDefault(const Constant('Home'))(); // Home, Work, Other
  TextColumn get street => text()();
  TextColumn get city => text()();
  TextColumn get postalCode => text()();
  TextColumn get country => text().withDefault(const Constant('CH'))();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
