/// Sync event entity for the outbox pattern.
library;

/// The current state of a sync event in the outbox.
enum SyncEventStatus { pending, uploading, uploaded, failed }

/// The operation that was performed on the record.
enum SyncOperation { insert, update, delete }

/// A single change event that needs to be pushed to the cloud.
class SyncEventEntity {
  final int id;
  final String tableName;
  final SyncOperation operation;
  final String recordId;
  final String payload;
  final DateTime createdAt;
  final String deviceId;
  final DateTime? syncedAt;
  final SyncEventStatus status;
  final int retryCount;
  final String? errorMessage;

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

  factory SyncEventEntity.fromJson(Map<String, dynamic> json) =>
      SyncEventEntity(
        id: json['id'] as int,
        tableName: json['table_name'] as String,
        operation: SyncOperation.values.firstWhere(
          (e) => e.name == json['operation'],
          orElse: () => SyncOperation.insert,
        ),
        recordId: json['record_id'] as String,
        payload: json['payload'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        deviceId: json['device_id'] as String,
        syncedAt: json['synced_at'] != null
            ? DateTime.parse(json['synced_at'] as String)
            : null,
        status: SyncEventStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => SyncEventStatus.pending,
        ),
        retryCount: json['retry_count'] as int? ?? 0,
        errorMessage: json['error_message'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'table_name': tableName,
        'operation': operation.name,
        'record_id': recordId,
        'payload': payload,
        'created_at': createdAt.toIso8601String(),
        'device_id': deviceId,
        if (syncedAt != null) 'synced_at': syncedAt!.toIso8601String(),
        'status': status.name,
        'retry_count': retryCount,
        if (errorMessage != null) 'error_message': errorMessage,
      };

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

  @override
  String toString() =>
      'SyncEventEntity(id: $id, table: $tableName, op: ${operation.name}, status: ${status.name})';
}
