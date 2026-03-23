import 'package:drift/drift.dart';

/// Restaurant-specific Gang (course) definitions.
///
/// Gangs represent the multi-course service structure of a meal.
/// Swiss defaults: Gang 1 = Vorspeise, Gang 2 = Hauptgang,
/// Gang 3 = Dessert, Gang 4 = Getränke.
@DataClassName('GangTemplate')
class GangTemplates extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();

  /// Display name, e.g. "Vorspeise", "Hauptgang".
  TextColumn get name => text()();

  /// Sort order for display (1 = first course, etc.).
  IntColumn get sortOrder => integer().withDefault(const Constant(1))();

  /// Hex color string, e.g. '#528DFF'. Used for Gang badges on KDS/POS.
  TextColumn get color => text().withDefault(const Constant('#528DFF'))();

  /// Whether this is a system/default Gang (cannot be deleted).
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
