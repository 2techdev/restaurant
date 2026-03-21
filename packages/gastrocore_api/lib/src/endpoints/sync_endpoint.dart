/// Sync endpoint methods — outbox push and cursor-based pull.
library;

import 'package:gastrocore_models/gastrocore_models.dart';
import '../client/gastrocore_client.dart';

/// Response from a cursor-based pull operation.
class PullResponse {
  /// Changes since the last cursor.
  final List<Map<String, dynamic>> changes;

  /// Opaque cursor to use in the next pull request.
  final String nextCursor;

  /// Whether more pages are available.
  final bool hasMore;

  const PullResponse({
    required this.changes,
    required this.nextCursor,
    this.hasMore = false,
  });

  factory PullResponse.fromJson(Map<String, dynamic> json) => PullResponse(
        changes: (json['changes'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>(),
        nextCursor: json['next_cursor'] as String? ?? '',
        hasMore: json['has_more'] as bool? ?? false,
      );
}

/// Response from a batch push operation.
class PushResponse {
  final int accepted;
  final int rejected;
  final List<String> rejectedIds;

  const PushResponse({
    required this.accepted,
    required this.rejected,
    this.rejectedIds = const [],
  });

  factory PushResponse.fromJson(Map<String, dynamic> json) => PushResponse(
        accepted: json['accepted'] as int? ?? 0,
        rejected: json['rejected'] as int? ?? 0,
        rejectedIds: (json['rejected_ids'] as List<dynamic>? ?? [])
            .cast<String>(),
      );
}

class SyncEndpoint {
  final GastrocoreClient _client;

  const SyncEndpoint(this._client);

  /// Push outbox events to the cloud backend.
  Future<PushResponse> pushEvents({
    required String tenantId,
    required List<SyncEventEntity> events,
  }) async {
    final json = await _client.post('/api/v1/sync/push', {
      'tenant_id': tenantId,
      'events': events.map((e) => e.toJson()).toList(),
    });
    return PushResponse.fromJson(json);
  }

  /// Pull changes since [cursor] using cursor-based pagination.
  Future<PullResponse> pullChanges({
    required String tenantId,
    required String cursor,
    int? limit,
  }) async {
    final params = <String, String>{
      'tenant_id': tenantId,
      'cursor': cursor,
      if (limit != null) 'limit': limit.toString(),
    };
    final json = await _client.get('/api/v1/sync/pull', queryParams: params);
    return PullResponse.fromJson(json);
  }

  /// Register this device for sync and get initial sync cursor.
  Future<String> registerDevice({
    required String tenantId,
    required String deviceId,
  }) async {
    final json = await _client.post('/api/v1/sync/devices', {
      'tenant_id': tenantId,
      'device_id': deviceId,
    });
    return json['cursor'] as String? ?? '';
  }

  /// Acknowledge that events up to [eventId] have been processed.
  Future<void> acknowledgeEvents({
    required String tenantId,
    required String deviceId,
    required int upToEventId,
  }) async {
    await _client.post('/api/v1/sync/ack', {
      'tenant_id': tenantId,
      'device_id': deviceId,
      'up_to_event_id': upToEventId,
    });
  }
}
