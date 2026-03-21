/// Shelf endpoint handlers for sync status and handshake.
library;

import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../lan_sync_models.dart';

/// GET  /sync/status     — health check + current sync cursor.
/// POST /sync/handshake  — secondary device registration (handled in
///                         [LanSyncService], but cursor access is here).
class SyncStatusEndpoint {
  SyncStatusEndpoint({
    required this.primaryDeviceId,
    required this.primaryDeviceName,
    required this.tenantId,
    required this.getCursor,
    required this.getConnectedPeerCount,
  });

  final String primaryDeviceId;
  final String primaryDeviceName;
  final String tenantId;

  /// Returns the current sync cursor (used by secondaries to resume from).
  final Future<String> Function() getCursor;

  /// Returns the number of currently connected secondary devices.
  final int Function() getConnectedPeerCount;

  // ---------------------------------------------------------------------------

  Future<Response> getStatus(Request request) async {
    try {
      final cursor = await getCursor();
      return Response.ok(
        jsonEncode({
          'primary_device_id': primaryDeviceId,
          'primary_device_name': primaryDeviceName,
          'tenant_id': tenantId,
          'cursor': cursor,
          'connected_peers': getConnectedPeerCount(),
          'server_time': DateTime.now().toUtc().toIso8601String(),
        }),
        headers: _json,
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: _json,
      );
    }
  }

  /// Used by [LanSyncService._handleHandshake] to embed the cursor in the
  /// [HandshakeResponse].
  Future<String> getCurrentCursor() => getCursor();
}

const _json = {'Content-Type': 'application/json'};
