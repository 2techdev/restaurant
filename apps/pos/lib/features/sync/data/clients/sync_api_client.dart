/// HTTP client for the GastroCore cloud sync API.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;

/// A single sync event to push to the server.
class RemoteSyncEvent {
  const RemoteSyncEvent({
    required this.id,
    required this.tenantId,
    required this.deviceId,
    required this.tableName,
    required this.recordId,
    required this.operation,
    required this.payload,
    required this.createdAt,
  });

  final String id;
  final String tenantId;
  final String deviceId;
  final String tableName;
  final String recordId;
  final String operation;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenant_id': tenantId,
        'device_id': deviceId,
        'table_name': tableName,
        'record_id': recordId,
        'operation': operation,
        'payload': payload,
        'created_at': createdAt.toUtc().toIso8601String(),
      };
}

/// Response from the server after a pull request.
class PullResult {
  const PullResult({
    required this.events,
    required this.cursor,
    required this.hasMore,
  });

  final List<RemoteSyncEvent> events;
  final String cursor;
  final bool hasMore;
}

/// HTTP client for sync push/pull operations.
class SyncApiClient {
  SyncApiClient({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 30),
    this.authTokenProvider,
    this.tenantIdProvider,
  });

  final String baseUrl;
  final Duration timeout;

  /// Async resolver for the Bearer token. Resolved per request so the
  /// client picks up token rotations without rebuilding the provider.
  /// Returns null/'' for local-demo / unauthenticated mode — those calls
  /// go through without an Authorization header.
  final Future<String?> Function()? authTokenProvider;

  /// Resolves the active tenant for the current operator session. Wired to
  /// `activeTenantProvider` (see core/tenant/active_tenant_provider.dart).
  /// When a tenant is resolved, every request carries `X-Tenant-ID`, which
  /// the cloud uses as the authoritative tenant scope (the body/query
  /// `tenant_id` remains for backwards compatibility with v1 endpoints).
  /// Returns null when no operator is signed in — callers stay tenant-less.
  final String Function()? tenantIdProvider;

  final _client = http.Client();

  Future<Map<String, String>> _headers({bool json = false}) async {
    final headers = <String, String>{};
    if (json) headers['Content-Type'] = 'application/json';
    final token = await authTokenProvider?.call();
    if (token != null && token.isNotEmpty && token != 'local') {
      headers['Authorization'] = 'Bearer $token';
    }
    final tid = tenantIdProvider?.call();
    if (tid != null && tid.isNotEmpty) {
      headers['X-Tenant-ID'] = tid;
    }
    return headers;
  }

  /// Push a batch of events to the server.
  /// Returns (accepted, rejected) counts.
  Future<({int accepted, int rejected})> push(List<RemoteSyncEvent> events) async {
    if (events.isEmpty) return (accepted: 0, rejected: 0);

    final body = jsonEncode({
      'device_id': events.first.deviceId,
      'tenant_id': events.first.tenantId,
      'events': events.map((e) => e.toJson()).toList(),
    });

    final response = await _client
        .post(
          Uri.parse('$baseUrl/api/v1/sync/push'),
          headers: await _headers(json: true),
          body: body,
        )
        .timeout(timeout);

    if (response.statusCode != 200) {
      throw SyncApiException(
        'Push failed: ${response.statusCode} ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return (
      accepted: (json['accepted'] as num?)?.toInt() ?? 0,
      rejected: (json['rejected'] as num?)?.toInt() ?? 0,
    );
  }

  /// Pull events from the server since [cursor].
  Future<PullResult> pull({
    required String deviceId,
    required String tenantId,
    required String cursor,
    int limit = 100,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/sync/pull').replace(
      queryParameters: {
        'device_id': deviceId,
        'tenant_id': tenantId,
        'cursor': cursor,
        'limit': '$limit',
      },
    );

    final response =
        await _client.get(uri, headers: await _headers()).timeout(timeout);

    if (response.statusCode != 200) {
      throw SyncApiException(
        'Pull failed: ${response.statusCode} ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final rawEvents = (json['events'] as List<dynamic>?) ?? [];

    final events = rawEvents.map((e) {
      final m = e as Map<String, dynamic>;
      return RemoteSyncEvent(
        id: m['id'] as String? ?? '',
        tenantId: m['tenant_id'] as String? ?? tenantId,
        deviceId: m['device_id'] as String? ?? '',
        tableName: m['table_name'] as String? ?? '',
        recordId: m['record_id'] as String? ?? '',
        operation: m['operation'] as String? ?? 'update',
        payload: (m['payload'] as Map<String, dynamic>?) ?? {},
        createdAt: DateTime.tryParse(m['created_at'] as String? ?? '') ?? DateTime.now(),
      );
    }).toList();

    return PullResult(
      events: events,
      cursor: json['cursor'] as String? ?? cursor,
      hasMore: json['has_more'] as bool? ?? false,
    );
  }

  /// Check sync status for this device.
  Future<Map<String, dynamic>> getStatus({
    required String deviceId,
    required String tenantId,
    String cursor = '',
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/sync/status').replace(
      queryParameters: {
        'device_id': deviceId,
        'tenant_id': tenantId,
        if (cursor.isNotEmpty) 'cursor': cursor,
      },
    );
    final response =
        await _client.get(uri, headers: await _headers()).timeout(timeout);
    if (response.statusCode != 200) {
      throw SyncApiException('Status check failed: ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  void dispose() => _client.close();
}

/// Exception thrown when the sync API returns an error.
class SyncApiException implements Exception {
  const SyncApiException(this.message);
  final String message;

  @override
  String toString() => 'SyncApiException: $message';
}
