/// Riverpod providers for the Waiter feature.
///
/// Exposes [WaiterOrderService], the active waiter session (selected table,
/// current draft ticket), and live streams for tables and active orders.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:gastrocore_pos/features/kitchen/presentation/providers/kitchen_provider.dart';
import 'package:gastrocore_pos/features/menu/data/repositories/menu_repository_impl.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/category_entity.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/product_entity.dart';
import 'package:gastrocore_pos/features/orders/data/repositories/order_repository_impl.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/features/tables/data/repositories/table_repository_impl.dart';
import 'package:gastrocore_pos/features/tables/domain/entities/table_entity.dart';
import 'package:gastrocore_pos/features/tables/presentation/providers/table_provider.dart';
import 'package:gastrocore_pos/features/waiter/services/waiter_order_service.dart';

// ---------------------------------------------------------------------------
// WaiterOrderService provider
// ---------------------------------------------------------------------------

/// Singleton [WaiterOrderService] wired to the app database.
final waiterOrderServiceProvider = Provider<WaiterOrderService>((ref) {
  final db = ref.watch(databaseProvider);
  return WaiterOrderService(
    orderRepo: OrderRepositoryImpl(db),
    kitchenRepo: ref.watch(kitchenRepositoryProvider),
    tableRepo: TableRepositoryImpl(db),
  );
});

// ---------------------------------------------------------------------------
// Menu repository (reused from the menu feature)
// ---------------------------------------------------------------------------

final _menuRepoProvider = Provider<MenuRepositoryImpl>((ref) {
  return MenuRepositoryImpl(ref.watch(databaseProvider));
});

// ---------------------------------------------------------------------------
// Session state: selected table & active ticket
// ---------------------------------------------------------------------------

/// The table the waiter has currently selected to take an order for.
final waiterSelectedTableProvider =
    StateProvider<RestaurantTableEntity?>((ref) => null);

/// The draft ticket the waiter is actively building.
///
/// `null` means no order is in progress for the selected table.
final waiterActiveTicketProvider =
    StateNotifierProvider<WaiterActiveTicketNotifier, TicketEntity?>((ref) {
  return WaiterActiveTicketNotifier(ref);
});

class WaiterActiveTicketNotifier extends StateNotifier<TicketEntity?> {
  final Ref _ref;

  WaiterActiveTicketNotifier(this._ref) : super(null);

  String get _tenantId => _ref.read(tenantIdProvider);
  String get _deviceId => _ref.read(deviceIdProvider);

  WaiterOrderService get _svc => _ref.read(waiterOrderServiceProvider);

  /// Start a new order for [table], claiming the table.
  Future<void> startOrder(RestaurantTableEntity table) async {
    final user = _ref.read(currentUserProvider);
    if (user == null) return;

    _ref.read(waiterSelectedTableProvider.notifier).state = table;

    final ticket = await _svc.openNewOrder(
      tenantId: _tenantId,
      waiterId: user.id,
      waiterName: user.name,
      tableId: table.id,
      deviceId: _deviceId,
    );
    state = ticket;
  }

  /// Load an existing open ticket as the active ticket.
  Future<void> loadTicket(String ticketId) async {
    final db = _ref.read(databaseProvider);
    final repo = OrderRepositoryImpl(db);
    state = await repo.getTicketById(ticketId);
  }

  /// Add a product to the active ticket.
  Future<void> addProduct(
    ProductEntity product, {
    double quantity = 1,
    String? notes,
  }) async {
    if (state == null) return;
    final updated = await _svc.addItemToTicket(
      ticketId: state!.id,
      product: product,
      quantity: quantity,
      notes: notes,
    );
    state = updated;
  }

  /// Remove an item from the active ticket.
  Future<void> removeItem(String itemId) async {
    if (state == null) return;
    final updated = await _svc.removeItemFromTicket(
      ticketId: state!.id,
      itemId: itemId,
    );
    state = updated;
  }

  /// Send all unsent items to the kitchen.
  Future<void> sendToKitchen() async {
    if (state == null) return;
    final user = _ref.read(currentUserProvider);
    final updated = await _svc.sendToKitchen(
      ticketId: state!.id,
      waiterName: user?.name ?? '',
    );
    state = updated;
  }

  /// Mark the current order as served.
  Future<void> markServed() async {
    if (state == null) return;
    await _svc.markServed(state!.id);
    // Reload to get updated status.
    final db = _ref.read(databaseProvider);
    state = await OrderRepositoryImpl(db).getTicketById(state!.id);
  }

  /// Request the bill for the current order.
  Future<void> requestBill() async {
    if (state == null) return;
    await _svc.requestBill(state!.id);
    final db = _ref.read(databaseProvider);
    state = await OrderRepositoryImpl(db).getTicketById(state!.id);
  }

  /// Clear the active ticket (e.g. after payment or navigating away).
  void clear() => state = null;
}

// ---------------------------------------------------------------------------
// Active orders for the current waiter
// ---------------------------------------------------------------------------

/// All open waiter orders assigned to the currently logged-in user.
final waiterActiveOrdersProvider =
    FutureProvider<List<TicketEntity>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];

  final svc = ref.watch(waiterOrderServiceProvider);
  final tenantId = ref.watch(tenantIdProvider);
  return svc.getActiveOrdersForWaiter(tenantId: tenantId, waiterId: user.id);
});

// ---------------------------------------------------------------------------
// Tables (reuse existing floor / table providers)
// ---------------------------------------------------------------------------

/// All tables across all floors for the current tenant, for the grid view.
///
/// Groups tables by floor using [floorsProvider] and [allTablesProvider].
final waiterAllTablesProvider = FutureProvider<List<RestaurantTableEntity>>(
  (ref) => ref.watch(allTablesProvider.future),
);

// ---------------------------------------------------------------------------
// Menu providers (categories + products per category)
// ---------------------------------------------------------------------------

/// All active categories for the menu browser.
final waiterCategoriesProvider = FutureProvider<List<CategoryEntity>>((ref) {
  final repo = ref.watch(_menuRepoProvider);
  final tenantId = ref.watch(tenantIdProvider);
  return repo.getAllCategories(tenantId);
});

/// The category the waiter is currently browsing.
final waiterSelectedCategoryProvider =
    StateProvider<CategoryEntity?>((ref) => null);

/// Products in the currently selected category.
final waiterProductsProvider = FutureProvider<List<ProductEntity>>((ref) async {
  final category = ref.watch(waiterSelectedCategoryProvider);
  if (category == null) return const [];
  final repo = ref.watch(_menuRepoProvider);
  return repo.getProductsByCategory(category.id);
});

/// Search query for product lookup.
final waiterSearchQueryProvider = StateProvider<String>((ref) => '');

/// Products filtered by the current search query (across all categories).
final waiterSearchResultsProvider =
    FutureProvider<List<ProductEntity>>((ref) async {
  final query = ref.watch(waiterSearchQueryProvider).trim();
  if (query.isEmpty) return const [];
  final repo = ref.watch(_menuRepoProvider);
  final tenantId = ref.watch(tenantIdProvider);
  return repo.searchProducts(tenantId, query);
});
