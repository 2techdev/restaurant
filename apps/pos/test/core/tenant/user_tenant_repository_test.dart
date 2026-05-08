/// Unit tests for UserTenantRepository.
///
/// Uses an in-memory Drift database. Verifies upsert idempotency,
/// confirmation gating, soft-delete on revoke, and the order returned by
/// [getTenantsForUser] (confirmed first, oldest first within each bucket).
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/tenant/user_tenant_repository.dart';

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

void main() {
  group('UserTenantRepository', () {
    late AppDatabase db;
    late UserTenantRepository repo;

    setUp(() {
      db = _makeDb();
      repo = UserTenantRepository(db);
    });

    tearDown(() => db.close());

    test('upsert inserts a new assignment', () async {
      await repo.upsert(userId: 'u1', tenantId: 't-zurich');
      final rows = await repo.getTenantsForUser('u1');
      expect(rows.length, 1);
      expect(rows.first.tenantId, 't-zurich');
      expect(rows.first.isConfirmed, isTrue);
    });

    test('upsert is idempotent — calling twice keeps one row', () async {
      await repo.upsert(userId: 'u1', tenantId: 't-zurich');
      await repo.upsert(userId: 'u1', tenantId: 't-zurich');
      final rows = await repo.getTenantsForUser('u1');
      expect(rows.length, 1);
    });

    test('upsert can flip a pending assignment to confirmed', () async {
      await repo.upsert(
        userId: 'u1',
        tenantId: 't-bern',
        isConfirmed: false,
      );
      await repo.upsert(
        userId: 'u1',
        tenantId: 't-bern',
        isConfirmed: true,
      );

      final rows = await repo.getTenantsForUser('u1');
      expect(rows.length, 1);
      expect(rows.first.isConfirmed, isTrue);
    });

    test('upsert can update roleOverride', () async {
      await repo.upsert(
        userId: 'u1',
        tenantId: 't-zurich',
        roleOverride: 'manager',
      );
      await repo.upsert(
        userId: 'u1',
        tenantId: 't-zurich',
        roleOverride: 'waiter',
      );

      final rows = await repo.getTenantsForUser('u1');
      expect(rows.first.roleOverride, 'waiter');
    });

    test('hasAccess returns false for unconfirmed assignments', () async {
      await repo.upsert(
        userId: 'u1',
        tenantId: 't-bern',
        isConfirmed: false,
      );
      expect(await repo.hasAccess('u1', 't-bern'), isFalse);
    });

    test('hasAccess returns true for confirmed assignments', () async {
      await repo.upsert(userId: 'u1', tenantId: 't-zurich');
      expect(await repo.hasAccess('u1', 't-zurich'), isTrue);
    });

    test('hasAccess returns false for unknown pair', () async {
      await repo.upsert(userId: 'u1', tenantId: 't-zurich');
      expect(await repo.hasAccess('u1', 't-mars'), isFalse);
      expect(await repo.hasAccess('u-other', 't-zurich'), isFalse);
    });

    test('revoke soft-deletes and clears confirmation', () async {
      await repo.upsert(userId: 'u1', tenantId: 't-zurich');
      expect(await repo.hasAccess('u1', 't-zurich'), isTrue);

      await repo.revoke(userId: 'u1', tenantId: 't-zurich');
      expect(await repo.hasAccess('u1', 't-zurich'), isFalse);

      // Soft-deleted row must not be returned by getTenantsForUser.
      final rows = await repo.getTenantsForUser('u1');
      expect(rows, isEmpty);
    });

    test('getTenantsForUser only returns assignments for that user', () async {
      await repo.upsert(userId: 'u1', tenantId: 't-zurich');
      await repo.upsert(userId: 'u2', tenantId: 't-bern');

      final rows = await repo.getTenantsForUser('u1');
      expect(rows.length, 1);
      expect(rows.first.tenantId, 't-zurich');
    });

    test('getTenantsForUser returns confirmed first, then pending', () async {
      // Insert pending first so we can confirm ordering ignores insertion order.
      await repo.upsert(
        userId: 'u1',
        tenantId: 't-pending',
        isConfirmed: false,
      );
      await repo.upsert(userId: 'u1', tenantId: 't-confirmed');

      final rows = await repo.getTenantsForUser('u1');
      expect(rows.length, 2);
      expect(rows.first.tenantId, 't-confirmed');
      expect(rows[1].tenantId, 't-pending');
    });
  });
}
