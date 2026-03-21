/// Drift-backed inventory repository.
///
/// Orchestrates inventory items, transactions, and suppliers.
/// All stock mutations are recorded as immutable [InventoryTransaction] rows
/// so a full audit trail is preserved.
library;

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/features/inventory/domain/entities/inventory_item_entity.dart';
import 'package:gastrocore_pos/features/inventory/domain/entities/inventory_transaction_entity.dart';
import 'package:gastrocore_pos/features/inventory/domain/entities/supplier_entity.dart';
import 'package:gastrocore_pos/features/inventory/data/daos/inventory_dao.dart';

class InventoryRepositoryImpl {
  final AppDatabase _db;
  final _uuid = const Uuid();

  InventoryRepositoryImpl(this._db);

  InventoryDao get _dao => _db.inventoryDao;

  // =========================================================================
  // Inventory Items
  // =========================================================================

  Future<List<InventoryItemEntity>> getAllItems(String tenantId) async {
    final rows = await _dao.getAllItems(tenantId);
    return rows.map(_itemToEntity).toList();
  }

  Future<List<InventoryItemEntity>> getLowStockItems(String tenantId) async {
    final rows = await _dao.getLowStockItems(tenantId);
    return rows.map(_itemToEntity).toList();
  }

  Future<List<InventoryItemEntity>> getOutOfStockItems(String tenantId) async {
    final rows = await _dao.getOutOfStockItems(tenantId);
    return rows.map(_itemToEntity).toList();
  }

  Future<List<InventoryItemEntity>> getAlertItems(String tenantId) async {
    final all = await _dao.getAllItems(tenantId);
    return all
        .where((i) => i.quantity <= 0 || (i.minQuantity > 0 && i.quantity <= i.minQuantity))
        .map(_itemToEntity)
        .toList()
      ..sort((a, b) {
        // Out-of-stock first, then low stock, then by name
        if (a.isOutOfStock && !b.isOutOfStock) return -1;
        if (!a.isOutOfStock && b.isOutOfStock) return 1;
        return a.name.compareTo(b.name);
      });
  }

  Future<InventoryItemEntity?> getItemById(String id) async {
    final row = await _dao.getItemById(id);
    return row == null ? null : _itemToEntity(row);
  }

  Stream<List<InventoryItemEntity>> watchAllItems(String tenantId) =>
      _dao.watchAllItems(tenantId).map((rows) => rows.map(_itemToEntity).toList());

  Future<InventoryItemEntity> createItem(InventoryItemEntity entity) async {
    final now = DateTime.now();
    await _dao.insertItem(
      InventoryItemsCompanion(
        id: Value(entity.id),
        tenantId: Value(entity.tenantId),
        productId: Value(entity.productId),
        name: Value(entity.name),
        quantity: Value(entity.quantity),
        minQuantity: Value(entity.minQuantity),
        unit: Value(entity.unit),
        supplierId: Value(entity.supplierId),
        costPriceCents: Value(entity.costPriceCents),
        lastRestockDate: Value(entity.lastRestockDate),
        notes: Value(entity.notes),
        isActive: Value(entity.isActive),
        createdAt: Value(now),
        updatedAt: Value(now),
        isDeleted: const Value(false),
      ),
    );
    return (await getItemById(entity.id))!;
  }

  Future<void> updateItem(InventoryItemEntity entity) async {
    await _dao.updateItem(
      InventoryItemsCompanion(
        id: Value(entity.id),
        productId: Value(entity.productId),
        name: Value(entity.name),
        minQuantity: Value(entity.minQuantity),
        unit: Value(entity.unit),
        supplierId: Value(entity.supplierId),
        costPriceCents: Value(entity.costPriceCents),
        notes: Value(entity.notes),
        isActive: Value(entity.isActive),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> deleteItem(String id) => _dao.softDeleteItem(id);

  // =========================================================================
  // Stock Mutations (all create an InventoryTransaction row)
  // =========================================================================

  /// Add stock (restock from supplier or manual addition).
  Future<InventoryItemEntity> restock({
    required String tenantId,
    required String itemId,
    required double quantityAdded,
    String? userId,
    String? userName,
    String? notes,
    DateTime? date,
  }) async {
    final item = await _dao.getItemById(itemId);
    if (item == null) throw StateError('InventoryItem $itemId not found');

    final before = item.quantity;
    final after = before + quantityAdded;

    await _db.transaction(() async {
      await _dao.updateItem(
        InventoryItemsCompanion(
          id: Value(itemId),
          quantity: Value(after),
          lastRestockDate: Value(date ?? DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await _dao.insertTransaction(
        InventoryTransactionsCompanion(
          id: Value(_uuid.v4()),
          tenantId: Value(tenantId),
          itemId: Value(itemId),
          type: const Value('restock'),
          quantity: Value(quantityAdded),
          quantityBefore: Value(before),
          quantityAfter: Value(after),
          timestamp: Value(date ?? DateTime.now()),
          userId: Value(userId),
          userName: Value(userName),
          notes: Value(notes),
        ),
      );
    });

    return (await getItemById(itemId))!;
  }

  /// Deduct stock for a completed sale.
  ///
  /// Called automatically when an order is completed.
  /// Silent – does not throw if item is not found (product may not be tracked).
  Future<void> deductForSale({
    required String tenantId,
    required String productId,
    required double quantity,
    required String ticketId,
    String? userId,
    String? userName,
  }) async {
    final item = await _dao.getItemByProductId(tenantId, productId);
    if (item == null) return; // product not tracked in inventory

    final before = item.quantity;
    final after = (before - quantity).clamp(-9999.0, double.infinity);

    await _db.transaction(() async {
      await _dao.updateItem(
        InventoryItemsCompanion(
          id: Value(item.id),
          quantity: Value(after),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await _dao.insertTransaction(
        InventoryTransactionsCompanion(
          id: Value(_uuid.v4()),
          tenantId: Value(tenantId),
          itemId: Value(item.id),
          type: const Value('sale'),
          quantity: Value(-quantity),
          quantityBefore: Value(before),
          quantityAfter: Value(after),
          timestamp: Value(DateTime.now()),
          userId: Value(userId),
          userName: Value(userName),
          ticketId: Value(ticketId),
          notes: const Value('Auto-deducted on order completion'),
        ),
      );
    });
  }

  /// Record waste / spoilage.
  Future<InventoryItemEntity> recordWaste({
    required String tenantId,
    required String itemId,
    required double quantity,
    String? userId,
    String? userName,
    String? notes,
  }) async {
    final item = await _dao.getItemById(itemId);
    if (item == null) throw StateError('InventoryItem $itemId not found');

    final before = item.quantity;
    final after = (before - quantity).clamp(-9999.0, double.infinity);

    await _db.transaction(() async {
      await _dao.updateItem(
        InventoryItemsCompanion(
          id: Value(itemId),
          quantity: Value(after),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await _dao.insertTransaction(
        InventoryTransactionsCompanion(
          id: Value(_uuid.v4()),
          tenantId: Value(tenantId),
          itemId: Value(itemId),
          type: const Value('waste'),
          quantity: Value(-quantity),
          quantityBefore: Value(before),
          quantityAfter: Value(after),
          timestamp: Value(DateTime.now()),
          userId: Value(userId),
          userName: Value(userName),
          notes: Value(notes),
        ),
      );
    });

    return (await getItemById(itemId))!;
  }

  /// Manual adjustment (stock-take correction).
  Future<InventoryItemEntity> adjust({
    required String tenantId,
    required String itemId,
    required double newQuantity,
    String? userId,
    String? userName,
    String? notes,
  }) async {
    final item = await _dao.getItemById(itemId);
    if (item == null) throw StateError('InventoryItem $itemId not found');

    final before = item.quantity;
    final delta = newQuantity - before;

    await _db.transaction(() async {
      await _dao.updateItem(
        InventoryItemsCompanion(
          id: Value(itemId),
          quantity: Value(newQuantity),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await _dao.insertTransaction(
        InventoryTransactionsCompanion(
          id: Value(_uuid.v4()),
          tenantId: Value(tenantId),
          itemId: Value(itemId),
          type: const Value('adjustment'),
          quantity: Value(delta),
          quantityBefore: Value(before),
          quantityAfter: Value(newQuantity),
          timestamp: Value(DateTime.now()),
          userId: Value(userId),
          userName: Value(userName),
          notes: Value(notes),
        ),
      );
    });

    return (await getItemById(itemId))!;
  }

  // =========================================================================
  // Transactions (read-only)
  // =========================================================================

  Future<List<InventoryTransactionEntity>> getTransactionsForItem(
    String itemId, {
    int limit = 50,
  }) async {
    final rows = await _dao.getTransactionsForItem(itemId, limit: limit);
    return rows.map(_txToEntity).toList();
  }

  Future<List<InventoryTransactionEntity>> getTransactionsByTenant(
    String tenantId, {
    DateTime? from,
    DateTime? to,
    String? type,
    int limit = 200,
  }) async {
    final rows = await _dao.getTransactionsByTenant(
      tenantId,
      from: from,
      to: to,
      type: type,
      limit: limit,
    );
    return rows.map(_txToEntity).toList();
  }

  // =========================================================================
  // Suppliers
  // =========================================================================

  Future<List<SupplierEntity>> getAllSuppliers(String tenantId) async {
    final rows = await _dao.getAllSuppliers(tenantId);
    return rows.map(_supplierToEntity).toList();
  }

  Stream<List<SupplierEntity>> watchAllSuppliers(String tenantId) =>
      _dao.watchAllSuppliers(tenantId).map(
        (rows) => rows.map(_supplierToEntity).toList(),
      );

  Future<SupplierEntity?> getSupplierById(String id) async {
    final row = await _dao.getSupplierById(id);
    return row == null ? null : _supplierToEntity(row);
  }

  Future<void> createSupplier(SupplierEntity entity) async {
    final now = DateTime.now();
    await _dao.insertSupplier(
      SuppliersCompanion(
        id: Value(entity.id),
        tenantId: Value(entity.tenantId),
        name: Value(entity.name),
        email: Value(entity.email),
        phone: Value(entity.phone),
        address: Value(entity.address),
        notes: Value(entity.notes),
        isActive: Value(entity.isActive),
        createdAt: Value(now),
        updatedAt: Value(now),
        isDeleted: const Value(false),
      ),
    );
  }

  Future<void> updateSupplier(SupplierEntity entity) async {
    await _dao.updateSupplier(
      SuppliersCompanion(
        id: Value(entity.id),
        name: Value(entity.name),
        email: Value(entity.email),
        phone: Value(entity.phone),
        address: Value(entity.address),
        notes: Value(entity.notes),
        isActive: Value(entity.isActive),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> deleteSupplier(String id) => _dao.softDeleteSupplier(id);

  // =========================================================================
  // Mappers
  // =========================================================================

  InventoryItemEntity _itemToEntity(InventoryItem row) => InventoryItemEntity(
        id: row.id,
        tenantId: row.tenantId,
        productId: row.productId,
        name: row.name,
        quantity: row.quantity,
        minQuantity: row.minQuantity,
        unit: row.unit,
        supplierId: row.supplierId,
        costPriceCents: row.costPriceCents,
        lastRestockDate: row.lastRestockDate,
        notes: row.notes,
        isActive: row.isActive,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
      );

  InventoryTransactionEntity _txToEntity(InventoryTransaction row) =>
      InventoryTransactionEntity(
        id: row.id,
        tenantId: row.tenantId,
        itemId: row.itemId,
        type: TransactionType.fromString(row.type),
        quantity: row.quantity,
        quantityBefore: row.quantityBefore,
        quantityAfter: row.quantityAfter,
        timestamp: row.timestamp,
        userId: row.userId,
        userName: row.userName,
        ticketId: row.ticketId,
        notes: row.notes,
      );

  SupplierEntity _supplierToEntity(Supplier row) => SupplierEntity(
        id: row.id,
        tenantId: row.tenantId,
        name: row.name,
        email: row.email,
        phone: row.phone,
        address: row.address,
        notes: row.notes,
        isActive: row.isActive,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
      );
}
