/// Tests for the audit-log retention policy + DAO purge.
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/features/audit_log/domain/retention_policy.dart';

void main() {
  group('auditLogRetentionCutoff', () {
    test('default window is 10 calendar years', () {
      final now = DateTime(2026, 4, 22, 10, 15);
      final cutoff = auditLogRetentionCutoff(now);
      expect(cutoff.year, 2016);
      expect(cutoff.month, 4);
      expect(cutoff.day, 22);
    });

    test('honours a custom window', () {
      final now = DateTime(2026, 4, 22);
      final cutoff = auditLogRetentionCutoff(now, years: 2);
      expect(cutoff.year, 2024);
    });

    test('uses calendar arithmetic, not raw days', () {
      // Crossing a leap year — naive `now - 3650 days` would drift by
      // 2–3 days. Calendar arithmetic pins month and day.
      final now = DateTime(2024, 2, 29);
      final cutoff = auditLogRetentionCutoff(now, years: 4);
      expect(cutoff.year, 2020);
      expect(cutoff.month, 2);
      expect(cutoff.day, 29);
    });
  });

  group('AuditLogDao purge', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    Future<void> seedAt(
      String id,
      String tenantId,
      DateTime ts,
    ) async {
      await db.into(db.auditLog).insert(
            AuditLogCompanion(
              id: Value(id),
              tenantId: Value(tenantId),
              deviceId: const Value('DEV-1'),
              userId: const Value('U-1'),
              userName: const Value('cashier'),
              action: const Value('payment_completed'),
              entityType: const Value('payment'),
              entityId: Value('pay-$id'),
              timestamp: Value(ts),
            ),
          );
    }

    test('purgeOlderThan deletes rows strictly older than the cutoff',
        () async {
      await seedAt('a', 't1', DateTime(2015, 1, 1));
      await seedAt('b', 't1', DateTime(2016, 4, 22));
      await seedAt('c', 't1', DateTime(2026, 4, 22));
      final cutoff = DateTime(2016, 4, 22);
      final removed =
          await db.auditLogDao.purgeOlderThan(cutoff, tenantId: 't1');
      expect(removed, 1); // only 'a' predates the cutoff
      final rows =
          await db.auditLogDao.getEntries(tenantId: 't1', limit: 0);
      expect(rows.map((r) => r.id).toSet(), {'b', 'c'});
    });

    test('purge is scoped to tenantId when given', () async {
      await seedAt('a', 't1', DateTime(2010));
      await seedAt('b', 't2', DateTime(2010));
      final removed = await db.auditLogDao
          .purgeOlderThan(DateTime(2020), tenantId: 't1');
      expect(removed, 1);
      final remaining =
          await db.auditLogDao.getEntries(tenantId: 't2', limit: 0);
      expect(remaining.length, 1);
      expect(remaining.first.id, 'b');
    });

    test('purge without tenantId applies across tenants', () async {
      await seedAt('a', 't1', DateTime(2010));
      await seedAt('b', 't2', DateTime(2010));
      await seedAt('c', 't1', DateTime(2030));
      final removed =
          await db.auditLogDao.purgeOlderThan(DateTime(2020));
      expect(removed, 2);
      final t1 =
          await db.auditLogDao.getEntries(tenantId: 't1', limit: 0);
      expect(t1.length, 1);
    });

    test('countOlderThan reports eligibility without deletion', () async {
      await seedAt('a', 't1', DateTime(2014));
      await seedAt('b', 't1', DateTime(2015));
      await seedAt('c', 't1', DateTime(2025));
      final count = await db.auditLogDao
          .countOlderThan(DateTime(2020), tenantId: 't1');
      expect(count, 2);
      final rows =
          await db.auditLogDao.getEntries(tenantId: 't1', limit: 0);
      expect(rows.length, 3, reason: 'count must not delete rows');
    });
  });
}
