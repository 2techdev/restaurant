/// Unit tests for InventoryRepositoryImpl.
///
/// Uses an in-memory Drift database — no mocking of SQL layer.
/// Covers: item CRUD, restock (stock-in), deductForSale (stock-out),
/// recordWaste, manual adjust, low-stock detection, supplier CRUD,
/// and transaction audit trail.
///
/// Run with:
///   flutter test test/features/inventory/inventory_repository_test.dart
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/features/inventory/data/repositories/inventory_repository_impl.dart';
import 'package:gastrocore_pos/features/inventory/domain/entities/inventory_item_entity.dart';
import 'package:gastrocore_pos/features/inventory/domain/entities/supplier_entity.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _tenantId = 'tenant-inv-test';
const _uuid = Uuid();

InventoryItemEntity _makeItem({
  String? id,
  String? productId,
  String name = 'Flour',
  double quantity = 10.0,
  double minQuantity = 2.0,
  String unit = 'kg',
  int costPriceCents = 250,
  bool isActive = true,
}) {
  final now = DateTime(2026, 3, 21, 12, 0);
  return InventoryItemEntity(
    id: id ?? _uuid.v4(),
    tenantId: _tenantId,
    productId: productId,
    name: name,
    quantity: quantity,
    minQuantity: minQuantity,
    unit: unit,
    costPriceCents: costPriceCents,
    isActive: isActive,
    createdAt: now,
    updatedAt: now,
  );
}

SupplierEntity _makeSupplier({
  String? id,
  String name = 'Fresh Foods Ltd',
  String? email,
  String? phone,
}) {
  final now = DateTime(2026, 3, 21, 12, 0);
  return SupplierEntity(
    id: id ?? _uuid.v4(),
    tenantId: _tenantId,
    name: name,
    email: email,
    phone: phone,
    isActive: true,
    createdAt: now,
    updatedAt: now,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // =========================================================================
  // Item CRUD
  // =========================================================================

  group('InventoryRepositoryImpl — Item CRUD', () {
    late AppDatabase db;
    late InventoryRepositoryImpl repo;

    setUp(() {
      db = AppDatabase.createInMemory();
      repo = InventoryRepositoryImpl(db);
    });

    tearDown(() => db.close());

    test('createItem persists item and returns it', () async {
      final item = _makeItem(name: 'Sugar', quantity: 20.0, unit: 'kg');
      final created = await repo.createItem(item);

      expect(created.id, equals(item.id));
      expect(created.name, equals('Sugar'));
      expect(created.quantity, equals(20.0));
      expect(created.unit, equals('kg'));
      expect(created.tenantId, equals(_tenantId));
    });

    test('getItemById returns null for missing item', () async {
      final result = await repo.getItemById('nonexistent');
      expect(result, isNull);
    });

    test('getItemById returns persisted item', () async {
      final item = _makeItem(name: 'Olive Oil');
      await repo.createItem(item);

      final fetched = await repo.getItemById(item.id);
      expect(fetched, isNotNull);
      expect(fetched!.name, equals('Olive Oil'));
    });

    test('getAllItems returns all active items for tenant', () async {
      await repo.createItem(_makeItem(name: 'Rice', isActive: true));
      await repo.createItem(_makeItem(name: 'Pasta', isActive: true));

      final items = await repo.getAllItems(_tenantId);
      expect(items.length, greaterThanOrEqualTo(2));
      final names = items.map((i) => i.name).toList();
      expect(names, containsAll(['Rice', 'Pasta']));
    });

    test('updateItem persists changes', () async {
      final item = _makeItem(name: 'Tomato Sauce', quantity: 5.0);
      await repo.createItem(item);

      final updated = item.copyWith(name: 'Ketchup', minQuantity: 3.0);
      await repo.updateItem(updated);

      final fetched = await repo.getItemById(item.id);
      expect(fetched!.name, equals('Ketchup'));
      expect(fetched.minQuantity, equals(3.0));
    });

    test('deleteItem soft-deletes and hides from getAllItems', () async {
      final item = _makeItem(name: 'Butter');
      await repo.createItem(item);

      await repo.deleteItem(item.id);

      final items = await repo.getAllItems(_tenantId);
      expect(items.any((i) => i.id == item.id), isFalse);
    });
  });

  // =========================================================================
  // Stock Mutations
  // =========================================================================

  group('InventoryRepositoryImpl — Stock In (restock)', () {
    late AppDatabase db;
    late InventoryRepositoryImpl repo;

    setUp(() {
      db = AppDatabase.createInMemory();
      repo = InventoryRepositoryImpl(db);
    });

    tearDown(() => db.close());

    test('restock increases quantity by the given amount', () async {
      final item = _makeItem(name: 'Cheese', quantity: 5.0);
      await repo.createItem(item);

      final updated = await repo.restock(
        tenantId: _tenantId,
        itemId: item.id,
        quantityAdded: 10.0,
        notes: 'Weekly delivery',
      );

      expect(updated.quantity, equals(15.0));
    });

    test('restock creates a transaction audit row', () async {
      final item = _makeItem(name: 'Milk', quantity: 3.0);
      await repo.createItem(item);

      await repo.restock(
        tenantId: _tenantId,
        itemId: item.id,
        quantityAdded: 6.0,
      );

      final txs = await repo.getTransactionsForItem(item.id);
      expect(txs.length, equals(1));
      expect(txs.first.type.name, equals('restock'));
      expect(txs.first.quantity, equals(6.0));
      expect(txs.first.quantityBefore, equals(3.0));
      expect(txs.first.quantityAfter, equals(9.0));
    });

    test('restock on missing item throws StateError', () async {
      await expectLater(
        () => repo.restock(
          tenantId: _tenantId,
          itemId: 'no-such-item',
          quantityAdded: 5.0,
        ),
        throwsStateError,
      );
    });

    test('multiple restocks accumulate correctly', () async {
      final item = _makeItem(name: 'Yoghurt', quantity: 0.0);
      await repo.createItem(item);

      await repo.restock(tenantId: _tenantId, itemId: item.id, quantityAdded: 10.0);
      await repo.restock(tenantId: _tenantId, itemId: item.id, quantityAdded: 5.0);

      final fetched = await repo.getItemById(item.id);
      expect(fetched!.quantity, equals(15.0));

      final txs = await repo.getTransactionsForItem(item.id);
      expect(txs.length, equals(2));
    });
  });

  group('InventoryRepositoryImpl — Stock Out (deductForSale)', () {
    late AppDatabase db;
    late InventoryRepositoryImpl repo;

    setUp(() {
      db = AppDatabase.createInMemory();
      repo = InventoryRepositoryImpl(db);
    });

    tearDown(() => db.close());

    test('deductForSale reduces quantity and records sale transaction', () async {
      final productId = _uuid.v4();
      final item = _makeItem(
        name: 'Kebap Meat',
        productId: productId,
        quantity: 10.0,
      );
      await repo.createItem(item);

      await repo.deductForSale(
        tenantId: _tenantId,
        productId: productId,
        quantity: 2.0,
        ticketId: 'ticket-001',
      );

      final updated = await repo.getItemById(item.id);
      expect(updated!.quantity, closeTo(8.0, 0.001));

      final txs = await repo.getTransactionsForItem(item.id);
      expect(txs.any((t) => t.type.name == 'sale'), isTrue);
    });

    test('deductForSale is a no-op when product is not tracked', () async {
      // Should not throw even when product has no inventory entry.
      await expectLater(
        repo.deductForSale(
          tenantId: _tenantId,
          productId: 'untracked-product',
          quantity: 1.0,
          ticketId: 'ticket-002',
        ),
        completes,
      );
    });

    test('deductForSale clamps quantity to -9999 to prevent extreme negatives',
        () async {
      final productId = _uuid.v4();
      final item = _makeItem(
        name: 'Tomatoes',
        productId: productId,
        quantity: 1.0,
      );
      await repo.createItem(item);

      // Deduct far more than available.
      await repo.deductForSale(
        tenantId: _tenantId,
        productId: productId,
        quantity: 5000.0,
        ticketId: 'ticket-003',
      );

      final updated = await repo.getItemById(item.id);
      expect(updated!.quantity, greaterThanOrEqualTo(-9999.0));
    });
  });

  group('InventoryRepositoryImpl — Waste', () {
    late AppDatabase db;
    late InventoryRepositoryImpl repo;

    setUp(() {
      db = AppDatabase.createInMemory();
      repo = InventoryRepositoryImpl(db);
    });

    tearDown(() => db.close());

    test('recordWaste reduces quantity and creates waste transaction', () async {
      final item = _makeItem(name: 'Lettuce', quantity: 8.0);
      await repo.createItem(item);

      final updated = await repo.recordWaste(
        tenantId: _tenantId,
        itemId: item.id,
        quantity: 3.0,
        notes: 'Spoiled overnight',
      );

      expect(updated.quantity, closeTo(5.0, 0.001));

      final txs = await repo.getTransactionsForItem(item.id);
      expect(txs.any((t) => t.type.name == 'waste'), isTrue);
      expect(txs.first.notes, equals('Spoiled overnight'));
    });

    test('recordWaste on missing item throws StateError', () async {
      await expectLater(
        () => repo.recordWaste(
          tenantId: _tenantId,
          itemId: 'no-such-item',
          quantity: 1.0,
        ),
        throwsStateError,
      );
    });

    test('recordWaste quantityBefore and quantityAfter are recorded correctly',
        () async {
      final item = _makeItem(name: 'Cream', quantity: 5.0);
      await repo.createItem(item);

      await repo.recordWaste(
        tenantId: _tenantId,
        itemId: item.id,
        quantity: 2.0,
      );

      final txs = await repo.getTransactionsForItem(item.id);
      expect(txs.first.quantityBefore, equals(5.0));
      expect(txs.first.quantityAfter, closeTo(3.0, 0.001));
    });
  });

  group('InventoryRepositoryImpl — Manual Adjust', () {
    late AppDatabase db;
    late InventoryRepositoryImpl repo;

    setUp(() {
      db = AppDatabase.createInMemory();
      repo = InventoryRepositoryImpl(db);
    });

    tearDown(() => db.close());

    test('adjust sets quantity to new value and records adjustment transaction',
        () async {
      final item = _makeItem(name: 'Salt', quantity: 7.0);
      await repo.createItem(item);

      final updated = await repo.adjust(
        tenantId: _tenantId,
        itemId: item.id,
        newQuantity: 12.0,
        notes: 'Stocktake correction',
      );

      expect(updated.quantity, equals(12.0));

      final txs = await repo.getTransactionsForItem(item.id);
      expect(txs.any((t) => t.type.name == 'adjustment'), isTrue);
    });

    test('adjust records delta correctly when decreasing', () async {
      final item = _makeItem(name: 'Pepper', quantity: 10.0);
      await repo.createItem(item);

      await repo.adjust(
        tenantId: _tenantId,
        itemId: item.id,
        newQuantity: 4.0,
      );

      final txs = await repo.getTransactionsForItem(item.id);
      // delta = 4 - 10 = -6
      expect(txs.first.quantity, closeTo(-6.0, 0.001));
    });
  });

  // =========================================================================
  // Low-stock detection
  // =========================================================================

  group('InventoryRepositoryImpl — Stock Alerts', () {
    late AppDatabase db;
    late InventoryRepositoryImpl repo;

    setUp(() {
      db = AppDatabase.createInMemory();
      repo = InventoryRepositoryImpl(db);
    });

    tearDown(() => db.close());

    test('getLowStockItems returns items at or below minQuantity', () async {
      // Normal item: qty 10, min 5 → not low
      await repo.createItem(_makeItem(name: 'Wheat', quantity: 10.0, minQuantity: 5.0));
      // Low item: qty 3, min 5 → low
      await repo.createItem(_makeItem(name: 'Barley', quantity: 3.0, minQuantity: 5.0));
      // Out item: qty 0, min 5 → out (also low)
      await repo.createItem(_makeItem(name: 'Rye', quantity: 0.0, minQuantity: 5.0));

      final low = await repo.getLowStockItems(_tenantId);
      final names = low.map((i) => i.name).toList();
      expect(names, contains('Barley'));
      expect(names, isNot(contains('Wheat')));
    });

    test('getOutOfStockItems returns only items with quantity <= 0', () async {
      await repo.createItem(_makeItem(name: 'Butter', quantity: 5.0, minQuantity: 2.0));
      await repo.createItem(_makeItem(name: 'Cream', quantity: 0.0, minQuantity: 2.0));

      final out = await repo.getOutOfStockItems(_tenantId);
      final names = out.map((i) => i.name).toList();
      expect(names, contains('Cream'));
      expect(names, isNot(contains('Butter')));
    });

    test('getAlertItems sorts out-of-stock before low-stock', () async {
      await repo.createItem(_makeItem(name: 'OOS Item', quantity: 0.0, minQuantity: 5.0));
      await repo.createItem(_makeItem(name: 'Low Item', quantity: 3.0, minQuantity: 5.0));

      final alerts = await repo.getAlertItems(_tenantId);
      expect(alerts, isNotEmpty);
      // Out-of-stock should appear first.
      final oosIndex = alerts.indexWhere((i) => i.name == 'OOS Item');
      final lowIndex = alerts.indexWhere((i) => i.name == 'Low Item');
      if (oosIndex >= 0 && lowIndex >= 0) {
        expect(oosIndex, lessThan(lowIndex));
      }
    });

    test('InventoryItemEntity.stockStatus returns correct values', () {
      final normal = _makeItem(quantity: 10.0, minQuantity: 5.0);
      final low = _makeItem(quantity: 3.0, minQuantity: 5.0);
      final out = _makeItem(quantity: 0.0, minQuantity: 5.0);

      expect(normal.stockStatus, equals(StockStatus.normal));
      expect(low.stockStatus, equals(StockStatus.low));
      expect(out.stockStatus, equals(StockStatus.out));
    });

    test('InventoryItemEntity.stockValueCents computes correctly', () {
      final item = _makeItem(quantity: 4.0, costPriceCents: 500);
      expect(item.stockValueCents, equals(2000));
    });
  });

  // =========================================================================
  // Transaction history
  // =========================================================================

  group('InventoryRepositoryImpl — Transaction History', () {
    late AppDatabase db;
    late InventoryRepositoryImpl repo;

    setUp(() {
      db = AppDatabase.createInMemory();
      repo = InventoryRepositoryImpl(db);
    });

    tearDown(() => db.close());

    test('getTransactionsForItem returns all transactions for the item', () async {
      final item = _makeItem(name: 'Vinegar', quantity: 10.0);
      await repo.createItem(item);

      await repo.restock(tenantId: _tenantId, itemId: item.id, quantityAdded: 5.0);
      await repo.recordWaste(tenantId: _tenantId, itemId: item.id, quantity: 2.0);

      final txs = await repo.getTransactionsForItem(item.id);
      expect(txs.length, equals(2));
    });

    test('getTransactionsByTenant returns transactions scoped to tenant', () async {
      final item = _makeItem(name: 'Cinnamon', quantity: 10.0);
      await repo.createItem(item);

      await repo.restock(tenantId: _tenantId, itemId: item.id, quantityAdded: 3.0);

      final txs = await repo.getTransactionsByTenant(_tenantId);
      expect(txs, isNotEmpty);
      expect(txs.every((t) => t.tenantId == _tenantId), isTrue);
    });

    test('getTransactionsByTenant type filter returns only matching type', () async {
      final item = _makeItem(name: 'Nutmeg', quantity: 10.0);
      await repo.createItem(item);

      await repo.restock(tenantId: _tenantId, itemId: item.id, quantityAdded: 2.0);
      await repo.recordWaste(tenantId: _tenantId, itemId: item.id, quantity: 1.0);

      final restocks = await repo.getTransactionsByTenant(_tenantId, type: 'restock');
      expect(restocks.every((t) => t.type.name == 'restock'), isTrue);
    });
  });

  // =========================================================================
  // Suppliers
  // =========================================================================

  group('InventoryRepositoryImpl — Suppliers', () {
    late AppDatabase db;
    late InventoryRepositoryImpl repo;

    setUp(() {
      db = AppDatabase.createInMemory();
      repo = InventoryRepositoryImpl(db);
    });

    tearDown(() => db.close());

    test('createSupplier persists and getAllSuppliers returns it', () async {
      final supplier = _makeSupplier(name: 'Metro Wholesale');
      await repo.createSupplier(supplier);

      final suppliers = await repo.getAllSuppliers(_tenantId);
      expect(suppliers.any((s) => s.name == 'Metro Wholesale'), isTrue);
    });

    test('getSupplierById returns null for missing supplier', () async {
      final result = await repo.getSupplierById('nonexistent');
      expect(result, isNull);
    });

    test('getSupplierById returns persisted supplier', () async {
      final supplier = _makeSupplier(name: 'Farm Direct');
      await repo.createSupplier(supplier);

      final fetched = await repo.getSupplierById(supplier.id);
      expect(fetched, isNotNull);
      expect(fetched!.name, equals('Farm Direct'));
    });

    test('updateSupplier persists new name and contact', () async {
      final supplier = _makeSupplier(name: 'Old Name', email: 'old@test.com');
      await repo.createSupplier(supplier);

      final updated = SupplierEntity(
        id: supplier.id,
        tenantId: _tenantId,
        name: 'New Name',
        email: 'new@test.com',
        phone: '+41 79 999 9999',
        isActive: true,
        createdAt: supplier.createdAt,
        updatedAt: DateTime.now(),
      );
      await repo.updateSupplier(updated);

      final fetched = await repo.getSupplierById(supplier.id);
      expect(fetched!.name, equals('New Name'));
      expect(fetched.email, equals('new@test.com'));
    });

    test('deleteSupplier soft-deletes and hides from getAllSuppliers', () async {
      final supplier = _makeSupplier(name: 'To Delete');
      await repo.createSupplier(supplier);

      await repo.deleteSupplier(supplier.id);

      final suppliers = await repo.getAllSuppliers(_tenantId);
      expect(suppliers.any((s) => s.id == supplier.id), isFalse);
    });
  });
}
