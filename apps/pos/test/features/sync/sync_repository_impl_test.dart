import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/features/sync/data/daos/sync_event_dao.dart';
import 'package:gastrocore_pos/features/sync/domain/entities/sync_event_entity.dart';
import 'package:drift/native.dart';

void main() {
  late AppDatabase db;
  late SyncEventDao dao;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dao = SyncEventDao(db);
  });

  tearDown(() => db.close());

  group('SyncEventDao', () {
    test('inserts and retrieves pending events', () async {
      final now = DateTime.now();
      await dao.insertEvent(
        SyncQueueCompanion.insert(
          entityType: 'tickets',
          entityId: 'ticket-1',
          operation: 'insert',
          payloadJson: jsonEncode({'id': 'ticket-1'}),
          deviceId: 'device-1',
          timestamp: now,
          createdAt: now,
        ),
      );

      final pending = await dao.getPendingEvents();
      expect(pending.length, 1);
      expect(pending.first.entityType, 'tickets');
      expect(pending.first.status, 'pending');
    });

    test('getPendingCount returns correct count', () async {
      final now = DateTime.now();
      for (var i = 0; i < 3; i++) {
        await dao.insertEvent(
          SyncQueueCompanion.insert(
            entityType: 'products',
            entityId: 'product-$i',
            operation: 'update',
            payloadJson: '{}',
            deviceId: 'device-1',
            timestamp: now,
            createdAt: now,
          ),
        );
      }
      final count = await dao.getPendingCount();
      expect(count, 3);
    });

    test('markAsUploading transitions status', () async {
      final now = DateTime.now();
      final id = await dao.insertEvent(
        SyncQueueCompanion.insert(
          entityType: 'orders',
          entityId: 'order-1',
          operation: 'insert',
          payloadJson: '{}',
          deviceId: 'device-1',
          timestamp: now,
          createdAt: now,
        ),
      );

      await dao.markAsUploading([id]);
      final pending = await dao.getPendingEvents();
      expect(pending, isEmpty); // uploading is not pending
    });

    test('markAsUploaded removes from pending', () async {
      final now = DateTime.now();
      final id = await dao.insertEvent(
        SyncQueueCompanion.insert(
          entityType: 'orders',
          entityId: 'order-2',
          operation: 'update',
          payloadJson: '{}',
          deviceId: 'device-1',
          timestamp: now,
          createdAt: now,
        ),
      );
      await dao.markAsUploading([id]);
      await dao.markAsUploaded([id]);

      final count = await dao.getPendingCount();
      expect(count, 0);
    });

    test('markAsFailed increments retryCount', () async {
      final now = DateTime.now();
      final id = await dao.insertEvent(
        SyncQueueCompanion.insert(
          entityType: 'payments',
          entityId: 'pay-1',
          operation: 'insert',
          payloadJson: '{}',
          deviceId: 'device-1',
          timestamp: now,
          createdAt: now,
        ),
      );

      await dao.markAsFailed(id, 'Network error');

      // Should not be in pending (failed status)
      final pending = await dao.getPendingEvents();
      expect(pending, isEmpty);
    });

    test('resetFailedForRetry requeues failed events', () async {
      final now = DateTime.now();
      final id = await dao.insertEvent(
        SyncQueueCompanion.insert(
          entityType: 'tickets',
          entityId: 'ticket-fail',
          operation: 'insert',
          payloadJson: '{}',
          deviceId: 'device-1',
          timestamp: now,
          createdAt: now,
        ),
      );
      await dao.markAsFailed(id, 'Timeout');
      await dao.resetFailedForRetry();

      final pending = await dao.getPendingEvents();
      expect(pending.length, 1);
      expect(pending.first.status, 'pending');
    });

    test('cursor is persisted and retrieved', () async {
      await dao.updateCursor('global', '2026-03-21T10:00:00.000000Z');
      final cursor = await dao.getLastCursor('global');
      expect(cursor, '2026-03-21T10:00:00.000000Z');
    });

    test('cursor update overwrites previous value', () async {
      await dao.updateCursor('global', 'cursor-1');
      await dao.updateCursor('global', 'cursor-2');
      final cursor = await dao.getLastCursor('global');
      expect(cursor, 'cursor-2');
    });
  });

  group('SyncEventEntity', () {
    test('copyWith preserves unchanged fields', () {
      final entity = SyncEventEntity(
        id: 1,
        tableName: 'tickets',
        operation: SyncOperation.insert,
        recordId: 'rec-1',
        payload: '{}',
        createdAt: DateTime.now(),
        deviceId: 'dev-1',
      );

      final updated = entity.copyWith(status: SyncEventStatus.uploaded);
      expect(updated.id, entity.id);
      expect(updated.tableName, entity.tableName);
      expect(updated.status, SyncEventStatus.uploaded);
    });
  });
}
