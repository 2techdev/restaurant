/// Extended sync tests: SyncEventEntity domain model, SyncEventDao outbox
/// operations, cursor management, and RemoteEventApplier table filtering.
///
/// HTTP-dependent SyncRepositoryImpl.pushPendingEvents / pullRemoteEvents
/// are tested via the existing sync_repository_impl_test.dart (DAO layer).
///
/// Run with:
///   flutter test test/features/sync/sync_extended_test.dart
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/features/sync/data/applier/remote_event_applier.dart';
import 'package:gastrocore_pos/features/sync/data/daos/sync_event_dao.dart';
import 'package:gastrocore_pos/features/sync/domain/entities/sync_event_entity.dart';
import 'package:gastrocore_pos/features/sync/domain/repositories/sync_repository.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _deviceId = 'DEV-SYNC-EXT-01';

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // =========================================================================
  // SyncEventEntity — domain model
  // =========================================================================

  group('SyncEventEntity', () {
    SyncEventEntity base() => SyncEventEntity(
          id: 1,
          tableName: 'tickets',
          operation: SyncOperation.insert,
          recordId: 'ticket-1',
          payload: '{"id":"ticket-1"}',
          createdAt: DateTime(2026, 3, 21),
          deviceId: _deviceId,
        );

    test('default status is pending', () {
      expect(base().status, equals(SyncEventStatus.pending));
    });

    test('default retryCount is 0', () {
      expect(base().retryCount, equals(0));
    });

    test('copyWith overrides status', () {
      final updated = base().copyWith(status: SyncEventStatus.uploaded);
      expect(updated.status, equals(SyncEventStatus.uploaded));
      expect(updated.id, equals(1));
    });

    test('copyWith overrides retryCount', () {
      final updated = base().copyWith(retryCount: 3);
      expect(updated.retryCount, equals(3));
    });

    test('copyWith preserves unchanged fields', () {
      final e = base().copyWith(errorMessage: 'Timeout');
      expect(e.tableName, equals('tickets'));
      expect(e.operation, equals(SyncOperation.insert));
      expect(e.recordId, equals('ticket-1'));
      expect(e.errorMessage, equals('Timeout'));
    });

    test('SyncOperation covers insert, update, delete', () {
      expect(
        SyncOperation.values,
        containsAll([SyncOperation.insert, SyncOperation.update, SyncOperation.delete]),
      );
    });

    test('SyncEventStatus covers all states', () {
      expect(
        SyncEventStatus.values,
        containsAll([
          SyncEventStatus.pending,
          SyncEventStatus.uploading,
          SyncEventStatus.uploaded,
          SyncEventStatus.failed,
        ]),
      );
    });
  });

  // =========================================================================
  // SyncStatus — repository enum
  // =========================================================================

  group('SyncStatus enum', () {
    test('covers all four states', () {
      expect(
        SyncStatus.values,
        containsAll([
          SyncStatus.idle,
          SyncStatus.syncing,
          SyncStatus.error,
          SyncStatus.offline,
        ]),
      );
    });
  });

  // =========================================================================
  // SyncEventDao — extended outbox tests
  // =========================================================================

  group('SyncEventDao — outbox management', () {
    late AppDatabase db;
    late SyncEventDao dao;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      dao = SyncEventDao(db);
    });

    tearDown(() async => db.close());

    Future<int> enqueue({
      String table = 'tickets',
      String operation = 'insert',
      String recordId = 'rec-1',
      String payload = '{}',
    }) async {
      final now = DateTime.now();
      return dao.insertEvent(
        SyncQueueCompanion.insert(
          entityType: table,
          entityId: recordId,
          operation: operation,
          payloadJson: payload,
          deviceId: _deviceId,
          timestamp: now,
          createdAt: now,
        ),
      );
    }

    test('fresh queue has 0 pending events', () async {
      expect(await dao.getPendingCount(), equals(0));
    });

    test('inserting 3 events yields count of 3', () async {
      await enqueue(recordId: 'r-1');
      await enqueue(recordId: 'r-2');
      await enqueue(recordId: 'r-3');
      expect(await dao.getPendingCount(), equals(3));
    });

    test('pending events are only "pending" status rows', () async {
      final id = await enqueue(recordId: 'r-pend');
      await dao.markAsUploading([id]);
      // markAsUploading → no longer "pending"
      expect(await dao.getPendingCount(), equals(0));
    });

    test('markAsUploaded removes from pending', () async {
      final id1 = await enqueue(recordId: 'up-1');
      final id2 = await enqueue(recordId: 'up-2');

      await dao.markAsUploading([id1, id2]);
      await dao.markAsUploaded([id1, id2]);

      expect(await dao.getPendingCount(), equals(0));
    });

    test('markAsFailed marks event as failed (not pending)', () async {
      final id = await enqueue(recordId: 'fail-1');
      await dao.markAsFailed(id, 'Connection refused');
      expect(await dao.getPendingCount(), equals(0));
    });

    test('resetFailedForRetry with maxRetries=5 re-queues events with retryCount < 5',
        () async {
      final id = await enqueue(recordId: 'retry-1');
      await dao.markAsFailed(id, 'error');
      // retryCount = 1 (< 5 default) → should be re-queued
      await dao.resetFailedForRetry(maxRetries: 5);
      expect(await dao.getPendingCount(), equals(1));
    });

    test('cursor is saved and retrieved', () async {
      await dao.updateCursor('global', '2026-03-21T10:00:00Z');
      final cursor = await dao.getLastCursor('global');
      expect(cursor, equals('2026-03-21T10:00:00Z'));
    });

    test('cursor update overwrites previous value', () async {
      await dao.updateCursor('global', 'cursor-v1');
      await dao.updateCursor('global', 'cursor-v2');
      expect(await dao.getLastCursor('global'), equals('cursor-v2'));
    });

    test('getLastCursor returns null when no cursor set', () async {
      final cursor = await dao.getLastCursor('no-cursor-key');
      expect(cursor, isNull);
    });

    test('getPendingEvents returns only pending rows', () async {
      final id1 = await enqueue(table: 'products', recordId: 'p-1');
      final id2 = await enqueue(table: 'products', recordId: 'p-2');
      final id3 = await enqueue(table: 'products', recordId: 'p-3');

      // Mark id3 as uploaded.
      await dao.markAsUploading([id3]);
      await dao.markAsUploaded([id3]);

      final pending = await dao.getPendingEvents();
      expect(pending.length, equals(2));
      expect(pending.map((e) => e.id).toList(), containsAll([id1, id2]));
      expect(pending.map((e) => e.id).toList(), isNot(contains(id3)));
    });

    test('payload JSON is stored and retrieved intact', () async {
      final payload = jsonEncode({'id': 'ticket-abc', 'status': 'sent', 'total': 2500});
      await enqueue(recordId: 'ticket-abc', payload: payload);

      final pending = await dao.getPendingEvents();
      expect(pending.first.payloadJson, equals(payload));
    });

    test('multiple tables can coexist in pending queue', () async {
      await enqueue(table: 'tickets', recordId: 't-1');
      await enqueue(table: 'products', recordId: 'p-1');
      await enqueue(table: 'payments', recordId: 'pay-1');

      final pending = await dao.getPendingEvents();
      expect(pending.length, equals(3));
      final tables = pending.map((e) => e.entityType).toSet();
      expect(tables, containsAll(['tickets', 'products', 'payments']));
    });
  });

  // =========================================================================
  // RemoteEventApplier — table allow-list
  // =========================================================================

  group('RemoteEventApplier — table allow-list', () {
    late AppDatabase db;
    late RemoteEventApplier applier;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      applier = RemoteEventApplier(db);
    });

    tearDown(() async => db.close());

    test('silently ignores unknown table names', () async {
      await expectLater(
        applier.apply(
          tableName: 'nonexistent_table',
          operation: 'insert',
          recordId: 'rec-1',
          payload: {'id': 'rec-1'},
        ),
        completes,
      );
    });

    test('silently ignores disallowed table: audit_log', () async {
      await expectLater(
        applier.apply(
          tableName: 'audit_log',
          operation: 'insert',
          recordId: 'log-1',
          payload: {'id': 'log-1'},
        ),
        completes,
      );
    });

    test('silently ignores disallowed table: license_tokens', () async {
      await expectLater(
        applier.apply(
          tableName: 'license_tokens',
          operation: 'update',
          recordId: 'lt-1',
          payload: {'id': 'lt-1'},
        ),
        completes,
      );
    });

    test('silently ignores disallowed table: sync_queue', () async {
      await expectLater(
        applier.apply(
          tableName: 'sync_queue',
          operation: 'insert',
          recordId: 'sq-1',
          payload: {'id': 'sq-1'},
        ),
        completes,
      );
    });

    test('delete operation completes without error for allowed table', () async {
      await expectLater(
        applier.apply(
          tableName: 'products',
          operation: 'delete',
          recordId: 'nonexistent-product',
          payload: {},
        ),
        completes,
      );
    });
  });
}
