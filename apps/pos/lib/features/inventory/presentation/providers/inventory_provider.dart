/// Riverpod providers for the inventory feature.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:gastrocore_pos/features/inventory/data/repositories/inventory_repository_impl.dart';
import 'package:gastrocore_pos/features/inventory/domain/entities/inventory_item_entity.dart';
import 'package:gastrocore_pos/features/inventory/domain/entities/inventory_transaction_entity.dart';
import 'package:gastrocore_pos/features/inventory/domain/entities/supplier_entity.dart';

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

final inventoryRepositoryProvider = Provider<InventoryRepositoryImpl>((ref) {
  return InventoryRepositoryImpl(ref.watch(databaseProvider));
});

// ---------------------------------------------------------------------------
// Items list
// ---------------------------------------------------------------------------

final inventoryItemsProvider =
    FutureProvider.autoDispose<List<InventoryItemEntity>>((ref) {
  final repo = ref.watch(inventoryRepositoryProvider);
  final tenantId = ref.watch(tenantIdProvider);
  return repo.getAllItems(tenantId);
});

/// Stream-based variant for real-time updates.
final inventoryItemsStreamProvider =
    StreamProvider.autoDispose<List<InventoryItemEntity>>((ref) {
  final repo = ref.watch(inventoryRepositoryProvider);
  final tenantId = ref.watch(tenantIdProvider);
  return repo.watchAllItems(tenantId);
});

final lowStockItemsProvider =
    FutureProvider.autoDispose<List<InventoryItemEntity>>((ref) {
  final repo = ref.watch(inventoryRepositoryProvider);
  final tenantId = ref.watch(tenantIdProvider);
  return repo.getLowStockItems(tenantId);
});

final alertItemsProvider =
    FutureProvider.autoDispose<List<InventoryItemEntity>>((ref) {
  final repo = ref.watch(inventoryRepositoryProvider);
  final tenantId = ref.watch(tenantIdProvider);
  return repo.getAlertItems(tenantId);
});

/// Count of items that need attention (for badge display).
final stockAlertCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final items = await ref.watch(alertItemsProvider.future);
  return items.length;
});

/// Map from productId -> current [StockStatus] for every tracked inventory
/// item that has a product link. Used by the product grid to decorate
/// tiles with a "low" / "bitti" badge without re-querying per tile.
///
/// Uses the live stream so a ticket-close deduction (which happens on the
/// database layer) propagates to the visible grid in real time. Items
/// without a productId are skipped — the grid is keyed by productId, not
/// inventory id. If the stream is still loading the map is empty, which
/// means the grid degrades to "no badges" rather than flashing wrong data.
final stockStatusByProductIdProvider =
    Provider.autoDispose<Map<String, StockStatus>>((ref) {
  final async = ref.watch(inventoryItemsStreamProvider);
  final items = async.valueOrNull ?? const <InventoryItemEntity>[];
  final out = <String, StockStatus>{};
  for (final item in items) {
    final pid = item.productId;
    if (pid == null || pid.isEmpty) continue;
    // If a product is tracked by multiple inventory rows, surface the
    // worst status — "out" wins over "low" wins over "normal". Rare in
    // practice but it prevents a second restocked row from masking a
    // truly empty one.
    final existing = out[pid];
    final next = item.stockStatus;
    if (existing == null) {
      out[pid] = next;
    } else if (_severity(next) > _severity(existing)) {
      out[pid] = next;
    }
  }
  return out;
});

int _severity(StockStatus s) => switch (s) {
      StockStatus.out => 2,
      StockStatus.low => 1,
      StockStatus.normal => 0,
    };

// ---------------------------------------------------------------------------
// Single item detail
// ---------------------------------------------------------------------------

final inventoryItemDetailProvider =
    FutureProvider.autoDispose.family<InventoryItemEntity?, String>((
  ref,
  itemId,
) {
  final repo = ref.watch(inventoryRepositoryProvider);
  return repo.getItemById(itemId);
});

// ---------------------------------------------------------------------------
// Transactions for an item
// ---------------------------------------------------------------------------

final itemTransactionsProvider =
    FutureProvider.autoDispose.family<List<InventoryTransactionEntity>, String>((
  ref,
  itemId,
) {
  final repo = ref.watch(inventoryRepositoryProvider);
  return repo.getTransactionsForItem(itemId, limit: 50);
});

// ---------------------------------------------------------------------------
// Suppliers
// ---------------------------------------------------------------------------

final suppliersProvider =
    FutureProvider.autoDispose<List<SupplierEntity>>((ref) {
  final repo = ref.watch(inventoryRepositoryProvider);
  final tenantId = ref.watch(tenantIdProvider);
  return repo.getAllSuppliers(tenantId);
});

final suppliersStreamProvider =
    StreamProvider.autoDispose<List<SupplierEntity>>((ref) {
  final repo = ref.watch(inventoryRepositoryProvider);
  final tenantId = ref.watch(tenantIdProvider);
  return repo.watchAllSuppliers(tenantId);
});

// ---------------------------------------------------------------------------
// Actions notifier
// ---------------------------------------------------------------------------

/// Stateless service notifier exposing mutation methods.
/// UI screens call methods; success refreshes dependent providers.
class InventoryActionsNotifier extends StateNotifier<AsyncValue<void>> {
  final InventoryRepositoryImpl _repo;
  final Ref _ref;
  final _uuid = const Uuid();

  InventoryActionsNotifier(this._repo, this._ref) : super(const AsyncData(null));

  String get _tenantId => _ref.read(tenantIdProvider);
  String? get _userId => _ref.read(currentUserProvider)?.id;
  String? get _userName => _ref.read(currentUserProvider)?.name;

  Future<bool> createItem(InventoryItemEntity entity) async {
    state = const AsyncLoading();
    try {
      await _repo.createItem(entity);
      _ref.invalidate(inventoryItemsProvider);
      _ref.invalidate(inventoryItemsStreamProvider);
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  Future<bool> updateItem(InventoryItemEntity entity) async {
    state = const AsyncLoading();
    try {
      await _repo.updateItem(entity);
      _ref.invalidate(inventoryItemsProvider);
      _ref.invalidate(inventoryItemsStreamProvider);
      _ref.invalidate(inventoryItemDetailProvider(entity.id));
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  Future<bool> deleteItem(String id) async {
    state = const AsyncLoading();
    try {
      await _repo.deleteItem(id);
      _ref.invalidate(inventoryItemsProvider);
      _ref.invalidate(inventoryItemsStreamProvider);
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  Future<bool> restock({
    required String itemId,
    required double quantity,
    String? notes,
    DateTime? date,
  }) async {
    state = const AsyncLoading();
    try {
      await _repo.restock(
        tenantId: _tenantId,
        itemId: itemId,
        quantityAdded: quantity,
        userId: _userId,
        userName: _userName,
        notes: notes,
        date: date,
      );
      _invalidateItem(itemId);
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  Future<bool> recordWaste({
    required String itemId,
    required double quantity,
    String? notes,
  }) async {
    state = const AsyncLoading();
    try {
      await _repo.recordWaste(
        tenantId: _tenantId,
        itemId: itemId,
        quantity: quantity,
        userId: _userId,
        userName: _userName,
        notes: notes,
      );
      _invalidateItem(itemId);
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  Future<bool> adjust({
    required String itemId,
    required double newQuantity,
    String? notes,
  }) async {
    state = const AsyncLoading();
    try {
      await _repo.adjust(
        tenantId: _tenantId,
        itemId: itemId,
        newQuantity: newQuantity,
        userId: _userId,
        userName: _userName,
        notes: notes,
      );
      _invalidateItem(itemId);
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  Future<bool> createSupplier(SupplierEntity entity) async {
    state = const AsyncLoading();
    try {
      await _repo.createSupplier(entity);
      _ref.invalidate(suppliersProvider);
      _ref.invalidate(suppliersStreamProvider);
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  Future<bool> updateSupplier(SupplierEntity entity) async {
    state = const AsyncLoading();
    try {
      await _repo.updateSupplier(entity);
      _ref.invalidate(suppliersProvider);
      _ref.invalidate(suppliersStreamProvider);
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  Future<bool> deleteSupplier(String id) async {
    state = const AsyncLoading();
    try {
      await _repo.deleteSupplier(id);
      _ref.invalidate(suppliersProvider);
      _ref.invalidate(suppliersStreamProvider);
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  void _invalidateItem(String itemId) {
    _ref.invalidate(inventoryItemsProvider);
    _ref.invalidate(inventoryItemsStreamProvider);
    _ref.invalidate(inventoryItemDetailProvider(itemId));
    _ref.invalidate(itemTransactionsProvider(itemId));
    _ref.invalidate(alertItemsProvider);
    _ref.invalidate(stockAlertCountProvider);
    _ref.invalidate(lowStockItemsProvider);
  }

  /// Build a new [InventoryItemEntity] with a fresh UUID.
  InventoryItemEntity buildNewItem({
    required String tenantId,
    required String name,
    double quantity = 0,
    double minQuantity = 0,
    String unit = 'pcs',
    String? productId,
    String? supplierId,
    int costPriceCents = 0,
    String? notes,
  }) {
    final now = DateTime.now();
    return InventoryItemEntity(
      id: _uuid.v4(),
      tenantId: tenantId,
      productId: productId,
      name: name,
      quantity: quantity,
      minQuantity: minQuantity,
      unit: unit,
      supplierId: supplierId,
      costPriceCents: costPriceCents,
      notes: notes,
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Build a new [SupplierEntity] with a fresh UUID.
  SupplierEntity buildNewSupplier({
    required String tenantId,
    required String name,
    String? email,
    String? phone,
    String? address,
    String? notes,
  }) {
    final now = DateTime.now();
    return SupplierEntity(
      id: _uuid.v4(),
      tenantId: tenantId,
      name: name,
      email: email,
      phone: phone,
      address: address,
      notes: notes,
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );
  }
}

final inventoryActionsProvider =
    StateNotifierProvider<InventoryActionsNotifier, AsyncValue<void>>((ref) {
  return InventoryActionsNotifier(
    ref.watch(inventoryRepositoryProvider),
    ref,
  );
});
