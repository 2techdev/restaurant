/// Riverpod providers for the table / floor-plan feature.
///
/// Exposes real-time streams for floors and tables, edit-mode state,
/// and a [TableManagementNotifier] for all mutating operations
/// (CRUD, merge, transfer, position updates).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/di/providers.dart';
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
final tablesProvider = StreamProvider<List<RestaurantTableEntity>>((ref) {
  final repo = ref.watch(tableRepositoryProvider);
  final floorId = ref.watch(selectedFloorProvider);
  if (floorId == null) return Stream.value(const []);
  return repo.watchTablesByFloor(floorId);
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
