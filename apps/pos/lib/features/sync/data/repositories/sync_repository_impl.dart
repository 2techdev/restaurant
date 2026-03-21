/// Drift + HTTP implementation of the sync repository.
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/features/sync/data/applier/remote_event_applier.dart';
import 'package:gastrocore_pos/features/sync/data/clients/sync_api_client.dart';
import 'package:gastrocore_pos/features/sync/data/daos/sync_event_dao.dart';
import 'package:gastrocore_pos/features/sync/domain/entities/sync_event_entity.dart';
import 'package:gastrocore_pos/features/sync/domain/repositories/sync_repository.dart';
import 'package:uuid/uuid.dart';

class SyncRepositoryImpl implements SyncRepository {
  SyncRepositoryImpl({
    required AppDatabase db,
    required SyncApiClient apiClient,
    required String tenantId,
    required String deviceId,
  })  : _dao = SyncEventDao(db),
        _api = apiClient,
        _applier = RemoteEventApplier(db),
        _tenantId = tenantId,
        _deviceId = deviceId;

  final SyncEventDao _dao;
  final SyncApiClient _api;
  final RemoteEventApplier _applier;
  final String _tenantId;
  final String _deviceId;

  static const _uuid = Uuid();
  static const _globalCursorKey = 'global';

  // ---------------------------------------------------------------------------
  // SyncRepository
  // ---------------------------------------------------------------------------

  @override
  Future<SyncStatus> getSyncStatus() async {
    final pending = await _dao.getPendingCount();
    return pending > 0 ? SyncStatus.idle : SyncStatus.idle;
  }

  @override
  Future<String> getLastCursor() async {
    return await _dao.getLastCursor(_globalCursorKey) ?? '';
  }

  @override
  Future<void> enqueueEvent({
    required String tableName,
    required SyncOperation operation,
    required String recordId,
    required String payload,
    required String deviceId,
  }) async {
    final now = DateTime.now();
    await _dao.insertEvent(
      SyncQueueCompanion(
        entityType: Value(tableName),
        entityId: Value(recordId),
        operation: Value(_operationToString(operation)),
        payloadJson: Value(payload),
        deviceId: Value(deviceId),
        timestamp: Value(now),
        status: const Value('pending'),
        createdAt: Value(now),
      ),
    );
  }

  @override
  Future<List<SyncEventEntity>> getPendingEvents() async {
    final rows = await _dao.getPendingEvents();
    return rows.map(_rowToEntity).toList();
  }

  @override
  Future<int> getPendingCount() => _dao.getPendingCount();

  @override
  Future<int> pushPendingEvents() async {
    final pending = await _dao.getPendingEvents();
    if (pending.isEmpty) return 0;

    final ids = pending.map((e) => e.id).toList();
    await _dao.markAsUploading(ids);

    try {
      final remoteEvents = pending.map((row) {
        Map<String, dynamic> payload = {};
        try {
          payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
        } catch (_) {}

        return RemoteSyncEvent(
          id: _uuid.v4(),
          tenantId: _tenantId,
          deviceId: row.deviceId,
          tableName: row.entityType,
          recordId: row.entityId,
          operation: row.operation,
          payload: payload,
          createdAt: row.createdAt,
        );
      }).toList();

      final result = await _api.push(remoteEvents);
      await _dao.markAsUploaded(ids);
      return result.accepted;
    } catch (e) {
      for (final id in ids) {
        await _dao.markAsFailed(id, e.toString());
      }
      rethrow;
    }
  }

  @override
  Future<String> pullRemoteEvents(String lastCursor) async {
    String cursor = lastCursor;
    bool hasMore = true;

    // Paginate until all pending remote events are fetched.
    while (hasMore) {
      final result = await _api.pull(
        deviceId: _deviceId,
        tenantId: _tenantId,
        cursor: cursor,
      );

      for (final event in result.events) {
        // Skip events that originated from this device — we already have them.
        if (event.deviceId == _deviceId) continue;
        await _applyRemoteEvent(event);
      }

      if (result.cursor.isNotEmpty && result.cursor != cursor) {
        cursor = result.cursor;
        await _dao.updateCursor(_globalCursorKey, cursor);
      }

      hasMore = result.hasMore;

      // Guard against a server that always returns hasMore = true.
      if (!result.hasMore || result.events.isEmpty) break;
    }

    return cursor;
  }

  /// Reset events that have failed (up to [maxRetries]) back to pending so
  /// the next push cycle will retry them.
  Future<void> resetFailedEvents({int maxRetries = 5}) =>
      _dao.resetFailedForRetry(maxRetries: maxRetries);

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Apply a remote event to the local database.
  ///
  /// 1. Write the row into the target table (upsert / soft-delete).
  /// 2. Record the event in sync_queue with status 'uploaded' so it is not
  ///    re-pushed to the server.
  Future<void> _applyRemoteEvent(RemoteSyncEvent event) async {
    // Step 1: Materialise the change in the actual entity table.
    await _applier.apply(
      tableName: event.tableName,
      operation: event.operation,
      recordId: event.recordId,
      payload: event.payload,
    );

    // Step 2: Record in the outbox as already uploaded (audit trail).
    final now = DateTime.now();
    await _dao.insertEvent(
      SyncQueueCompanion(
        entityType: Value(event.tableName),
        entityId: Value(event.recordId),
        operation: Value(event.operation),
        payloadJson: Value(jsonEncode(event.payload)),
        deviceId: Value(event.deviceId),
        timestamp: Value(now),
        status: const Value('uploaded'),
        createdAt: Value(event.createdAt),
      ),
    );
  }

  SyncEventEntity _rowToEntity(SyncQueueEntry row) {
    return SyncEventEntity(
      id: row.id,
      tableName: row.entityType,
      operation: _parseOperation(row.operation),
      recordId: row.entityId,
      payload: row.payloadJson,
      createdAt: row.createdAt,
      deviceId: row.deviceId,
      status: _parseStatus(row.status),
      retryCount: row.retryCount,
      errorMessage: row.errorMessage,
    );
  }

  static SyncOperation _parseOperation(String value) {
    return switch (value) {
      'update' => SyncOperation.update,
      'delete' => SyncOperation.delete,
      _ => SyncOperation.insert,
    };
  }

  static String _operationToString(SyncOperation op) {
    return switch (op) {
      SyncOperation.insert => 'insert',
      SyncOperation.update => 'update',
      SyncOperation.delete => 'delete',
    };
  }

  static SyncEventStatus _parseStatus(String value) {
    return switch (value) {
      'uploading' => SyncEventStatus.uploading,
      'uploaded' => SyncEventStatus.uploaded,
      'failed' => SyncEventStatus.failed,
      _ => SyncEventStatus.pending,
    };
  }
}
