/// Riverpod providers for the inventory feature.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/features/inventory/data/inventory_api_client.dart';
import 'package:gastrocore_pos/features/inventory/domain/inventory_item.dart';
import 'package:gastrocore_pos/features/inventory/domain/stock_movement.dart';
import 'package:gastrocore_pos/features/sync/presentation/providers/sync_provider.dart';

// ---------------------------------------------------------------------------
// API client
// ---------------------------------------------------------------------------

final inventoryApiClientProvider = Provider<InventoryApiClient>((ref) {
  final baseUrl = ref.watch(syncServerUrlProvider);
  final tenantId = ref.watch(tenantIdProvider);
  final client = InventoryApiClient(baseUrl: baseUrl, tenantId: tenantId);
  ref.onDispose(client.dispose);
  return client;
});

// ---------------------------------------------------------------------------
// Items list
// ---------------------------------------------------------------------------

final inventoryItemsProvider =
    FutureProvider<List<InventoryItem>>((ref) async {
  final client = ref.watch(inventoryApiClientProvider);
  return client.listItems();
});

final lowStockItemsProvider = FutureProvider<List<InventoryItem>>((ref) async {
  final client = ref.watch(inventoryApiClientProvider);
  return client.listItems(lowStockOnly: true);
});

// ---------------------------------------------------------------------------
// Movements for a specific item
// ---------------------------------------------------------------------------

final itemMovementsProvider =
    FutureProvider.family<List<StockMovement>, String>((ref, itemId) async {
  final client = ref.watch(inventoryApiClientProvider);
  return client.listMovements(itemId: itemId);
});

// ---------------------------------------------------------------------------
// Inventory notifier — mutations with optimistic refresh
// ---------------------------------------------------------------------------

class InventoryNotifier extends AsyncNotifier<List<InventoryItem>> {
  @override
  Future<List<InventoryItem>> build() async {
    final client = ref.watch(inventoryApiClientProvider);
    return client.listItems();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() {
      final client = ref.read(inventoryApiClientProvider);
      return client.listItems();
    });
  }

  Future<InventoryItem> createItem({
    required String name,
    String? sku,
    required String unit,
    required double currentQty,
    required double minQty,
    double? maxQty,
    int? costPerUnit,
    String? supplier,
    String? notes,
  }) async {
    final client = ref.read(inventoryApiClientProvider);
    final item = await client.createItem(
      name: name,
      sku: sku,
      unit: unit,
      currentQty: currentQty,
      minQty: minQty,
      maxQty: maxQty,
      costPerUnit: costPerUnit,
      supplier: supplier,
      notes: notes,
    );
    await refresh();
    return item;
  }

  Future<void> deleteItem(String id) async {
    final client = ref.read(inventoryApiClientProvider);
    await client.deleteItem(id);
    await refresh();
  }

  Future<StockMovement> recordMovement({
    required String itemId,
    required MovementType movementType,
    required double qty,
    String? notes,
    String? performedBy,
  }) async {
    final client = ref.read(inventoryApiClientProvider);
    final movement = await client.createMovement(
      itemId: itemId,
      movementType: movementType,
      qty: qty,
      notes: notes,
      performedBy: performedBy,
    );
    await refresh();
    return movement;
  }
}

final inventoryNotifierProvider =
    AsyncNotifierProvider<InventoryNotifier, List<InventoryItem>>(
  InventoryNotifier.new,
);
