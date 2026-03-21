/// Drift DAO for all inventory-related tables.
library;

import 'package:drift/drift.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/database/tables/inventory_items.dart';
import 'package:gastrocore_pos/core/database/tables/inventory_transactions.dart';
import 'package:gastrocore_pos/core/database/tables/suppliers.dart';

part 'inventory_dao.g.dart';

@DriftAccessor(tables: [InventoryItems, InventoryTransactions, Suppliers])
class InventoryDao extends DatabaseAccessor<AppDatabase>
    with _$InventoryDaoMixin {
  InventoryDao(super.db);

  // =========================================================================
  // InventoryItems
  // =========================================================================

  Future<List<InventoryItem>> getAllItems(String tenantId) =>
      (select(inventoryItems)
            ..where(
              (t) => t.tenantId.equals(tenantId) & t.isDeleted.equals(false),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .get();

  Future<List<InventoryItem>> getLowStockItems(String tenantId) async {
    final all = await getAllItems(tenantId);
    return all
        .where((i) => i.minQuantity > 0 && i.quantity <= i.minQuantity)
        .toList();
  }

  Future<List<InventoryItem>> getOutOfStockItems(String tenantId) async {
    final all = await getAllItems(tenantId);
    return all.where((i) => i.quantity <= 0).toList();
  }

  Future<InventoryItem?> getItemById(String id) =>
      (select(inventoryItems)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<InventoryItem?> getItemByProductId(
    String tenantId,
    String productId,
  ) =>
      (select(inventoryItems)
            ..where(
              (t) =>
                  t.tenantId.equals(tenantId) &
                  t.productId.equals(productId) &
                  t.isDeleted.equals(false),
            ))
          .getSingleOrNull();

  Stream<List<InventoryItem>> watchAllItems(String tenantId) =>
      (select(inventoryItems)
            ..where(
              (t) => t.tenantId.equals(tenantId) & t.isDeleted.equals(false),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .watch();

  Future<void> insertItem(InventoryItemsCompanion companion) =>
      into(inventoryItems).insertOnConflictUpdate(companion);

  Future<void> updateItem(InventoryItemsCompanion companion) =>
      (update(inventoryItems)..where((t) => t.id.equals(companion.id.value)))
          .write(companion);

  Future<void> softDeleteItem(String id) =>
      (update(inventoryItems)..where((t) => t.id.equals(id))).write(
        InventoryItemsCompanion(
          isDeleted: const Value(true),
          updatedAt: Value(DateTime.now()),
        ),
      );

  // =========================================================================
  // InventoryTransactions
  // =========================================================================

  Future<List<InventoryTransaction>> getTransactionsForItem(
    String itemId, {
    int limit = 50,
  }) =>
      (select(inventoryTransactions)
            ..where((t) => t.itemId.equals(itemId))
            ..orderBy([(t) => OrderingTerm.desc(t.timestamp)])
            ..limit(limit))
          .get();

  Future<List<InventoryTransaction>> getTransactionsByTenant(
    String tenantId, {
    DateTime? from,
    DateTime? to,
    String? type,
    int limit = 200,
  }) {
    final q = select(inventoryTransactions)
      ..where((t) => t.tenantId.equals(tenantId))
      ..orderBy([(t) => OrderingTerm.desc(t.timestamp)])
      ..limit(limit);
    if (from != null) {
      q.where((t) => t.timestamp.isBiggerOrEqualValue(from));
    }
    if (to != null) {
      q.where((t) => t.timestamp.isSmallerOrEqualValue(to));
    }
    if (type != null) {
      q.where((t) => t.type.equals(type));
    }
    return q.get();
  }

  Future<void> insertTransaction(InventoryTransactionsCompanion companion) =>
      into(inventoryTransactions).insert(companion);

  // =========================================================================
  // Suppliers
  // =========================================================================

  Future<List<Supplier>> getAllSuppliers(String tenantId) =>
      (select(suppliers)
            ..where(
              (t) => t.tenantId.equals(tenantId) & t.isDeleted.equals(false),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .get();

  Future<Supplier?> getSupplierById(String id) =>
      (select(suppliers)..where((t) => t.id.equals(id))).getSingleOrNull();

  Stream<List<Supplier>> watchAllSuppliers(String tenantId) =>
      (select(suppliers)
            ..where(
              (t) => t.tenantId.equals(tenantId) & t.isDeleted.equals(false),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .watch();

  Future<void> insertSupplier(SuppliersCompanion companion) =>
      into(suppliers).insertOnConflictUpdate(companion);

  Future<void> updateSupplier(SuppliersCompanion companion) =>
      (update(suppliers)..where((t) => t.id.equals(companion.id.value)))
          .write(companion);

  Future<void> softDeleteSupplier(String id) =>
      (update(suppliers)..where((t) => t.id.equals(id))).write(
        SuppliersCompanion(
          isDeleted: const Value(true),
          updatedAt: Value(DateTime.now()),
        ),
      );
}
