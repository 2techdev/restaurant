/// Tests for schema v7 migration additions.
///
/// Verifies that the three new tables introduced in v7
/// (fiscal_signatures, lan_sync_peers, manager_pins) are present and
/// fully functional, and that the performance indexes added in the same
/// migration can be queried without errors.
///
/// Uses an in-memory Drift database so these tests are fast and
/// self-contained. The in-memory path exercises [MigrationStrategy.onCreate]
/// which calls [m.createAll()], covering the same table DDL that the
/// [MigrationStrategy.onUpgrade] `from < 7` block applies to existing users.
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

/// Seed the minimum required tenant row so FK-dependent inserts succeed.
const _tenantId = 'tenant-v7-test';

Future<void> _seedTenant(AppDatabase db) async {
  final now = DateTime.now().toUtc();
  await db.into(db.tenants).insert(
        TenantsCompanion.insert(
          id: _tenantId,
          name: 'V7 Migration Test Restaurant',
          createdAt: now,
          updatedAt: now,
        ),
      );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  group('schema version', () {
    test('schemaVersion is at least 7', () {
      final db = _makeDb();
      expect(db.schemaVersion, greaterThanOrEqualTo(7));
      db.close();
    });
  });

  // -------------------------------------------------------------------------
  group('fiscal_signatures table', () {
    late AppDatabase db;

    setUp(() async {
      db = _makeDb();
      await _seedTenant(db);
    });
    tearDown(() => db.close());

    test('starts empty', () async {
      final rows = await db.select(db.fiscalSignatures).get();
      expect(rows, isEmpty);
    });

    test('insert and retrieve a fiscal signature row', () async {
      final now = DateTime.now().toUtc();
      await db.into(db.fiscalSignatures).insert(
            FiscalSignaturesCompanion.insert(
              id: 'fs-001',
              tenantId: _tenantId,
              receiptId: 'rcpt-001',
              tseSerialNumber: 'TSE-SN-12345678',
              transactionNumber: 42,
              signatureAlgorithm: 'ecdsa-plain-SHA384',
              signatureValue: 'base64sigvalue==',
              processType: 'Kassenbeleg-V1',
              processData: 'Vorgangstyp^Brutto^...',
              tseTimestamp: now,
              createdAt: now,
            ),
          );

      final rows = await db.select(db.fiscalSignatures).get();
      expect(rows.length, 1);

      final row = rows.first;
      expect(row.id, 'fs-001');
      expect(row.tseSerialNumber, 'TSE-SN-12345678');
      expect(row.transactionNumber, 42);
      expect(row.signatureAlgorithm, 'ecdsa-plain-SHA384');
      expect(row.processType, 'Kassenbeleg-V1');
    });

    test('filter by receipt_id', () async {
      final now = DateTime.now().toUtc();

      Future<void> insertSig(String id, String receiptId, int txNum) =>
          db.into(db.fiscalSignatures).insert(
                FiscalSignaturesCompanion.insert(
                  id: id,
                  tenantId: _tenantId,
                  receiptId: receiptId,
                  tseSerialNumber: 'TSE-SN',
                  transactionNumber: txNum,
                  signatureAlgorithm: 'ecdsa-plain-SHA384',
                  signatureValue: 'sig',
                  processType: 'Kassenbeleg-V1',
                  processData: 'data',
                  tseTimestamp: now,
                  createdAt: now,
                ),
              );

      await insertSig('fs-1', 'rcpt-A', 1);
      await insertSig('fs-2', 'rcpt-B', 2);
      await insertSig('fs-3', 'rcpt-A', 3);

      final forA = await (db.select(db.fiscalSignatures)
            ..where((t) => t.receiptId.equals('rcpt-A')))
          .get();
      expect(forA.length, 2);
    });

    test('delete removes only targeted row', () async {
      final now = DateTime.now().toUtc();
      await db.into(db.fiscalSignatures).insert(
            FiscalSignaturesCompanion.insert(
              id: 'fs-del',
              tenantId: _tenantId,
              receiptId: 'rcpt-del',
              tseSerialNumber: 'TSE',
              transactionNumber: 99,
              signatureAlgorithm: 'ecdsa-plain-SHA384',
              signatureValue: 'sig',
              processType: 'Kassenbeleg-V1',
              processData: 'data',
              tseTimestamp: now,
              createdAt: now,
            ),
          );

      await (db.delete(db.fiscalSignatures)
            ..where((t) => t.id.equals('fs-del')))
          .go();

      final rows = await db.select(db.fiscalSignatures).get();
      expect(rows, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  group('lan_sync_peers table', () {
    late AppDatabase db;

    setUp(() async {
      db = _makeDb();
      await _seedTenant(db);
    });
    tearDown(() => db.close());

    test('starts empty', () async {
      final rows = await db.select(db.lanSyncPeers).get();
      expect(rows, isEmpty);
    });

    test('insert and retrieve a peer row', () async {
      final now = DateTime.now().toUtc();
      await db.into(db.lanSyncPeers).insert(
            LanSyncPeersCompanion.insert(
              deviceId: 'device-pos-02',
              tenantId: _tenantId,
              deviceName: 'POS-Kasse-2',
              ipAddress: '192.168.1.102',
              createdAt: now,
              updatedAt: now,
            ),
          );

      final rows = await db.select(db.lanSyncPeers).get();
      expect(rows.length, 1);

      final row = rows.first;
      expect(row.deviceId, 'device-pos-02');
      expect(row.deviceName, 'POS-Kasse-2');
      expect(row.ipAddress, '192.168.1.102');
      expect(row.port, 7070); // default
      expect(row.isReachable, isFalse); // default
    });

    test('composite PK (device_id, tenant_id) prevents duplicate inserts',
        () async {
      final now = DateTime.now().toUtc();
      final companion = LanSyncPeersCompanion.insert(
        deviceId: 'device-dup',
        tenantId: _tenantId,
        deviceName: 'POS-1',
        ipAddress: '10.0.0.1',
        createdAt: now,
        updatedAt: now,
      );

      await db.into(db.lanSyncPeers).insert(companion);
      // Second insert should throw a unique-constraint violation.
      expect(
        () => db.into(db.lanSyncPeers).insert(companion),
        throwsA(anything),
      );
    });

    test('filter reachable peers', () async {
      final now = DateTime.now().toUtc();

      Future<void> insertPeer(
          String deviceId, String ip, bool reachable) async {
        await db.into(db.lanSyncPeers).insert(
              LanSyncPeersCompanion.insert(
                deviceId: deviceId,
                tenantId: _tenantId,
                deviceName: 'Device-$deviceId',
                ipAddress: ip,
                isReachable: Value(reachable),
                createdAt: now,
                updatedAt: now,
              ),
            );
      }

      await insertPeer('d1', '10.0.0.1', true);
      await insertPeer('d2', '10.0.0.2', false);
      await insertPeer('d3', '10.0.0.3', true);

      final reachable = await (db.select(db.lanSyncPeers)
            ..where((t) => t.isReachable.equals(true)))
          .get();
      expect(reachable.length, 2);
    });

    test('update ip_address on re-discovery', () async {
      final now = DateTime.now().toUtc();
      await db.into(db.lanSyncPeers).insert(
            LanSyncPeersCompanion.insert(
              deviceId: 'device-upd',
              tenantId: _tenantId,
              deviceName: 'POS-3',
              ipAddress: '192.168.1.10',
              createdAt: now,
              updatedAt: now,
            ),
          );

      await (db.update(db.lanSyncPeers)
            ..where((t) => t.deviceId.equals('device-upd')))
          .write(LanSyncPeersCompanion(
            ipAddress: const Value('192.168.1.99'),
            isReachable: const Value(true),
            updatedAt: Value(DateTime.now().toUtc()),
          ));

      final row = await (db.select(db.lanSyncPeers)
            ..where((t) => t.deviceId.equals('device-upd')))
          .getSingle();
      expect(row.ipAddress, '192.168.1.99');
      expect(row.isReachable, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  group('manager_pins table', () {
    late AppDatabase db;

    setUp(() async {
      db = _makeDb();
      await _seedTenant(db);
    });
    tearDown(() => db.close());

    test('starts empty', () async {
      final rows = await db.select(db.managerPins).get();
      expect(rows, isEmpty);
    });

    test('insert and retrieve a manager PIN event', () async {
      final now = DateTime.now().toUtc();
      await db.into(db.managerPins).insert(
            ManagerPinsCompanion.insert(
              id: 'mp-001',
              tenantId: _tenantId,
              managerId: 'user-manager-01',
              managerName: 'Klaus Wagner',
              action: 'void_ticket',
              entityType: const Value('ticket'),
              entityId: const Value('tkt-555'),
              reason: const Value('Customer complaint'),
              deviceId: 'device-pos-01',
              authorisedAt: now,
            ),
          );

      final rows = await db.select(db.managerPins).get();
      expect(rows.length, 1);

      final row = rows.first;
      expect(row.id, 'mp-001');
      expect(row.managerId, 'user-manager-01');
      expect(row.managerName, 'Klaus Wagner');
      expect(row.action, 'void_ticket');
      expect(row.entityType, 'ticket');
      expect(row.entityId, 'tkt-555');
      expect(row.reason, 'Customer complaint');
    });

    test('insert without optional fields succeeds', () async {
      final now = DateTime.now().toUtc();
      await db.into(db.managerPins).insert(
            ManagerPinsCompanion.insert(
              id: 'mp-002',
              tenantId: _tenantId,
              managerId: 'user-mgr-02',
              managerName: 'Anna Fischer',
              action: 'apply_discount',
              deviceId: 'device-kiosk-01',
              authorisedAt: now,
            ),
          );

      final row = await (db.select(db.managerPins)
            ..where((t) => t.id.equals('mp-002')))
          .getSingle();
      expect(row.reason, isNull);
      expect(row.entityType, isNull);
      expect(row.entityId, isNull);
    });

    test('filter by manager_id', () async {
      final now = DateTime.now().toUtc();

      Future<void> insertPin(String id, String managerId) =>
          db.into(db.managerPins).insert(
                ManagerPinsCompanion.insert(
                  id: id,
                  tenantId: _tenantId,
                  managerId: managerId,
                  managerName: 'Manager $managerId',
                  action: 'void_ticket',
                  deviceId: 'dev-01',
                  authorisedAt: now,
                ),
              );

      await insertPin('pin-1', 'mgr-A');
      await insertPin('pin-2', 'mgr-B');
      await insertPin('pin-3', 'mgr-A');

      final forMgrA = await (db.select(db.managerPins)
            ..where((t) => t.managerId.equals('mgr-A')))
          .get();
      expect(forMgrA.length, 2);
    });

    test('multiple actions by same manager are all recorded', () async {
      final now = DateTime.now().toUtc();
      for (var i = 0; i < 3; i++) {
        await db.into(db.managerPins).insert(
              ManagerPinsCompanion.insert(
                id: 'mp-multi-$i',
                tenantId: _tenantId,
                managerId: 'mgr-multi',
                managerName: 'Multi Manager',
                action: 'apply_discount',
                deviceId: 'dev-01',
                authorisedAt: now.add(Duration(seconds: i)),
              ),
            );
      }

      final rows = await (db.select(db.managerPins)
            ..where((t) => t.managerId.equals('mgr-multi')))
          .get();
      expect(rows.length, 3);
    });
  });

  // -------------------------------------------------------------------------
  group('v7 tables coexist with earlier tables', () {
    late AppDatabase db;

    setUp(() async {
      db = _makeDb();
      await _seedTenant(db);
    });
    tearDown(() => db.close());

    test('tickets table remains accessible', () async {
      final tickets = await db.select(db.tickets).get();
      expect(tickets, isEmpty);
    });

    test('license_tokens table (v5) remains accessible', () async {
      final tokens = await db.select(db.licenseTokens).get();
      expect(tokens, isEmpty);
    });

    test('day_close_summaries table (v6) remains accessible', () async {
      final summaries = await db.select(db.dayCloseSummaries).get();
      expect(summaries, isEmpty);
    });

    test('all three v7 tables are empty on fresh DB', () async {
      expect(await db.select(db.fiscalSignatures).get(), isEmpty);
      expect(await db.select(db.lanSyncPeers).get(), isEmpty);
      expect(await db.select(db.managerPins).get(), isEmpty);
    });
  });
}
