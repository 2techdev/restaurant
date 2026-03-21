/// Drift-backed implementation of the table / floor-plan repository.
///
/// Manages restaurant floors and tables: CRUD operations, real-time streams,
/// position updates (drag-and-drop), table merge, and order transfer.
library;

import 'package:drift/drift.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/tables/domain/entities/table_entity.dart';

class TableRepositoryImpl {
  final AppDatabase _db;

  TableRepositoryImpl(this._db);

  // =========================================================================
  // Floors – Queries
  // =========================================================================

  /// All floors for [tenantId], ordered by [displayOrder].
  Future<List<FloorEntity>> getFloors(String tenantId) async {
    final query = _db.select(_db.floors)
      ..where(
        (f) => f.tenantId.equals(tenantId) & f.isDeleted.equals(false),
      )
      ..orderBy([(f) => OrderingTerm.asc(f.displayOrder)]);
    return (await query.get()).map(_floorToEntity).toList();
  }

  /// Real-time stream of floors for [tenantId].
  Stream<List<FloorEntity>> watchFloors(String tenantId) {
    return (_db.select(_db.floors)
          ..where(
              (f) => f.tenantId.equals(tenantId) & f.isDeleted.equals(false))
          ..orderBy([(f) => OrderingTerm.asc(f.displayOrder)]))
        .watch()
        .map((rows) => rows.map(_floorToEntity).toList());
  }

  // =========================================================================
  // Floors – CRUD
  // =========================================================================

  /// Insert a new floor and return its entity.
  Future<FloorEntity> createFloor({
    required String tenantId,
    required String name,
    required int displayOrder,
  }) async {
    final id = IdGenerator.generateId();
    final now = DateTime.now();
    await _db.into(_db.floors).insert(FloorsCompanion(
          id: Value(id),
          tenantId: Value(tenantId),
          name: Value(name),
          displayOrder: Value(displayOrder),
          createdAt: Value(now),
          updatedAt: Value(now),
        ));
    return FloorEntity(
        id: id, tenantId: tenantId, name: name, displayOrder: displayOrder);
  }

  /// Update floor name and/or display order.
  Future<void> updateFloor({
    required String floorId,
    String? name,
    int? displayOrder,
  }) async {
    final current = await (_db.select(_db.floors)
          ..where((f) => f.id.equals(floorId)))
        .getSingleOrNull();
    if (current == null) return;
    await (_db.update(_db.floors)..where((f) => f.id.equals(floorId))).write(
      FloorsCompanion(
        name: Value(name ?? current.name),
        displayOrder: Value(displayOrder ?? current.displayOrder),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Soft-delete a floor (marks [isDeleted] = true).
  Future<void> deleteFloor(String floorId) async {
    await (_db.update(_db.floors)..where((f) => f.id.equals(floorId))).write(
      FloorsCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  // =========================================================================
  // Tables – Queries
  // =========================================================================

  /// Tables on [floorId], ordered by name.
  Future<List<RestaurantTableEntity>> getTablesByFloor(String floorId) async {
    final query = _db.select(_db.restaurantTables)
      ..where(
        (t) => t.floorId.equals(floorId) & t.isDeleted.equals(false),
      )
      ..orderBy([(t) => OrderingTerm.asc(t.name)]);
    return (await query.get()).map(_tableToEntity).toList();
  }

  /// All tables for [tenantId] across all floors.
  Future<List<RestaurantTableEntity>> getAllTables(String tenantId) async {
    final query = _db.select(_db.restaurantTables)
      ..where(
        (t) => t.tenantId.equals(tenantId) & t.isDeleted.equals(false),
      )
      ..orderBy([(t) => OrderingTerm.asc(t.name)]);
    return (await query.get()).map(_tableToEntity).toList();
  }

  /// Real-time stream of tables on [floorId].
  Stream<List<RestaurantTableEntity>> watchTablesByFloor(String floorId) {
    return (_db.select(_db.restaurantTables)
          ..where(
              (t) => t.floorId.equals(floorId) & t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch()
        .map((rows) => rows.map(_tableToEntity).toList());
  }

  // =========================================================================
  // Tables – CRUD
  // =========================================================================

  /// Insert a new table and return its entity.
  Future<RestaurantTableEntity> createTable({
    required String tenantId,
    required String floorId,
    required String name,
    int capacity = 4,
    TableShape shape = TableShape.rectangle,
    double posX = 50,
    double posY = 50,
    double width = 120,
    double height = 80,
  }) async {
    final id = IdGenerator.generateId();
    final now = DateTime.now();
    await _db.into(_db.restaurantTables).insert(RestaurantTablesCompanion(
          id: Value(id),
          tenantId: Value(tenantId),
          floorId: Value(floorId),
          name: Value(name),
          capacity: Value(capacity),
          shape: Value(_tableShapeToString(shape)),
          posX: Value(posX),
          posY: Value(posY),
          width: Value(width),
          height: Value(height),
          status: const Value('available'),
          createdAt: Value(now),
          updatedAt: Value(now),
        ));
    return RestaurantTableEntity(
      id: id,
      tenantId: tenantId,
      floorId: floorId,
      name: name,
      capacity: capacity,
      shape: shape,
      posX: posX,
      posY: posY,
      width: width,
      height: height,
    );
  }

  /// Update table metadata (name, capacity, shape, floor, dimensions).
  Future<void> updateTable({
    required String tableId,
    String? name,
    int? capacity,
    TableShape? shape,
    String? floorId,
    double? width,
    double? height,
  }) async {
    final current = await (_db.select(_db.restaurantTables)
          ..where((t) => t.id.equals(tableId)))
        .getSingleOrNull();
    if (current == null) return;
    await (_db.update(_db.restaurantTables)
          ..where((t) => t.id.equals(tableId)))
        .write(RestaurantTablesCompanion(
      name: Value(name ?? current.name),
      capacity: Value(capacity ?? current.capacity),
      shape: Value(shape != null ? _tableShapeToString(shape) : current.shape),
      floorId: Value(floorId ?? current.floorId),
      width: Value(width ?? current.width),
      height: Value(height ?? current.height),
      updatedAt: Value(DateTime.now()),
    ));
  }

  /// Update the canvas position of a table (used during drag-and-drop).
  Future<void> updateTablePosition(
      String tableId, double posX, double posY) async {
    await (_db.update(_db.restaurantTables)
          ..where((t) => t.id.equals(tableId)))
        .write(RestaurantTablesCompanion(
      posX: Value(posX),
      posY: Value(posY),
      updatedAt: Value(DateTime.now()),
    ));
  }

  /// Soft-delete a table.
  Future<void> deleteTable(String tableId) async {
    await (_db.update(_db.restaurantTables)
          ..where((t) => t.id.equals(tableId)))
        .write(RestaurantTablesCompanion(
      isDeleted: const Value(true),
      updatedAt: Value(DateTime.now()),
    ));
  }

  // =========================================================================
  // Tables – Status & Order
  // =========================================================================

  /// Update the status of a table.
  Future<void> updateTableStatus(String tableId, TableStatus status) async {
    await (_db.update(_db.restaurantTables)
          ..where((t) => t.id.equals(tableId)))
        .write(RestaurantTablesCompanion(
      status: Value(_tableStatusToString(status)),
      updatedAt: Value(DateTime.now()),
    ));
  }

  /// Link an active order to a table and mark it as occupied.
  Future<void> linkOrderToTable(String tableId, String orderId) async {
    await (_db.update(_db.restaurantTables)
          ..where((t) => t.id.equals(tableId)))
        .write(RestaurantTablesCompanion(
      currentOrderId: Value(orderId),
      status: const Value('occupied'),
      updatedAt: Value(DateTime.now()),
    ));
  }

  /// Clear a table: set status back to available and remove the linked order.
  Future<void> clearTable(String tableId) async {
    await (_db.update(_db.restaurantTables)
          ..where((t) => t.id.equals(tableId)))
        .write(RestaurantTablesCompanion(
      currentOrderId: const Value(null),
      status: const Value('available'),
      updatedAt: Value(DateTime.now()),
    ));
  }

  /// Update the number of guests tracked on the active ticket for a table.
  ///
  /// Requires that [currentOrderId] is set on the table.
  Future<void> updateGuestCount(String ticketId, int guestCount) async {
    await (_db.update(_db.tickets)..where((t) => t.id.equals(ticketId))).write(
      TicketsCompanion(
        guestCount: Value(guestCount),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  // =========================================================================
  // Merge Tables
  // =========================================================================

  /// Merge [secondaryTableId] into [primaryTableId].
  ///
  /// Behaviour:
  /// - If the secondary table has an active order and the primary does not,
  ///   the order is re-linked to the primary table.
  /// - The secondary table is cleared and marked as [TableStatus.dirty].
  ///
  /// This runs inside a single DB transaction.
  Future<void> mergeTables({
    required String primaryTableId,
    required String secondaryTableId,
  }) async {
    await _db.transaction(() async {
      final primary = await (_db.select(_db.restaurantTables)
            ..where((t) => t.id.equals(primaryTableId)))
          .getSingleOrNull();
      final secondary = await (_db.select(_db.restaurantTables)
            ..where((t) => t.id.equals(secondaryTableId)))
          .getSingleOrNull();

      if (primary == null || secondary == null) return;

      final orderId = secondary.currentOrderId;

      if (orderId != null && primary.currentOrderId == null) {
        // Move the order to the primary table.
        await (_db.update(_db.restaurantTables)
              ..where((t) => t.id.equals(primaryTableId)))
            .write(RestaurantTablesCompanion(
          currentOrderId: Value(orderId),
          status: const Value('occupied'),
          updatedAt: Value(DateTime.now()),
        ));

        // Point the ticket at the new (primary) table.
        await (_db.update(_db.tickets)
              ..where((t) => t.id.equals(orderId)))
            .write(TicketsCompanion(
          tableId: Value(primaryTableId),
          updatedAt: Value(DateTime.now()),
        ));
      }

      // Clear the secondary table.
      await (_db.update(_db.restaurantTables)
            ..where((t) => t.id.equals(secondaryTableId)))
          .write(RestaurantTablesCompanion(
        currentOrderId: const Value(null),
        status: const Value('dirty'),
        updatedAt: Value(DateTime.now()),
      ));
    });
  }

  // =========================================================================
  // Transfer Order
  // =========================================================================

  /// Transfer the active order from [fromTableId] to [toTableId].
  ///
  /// After the transfer:
  /// - [toTableId] is linked to the order and marked occupied.
  /// - [fromTableId] is cleared and marked dirty.
  ///
  /// Does nothing if [fromTableId] has no active order.
  Future<void> transferOrder({
    required String fromTableId,
    required String toTableId,
  }) async {
    await _db.transaction(() async {
      final fromTable = await (_db.select(_db.restaurantTables)
            ..where((t) => t.id.equals(fromTableId)))
          .getSingleOrNull();
      if (fromTable == null || fromTable.currentOrderId == null) return;

      final orderId = fromTable.currentOrderId!;

      // Re-link the order to the destination table.
      await (_db.update(_db.restaurantTables)
            ..where((t) => t.id.equals(toTableId)))
          .write(RestaurantTablesCompanion(
        currentOrderId: Value(orderId),
        status: const Value('occupied'),
        updatedAt: Value(DateTime.now()),
      ));

      // Update the ticket's table reference.
      await (_db.update(_db.tickets)
            ..where((t) => t.id.equals(orderId)))
          .write(TicketsCompanion(
        tableId: Value(toTableId),
        updatedAt: Value(DateTime.now()),
      ));

      // Clear the source table.
      await (_db.update(_db.restaurantTables)
            ..where((t) => t.id.equals(fromTableId)))
          .write(RestaurantTablesCompanion(
        currentOrderId: const Value(null),
        status: const Value('dirty'),
        updatedAt: Value(DateTime.now()),
      ));
    });
  }

  // =========================================================================
  // Mappers – Floor
  // =========================================================================

  FloorEntity _floorToEntity(Floor row) {
    return FloorEntity(
      id: row.id,
      tenantId: row.tenantId,
      name: row.name,
      displayOrder: row.displayOrder,
    );
  }

  // =========================================================================
  // Mappers – Table
  // =========================================================================

  RestaurantTableEntity _tableToEntity(RestaurantTable row) {
    return RestaurantTableEntity(
      id: row.id,
      tenantId: row.tenantId,
      floorId: row.floorId,
      name: row.name,
      capacity: row.capacity,
      shape: _parseTableShape(row.shape),
      posX: row.posX,
      posY: row.posY,
      width: row.width,
      height: row.height,
      status: _parseTableStatus(row.status),
      currentOrderId: row.currentOrderId,
    );
  }

  // =========================================================================
  // Enum serialisation
  // =========================================================================

  static TableShape _parseTableShape(String value) {
    return switch (value) {
      'circle' => TableShape.circle,
      'square' => TableShape.square,
      _ => TableShape.rectangle,
    };
  }

  static TableStatus _parseTableStatus(String value) {
    return switch (value) {
      'available' => TableStatus.available,
      'occupied' => TableStatus.occupied,
      'reserved' => TableStatus.reserved,
      'dirty' => TableStatus.dirty,
      _ => TableStatus.available,
    };
  }

  static String _tableStatusToString(TableStatus status) {
    return switch (status) {
      TableStatus.available => 'available',
      TableStatus.occupied => 'occupied',
      TableStatus.reserved => 'reserved',
      TableStatus.dirty => 'dirty',
    };
  }

  static String _tableShapeToString(TableShape shape) {
    return switch (shape) {
      TableShape.rectangle => 'rectangle',
      TableShape.circle => 'circle',
      TableShape.square => 'square',
    };
  }
}
