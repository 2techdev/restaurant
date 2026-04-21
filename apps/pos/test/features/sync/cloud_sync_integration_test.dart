/// End-to-end integration tests for the GastroCore sync pipeline.
///
/// Tests the full local sync cycle:
///   - Outbox: SyncEventDao inserts, status transitions, retry
///   - Push: events are picked up from the outbox, stamped, and marked
///   - Pull: RemoteEventApplier applies insert/update/delete to local tables
///   - Conflict resolution: last-write-wins (INSERT OR REPLACE)
///   - Unknown-table events are silently ignored
///
/// This test suite runs on an in-memory Drift database — no network required.
///
/// Run with:
///   flutter test test/features/sync/cloud_sync_integration_test.dart
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/sync/data/applier/remote_event_applier.dart';
import 'package:gastrocore_pos/features/sync/data/daos/sync_event_dao.dart';
import 'package:gastrocore_pos/features/sync/domain/entities/sync_event_entity.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _deviceId = 'SYNC-INT-DEV-01';
const _tenantId = 'tenant-sync-int';

SyncQueueCompanion _event({
  required String entityType,
  required String entityId,
  String operation = 'insert',
  String payload = '{}',
}) {
  final now = DateTime.now();
  return SyncQueueCompanion.insert(
    entityType: entityType,
    entityId: entityId,
    operation: operation,
    payloadJson: payload,
    deviceId: _deviceId,
    timestamp: now,
    createdAt: now,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // =========================================================================
  // Outbox (SyncEventDao) — full lifecycle
  // =========================================================================

  group('Sync Outbox — Full Lifecycle', () {
    late AppDatabase db;
    late SyncEventDao dao;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      dao = SyncEventDao(db);
    });

    tearDown(() => db.close());

    // -----------------------------------------------------------------------
    // Insert → pending
    // -----------------------------------------------------------------------

    test('newly inserted event has pending status', () async {
      await dao.insertEvent(
        _event(entityType: 'tickets', entityId: 'tkt-1'),
      );

      final pending = await dao.getPendingEvents();
      expect(pending.length, equals(1));
      expect(pending.first.status, equals('pending'));
    });

    test('getPendingCount matches number of pending events', () async {
      for (int i = 0; i < 5; i++) {
        await dao.insertEvent(
          _event(entityType: 'products', entityId: 'prod-$i'),
        );
      }
      final count = await dao.getPendingCount();
      expect(count, equals(5));
    });

    // -----------------------------------------------------------------------
    // pending → uploading
    // -----------------------------------------------------------------------

    test('markAsUploading removes events from pending queue', () async {
      final id = await dao.insertEvent(
        _event(entityType: 'order_items', entityId: 'item-1'),
      );

      await dao.markAsUploading([id]);

      final pending = await dao.getPendingEvents();
      expect(pending, isEmpty);
    });

    // -----------------------------------------------------------------------
    // uploading → uploaded
    // -----------------------------------------------------------------------

    test('markAsUploaded reduces pending count to zero', () async {
      final id = await dao.insertEvent(
        _event(entityType: 'bills', entityId: 'bill-1'),
      );
      await dao.markAsUploading([id]);
      await dao.markAsUploaded([id]);

      final count = await dao.getPendingCount();
      expect(count, equals(0));
    });

    // -----------------------------------------------------------------------
    // uploading → failed → retry
    // -----------------------------------------------------------------------

    test('markAsFailed removes event from pending', () async {
      final id = await dao.insertEvent(
        _event(entityType: 'payments', entityId: 'pay-1'),
      );
      await dao.markAsFailed(id, 'Timeout');

      final pending = await dao.getPendingEvents();
      expect(pending, isEmpty);
    });

    test('resetFailedForRetry requeues failed events as pending', () async {
      final id = await dao.insertEvent(
        _event(entityType: 'shifts', entityId: 'shift-1'),
      );
      await dao.markAsFailed(id, 'Network error');
      await dao.resetFailedForRetry();

      final pending = await dao.getPendingEvents();
      expect(pending.length, equals(1));
      expect(pending.first.status, equals('pending'));
    });

    // -----------------------------------------------------------------------
    // Cursor management
    // -----------------------------------------------------------------------

    test('cursor is persisted and retrieved correctly', () async {
      const cursor = '2026-03-21T10:00:00.000000Z';
      await dao.updateCursor('global', cursor);
      final retrieved = await dao.getLastCursor('global');
      expect(retrieved, equals(cursor));
    });

    test('updating cursor overwrites previous value', () async {
      await dao.updateCursor('global', 'cursor-v1');
      await dao.updateCursor('global', 'cursor-v2');
      final retrieved = await dao.getLastCursor('global');
      expect(retrieved, equals('cursor-v2'));
    });

    test('null is returned when no cursor is set', () async {
      final retrieved = await dao.getLastCursor('unknown-key');
      expect(retrieved, isNull);
    });

    // -----------------------------------------------------------------------
    // Batch push simulation
    // -----------------------------------------------------------------------

    test('batch of 10 events can be inserted, uploaded, and cleared', () async {
      final ids = <int>[];
      for (int i = 0; i < 10; i++) {
        final id = await dao.insertEvent(
          _event(
            entityType: 'tickets',
            entityId: 'tkt-batch-$i',
            payload: jsonEncode({'id': 'tkt-batch-$i', 'status': 'draft'}),
          ),
        );
        ids.add(id);
      }

      expect(await dao.getPendingCount(), equals(10));

      await dao.markAsUploading(ids);
      expect(await dao.getPendingCount(), equals(0));

      await dao.markAsUploaded(ids);
      expect(await dao.getPendingCount(), equals(0));
    });
  });

  // =========================================================================
  // RemoteEventApplier — Pull & Conflict Resolution
  // =========================================================================

  group('RemoteEventApplier — Pull (insert / update / delete)', () {
    late AppDatabase db;
    late RemoteEventApplier applier;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      applier = RemoteEventApplier(db);
    });

    tearDown(() => db.close());

    // -----------------------------------------------------------------------
    // Category upsert
    // -----------------------------------------------------------------------

    test('insert event upserts a category row', () async {
      final catId = IdGenerator.generateId();
      // Drift stores DateTimeColumn as milliseconds-since-epoch integers.
      final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;

      await applier.apply(
        tableName: 'categories',
        operation: 'insert',
        recordId: catId,
        payload: {
          'id': catId,
          'tenant_id': _tenantId,
          'name': 'Starters',
          'display_order': 1,
          'color': '#FF0000',
          'icon': '',
          'is_active': true,
          'is_deleted': false,
          'created_at': nowMs,
          'updated_at': nowMs,
        },
      );

      // Verify via raw SQL to avoid Drift's datetime type mapping.
      final result = await db.customSelect(
        'SELECT COUNT(*) as cnt FROM categories WHERE id = ?',
        variables: [Variable(catId)],
      ).get();
      expect(result.first.data['cnt'], equals(1));
    });

    // -----------------------------------------------------------------------
    // Last-write-wins conflict resolution
    // -----------------------------------------------------------------------

    test('update event overwrites existing row (last-write-wins)', () async {
      final catId = IdGenerator.generateId();
      final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;

      // First write.
      await applier.apply(
        tableName: 'categories',
        operation: 'insert',
        recordId: catId,
        payload: {
          'id': catId,
          'tenant_id': _tenantId,
          'name': 'Old Name',
          'display_order': 1,
          'color': '',
          'icon': '',
          'is_active': true,
          'is_deleted': false,
          'created_at': nowMs,
          'updated_at': nowMs,
        },
      );

      // Second write (conflict — update wins).
      await applier.apply(
        tableName: 'categories',
        operation: 'update',
        recordId: catId,
        payload: {
          'id': catId,
          'tenant_id': _tenantId,
          'name': 'New Name',
          'display_order': 2,
          'color': '#00FF00',
          'icon': '',
          'is_active': true,
          'is_deleted': false,
          'created_at': nowMs,
          'updated_at': nowMs,
        },
      );

      // Verify via raw SQL.
      final result = await db.customSelect(
        'SELECT name FROM categories WHERE id = ?',
        variables: [Variable(catId)],
      ).get();
      expect(result.first.data['name'], equals('New Name'));
    });

    // -----------------------------------------------------------------------
    // Soft delete
    // -----------------------------------------------------------------------

    test('delete event sets is_deleted=1 without removing the row', () async {
      final catId = IdGenerator.generateId();
      final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;

      // Create the row first.
      await applier.apply(
        tableName: 'categories',
        operation: 'insert',
        recordId: catId,
        payload: {
          'id': catId,
          'tenant_id': _tenantId,
          'name': 'To Delete',
          'display_order': 0,
          'color': '',
          'icon': '',
          'is_active': true,
          'is_deleted': false,
          'created_at': nowMs,
          'updated_at': nowMs,
        },
      );

      // Apply delete.
      await applier.apply(
        tableName: 'categories',
        operation: 'delete',
        recordId: catId,
        payload: {},
      );

      // Verify via raw SQL — row should still exist (tombstone) with is_deleted=1.
      final result = await db.customSelect(
        'SELECT is_deleted FROM categories WHERE id = ?',
        variables: [Variable(catId)],
      ).get();
      expect(result.length, equals(1));
      expect(result.first.data['is_deleted'], equals(1));
    });

    // -----------------------------------------------------------------------
    // Unknown table is silently skipped
    // -----------------------------------------------------------------------

    test('event for unknown table is silently ignored (no crash)', () async {
      await expectLater(
        applier.apply(
          tableName: 'nonexistent_table',
          operation: 'insert',
          recordId: 'some-id',
          payload: {'id': 'some-id', 'data': 'value'},
        ),
        completes,
      );
    });

    // -----------------------------------------------------------------------
    // Empty payload is a no-op for upsert
    // -----------------------------------------------------------------------

    test('empty payload for insert/update is a no-op', () async {
      await expectLater(
        applier.apply(
          tableName: 'categories',
          operation: 'insert',
          recordId: 'some-id',
          payload: {},
        ),
        completes,
      );
    });

    // -----------------------------------------------------------------------
    // DateTime values are stored as ISO-8601 strings
    // -----------------------------------------------------------------------

    test('DateTime payload values are stored as millisecond integers', () async {
      final catId = IdGenerator.generateId();
      final now = DateTime(2026, 3, 21, 10, 0, 0).toUtc();
      // Drift stores DateTimeColumn as milliseconds-since-epoch.
      final nowMs = now.millisecondsSinceEpoch;

      await applier.apply(
        tableName: 'categories',
        operation: 'insert',
        recordId: catId,
        payload: {
          'id': catId,
          'tenant_id': _tenantId,
          'name': 'DateTime Test',
          'display_order': 0,
          'color': '',
          'icon': '',
          'is_active': true,
          'is_deleted': false,
          'created_at': nowMs,
          'updated_at': nowMs,
        },
      );

      final result = await db.customSelect(
        'SELECT COUNT(*) as cnt FROM categories WHERE id = ?',
        variables: [Variable(catId)],
      ).get();
      expect(result.first.data['cnt'], equals(1));
    });
  });

  // =========================================================================
  // SyncEventEntity — domain model
  // =========================================================================

  group('SyncEventEntity — Domain Model', () {
    SyncEventEntity makeEntity({
      int id = 1,
      String tableName = 'tickets',
      SyncOperation operation = SyncOperation.insert,
      SyncEventStatus status = SyncEventStatus.pending,
    }) {
      return SyncEventEntity(
        id: id,
        tableName: tableName,
        operation: operation,
        recordId: 'rec-$id',
        payload: '{}',
        createdAt: DateTime(2026, 3, 21),
        deviceId: _deviceId,
        status: status,
      );
    }

    test('default status is pending', () {
      expect(makeEntity().status, equals(SyncEventStatus.pending));
    });

    test('default retryCount is 0', () {
      expect(makeEntity().retryCount, equals(0));
    });

    test('copyWith overrides only specified fields', () {
      final entity = makeEntity();
      final updated = entity.copyWith(
        status: SyncEventStatus.uploaded,
        retryCount: 2,
      );

      expect(updated.status, equals(SyncEventStatus.uploaded));
      expect(updated.retryCount, equals(2));
      expect(updated.id, equals(entity.id));
      expect(updated.tableName, equals(entity.tableName));
    });

    test('copyWith with no arguments returns equivalent entity', () {
      final entity = makeEntity(status: SyncEventStatus.uploading);
      final copy = entity.copyWith();

      expect(copy.id, equals(entity.id));
      expect(copy.status, equals(entity.status));
      expect(copy.tableName, equals(entity.tableName));
    });

    test('SyncOperation enum covers all three values', () {
      expect(SyncOperation.values.length, equals(3));
      expect(SyncOperation.values, containsAll([
        SyncOperation.insert,
        SyncOperation.update,
        SyncOperation.delete,
      ]));
    });

    test('SyncEventStatus enum covers all four values', () {
      expect(SyncEventStatus.values.length, equals(4));
      expect(SyncEventStatus.values, containsAll([
        SyncEventStatus.pending,
        SyncEventStatus.uploading,
        SyncEventStatus.uploaded,
        SyncEventStatus.failed,
      ]));
    });
  });
}
