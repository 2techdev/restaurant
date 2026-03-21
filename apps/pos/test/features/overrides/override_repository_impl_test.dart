/// Unit tests for OverrideRepositoryImpl.
///
/// Uses an in-memory Drift database. Covers:
///  - verifyManagerPin: correct PIN + manager role → returns user
///  - verifyManagerPin: correct PIN + cashier role → returns null
///  - verifyManagerPin: wrong PIN → returns null
///  - logOverride: writes an AuditLog row with the correct action key
///  - getOverrideLogs: returns all override entries for the tenant
///  - getOverrideLogs with entityId filter: returns only matching entries
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/overrides/data/repositories/override_repository_impl.dart';
import 'package:gastrocore_pos/features/overrides/domain/entities/override_action.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const _tenantId = 'tenant-1';
const _deviceId = 'DEV-TEST-01';

// Pre-hashed PINs (sha256 of '1234' and '5678').
// In production the UI hashes with crypto package; here we use literal hashes.
const _pin1234Hash =
    '03ac674216f3e15c761ee1a5e255f067953623c8b388b4459e13f978d7c846f4';
const _pin5678Hash =
    '1a32d8f49b2fe8bf7d8fb23a22db2e30f94ec9b1e756ed6fb76f8bdfd8f78c2b';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Future<void> _seedUser(
  AppDatabase db, {
  required String id,
  required String pinHash,
  required String role,
  bool isActive = true,
}) async {
  final now = DateTime.now();
  await db.into(db.users).insert(UsersCompanion(
        id: Value(id),
        tenantId: const Value(_tenantId),
        name: Value('User $id'),
        pinHash: Value(pinHash),
        role: Value(role),
        isActive: Value(isActive),
        createdAt: Value(now),
        updatedAt: Value(now),
        isDeleted: const Value(false),
        syncStatus: const Value(0),
      ));
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late AppDatabase db;
  late OverrideRepositoryImpl repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = OverrideRepositoryImpl(db);
  });

  tearDown(() async => db.close());

  // -------------------------------------------------------------------------
  // verifyManagerPin
  // -------------------------------------------------------------------------

  group('verifyManagerPin', () {
    test('returns manager user when PIN and role are correct', () async {
      await _seedUser(db, id: 'mgr-1', pinHash: _pin1234Hash, role: 'manager');

      final user = await repo.verifyManagerPin(_tenantId, _pin1234Hash);

      expect(user, isNotNull);
      expect(user!.id, equals('mgr-1'));
      expect(user.role.name, equals('manager'));
    });

    test('returns admin user when PIN and role are correct', () async {
      await _seedUser(db, id: 'adm-1', pinHash: _pin1234Hash, role: 'admin');

      final user = await repo.verifyManagerPin(_tenantId, _pin1234Hash);

      expect(user, isNotNull);
      expect(user!.role.name, equals('admin'));
    });

    test('returns null when user has cashier role (insufficient privilege)',
        () async {
      await _seedUser(db,
          id: 'cas-1', pinHash: _pin1234Hash, role: 'cashier');

      final user = await repo.verifyManagerPin(_tenantId, _pin1234Hash);

      expect(user, isNull);
    });

    test('returns null when user has waiter role', () async {
      await _seedUser(db,
          id: 'wait-1', pinHash: _pin1234Hash, role: 'waiter');

      final user = await repo.verifyManagerPin(_tenantId, _pin1234Hash);

      expect(user, isNull);
    });

    test('returns null for wrong PIN', () async {
      await _seedUser(db, id: 'mgr-2', pinHash: _pin1234Hash, role: 'manager');

      final user = await repo.verifyManagerPin(_tenantId, _pin5678Hash);

      expect(user, isNull);
    });

    test('returns null when user is inactive', () async {
      await _seedUser(db,
          id: 'mgr-3',
          pinHash: _pin1234Hash,
          role: 'manager',
          isActive: false);

      final user = await repo.verifyManagerPin(_tenantId, _pin1234Hash);

      expect(user, isNull);
    });

    test('does not return user from a different tenant', () async {
      // Insert manager in tenant-other.
      final now = DateTime.now();
      await db.into(db.users).insert(UsersCompanion(
            id: const Value('mgr-other'),
            tenantId: const Value('tenant-other'),
            name: const Value('Other Manager'),
            pinHash: Value(_pin1234Hash),
            role: const Value('manager'),
            isActive: const Value(true),
            createdAt: Value(now),
            updatedAt: Value(now),
            isDeleted: const Value(false),
            syncStatus: const Value(0),
          ));

      final user = await repo.verifyManagerPin(_tenantId, _pin1234Hash);

      expect(user, isNull);
    });
  });

  // -------------------------------------------------------------------------
  // logOverride + getOverrideLogs
  // -------------------------------------------------------------------------

  group('logOverride', () {
    test('writes an AuditLog row with the correct action key', () async {
      final log = OverrideLogEntity(
        id: IdGenerator.generateId(),
        tenantId: _tenantId,
        deviceId: _deviceId,
        requestedByUserId: 'cas-1',
        requestedByName: 'Cashier A',
        approvedByUserId: 'mgr-1',
        approvedByName: 'Manager B',
        action: OverrideAction.voidTicket,
        entityType: 'ticket',
        entityId: 'ticket-42',
        reason: 'Müşteri İptali',
        timestamp: DateTime.now(),
      );

      await repo.logOverride(log);

      final rows = await db.select(db.auditLog).get();
      expect(rows, hasLength(1));
      expect(rows.first.action, equals('override:void_ticket'));
      expect(rows.first.entityId, equals('ticket-42'));
    });
  });

  group('getOverrideLogs', () {
    test('returns all override entries for the tenant', () async {
      final now = DateTime.now();
      for (final action in [
        OverrideAction.voidItem,
        OverrideAction.refundTicket,
        OverrideAction.discountPercent,
      ]) {
        final log = OverrideLogEntity(
          id: IdGenerator.generateId(),
          tenantId: _tenantId,
          deviceId: _deviceId,
          requestedByUserId: 'cas-1',
          requestedByName: 'Cashier',
          approvedByUserId: 'mgr-1',
          approvedByName: 'Manager',
          action: action,
          entityType: 'ticket',
          entityId: 'ticket-${action.name}',
          reason: 'Test',
          timestamp: now,
        );
        await repo.logOverride(log);
      }

      final logs = await repo.getOverrideLogs(_tenantId);

      expect(logs, hasLength(3));
      // Verify all are override entries.
      expect(logs.every((l) => l.action.auditKey.startsWith('override:')),
          isTrue);
    });

    test('filters by entityId when provided', () async {
      final now = DateTime.now();

      await repo.logOverride(OverrideLogEntity(
        id: IdGenerator.generateId(),
        tenantId: _tenantId,
        deviceId: _deviceId,
        requestedByUserId: 'cas-1',
        requestedByName: 'Cashier',
        approvedByUserId: 'mgr-1',
        approvedByName: 'Manager',
        action: OverrideAction.voidTicket,
        entityType: 'ticket',
        entityId: 'ticket-A',
        reason: 'Test',
        timestamp: now,
      ));

      await repo.logOverride(OverrideLogEntity(
        id: IdGenerator.generateId(),
        tenantId: _tenantId,
        deviceId: _deviceId,
        requestedByUserId: 'cas-1',
        requestedByName: 'Cashier',
        approvedByUserId: 'mgr-1',
        approvedByName: 'Manager',
        action: OverrideAction.refundItem,
        entityType: 'ticket',
        entityId: 'ticket-B',
        reason: 'Test',
        timestamp: now,
      ));

      final filteredA =
          await repo.getOverrideLogs(_tenantId, entityId: 'ticket-A');
      final filteredB =
          await repo.getOverrideLogs(_tenantId, entityId: 'ticket-B');

      expect(filteredA, hasLength(1));
      expect(filteredA.first.entityId, equals('ticket-A'));

      expect(filteredB, hasLength(1));
      expect(filteredB.first.action, equals(OverrideAction.refundItem));
    });

    test('does not return non-override AuditLog entries', () async {
      // Insert a regular audit log entry (not an override).
      await db.into(db.auditLog).insert(AuditLogCompanion(
            id: const Value('audit-1'),
            tenantId: const Value(_tenantId),
            deviceId: const Value(_deviceId),
            userId: const Value('usr-1'),
            userName: const Value('User 1'),
            entityType: const Value('ticket'),
            entityId: const Value('ticket-99'),
            action: const Value('status_change'),
            timestamp: Value(DateTime.now()),
          ));

      final logs = await repo.getOverrideLogs(_tenantId);

      expect(logs, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // createAndLogOverride
  // -------------------------------------------------------------------------

  group('createAndLogOverride', () {
    test('creates log entity and persists it', () async {
      await _seedUser(db, id: 'mgr-x', pinHash: _pin1234Hash, role: 'manager');
      final approver = (await repo.verifyManagerPin(_tenantId, _pin1234Hash))!;

      final log = await repo.createAndLogOverride(
        tenantId: _tenantId,
        deviceId: _deviceId,
        requestedByUserId: 'cas-x',
        requestedByName: 'Kasiyeri',
        approver: approver,
        action: OverrideAction.discountFixed,
        entityType: 'ticket',
        entityId: 'ticket-10',
        reason: 'Müşteri Sadakati',
      );

      expect(log.approvedByUserId, equals('mgr-x'));
      expect(log.action, equals(OverrideAction.discountFixed));

      final rows = await db.select(db.auditLog).get();
      expect(rows, hasLength(1));
      expect(rows.first.action, equals('override:discount_fixed'));
    });
  });
}
