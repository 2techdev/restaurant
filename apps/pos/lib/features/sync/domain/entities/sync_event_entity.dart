/// Domain entity representing a single sync event in the outbox.
library;

/// The current state of a sync event in the outbox.
///
/// `dead` is the terminal state for poison events: those that have
/// failed more than the retry budget (default 5 attempts) or were
/// rejected with a non-retryable error. Dead events stay in the outbox
/// for forensic inspection and can be manually requeued or purged from
/// the DLQ (dead-letter queue) screen in Settings.
enum SyncEventStatus { pending, uploading, uploaded, failed, dead }

/// The operation that was performed on the record.
enum SyncOperation { insert, update, delete }

/// A single change event that needs to be pushed to the cloud.
class SyncEventEntity {
  const SyncEventEntity({
    required this.id,
    required this.tableName,
    required this.operation,
    required this.recordId,
    required this.payload,
    required this.createdAt,
    required this.deviceId,
    this.syncedAt,
    this.status = SyncEventStatus.pending,
    this.retryCount = 0,
    this.errorMessage,
  });

  final int id;
  final String tableName;     // e.g. 'tickets', 'products'
  final SyncOperation operation;
  final String recordId;      // UUID of the changed record
  final String payload;       // JSON string of the record
  final DateTime createdAt;
  final String deviceId;
  final DateTime? syncedAt;
  final SyncEventStatus status;
  final int retryCount;
  final String? errorMessage;

  SyncEventEntity copyWith({
    SyncEventStatus? status,
    DateTime? syncedAt,
    int? retryCount,
    String? errorMessage,
  }) {
    return SyncEventEntity(
      id: id,
      tableName: tableName,
      operation: operation,
      recordId: recordId,
      payload: payload,
      createdAt: createdAt,
      deviceId: deviceId,
      syncedAt: syncedAt ?? this.syncedAt,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
