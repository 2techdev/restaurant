/// Riverpod providers for the table / floor-plan feature.
///
/// Exposes real-time streams for floors and tables, edit-mode state,
/// and a [TableManagementNotifier] for all mutating operations
/// (CRUD, merge, transfer, position updates).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/features/orders/presentation/providers/order_provider.dart';
import 'package:gastrocore_pos/features/tables/data/repositories/table_repository_impl.dart';
import 'package:gastrocore_pos/features/tables/domain/entities/table_entity.dart';

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

/// Singleton [TableRepositoryImpl] backed by the app database.
final tableRepositoryProvider = Provider<TableRepositoryImpl>((ref) {
  return TableRepositoryImpl(ref.watch(databaseProvider));
});

// ---------------------------------------------------------------------------
// Floors – real-time stream
// ---------------------------------------------------------------------------

/// Live stream of all floors for the current tenant, ordered by displayOrder.
final floorsProvider = StreamProvider<List<FloorEntity>>((ref) {
  final repo = ref.watch(tableRepositoryProvider);
  final tenantId = ref.watch(tenantIdProvider);
  return repo.watchFloors(tenantId);
});

/// The currently selected floor ID.
/// `null` = nothing selected yet (UI auto-selects first floor on load).
final selectedFloorProvider = StateProvider<String?>((ref) => null);

// ---------------------------------------------------------------------------
// Tables – real-time stream
// ---------------------------------------------------------------------------

/// Live stream of tables for the currently selected floor.
/// Returns an empty list when no floor is selected.
///
/// Temporary tables (M4 ad-hoc rows) are filtered out: they don't have
/// a position on the canvas and appear instead on the open-tickets
/// rail / sales shell. This keeps the floor plan clean of transient
/// rows that would otherwise pile up at (0, 0).
final tablesProvider = StreamProvider<List<RestaurantTableEntity>>((ref) {
  final repo = ref.watch(tableRepositoryProvider);
  final floorId = ref.watch(selectedFloorProvider);
  if (floorId == null) return Stream.value(const []);
  return repo
      .watchTablesByFloor(floorId)
      .map((tables) => tables.where((t) => !t.isTemporary).toList());
});

/// All non-temporary tables for the current tenant across every floor.
/// Used by transfer-order and merge dialogs that need a complete list
/// of "real" floor-plan tables.
final allFloorTablesProvider =
    FutureProvider<List<RestaurantTableEntity>>((ref) async {
  final repo = ref.watch(tableRepositoryProvider);
  final tenantId = ref.watch(tenantIdProvider);
  final tables = await repo.getAllTables(tenantId);
  return tables.where((t) => !t.isTemporary).toList();
});

/// All open temporary tables for the current tenant. Pilot crews see
/// these on the sales-shell topbar / open-tickets rail; cleanup happens
/// automatically when the bound ticket settles or is voided.
final openTemporaryTablesProvider =
    FutureProvider<List<RestaurantTableEntity>>((ref) async {
  final repo = ref.watch(tableRepositoryProvider);
  final tenantId = ref.watch(tenantIdProvider);
  final tables = await repo.getAllTables(tenantId);
  return tables.where((t) => t.isTemporary).toList();
});

// ---------------------------------------------------------------------------
// Edit mode
// ---------------------------------------------------------------------------

/// All tables for the current tenant across every floor.
/// Used by transfer-order and merge dialogs.
final allTablesProvider = FutureProvider<List<RestaurantTableEntity>>((ref) {
  final repo = ref.watch(tableRepositoryProvider);
  final tenantId = ref.watch(tenantIdProvider);
  return repo.getAllTables(tenantId);
});

/// Whether the floor plan is in drag-and-drop edit mode.
final tableEditModeProvider = StateProvider<bool>((ref) => false);

// ---------------------------------------------------------------------------
// Enriched tables — table joined with its active ticket (Faz 2)
// ---------------------------------------------------------------------------

/// Read-only view of a table plus its current ticket (when one exists).
/// The floor plan grid uses this to render guest count, sitting
/// duration, gross total and waiter initials on each tile without
/// recomputing the join inside the widget.
class EnrichedTable {
  const EnrichedTable({required this.table, this.ticket});
  final RestaurantTableEntity table;
  final TicketEntity? ticket;

  /// Whether this row has an active (non-completed/non-cancelled) ticket.
  bool get isOccupied => ticket != null && ticket!.items.isNotEmpty;

  /// `null` when the ticket isn't open yet; otherwise minutes since
  /// the ticket was opened (clamped to 0 to avoid negative skew when
  /// device clocks drift).
  int? get sittingMinutes {
    final t = ticket;
    if (t == null) return null;
    final delta = DateTime.now().difference(t.openedAt).inMinutes;
    return delta < 0 ? 0 : delta;
  }
}

/// Live join of [tablesProvider] (selected floor) with the open-ticket
/// list. Each entry carries the table + its current ticket (or null).
///
/// Re-emits when either side changes. Lookup is O(N+M) by tableId; for
/// the pilot floor (≤ ~20 tables × ≤ ~40 open tickets) this is fine.
final enrichedTablesProvider =
    Provider<AsyncValue<List<EnrichedTable>>>((ref) {
  final tablesAsync = ref.watch(tablesProvider);
  final ticketsAsync = ref.watch(openTicketsProvider);

  if (tablesAsync.isLoading || ticketsAsync.isLoading) {
    return const AsyncLoading();
  }
  if (tablesAsync.hasError) {
    return AsyncError(tablesAsync.error!, tablesAsync.stackTrace!);
  }
  if (ticketsAsync.hasError) {
    return AsyncError(ticketsAsync.error!, ticketsAsync.stackTrace!);
  }

  final tables = tablesAsync.value ?? const <RestaurantTableEntity>[];
  final tickets = ticketsAsync.value ?? const <TicketEntity>[];

  // Index tickets by tableId (the latest open ticket wins if a table
  // somehow has multiple — shouldn't happen but defensive).
  final byTable = <String, TicketEntity>{};
  for (final t in tickets) {
    final tid = t.tableId;
    if (tid == null || tid.isEmpty) continue;
    byTable[tid] = t;
  }

  return AsyncData(
    tables
        .map((t) => EnrichedTable(table: t, ticket: byTable[t.id]))
        .toList(growable: false),
  );
});

/// Filter modes for the v3 floor-plan top bar.
enum FloorPlanFilter {
  /// Show every table regardless of state.
  all,

  /// Only tables with an active ticket (occupied / bill requested).
  active,

  /// Only tables whose waiter / guest has requested the bill.
  pending,

  /// Only free + dirty tables — nothing to settle right now.
  free,
}

/// Operator-selected filter for the floor-plan grid. Local state, not
/// persisted; defaults to [FloorPlanFilter.all] each session.
final floorPlanFilterProvider =
    StateProvider<FloorPlanFilter>((ref) => FloorPlanFilter.all);

// ---------------------------------------------------------------------------
// Zone filter (pilot: local, not persisted to DB)
// ---------------------------------------------------------------------------

/// Canonical zone labels shown as filter chips above the floor plan grid.
/// Kept in Turkish to match the pilot UI. `hepsi` ("all") means no filter.
///
/// Persisting zone-per-table would require a new column on
/// [restaurant_tables]; for the pilot we keep a local assignment map and a
/// selection state in Riverpod so the feature can be exercised without a
/// schema migration. Unknown / unassigned tables fall back to `icSalon`.
enum TableZone {
  hepsi,
  icSalon,
  teras,
  bar,
}

/// Display label (Turkish) for [TableZone].
String tableZoneLabel(TableZone z) => switch (z) {
      TableZone.hepsi => 'Hepsi',
      TableZone.icSalon => 'İç Salon',
      TableZone.teras => 'Teras',
      TableZone.bar => 'Bar',
    };

/// Currently selected zone filter. `hepsi` = no filter.
final selectedTableZoneProvider =
    StateProvider<TableZone>((ref) => TableZone.hepsi);

/// Local per-table zone assignments (pilot, in-memory).
///
/// Keys are table IDs; missing entries are treated as [TableZone.icSalon] by
/// [tableZoneForId]. This map replaces what would otherwise be a new
/// `zone` column on restaurant_tables — kept as a provider for the pilot so
/// no Drift migration is required.
final tableZoneAssignmentsProvider =
    StateProvider<Map<String, TableZone>>((ref) => const {});

/// Resolve the zone for a given table ID, falling back to İç Salon.
TableZone tableZoneForId(
  Map<String, TableZone> assignments,
  String tableId,
) =>
    assignments[tableId] ?? TableZone.icSalon;

// ---------------------------------------------------------------------------
// Table management notifier
// ---------------------------------------------------------------------------

/// State held by [TableManagementNotifier].
class TableManagementState {
  final bool isLoading;
  final String? error;

  const TableManagementState({this.isLoading = false, this.error});

  TableManagementState copyWith({bool? isLoading, String? error}) {
    return TableManagementState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// Notifier for all mutating table/floor operations.
///
/// Streams in [floorsProvider] and [tablesProvider] react automatically
/// to DB changes – callers do not need to manually invalidate providers.
class TableManagementNotifier
    extends StateNotifier<TableManagementState> {
  final TableRepositoryImpl _repo;
  final Ref _ref;

  TableManagementNotifier(this._repo, this._ref)
      : super(const TableManagementState());

  String get _tenantId => _ref.read(tenantIdProvider);

  // ---- Floors ----

  Future<FloorEntity?> createFloor({
    required String name,
    required int displayOrder,
  }) async {
    state = state.copyWith(isLoading: true);
    try {
      final floor = await _repo.createFloor(
        tenantId: _tenantId,
        name: name,
        displayOrder: displayOrder,
      );
      state = state.copyWith(isLoading: false);
      return floor;
    } catch (e) {
      state = TableManagementState(error: e.toString());
      return null;
    }
  }

  Future<void> updateFloor({
    required String floorId,
    String? name,
    int? displayOrder,
  }) async {
    state = state.copyWith(isLoading: true);
    try {
      await _repo.updateFloor(
          floorId: floorId, name: name, displayOrder: displayOrder);
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = TableManagementState(error: e.toString());
    }
  }

  Future<void> deleteFloor(String floorId) async {
    state = state.copyWith(isLoading: true);
    try {
      await _repo.deleteFloor(floorId);
      // Deselect the floor if it was selected.
      if (_ref.read(selectedFloorProvider) == floorId) {
        _ref.read(selectedFloorProvider.notifier).state = null;
      }
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = TableManagementState(error: e.toString());
    }
  }

  // ---- Tables ----

  Future<RestaurantTableEntity?> createTable({
    required String floorId,
    required String name,
    int capacity = 4,
    TableShape shape = TableShape.rectangle,
    double posX = 50,
    double posY = 50,
    double width = 120,
    double height = 80,
  }) async {
    state = state.copyWith(isLoading: true);
    try {
      final table = await _repo.createTable(
        tenantId: _tenantId,
        floorId: floorId,
        name: name,
        capacity: capacity,
        shape: shape,
        posX: posX,
        posY: posY,
        width: width,
        height: height,
      );
      state = state.copyWith(isLoading: false);
      return table;
    } catch (e) {
      state = TableManagementState(error: e.toString());
      return null;
    }
  }

  Future<void> updateTable({
    required String tableId,
    String? name,
    int? capacity,
    TableShape? shape,
    String? floorId,
    double? width,
    double? height,
  }) async {
    state = state.copyWith(isLoading: true);
    try {
      await _repo.updateTable(
        tableId: tableId,
        name: name,
        capacity: capacity,
        shape: shape,
        floorId: floorId,
        width: width,
        height: height,
      );
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = TableManagementState(error: e.toString());
    }
  }

  Future<void> deleteTable(String tableId) async {
    state = state.copyWith(isLoading: true);
    try {
      await _repo.deleteTable(tableId);
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = TableManagementState(error: e.toString());
    }
  }

  /// M4 — create an ad-hoc table from the sales-shell numpad.
  ///
  /// Conventions:
  ///   * `name` is `"Tisch <number>"` (caller composes the prefix).
  ///   * Uniqueness is enforced across persistent + open temporary
  ///     rows; clashes return [TempTableError.duplicate].
  ///   * Capacity defaults to 4 — pilot crews never want to be
  ///     interrupted by a capacity prompt while a guest is at the
  ///     counter. Adjust later via the regular table-edit UI.
  ///   * Floor: the first persistent floor wins. Pilot tenants always
  ///     have at least one ("EG / Erdgeschoss"); we error if not.
  Future<TempTableCreateResult> createTemporaryTable({
    required String name,
    int capacity = 4,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return const TempTableCreateResult.failure(
          TempTableError.invalidName);
    }
    final existing = await _repo.findTableByName(_tenantId, trimmed);
    if (existing != null) {
      return TempTableCreateResult.failure(
        TempTableError.duplicate,
        clashingTable: existing,
      );
    }

    // Find a floor — temporary tables don't surface on the plan, but
    // every row needs a floor FK so reservations / merges work.
    final floors = await _repo.getFloors(_tenantId);
    if (floors.isEmpty) {
      return const TempTableCreateResult.failure(TempTableError.noFloor);
    }
    final floorId = floors.first.id;

    state = state.copyWith(isLoading: true);
    try {
      final table = await _repo.createTable(
        tenantId: _tenantId,
        floorId: floorId,
        name: trimmed,
        capacity: capacity,
        isTemporary: true,
      );
      state = state.copyWith(isLoading: false);
      return TempTableCreateResult.success(table);
    } catch (e) {
      state = TableManagementState(error: e.toString());
      return const TempTableCreateResult.failure(TempTableError.dbError);
    }
  }

  /// M4 — close path hook.
  ///
  /// Called after a ticket settles or is cancelled. If the ticket's
  /// table was an ad-hoc row, soft-deletes it and returns the
  /// pre-delete entity so the caller can drop an audit entry; returns
  /// null for persistent tables. Safe to call blindly.
  Future<RestaurantTableEntity?> closeTemporaryTableIfApplicable(
    String tableId,
  ) async {
    return _repo.deleteTemporaryTable(tableId);
  }

  Future<void> updateTablePosition(
      String tableId, double posX, double posY) async {
    // Silent update – no loading state to avoid re-renders during drag.
    try {
      await _repo.updateTablePosition(tableId, posX, posY);
    } catch (e) {
      state = TableManagementState(error: e.toString());
    }
  }

  Future<void> updateTableStatus(String tableId, TableStatus status) async {
    try {
      await _repo.updateTableStatus(tableId, status);
    } catch (e) {
      state = TableManagementState(error: e.toString());
    }
  }

  Future<void> updateGuestCount(String ticketId, int guestCount) async {
    try {
      await _repo.updateGuestCount(ticketId, guestCount);
    } catch (e) {
      state = TableManagementState(error: e.toString());
    }
  }

  // ---- Merge & Transfer ----

  Future<void> mergeTables({
    required String primaryTableId,
    required String secondaryTableId,
  }) async {
    state = state.copyWith(isLoading: true);
    try {
      await _repo.mergeTables(
        primaryTableId: primaryTableId,
        secondaryTableId: secondaryTableId,
      );
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = TableManagementState(error: e.toString());
    }
  }

  Future<void> transferOrder({
    required String fromTableId,
    required String toTableId,
  }) async {
    state = state.copyWith(isLoading: true);
    try {
      await _repo.transferOrder(
        fromTableId: fromTableId,
        toTableId: toTableId,
      );
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = TableManagementState(error: e.toString());
    }
  }

  void clearError() => state = state.copyWith(isLoading: false);
}

/// Provider for [TableManagementNotifier].
final tableManagementProvider =
    StateNotifierProvider<TableManagementNotifier, TableManagementState>((ref) {
  return TableManagementNotifier(ref.watch(tableRepositoryProvider), ref);
});

// ---------------------------------------------------------------------------
// Temporary-table create result
// ---------------------------------------------------------------------------

/// Outcome of `createTemporaryTable`. Sealed so callers exhaust the
/// success / failure branches and surface the right snackbar copy.
sealed class TempTableCreateResult {
  const TempTableCreateResult();

  const factory TempTableCreateResult.success(RestaurantTableEntity table) =
      TempTableCreateSuccess;

  const factory TempTableCreateResult.failure(
    TempTableError error, {
    RestaurantTableEntity? clashingTable,
  }) = TempTableCreateFailure;
}

class TempTableCreateSuccess extends TempTableCreateResult {
  final RestaurantTableEntity table;
  const TempTableCreateSuccess(this.table);
}

class TempTableCreateFailure extends TempTableCreateResult {
  final TempTableError error;
  final RestaurantTableEntity? clashingTable;
  const TempTableCreateFailure(this.error, {this.clashingTable});
}

enum TempTableError {
  invalidName,
  duplicate,
  noFloor,
  dbError,
}
