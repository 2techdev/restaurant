/// Riverpod providers for the Waiter feature.
///
/// Exposes [WaiterOrderService], the active waiter session (selected table,
/// current draft ticket), and live streams for tables and active orders.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:gastrocore_pos/features/kitchen/presentation/providers/kitchen_provider.dart';
import 'package:gastrocore_pos/features/menu/data/repositories/menu_repository_impl.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/category_entity.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/product_entity.dart';
import 'package:gastrocore_pos/features/orders/data/repositories/order_repository_impl.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/order_item_entity.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/features/tables/data/repositories/table_repository_impl.dart';
import 'package:gastrocore_pos/features/tables/domain/entities/table_entity.dart';
import 'package:gastrocore_pos/features/tables/presentation/providers/table_provider.dart';
import 'package:gastrocore_pos/features/waiter/data/repositories/service_call_repository_impl.dart';
import 'package:gastrocore_pos/features/waiter/domain/entities/service_call_entity.dart';
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

  /// Active stream subscription to the current ticket's Drift-backed watcher.
  ///
  /// Re-created every time a new ticket becomes active (startOrder / loadTicket
  /// / transferToTable) so KDS-side item status changes push through to the
  /// waiter UI without a manual refresh. `null` when no ticket is loaded.
  StreamSubscription<TicketEntity?>? _watchSub;

  WaiterActiveTicketNotifier(this._ref) : super(null);

  String get _tenantId => _ref.read(tenantIdProvider);
  String get _deviceId => _ref.read(deviceIdProvider);

  WaiterOrderService get _svc => _ref.read(waiterOrderServiceProvider);

  OrderRepositoryImpl get _orderRepo =>
      OrderRepositoryImpl(_ref.read(databaseProvider));

  /// Bind the reactive watcher to [ticketId], replacing any previous
  /// subscription. Emissions update [state] so the UI reacts to KDS-side
  /// changes (e.g. items flipped to ready).
  void _bindWatcher(String ticketId) {
    _watchSub?.cancel();
    _watchSub = _orderRepo.watchTicketById(ticketId).listen((next) {
      if (!mounted) return;
      state = next;
    });
  }

  void _unbindWatcher() {
    _watchSub?.cancel();
    _watchSub = null;
  }

  @override
  void dispose() {
    _unbindWatcher();
    super.dispose();
  }

  /// Start a new order for [table], claiming the table.
  ///
  /// [guestCount] is the initial cover count — pass the value the waiter
  /// picked at the table-select step. Defaults to the service default so
  /// existing callers keep working.
  Future<void> startOrder(
    RestaurantTableEntity table, {
    int? guestCount,
  }) async {
    final user = _ref.read(currentUserProvider);
    if (user == null) return;

    _ref.read(waiterSelectedTableProvider.notifier).state = table;

    final ticket = await _svc.openNewOrder(
      tenantId: _tenantId,
      waiterId: user.id,
      waiterName: user.name,
      tableId: table.id,
      deviceId: _deviceId,
      guestCount: guestCount ?? 2,
    );
    state = ticket;
    _bindWatcher(ticket.id);
  }

  /// Update the cover count on the active ticket.
  ///
  /// No-op if there is no active ticket or the ticket is closed.
  Future<void> updateGuestCount(int guestCount) async {
    if (state == null) return;
    final updated = await _svc.updateGuestCount(
      ticketId: state!.id,
      guestCount: guestCount,
    );
    if (updated != null) state = updated;
  }

  /// Load an existing open ticket as the active ticket.
  Future<void> loadTicket(String ticketId) async {
    state = await _orderRepo.getTicketById(ticketId);
    if (state != null) _bindWatcher(ticketId);
  }

  /// Add a product to the active ticket.
  ///
  /// [seat] tags the line for split-by-seat billing. `0` (default) = shared;
  /// 1..ticket.guestCount identifies a specific cover.
  Future<void> addProduct(
    ProductEntity product, {
    double quantity = 1,
    List<OrderItemModifierEntity> modifiers = const [],
    String? notes,
    int course = 1,
    int seat = 0,
  }) async {
    if (state == null) return;
    final updated = await _svc.addItemToTicket(
      ticketId: state!.id,
      product: product,
      quantity: quantity,
      modifiers: modifiers,
      notes: notes,
      course: course,
      seat: seat,
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

  /// Fire a single gang (1..3) to the kitchen.
  ///
  /// Unsent items in the gang are pushed as a unit so the expo station
  /// plates them together.
  Future<void> fireGang(int gang) async {
    if (state == null) return;
    final user = _ref.read(currentUserProvider);
    final updated = await _svc.fireGang(
      ticketId: state!.id,
      gang: gang,
      waiterName: user?.name ?? '',
    );
    state = updated;
  }

  /// Move the current ticket to another table.
  Future<void> transferToTable(RestaurantTableEntity newTable) async {
    if (state == null) return;
    final updated = await _svc.transferToTable(
      ticketId: state!.id,
      newTableId: newTable.id,
    );
    state = updated;
    // Keep the session's selected table in sync with the ticket.
    _ref.read(waiterSelectedTableProvider.notifier).state = newTable;
  }

  /// Mark the current order as served.
  Future<void> markServed() async {
    if (state == null) return;
    await _svc.markServed(state!.id);
    state = await _orderRepo.getTicketById(state!.id);
  }

  /// Request the bill for the current order.
  Future<void> requestBill() async {
    if (state == null) return;
    await _svc.requestBill(state!.id);
    state = await _orderRepo.getTicketById(state!.id);
  }

  /// Clear the active ticket (e.g. after payment or navigating away).
  void clear() {
    _unbindWatcher();
    state = null;
  }
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

// ---------------------------------------------------------------------------
// Course / allergen quick-entry state (fine dining)
// ---------------------------------------------------------------------------

/// The gang (course group) number every new item is tagged with until the
/// waiter changes it. Valid values are 1..[RestaurantSettings.clampedMaxGangs]
/// when `gangsEnabled` is true; irrelevant (but still 1) when disabled.
///
/// Persists across quick-add taps so a waiter can pick "Gang 2" once and
/// tap 5 dishes in a row. The kitchen fires each gang as a unit.
final waiterCurrentCourseProvider = StateProvider<int>((ref) => 1);

/// The seat (cover) number every new item is tagged with until the waiter
/// changes it. `0` = shared / unassigned; 1..ticket.guestCount identifies a
/// specific cover for split-by-seat billing.
///
/// Persists across quick-add taps so a waiter can pick "Seat 2" once and
/// tap every dish for that guest in a row.
final waiterCurrentSeatProvider = StateProvider<int>((ref) => 0);

/// Allergen / dietary flags the waiter has currently toggled on.
///
/// These are flushed into the next added item's `notes` field and then
/// cleared, so they never silently stick to unrelated items.
final waiterPendingAllergensProvider =
    StateProvider<Set<String>>((ref) => <String>{});

/// Products filtered by the current search query (across all categories).
final waiterSearchResultsProvider =
    FutureProvider<List<ProductEntity>>((ref) async {
  final query = ref.watch(waiterSearchQueryProvider).trim();
  if (query.isEmpty) return const [];
  final repo = ref.watch(_menuRepoProvider);
  final tenantId = ref.watch(tenantIdProvider);
  return repo.searchProducts(tenantId, query);
});

// ---------------------------------------------------------------------------
// Service calls (waiter → boss/KDS dashboards)
// ---------------------------------------------------------------------------

final serviceCallRepositoryProvider =
    Provider<ServiceCallRepositoryImpl>((ref) {
  return ServiceCallRepositoryImpl(ref.watch(databaseProvider));
});

/// Active (non-resolved) calls for the current waiter, live.
final waiterActiveServiceCallsProvider =
    StreamProvider<List<ServiceCallEntity>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return Stream.value(const []);
  final tenantId = ref.watch(tenantIdProvider);
  final repo = ref.watch(serviceCallRepositoryProvider);
  return repo
      .watchActive(tenantId)
      .map((calls) => calls.where((c) => c.waiterId == user.id).toList());
});

/// Raise a new service call from the waiter UI.
///
/// Looks up the active session (selected table + ticket) so the call is
/// routed with enough context for the dashboard operator to respond.
/// Accepts a [WidgetRef] so it can be called straight from a widget's
/// event handler.
Future<ServiceCallEntity?> raiseServiceCall(
  WidgetRef ref, {
  required ServiceCallKind kind,
  String? note,
}) async {
  final user = ref.read(currentUserProvider);
  if (user == null) return null;
  final tenantId = ref.read(tenantIdProvider);
  final deviceId = ref.read(deviceIdProvider);
  final table = ref.read(waiterSelectedTableProvider);
  final ticket = ref.read(waiterActiveTicketProvider);

  final entity = ServiceCallEntity(
    id: IdGenerator.generateId(),
    tenantId: tenantId,
    tableId: table?.id,
    ticketId: ticket?.id,
    waiterId: user.id,
    waiterName: user.name,
    kind: kind,
    note: note,
    createdAt: DateTime.now(),
  );
  return ref
      .read(serviceCallRepositoryProvider)
      .create(entity, deviceId: deviceId);
}
