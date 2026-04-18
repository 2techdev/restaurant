import 'package:drift/drift.dart';

/// Kitchen stations — cold / hot / dessert / bar etc.
///
/// The [code] column is the stable identifier used as a printer group on
/// [Products] and [KitchenTickets], while [name] / [icon] / [color] feed the
/// KDS station filter UI.
@DataClassName('Station')
class Stations extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();

  /// Stable code, e.g. 'kitchen', 'grill', 'cold', 'bar', 'dessert'.
  /// Matches [Products.printerGroup] and [KitchenTickets.printerGroup].
  TextColumn get code => text()();

  /// Display name, e.g. "Grill", "Kalte Küche".
  TextColumn get name => text()();

  /// Material icon code point, stored as string for portability.
  TextColumn get icon => text().nullable()();

  /// Hex color string (optional), e.g. '#F97316'.
  TextColumn get color => text().nullable()();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// System default station (cannot be deleted, only deactivated).
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
