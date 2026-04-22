/// Abstract sync repository interface.
library;

import 'package:gastrocore_pos/features/sync/domain/entities/sync_event_entity.dart';

/// The overall sync state visible to the UI.
enum SyncStatus { idle, syncing, error, offline }

/// Abstract interface for the sync repository.
abstract class SyncRepository {
  /// Push all pending outbox events to the cloud.
  /// Returns the number of events successfully pushed.
  Future<int> pushPendingEvents();

  /// Pull remote events since [lastCursor] and apply them to the local DB.
  /// Returns the new cursor to use for the next pull.
  Future<String> pullRemoteEvents(String lastCursor);

  /// Get the current sync status.
  Future<SyncStatus> getSyncStatus();

  /// Add an event to the local outbox (called on every write operation).
  Future<void> enqueueEvent({
    required String tableName,
    required SyncOperation operation,
    required String recordId,
    required String payload,
    required String deviceId,
  });

  /// Get all pending events from the outbox.
  Future<List<SyncEventEntity>> getPendingEvents();

  /// Count of events waiting to be pushed.
  Future<int> getPendingCount();

  /// Get the last pull cursor (empty string if never synced).
  Future<String> getLastCursor();

  // ---------------------------------------------------------------------------
  // Dead-letter queue (DLQ)
  //
  // Poison events that have exhausted their retry budget end up here. The
  // DLQ is a manual-intervention surface: the operator can inspect the
  // error message, requeue an event if the cause was transient, or purge
  // it if the payload is corrupted.
  // ---------------------------------------------------------------------------

  /// List every event currently in the DLQ.
  Future<List<SyncEventEntity>> getDeadLetterEvents();

  /// Count of events in the DLQ.
  Future<int> getDeadLetterCount();

  /// Move a DLQ entry back to `pending` so the next sync cycle retries it.
  Future<void> requeueDeadLetterEvent(int id);

  /// Delete a DLQ entry permanently.
  Future<void> purgeDeadLetterEvent(int id);
}
