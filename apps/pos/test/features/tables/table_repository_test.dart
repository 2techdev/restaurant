/// Unit tests for TableRepositoryImpl.
///
/// Uses an in-memory Drift database so no file system access is required.
/// Covers floors and tables CRUD, status updates, position updates,
/// table merge, and order transfer operations.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/features/tables/data/repositories/table_repository_impl.dart';
import 'package:gastrocore_pos/features/tables/domain/entities/table_entity.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _tenantId = 'tenant-001';
const _floorId = 'floor-001';
const _floor2Id = 'floor-002';

Future<AppDatabase> _openDb() async => AppDatabase.createInMemory();

/// Insert a raw floor row so tests don't depend on createFloor() itself.
Future<void> _seedFloor(
  AppDatabase db, {
  String id = _floorId,
  String name = 'Main Hall',
  int displayOrder = 0,
}) async {
  await db.into(db.floors).insert(FloorsCompanion.insert(
        id: id,
        tenantId: _tenantId,
        name: name,
        displayOrder: Value(displayOrder),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
}

/// Insert a raw table row.
Future<void> _seedTable(
  AppDatabase db, {
  required String id,
  String floorId = _floorId,
  String name = 'T1',
  String status = 'available',
  String? currentOrderId,
}) async {
  await db.into(db.restaurantTables).insert(
        RestaurantTablesCompanion.insert(
          id: id,
          tenantId: _tenantId,
          floorId: floorId,
          name: name,
          capacity: const Value(4),
          posX: const Value(0.0),
          posY: const Value(0.0),
          width: const Value(120.0),
          height: const Value(80.0),
          status: Value(status),
          currentOrderId: Value(currentOrderId),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
}

/// Insert a minimal ticket row.
Future<void> _seedTicket(AppDatabase db, String ticketId,
    {String? tableId}) async {
  await db.into(db.tickets).insert(TicketsCompanion.insert(
        id: ticketId,
        tenantId: _tenantId,
        orderNumber: 1,
        tableId: Value(tableId),
        status: const Value('open'),
        openedAt: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        deviceId: 'DEV-01',
      ));
}

// ---------------------------------------------------------------------------
// Test suite
// ---------------------------------------------------------------------------

void main() {
  // =========================================================================
  // Floor tests
  // =========================================================================

  group('Floors', () {
    test('getFloors returns floors ordered by displayOrder', () async {
      final db = await _openDb();
      final repo = TableRepositoryImpl(db);

      await _seedFloor(db, id: 'f1', name: 'Terrace', displayOrder: 2);
      await _seedFloor(db, id: 'f2', name: 'Main Hall', displayOrder: 0);
      await _seedFloor(db, id: 'f3', name: 'Bar', displayOrder: 1);

      final floors = await repo.getFloors(_tenantId);

      expect(floors.length, 3);
      expect(floors[0].name, 'Main Hall');
      expect(floors[1].name, 'Bar');
      expect(floors[2].name, 'Terrace');

      await db.close();
    });

    test('getFloors excludes soft-deleted floors', () async {
      final db = await _openDb();
      final repo = TableRepositoryImpl(db);

      await _seedFloor(db, id: 'f1', name: 'Active');
      // Manually soft-delete a second floor.
      await _seedFloor(db, id: 'f2', name: 'Deleted');
      await (db.update(db.floors)..where((f) => f.id.equals('f2'))).write(
        FloorsCompanion(isDeleted: const Value(true)),
      );

      final floors = await repo.getFloors(_tenantId);

      expect(floors.length, 1);
      expect(floors.first.name, 'Active');

      await db.close();
    });

    test('createFloor inserts and returns FloorEntity', () async {
      final db = await _openDb();
      final repo = TableRepositoryImpl(db);

      final floor = await repo.createFloor(
        tenantId: _tenantId,
        name: 'Rooftop',
        displayOrder: 3,
      );

      expect(floor.name, 'Rooftop');
      expect(floor.displayOrder, 3);
      expect(floor.tenantId, _tenantId);

      final fetched = await repo.getFloors(_tenantId);
      expect(fetched.length, 1);

      await db.close();
    });

    test('updateFloor changes name and displayOrder', () async {
      final db = await _openDb();
      final repo = TableRepositoryImpl(db);

      await _seedFloor(db, id: 'f1', name: 'Old Name', displayOrder: 0);
      await repo.updateFloor(floorId: 'f1', name: 'New Name', displayOrder: 5);

      final floors = await repo.getFloors(_tenantId);
      expect(floors.first.name, 'New Name');
      expect(floors.first.displayOrder, 5);

      await db.close();
    });

    test('updateFloor with only name keeps existing displayOrder', () async {
      final db = await _openDb();
      final repo = TableRepositoryImpl(db);

      await _seedFloor(db, id: 'f1', name: 'Old', displayOrder: 7);
      await repo.updateFloor(floorId: 'f1', name: 'New');

      final floors = await repo.getFloors(_tenantId);
      expect(floors.first.name, 'New');
      expect(floors.first.displayOrder, 7);

      await db.close();
    });

    test('deleteFloor soft-deletes the floor', () async {
      final db = await _openDb();
      final repo = TableRepositoryImpl(db);

      await _seedFloor(db, id: 'f1');
      await repo.deleteFloor('f1');

      final floors = await repo.getFloors(_tenantId);
      expect(floors, isEmpty);

      await db.close();
    });

    test('watchFloors emits updated list on change', () async {
      final db = await _openDb();
      final repo = TableRepositoryImpl(db);

      final stream = repo.watchFloors(_tenantId);
      final first = await stream.first;
      expect(first, isEmpty);

      await repo.createFloor(
          tenantId: _tenantId, name: 'Hall', displayOrder: 0);
      final second = await stream.first;
      expect(second.length, 1);

      await db.close();
    });
  });

  // =========================================================================
  // Table tests
  // =========================================================================

  group('Tables', () {
    test('getTablesByFloor returns tables on the given floor', () async {
      final db = await _openDb();
      final repo = TableRepositoryImpl(db);

      await _seedFloor(db, id: _floorId);
      await _seedFloor(db, id: _floor2Id, name: 'Terrace');
      await _seedTable(db, id: 't1', floorId: _floorId, name: 'T1');
      await _seedTable(db, id: 't2', floorId: _floorId, name: 'T2');
      await _seedTable(db, id: 't3', floorId: _floor2Id, name: 'TR1');

      final tables = await repo.getTablesByFloor(_floorId);

      expect(tables.length, 2);
      expect(tables.map((t) => t.name), containsAll(['T1', 'T2']));

      await db.close();
    });

    test('getAllTables returns all non-deleted tables for tenant', () async {
      final db = await _openDb();
      final repo = TableRepositoryImpl(db);

      await _seedFloor(db, id: _floorId);
      await _seedFloor(db, id: _floor2Id, name: 'Bar');
      await _seedTable(db, id: 't1', floorId: _floorId);
      await _seedTable(db, id: 't2', floorId: _floor2Id, name: 'B1');

      final all = await repo.getAllTables(_tenantId);
      expect(all.length, 2);

      await db.close();
    });

    test('createTable inserts with correct defaults', () async {
      final db = await _openDb();
      final repo = TableRepositoryImpl(db);

      await _seedFloor(db);
      final table = await repo.createTable(
        tenantId: _tenantId,
        floorId: _floorId,
        name: 'T5',
        capacity: 6,
        shape: TableShape.circle,
      );

      expect(table.name, 'T5');
      expect(table.capacity, 6);
      expect(table.shape, TableShape.circle);
      expect(table.status, TableStatus.available);

      final fetched = await repo.getTablesByFloor(_floorId);
      expect(fetched.length, 1);
      expect(fetched.first.shape, TableShape.circle);

      await db.close();
    });

    test('updateTable changes specified fields', () async {
      final db = await _openDb();
      final repo = TableRepositoryImpl(db);

      await _seedFloor(db);
      await _seedTable(db, id: 't1', name: 'T1');
      await repo.updateTable(tableId: 't1', name: 'T1-Renamed', capacity: 8);

      final tables = await repo.getTablesByFloor(_floorId);
      expect(tables.first.name, 'T1-Renamed');
      expect(tables.first.capacity, 8);

      await db.close();
    });

    test('updateTable with shape = circle round-trips correctly', () async {
      final db = await _openDb();
      final repo = TableRepositoryImpl(db);

      await _seedFloor(db);
      await _seedTable(db, id: 't1');
      await repo.updateTable(tableId: 't1', shape: TableShape.circle);

      final tables = await repo.getTablesByFloor(_floorId);
      expect(tables.first.shape, TableShape.circle);

      await db.close();
    });

    test('deleteTable soft-deletes', () async {
      final db = await _openDb();
      final repo = TableRepositoryImpl(db);

      await _seedFloor(db);
      await _seedTable(db, id: 't1');
      await repo.deleteTable('t1');

      final tables = await repo.getTablesByFloor(_floorId);
      expect(tables, isEmpty);

      await db.close();
    });

    test('updateTableStatus changes status', () async {
      final db = await _openDb();
      final repo = TableRepositoryImpl(db);

      await _seedFloor(db);
      await _seedTable(db, id: 't1', status: 'available');
      await repo.updateTableStatus('t1', TableStatus.reserved);

      final tables = await repo.getTablesByFloor(_floorId);
      expect(tables.first.status, TableStatus.reserved);

      await db.close();
    });

    test('updateTablePosition updates posX and posY', () async {
      final db = await _openDb();
      final repo = TableRepositoryImpl(db);

      await _seedFloor(db);
      await _seedTable(db, id: 't1');
      await repo.updateTablePosition('t1', 250.0, 380.0);

      final tables = await repo.getTablesByFloor(_floorId);
      expect(tables.first.posX, 250.0);
      expect(tables.first.posY, 380.0);

      await db.close();
    });

    test('linkOrderToTable marks table as occupied', () async {
      final db = await _openDb();
      final repo = TableRepositoryImpl(db);

      await _seedFloor(db);
      await _seedTable(db, id: 't1');
      await repo.linkOrderToTable('t1', 'order-abc');

      final tables = await repo.getTablesByFloor(_floorId);
      expect(tables.first.status, TableStatus.occupied);
      expect(tables.first.currentOrderId, 'order-abc');

      await db.close();
    });

    test('clearTable resets status to available and removes order', () async {
      final db = await _openDb();
      final repo = TableRepositoryImpl(db);

      await _seedFloor(db);
      await _seedTable(db, id: 't1', status: 'occupied', currentOrderId: 'o1');
      await repo.clearTable('t1');

      final tables = await repo.getTablesByFloor(_floorId);
      expect(tables.first.status, TableStatus.available);
      expect(tables.first.currentOrderId, isNull);

      await db.close();
    });

    test('updateGuestCount updates the ticket guestCount', () async {
      final db = await _openDb();
      final repo = TableRepositoryImpl(db);

      await _seedFloor(db);
      await _seedTable(db, id: 't1', status: 'occupied', currentOrderId: 'o1');
      await _seedTicket(db, 'o1', tableId: 't1');

      await repo.updateGuestCount('o1', 5);

      final ticket = await (db.select(db.tickets)
            ..where((t) => t.id.equals('o1')))
          .getSingleOrNull();
      expect(ticket?.guestCount, 5);

      await db.close();
    });
  });

  // =========================================================================
  // Merge tables
  // =========================================================================

  group('mergeTables', () {
    test('moves secondary order to primary when primary is free', () async {
      final db = await _openDb();
      final repo = TableRepositoryImpl(db);

      await _seedFloor(db);
      await _seedTable(db, id: 'primary', status: 'available');
      await _seedTable(db,
          id: 'secondary',
          name: 'T2',
          status: 'occupied',
          currentOrderId: 'order-1');
      await _seedTicket(db, 'order-1', tableId: 'secondary');

      await repo.mergeTables(
          primaryTableId: 'primary', secondaryTableId: 'secondary');

      final tables = await repo.getAllTables(_tenantId);
      final primary = tables.firstWhere((t) => t.id == 'primary');
      final secondary = tables.firstWhere((t) => t.id == 'secondary');

      expect(primary.status, TableStatus.occupied);
      expect(primary.currentOrderId, 'order-1');
      expect(secondary.status, TableStatus.dirty);
      expect(secondary.currentOrderId, isNull);

      // Ticket tableId should point to primary.
      final ticket = await (db.select(db.tickets)
            ..where((t) => t.id.equals('order-1')))
          .getSingleOrNull();
      expect(ticket?.tableId, 'primary');

      await db.close();
    });

    test('clears secondary even when primary is already occupied', () async {
      final db = await _openDb();
      final repo = TableRepositoryImpl(db);

      await _seedFloor(db);
      await _seedTable(db,
          id: 'primary',
          status: 'occupied',
          currentOrderId: 'order-A');
      await _seedTable(db,
          id: 'secondary',
          name: 'T2',
          status: 'occupied',
          currentOrderId: 'order-B');
      await _seedTicket(db, 'order-A', tableId: 'primary');
      await _seedTicket(db, 'order-B', tableId: 'secondary');

      await repo.mergeTables(
          primaryTableId: 'primary', secondaryTableId: 'secondary');

      final tables = await repo.getAllTables(_tenantId);
      final secondary = tables.firstWhere((t) => t.id == 'secondary');

      expect(secondary.status, TableStatus.dirty);
      expect(secondary.currentOrderId, isNull);

      await db.close();
    });
  });

  // =========================================================================
  // Transfer order
  // =========================================================================

  group('transferOrder', () {
    test('moves order from source to destination table', () async {
      final db = await _openDb();
      final repo = TableRepositoryImpl(db);

      await _seedFloor(db);
      await _seedTable(db,
          id: 'src',
          status: 'occupied',
          currentOrderId: 'order-X');
      await _seedTable(db, id: 'dst', name: 'T2', status: 'available');
      await _seedTicket(db, 'order-X', tableId: 'src');

      await repo.transferOrder(fromTableId: 'src', toTableId: 'dst');

      final tables = await repo.getAllTables(_tenantId);
      final src = tables.firstWhere((t) => t.id == 'src');
      final dst = tables.firstWhere((t) => t.id == 'dst');

      expect(src.status, TableStatus.dirty);
      expect(src.currentOrderId, isNull);
      expect(dst.status, TableStatus.occupied);
      expect(dst.currentOrderId, 'order-X');

      final ticket = await (db.select(db.tickets)
            ..where((t) => t.id.equals('order-X')))
          .getSingleOrNull();
      expect(ticket?.tableId, 'dst');

      await db.close();
    });

    test('does nothing when source table has no order', () async {
      final db = await _openDb();
      final repo = TableRepositoryImpl(db);

      await _seedFloor(db);
      await _seedTable(db, id: 'src', status: 'available');
      await _seedTable(db, id: 'dst', name: 'T2', status: 'available');

      // Should not throw.
      await expectLater(
        repo.transferOrder(fromTableId: 'src', toTableId: 'dst'),
        completes,
      );

      final tables = await repo.getAllTables(_tenantId);
      final dst = tables.firstWhere((t) => t.id == 'dst');
      expect(dst.currentOrderId, isNull);

      await db.close();
    });
  });

  // =========================================================================
  // State flags (orthogonal to TableStatus) — S3.2
  // =========================================================================

  group('TableFlag codec', () {
    test('decode empty / null returns empty set', () {
      expect(decodeTableFlags(null), isEmpty);
      expect(decodeTableFlags(''), isEmpty);
    });

    test('round-trip preserves flag set', () {
      const flags = {TableFlag.billRequested, TableFlag.vip};
      final encoded = encodeTableFlags(flags);
      expect(decodeTableFlags(encoded), flags);
    });

    test('encoding is deterministic (enum declaration order)', () {
      // Independent of insertion order the CSV must be stable so
      // sync payloads diff cleanly.
      final a = encodeTableFlags({TableFlag.vip, TableFlag.billRequested});
      final b = encodeTableFlags({TableFlag.billRequested, TableFlag.vip});
      expect(a, b);
      // billRequested declares before vip → it comes first in the CSV.
      expect(a.indexOf('billRequested'), lessThan(a.indexOf('vip')));
    });

    test('decode silently drops unknown tokens', () {
      final flags = decodeTableFlags('billRequested,ghostFlag,vip');
      expect(flags, {TableFlag.billRequested, TableFlag.vip});
    });
  });

  group('setTableFlag', () {
    test('adds a flag without touching TableStatus', () async {
      final db = await _openDb();
      final repo = TableRepositoryImpl(db);

      await _seedFloor(db);
      await _seedTable(db, id: 't1', status: 'occupied');

      await repo.setTableFlag(
        tableId: 't1',
        flag: TableFlag.billRequested,
        enabled: true,
      );

      final tables = await repo.getAllTables(_tenantId);
      final t1 = tables.firstWhere((t) => t.id == 't1');
      expect(t1.status, TableStatus.occupied);
      expect(t1.flags, {TableFlag.billRequested});
      expect(t1.hasFlag(TableFlag.billRequested), true);

      await db.close();
    });

    test('stacks multiple flags simultaneously', () async {
      final db = await _openDb();
      final repo = TableRepositoryImpl(db);

      await _seedFloor(db);
      await _seedTable(db, id: 't1', status: 'occupied');

      await repo.setTableFlag(
        tableId: 't1',
        flag: TableFlag.billRequested,
        enabled: true,
      );
      await repo.setTableFlag(
        tableId: 't1',
        flag: TableFlag.vip,
        enabled: true,
      );

      final tables = await repo.getAllTables(_tenantId);
      final t1 = tables.firstWhere((t) => t.id == 't1');
      // SambaPOS parity: Occupied + BillRequested + VIP coexist.
      expect(t1.status, TableStatus.occupied);
      expect(t1.flags, {TableFlag.billRequested, TableFlag.vip});

      await db.close();
    });

    test('removes a flag without clearing the others', () async {
      final db = await _openDb();
      final repo = TableRepositoryImpl(db);

      await _seedFloor(db);
      await _seedTable(db, id: 't1', status: 'occupied');
      await repo.setTableFlags(
        tableId: 't1',
        flags: {TableFlag.billRequested, TableFlag.vip},
      );

      await repo.setTableFlag(
        tableId: 't1',
        flag: TableFlag.billRequested,
        enabled: false,
      );

      final tables = await repo.getAllTables(_tenantId);
      final t1 = tables.firstWhere((t) => t.id == 't1');
      expect(t1.flags, {TableFlag.vip});

      await db.close();
    });

    test('setting an already-present flag is idempotent', () async {
      final db = await _openDb();
      final repo = TableRepositoryImpl(db);

      await _seedFloor(db);
      await _seedTable(db, id: 't1');
      await repo.setTableFlag(
        tableId: 't1',
        flag: TableFlag.vip,
        enabled: true,
      );
      // Call twice — must still be a single flag.
      await repo.setTableFlag(
        tableId: 't1',
        flag: TableFlag.vip,
        enabled: true,
      );

      final tables = await repo.getAllTables(_tenantId);
      expect(tables.first.flags, {TableFlag.vip});

      await db.close();
    });
  });

  group('clearTable + clearTableFlags', () {
    test('clearTable resets status AND drops every flag', () async {
      final db = await _openDb();
      final repo = TableRepositoryImpl(db);

      await _seedFloor(db);
      await _seedTable(db, id: 't1', status: 'occupied');
      await repo.setTableFlags(
        tableId: 't1',
        flags: {TableFlag.billRequested, TableFlag.vip},
      );

      await repo.clearTable('t1');

      final tables = await repo.getAllTables(_tenantId);
      final t1 = tables.firstWhere((t) => t.id == 't1');
      expect(t1.status, TableStatus.available);
      expect(t1.flags, isEmpty);

      await db.close();
    });

    test('clearTableFlags preserves status', () async {
      final db = await _openDb();
      final repo = TableRepositoryImpl(db);

      await _seedFloor(db);
      await _seedTable(db, id: 't1', status: 'occupied');
      await repo.setTableFlags(
        tableId: 't1',
        flags: {TableFlag.billRequested},
      );

      await repo.clearTableFlags('t1');

      final tables = await repo.getAllTables(_tenantId);
      final t1 = tables.firstWhere((t) => t.id == 't1');
      // Status untouched — the guests are still there, just the
      // bill-requested signal has been acknowledged.
      expect(t1.status, TableStatus.occupied);
      expect(t1.flags, isEmpty);

      await db.close();
    });
  });
}
