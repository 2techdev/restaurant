/// Extended tests for [AuditService] and [AuditLogDao].
///
/// Tests the full write → query cycle using an in-memory database.
/// Covers all convenience shortcuts, user context, and DAO filtering.
///
/// Run with:
///   flutter test test/features/audit_log/audit_service_extended_test.dart
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/services/audit_service.dart';
import 'package:gastrocore_pos/features/audit_log/domain/entities/audit_action.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _tenantId = 'tenant-audit-test';
const _deviceId = 'DEV-AUDIT-01';

AuditService _makeService(AppDatabase db, {String? userId, String? userName}) {
  final svc = AuditService(
    db: db,
    tenantId: _tenantId,
    deviceId: _deviceId,
  );
  if (userId != null && userName != null) {
    svc.setUser(userId: userId, userName: userName);
  }
  return svc;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // =========================================================================
  // AuditAction enum
  // =========================================================================

  group('AuditAction', () {
    test('fromString round-trips all known actions', () {
      for (final action in AuditAction.values) {
        expect(AuditAction.fromString(action.name), equals(action));
      }
    });

    test('fromString returns orderEdited for unknown value', () {
      expect(AuditAction.fromString('totally_unknown'), equals(AuditAction.orderEdited));
    });

    test('each action has a non-empty label', () {
      for (final action in AuditAction.values) {
        expect(action.label, isNotEmpty);
      }
    });

    test('covers 25 distinct actions', () {
      // Baseline of 21 has grown with product availability, customer/ticket
      // linking, loyalty redemption, and receipt reprint compliance.
      expect(AuditAction.values.length, equals(25));
    });
  });

  // =========================================================================
  // AuditService — log + query cycle
  // =========================================================================

  group('AuditService — log()', () {
    late AppDatabase db;
    late AuditService svc;

    setUp(() {
      db = AppDatabase.createInMemory();
      svc = _makeService(db, userId: 'user-1', userName: 'Anna');
    });

    tearDown(() async => db.close());

    test('log writes an entry to audit_log table', () async {
      await svc.log(
        action: AuditAction.orderCreated,
        entityType: 'ticket',
        entityId: 'ticket-1',
      );

      final entries = await db.auditLogDao.getEntries(tenantId: _tenantId);
      expect(entries.length, equals(1));
      expect(entries.first.action, equals(AuditAction.orderCreated));
      expect(entries.first.entityId, equals('ticket-1'));
    });

    test('log stores tenantId and deviceId', () async {
      await svc.log(
        action: AuditAction.shiftOpened,
        entityType: 'shift',
        entityId: 'shift-1',
      );

      final entries = await db.auditLogDao.getEntries(tenantId: _tenantId);
      expect(entries.first.tenantId, equals(_tenantId));
      expect(entries.first.deviceId, equals(_deviceId));
    });

    test('log stores session user when no override given', () async {
      await svc.log(
        action: AuditAction.orderEdited,
        entityType: 'ticket',
        entityId: 'ticket-2',
      );

      final entries = await db.auditLogDao.getEntries(tenantId: _tenantId);
      expect(entries.first.userId, equals('user-1'));
      expect(entries.first.userName, equals('Anna'));
    });

    test('log uses override userId/userName when provided', () async {
      await svc.log(
        action: AuditAction.managerOverride,
        entityType: 'override',
        entityId: 'ov-1',
        userId: 'manager-99',
        userName: 'Hans Manager',
      );

      final entries = await db.auditLogDao.getEntries(tenantId: _tenantId);
      expect(entries.first.userId, equals('manager-99'));
      expect(entries.first.userName, equals('Hans Manager'));
    });

    test('log stores reason, oldValueJson, newValueJson', () async {
      await svc.log(
        action: AuditAction.discountApplied,
        entityType: 'ticket',
        entityId: 'ticket-3',
        oldValueJson: '{"discount":0}',
        newValueJson: '{"discount":10}',
        reason: 'Manager approval',
      );

      final entries = await db.auditLogDao.getEntries(tenantId: _tenantId);
      expect(entries.first.reason, equals('Manager approval'));
      expect(entries.first.oldValueJson, equals('{"discount":0}'));
      expect(entries.first.newValueJson, equals('{"discount":10}'));
    });

    test('log never throws even when DB fails (swallows exceptions)', () async {
      // Close the DB to force an error on next write.
      await db.close();

      // Should not throw.
      await expectLater(
        svc.log(
          action: AuditAction.orderCreated,
          entityType: 'ticket',
          entityId: 'ticket-x',
        ),
        completes,
      );

      // Re-open for tearDown.
      db = AppDatabase.createInMemory();
    });
  });

  // =========================================================================
  // AuditService — setUser / clearUser
  // =========================================================================

  group('AuditService — user context', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.createInMemory();
    });

    tearDown(() async => db.close());

    test('clearUser sets empty strings for userId/userName', () async {
      final svc = _makeService(db, userId: 'user-2', userName: 'Bob');
      svc.clearUser();

      await svc.log(
        action: AuditAction.userLoggedOut,
        entityType: 'user',
        entityId: 'user-2',
      );

      final entries = await db.auditLogDao.getEntries(tenantId: _tenantId);
      expect(entries.first.userId, isEmpty);
      expect(entries.first.userName, isEmpty);
    });
  });

  // =========================================================================
  // AuditService — convenience shortcuts
  // =========================================================================

  group('AuditService — convenience shortcuts', () {
    late AppDatabase db;
    late AuditService svc;

    setUp(() {
      db = AppDatabase.createInMemory();
      svc = _makeService(db);
    });

    tearDown(() async => db.close());

    test('logOrderCreated records orderCreated action', () async {
      await svc.logOrderCreated('ticket-10');
      final e = (await db.auditLogDao.getEntries(tenantId: _tenantId)).first;
      expect(e.action, equals(AuditAction.orderCreated));
      expect(e.entityId, equals('ticket-10'));
    });

    test('logOrderCancelled records orderCancelled with reason', () async {
      await svc.logOrderCancelled('ticket-11', reason: 'Customer left');
      final e = (await db.auditLogDao.getEntries(tenantId: _tenantId)).first;
      expect(e.action, equals(AuditAction.orderCancelled));
      expect(e.reason, equals('Customer left'));
    });

    test('logOrderVoided records orderVoided', () async {
      await svc.logOrderVoided('ticket-12');
      final e = (await db.auditLogDao.getEntries(tenantId: _tenantId)).first;
      expect(e.action, equals(AuditAction.orderVoided));
    });

    test('logPaymentReceived records paymentReceived', () async {
      await svc.logPaymentReceived('pay-1');
      final e = (await db.auditLogDao.getEntries(tenantId: _tenantId)).first;
      expect(e.action, equals(AuditAction.paymentReceived));
      expect(e.entityType, equals('payment'));
    });

    test('logPaymentRefunded records paymentRefunded', () async {
      await svc.logPaymentRefunded('pay-2', reason: 'Customer request');
      final e = (await db.auditLogDao.getEntries(tenantId: _tenantId)).first;
      expect(e.action, equals(AuditAction.paymentRefunded));
      expect(e.reason, equals('Customer request'));
    });

    test('logDiscountApplied records discountApplied', () async {
      await svc.logDiscountApplied('ticket-13');
      final e = (await db.auditLogDao.getEntries(tenantId: _tenantId)).first;
      expect(e.action, equals(AuditAction.discountApplied));
    });

    test('logShiftOpened records shiftOpened', () async {
      await svc.logShiftOpened('shift-1');
      final e = (await db.auditLogDao.getEntries(tenantId: _tenantId)).first;
      expect(e.action, equals(AuditAction.shiftOpened));
      expect(e.entityType, equals('shift'));
    });

    test('logShiftClosed records shiftClosed', () async {
      await svc.logShiftClosed('shift-2');
      final e = (await db.auditLogDao.getEntries(tenantId: _tenantId)).first;
      expect(e.action, equals(AuditAction.shiftClosed));
    });

    test('logUserLoggedIn records userLoggedIn with user details', () async {
      await svc.logUserLoggedIn('user-99', 'Max Muster');
      final e = (await db.auditLogDao.getEntries(tenantId: _tenantId)).first;
      expect(e.action, equals(AuditAction.userLoggedIn));
      expect(e.userId, equals('user-99'));
      expect(e.userName, equals('Max Muster'));
    });

    test('logUserLoggedOut records userLoggedOut', () async {
      await svc.logUserLoggedOut('user-99', 'Max Muster');
      final e = (await db.auditLogDao.getEntries(tenantId: _tenantId)).first;
      expect(e.action, equals(AuditAction.userLoggedOut));
    });

    test('logManagerOverride records managerOverride', () async {
      await svc.logManagerOverride('override-1', reason: 'Approved');
      final e = (await db.auditLogDao.getEntries(tenantId: _tenantId)).first;
      expect(e.action, equals(AuditAction.managerOverride));
      expect(e.reason, equals('Approved'));
    });

    test('logSettingChanged records settingChanged with old/new values', () async {
      await svc.logSettingChanged(
        'tax_rate',
        oldValueJson: '8.0',
        newValueJson: '8.1',
      );
      final e = (await db.auditLogDao.getEntries(tenantId: _tenantId)).first;
      expect(e.action, equals(AuditAction.settingChanged));
      expect(e.oldValueJson, equals('8.0'));
      expect(e.newValueJson, equals('8.1'));
    });

    test('logCashDrawerOpened records cashDrawerOpened', () async {
      await svc.logCashDrawerOpened('shift-3');
      final e = (await db.auditLogDao.getEntries(tenantId: _tenantId)).first;
      expect(e.action, equals(AuditAction.cashDrawerOpened));
    });

    test('logPriceChanged records priceChanged with product entity', () async {
      await svc.logPriceChanged(
        'prod-1',
        oldValueJson: '1000',
        newValueJson: '1200',
      );
      final e = (await db.auditLogDao.getEntries(tenantId: _tenantId)).first;
      expect(e.action, equals(AuditAction.priceChanged));
      expect(e.entityType, equals('product'));
    });
  });

  // =========================================================================
  // AuditLogDao — filtering
  // =========================================================================

  group('AuditLogDao — filtering', () {
    late AppDatabase db;
    late AuditService svc;

    setUp(() async {
      db = AppDatabase.createInMemory();
      svc = _makeService(db, userId: 'user-filter', userName: 'Filter User');
    });

    tearDown(() async => db.close());

    test('getEntries returns all entries for the tenant', () async {
      for (var i = 0; i < 3; i++) {
        await svc.log(
          action: AuditAction.orderCreated,
          entityType: 'ticket',
          entityId: 'ticket-$i',
        );
      }

      final entries = await db.auditLogDao.getEntries(tenantId: _tenantId);
      expect(entries.length, equals(3));
      final ids = entries.map((e) => e.entityId).toSet();
      expect(ids, containsAll(['ticket-0', 'ticket-1', 'ticket-2']));
    });

    test('getEntries filters by action', () async {
      await svc.logOrderCreated('t-1');
      await svc.logShiftOpened('s-1');
      await svc.logOrderCreated('t-2');

      final entries = await db.auditLogDao.getEntries(
        tenantId: _tenantId,
        action: AuditAction.orderCreated,
      );
      expect(entries.length, equals(2));
      for (final e in entries) {
        expect(e.action, equals(AuditAction.orderCreated));
      }
    });

    test('getEntries filters by userId', () async {
      await svc.logOrderCreated('t-10');

      // Second audit entry with different user
      final svc2 = _makeService(db, userId: 'other-user', userName: 'Other');
      await svc2.logOrderCreated('t-11');

      final entries = await db.auditLogDao.getEntries(
        tenantId: _tenantId,
        userId: 'user-filter',
      );
      expect(entries.length, equals(1));
      expect(entries.first.entityId, equals('t-10'));
    });

    test('getEntries respects limit parameter', () async {
      for (var i = 0; i < 10; i++) {
        await svc.logOrderCreated('t-$i');
      }

      final entries = await db.auditLogDao.getEntries(
        tenantId: _tenantId,
        limit: 5,
      );
      expect(entries.length, equals(5));
    });

    test('getEntries excludes entries from other tenants', () async {
      await svc.logOrderCreated('t-mine');

      final svc2 = AuditService(
        db: db,
        tenantId: 'other-tenant',
        deviceId: _deviceId,
      );
      await svc2.logOrderCreated('t-other');

      final entries = await db.auditLogDao.getEntries(tenantId: _tenantId);
      expect(entries.length, equals(1));
      expect(entries.first.entityId, equals('t-mine'));
    });
  });
}
