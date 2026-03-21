import 'package:drift/drift.dart';

/// Inventory items table.
///
/// Tracks stock levels for products (and standalone ingredients).
/// [productId] is nullable — a restaurant may track items (e.g. "Olive Oil")
/// that are not directly mapped to a menu product.
@DataClassName('InventoryItem')
class InventoryItems extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();

  /// Optional link to a [Products] row.
  TextColumn get productId => text().nullable()();

  TextColumn get name => text()();

  /// Current stock level (may be fractional, e.g. 1.5 kg).
  RealColumn get quantity => real().withDefault(const Constant(0.0))();

  /// Threshold below which a low-stock alert fires.
  RealColumn get minQuantity => real().withDefault(const Constant(0.0))();

  /// Measurement unit string: pcs | kg | L | g | mL | box | portion …
  TextColumn get unit => text().withDefault(const Constant('pcs'))();

  /// Optional link to a [Suppliers] row.
  TextColumn get supplierId => text().nullable()();

  /// Purchase / cost price in cents (e.g. 450 = CHF 4.50).
  IntColumn get costPriceCents => integer().withDefault(const Constant(0))();

  DateTimeColumn get lastRestockDate => dateTime().nullable()();
  TextColumn get notes => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
