import 'package:drift/drift.dart';

/// Immutable ledger of every stock movement.
///
/// Types:
///   restock    – goods received from supplier
///   sale       – deducted automatically when an order is completed
///   waste      – spoilage / breakage / expiry recorded by staff
///   adjustment – manual correction during a stock-take
@DataClassName('InventoryTransaction')
class InventoryTransactions extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  TextColumn get itemId => text()(); // FK → inventory_items.id

  /// One of: restock | sale | waste | adjustment
  TextColumn get type => text()();

  /// Delta applied. Positive = stock added, negative = stock removed.
  RealColumn get quantity => real()();

  RealColumn get quantityBefore => real()();
  RealColumn get quantityAfter => real()();

  DateTimeColumn get timestamp => dateTime()();
  TextColumn get userId => text().nullable()();
  TextColumn get userName => text().nullable()();

  /// Link to a [Tickets] row when type == 'sale'.
  TextColumn get ticketId => text().nullable()();

  TextColumn get notes => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
