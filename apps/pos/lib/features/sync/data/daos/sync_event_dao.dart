/// Drift DAO for sync_queue and sync_metadata tables.
library;

import 'package:drift/drift.dart';
import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/database/tables/sync_queue.dart';
import 'package:gastrocore_pos/core/database/tables/sync_metadata.dart';

part 'sync_event_dao.g.dart';

@DriftAccessor(tables: [SyncQueue, SyncMetadata])
class SyncEventDao extends DatabaseAccessor<AppDatabase>
    with _$SyncEventDaoMixin {
  SyncEventDao(super.db);

  // ---------------------------------------------------------------------------
  // Outbox (sync_queue)
  // ---------------------------------------------------------------------------

  /// Insert a new event into the outbox.
  Future<int> insertEvent(SyncQueueCompanion entry) =>
      into(syncQueue).insert(entry);

  /// Get all events with status = 'pending', ordered by createdAt ASC.
  Future<List<SyncQueueEntry>> getPendingEvents() {
    return (select(syncQueue)
          ..where((t) => t.status.equals('pending'))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  /// Count pending events.
  Future<int> getPendingCount() async {
    final countExpr = syncQueue.id.count();
    final result = await (selectOnly(syncQueue)
          ..addColumns([countExpr])
          ..where(syncQueue.status.equals('pending')))
        .getSingle();
    return result.read(countExpr) ?? 0;
  }

  /// Mark a list of events as uploading.
  Future<void> markAsUploading(List<int> ids) async {
    await (update(syncQueue)..where((t) => t.id.isIn(ids))).write(
      const SyncQueueCompanion(status: Value('uploading')),
    );
  }

  /// Mark a list of events as successfully uploaded.
  Future<void> markAsUploaded(List<int> ids) async {
    await (update(syncQueue)..where((t) => t.id.isIn(ids))).write(
      SyncQueueCompanion(
        status: const Value('uploaded'),
        timestamp: Value(DateTime.now()),
      ),
    );
  }

  /// Mark an event as failed and record the error.
  Future<void> markAsFailed(int id, String error) async {
    final entry = await (select(syncQueue)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (entry == null) return;
    await (update(syncQueue)..where((t) => t.id.equals(id))).write(
      SyncQueueCompanion(
        status: const Value('failed'),
        errorMessage: Value(error),
        retryCount: Value(entry.retryCount + 1),
      ),
    );
  }

  /// Reset failed events to pending for retry (up to [maxRetries] attempts).
  Future<void> resetFailedForRetry({int maxRetries = 5}) async {
    await (update(syncQueue)
          ..where(
            (t) =>
                t.status.equals('failed') &
                t.retryCount.isSmallerThanValue(maxRetries),
          ))
        .write(const SyncQueueCompanion(status: Value('pending')));
  }

  // ---------------------------------------------------------------------------
  // Metadata / cursor (sync_metadata)
  // ---------------------------------------------------------------------------

  /// Get the last cursor for an entity type (or global with key 'global').
  Future<String?> getLastCursor(String entityType) async {
    final row = await (select(syncMetadata)
          ..where((t) => t.entityType.equals(entityType)))
        .getSingleOrNull();
    return row?.lastCursor;
  }

  /// Update the cursor and last sync time for an entity type.
  Future<void> updateCursor(String entityType, String cursor) async {
    await into(syncMetadata).insertOnConflictUpdate(
      SyncMetadataCompanion(
        entityType: Value(entityType),
        lastSyncAt: Value(DateTime.now()),
        lastCursor: Value(cursor),
      ),
    );
  }

  /// Get the last sync time for an entity type.
  Future<DateTime?> getLastSyncAt(String entityType) async {
    final row = await (select(syncMetadata)
          ..where((t) => t.entityType.equals(entityType)))
        .getSingleOrNull();
    return row?.lastSyncAt;
  }
}
