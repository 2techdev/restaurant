/// Unit tests for [AuditService].
///
/// Uses an in-memory Drift database so no file I/O is required.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/services/audit_service.dart';
import 'package:gastrocore_pos/features/audit_log/domain/entities/audit_action.dart';

AppDatabase _makeDb() => AppDatabase.createInMemory();

AuditService _makeService(AppDatabase db) => AuditService(
      db: db,
      tenantId: 'tenant-1',
      deviceId: 'dev-001',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuditService — setUser / clearUser', () {
    test('setUser stores context used by subsequent log calls', () async {
      final db = _makeDb();
      final svc = _makeService(db);
      svc.setUser(userId: 'u1', userName: 'Alice');

      await svc.log(
        action: AuditAction.orderCreated,
        entityType: 'ticket',
        entityId: 'tkt-1',
      );

      final entries = await db.auditLogDao.getEntries(tenantId: 'tenant-1');
      expect(entries, hasLength(1));
      expect(entries.first.userId, 'u1');
      expect(entries.first.userName, 'Alice');

      await db.close();
    });

    test('clearUser means empty userId/userName in subsequent logs', () async {
      final db = _makeDb();
      final svc = _makeService(db);
      svc.setUser(userId: 'u2', userName: 'Bob');
      svc.clearUser();

      await svc.log(
        action: AuditAction.userLoggedOut,
        entityType: 'user',
        entityId: 'u2',
      );

      final entries = await db.auditLogDao.getEntries(tenantId: 'tenant-1');
      expect(entries.first.userId, '');
      expect(entries.first.userName, '');

      await db.close();
    });

    test('log override userId/userName takes precedence over session', () async {
      final db = _makeDb();
      final svc = _makeService(db);
      svc.setUser(userId: 'u1', userName: 'Alice');

      await svc.log(
        action: AuditAction.managerOverride,
        entityType: 'override',
        entityId: 'mgr-1',
        userId: 'mgr-99',
        userName: 'Manager',
      );

      final entries = await db.auditLogDao.getEntries(tenantId: 'tenant-1');
      expect(entries.first.userId, 'mgr-99');
      expect(entries.first.userName, 'Manager');

      await db.close();
    });
  });

  group('AuditService — log content', () {
    test('stores all fields correctly', () async {
      final db = _makeDb();
      final svc = _makeService(db);
      svc.setUser(userId: 'u1', userName: 'Alice');

      await svc.log(
        action: AuditAction.discountApplied,
        entityType: 'ticket',
        entityId: 'tkt-42',
        oldValueJson: '{"discount":0}',
        newValueJson: '{"discount":500}',
        reason: 'Manager approval',
        ipAddress: '192.168.1.10',
      );

      final entry = (await db.auditLogDao.getEntries(tenantId: 'tenant-1')).first;
      expect(entry.action, AuditAction.discountApplied);
      expect(entry.entityType, 'ticket');
      expect(entry.entityId, 'tkt-42');
      expect(entry.oldValueJson, '{"discount":0}');
      expect(entry.newValueJson, '{"discount":500}');
      expect(entry.reason, 'Manager approval');
      expect(entry.ipAddress, '192.168.1.10');
      expect(entry.deviceId, 'dev-001');
      expect(entry.tenantId, 'tenant-1');

      await db.close();
    });

    test('never throws when DB write fails (silent swallow)', () async {
      final db = _makeDb();
      final svc = _makeService(db);
      await db.close(); // close DB to cause insert to fail

      // Must not throw.
      await expectLater(
        svc.log(
          action: AuditAction.orderCreated,
          entityType: 'ticket',
          entityId: 'tkt-99',
        ),
        completes,
      );
    });
  });

  group('AuditService — convenience shortcuts', () {
    late AppDatabase db;
    late AuditService svc;

    setUp(() {
      db = _makeDb();
      svc = _makeService(db);
      svc.setUser(userId: 'u1', userName: 'Alice');
    });

    tearDown(() => db.close());

    Future<AuditAction> firstAction() async {
      final entries = await db.auditLogDao.getEntries(tenantId: 'tenant-1');
      return entries.first.action;
    }

    test('logOrderCreated', () async {
      await svc.logOrderCreated('tkt-1');
      expect(await firstAction(), AuditAction.orderCreated);
    });

    test('logOrderCancelled', () async {
      await svc.logOrderCancelled('tkt-2', reason: 'test');
      expect(await firstAction(), AuditAction.orderCancelled);
    });

    test('logOrderVoided', () async {
      await svc.logOrderVoided('tkt-3');
      expect(await firstAction(), AuditAction.orderVoided);
    });

    test('logPaymentReceived', () async {
      await svc.logPaymentReceived('pay-1');
      expect(await firstAction(), AuditAction.paymentReceived);
    });

    test('logPaymentRefunded', () async {
      await svc.logPaymentRefunded('pay-2');
      expect(await firstAction(), AuditAction.paymentRefunded);
    });

    test('logDiscountApplied', () async {
      await svc.logDiscountApplied('tkt-4');
      expect(await firstAction(), AuditAction.discountApplied);
    });

    test('logShiftOpened', () async {
      await svc.logShiftOpened('shift-1');
      expect(await firstAction(), AuditAction.shiftOpened);
    });

    test('logShiftClosed', () async {
      await svc.logShiftClosed('shift-1');
      expect(await firstAction(), AuditAction.shiftClosed);
    });

    test('logUserLoggedIn uses provided userId/userName', () async {
      await svc.logUserLoggedIn('u99', 'Charlie');
      final entry = (await db.auditLogDao.getEntries(tenantId: 'tenant-1')).first;
      expect(entry.userId, 'u99');
      expect(entry.userName, 'Charlie');
      expect(entry.action, AuditAction.userLoggedIn);
    });

    test('logCashDrawerOpened', () async {
      await svc.logCashDrawerOpened('shift-2');
      expect(await firstAction(), AuditAction.cashDrawerOpened);
    });
  });

  group('AuditLogDao — filters', () {
    late AppDatabase db;
    late AuditService svc;

    setUp(() {
      db = _makeDb();
      svc = _makeService(db);
      svc.setUser(userId: 'u1', userName: 'Alice');
    });

    tearDown(() => db.close());

    test('filter by action', () async {
      await svc.logOrderCreated('tkt-1');
      await svc.logOrderCancelled('tkt-2');
      await svc.logShiftOpened('shift-1');

      final orders = await db.auditLogDao.getEntries(
        tenantId: 'tenant-1',
        action: AuditAction.orderCreated,
      );
      expect(orders, hasLength(1));
      expect(orders.first.action, AuditAction.orderCreated);
    });

    test('filter by userId', () async {
      svc.setUser(userId: 'u1', userName: 'Alice');
      await svc.logOrderCreated('tkt-1');
      svc.setUser(userId: 'u2', userName: 'Bob');
      await svc.logOrderCreated('tkt-2');

      final aliceEntries = await db.auditLogDao.getEntries(
        tenantId: 'tenant-1',
        userId: 'u1',
      );
      expect(aliceEntries, hasLength(1));
      expect(aliceEntries.first.userId, 'u1');
    });

    test('date range filter excludes outside entries', () async {
      await svc.logOrderCreated('tkt-old');

      final future = DateTime.now().add(const Duration(days: 2));
      final entries = await db.auditLogDao.getEntries(
        tenantId: 'tenant-1',
        from: future,
      );
      expect(entries, isEmpty);
    });
  });
}
