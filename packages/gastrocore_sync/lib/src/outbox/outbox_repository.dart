/// Abstract interface for the outbox persistence layer.
///
/// Implementations provide app-specific storage (e.g. Drift/SQLite for POS,
/// in-memory for tests).
library;

import 'package:gastrocore_models/gastrocore_models.dart';

abstract interface class OutboxRepository {
  /// Return all events with [SyncEventStatus.pending] or [SyncEventStatus.failed]
  /// up to [maxRetries], ordered by [SyncEventEntity.id] ascending.
  Future<List<SyncEventEntity>> getPendingEvents({int maxRetries = 3});

  /// Mark the event as [SyncEventStatus.uploading].
  Future<void> markUploading(int eventId);

  /// Mark the event as [SyncEventStatus.uploaded] and record [syncedAt].
  Future<void> markUploaded(int eventId, DateTime syncedAt);

  /// Mark the event as [SyncEventStatus.failed] and increment [retryCount].
  Future<void> markFailed(int eventId, String errorMessage);

  /// Delete all successfully uploaded events older than [before].
  Future<void> pruneUploaded(DateTime before);

  /// Insert a new event into the outbox.
  Future<void> enqueue(SyncEventEntity event);
}
