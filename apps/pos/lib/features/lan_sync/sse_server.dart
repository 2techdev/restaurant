/// Server-Sent Events broadcaster — runs on the primary device.
library;

import 'dart:async';
import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'lan_sync_models.dart';

/// Manages SSE connections from secondary devices and fans out sync messages.
///
/// Usage:
/// ```dart
/// final server = SseServer();
/// // Mount server.handler on the shelf router at GET /sync/events
/// server.broadcast(message);   // push to all connected secondaries
/// ```
class SseServer {
  final Map<String, _SseConnection> _connections = {};

  /// Number of currently connected secondary devices.
  int get connectionCount => _connections.length;

  /// Shelf handler — secondary devices open a long-lived GET to this endpoint.
  ///
  /// Query parameter `device_id` is used to track the connection.
  Future<Response> handler(Request request) async {
    final deviceId =
        request.url.queryParameters['device_id'] ?? 'unknown-${_connections.length}';

    final controller = StreamController<List<int>>();
    final conn = _SseConnection(deviceId: deviceId, controller: controller);
    _connections[deviceId] = conn;

    // Keep-alive ping every 20 seconds.
    final pingTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!controller.isClosed) {
        controller.add(utf8.encode(': ping\n\n'));
      }
    });

    // Clean up when the stream consumer (HTTP client) disconnects.
    controller.onCancel = () {
      pingTimer.cancel();
      _connections.remove(deviceId);
      if (!controller.isClosed) controller.close();
    };

    // Send a welcome comment so the client knows the stream is live.
    controller.add(utf8.encode(': connected device_id=$deviceId\n\n'));

    return Response.ok(
      controller.stream,
      headers: {
        'Content-Type': 'text/event-stream; charset=utf-8',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
        'X-Accel-Buffering': 'no', // disable nginx proxy buffering
      },
    );
  }

  /// Broadcast [message] to every connected secondary as an SSE event.
  void broadcast(SyncMessage message) {
    _fanOut('data: ${jsonEncode(message.toJson())}\n\n');
  }

  /// Broadcast a typed event (e.g. `table_status`, `shift_closed`).
  void broadcastTyped(String eventType, Map<String, dynamic> payload) {
    _fanOut('event: $eventType\ndata: ${jsonEncode(payload)}\n\n');
  }

  void _fanOut(String text) {
    final bytes = utf8.encode(text);
    final dead = <String>[];
    for (final entry in _connections.entries) {
      if (entry.value.controller.isClosed) {
        dead.add(entry.key);
      } else {
        entry.value.controller.add(bytes);
      }
    }
    for (final id in dead) {
      _connections.remove(id);
    }
  }

  /// Gracefully close all open SSE connections.
  Future<void> closeAll() async {
    for (final conn in _connections.values) {
      if (!conn.controller.isClosed) await conn.controller.close();
    }
    _connections.clear();
  }
}

class _SseConnection {
  const _SseConnection({
    required this.deviceId,
    required this.controller,
  });

  final String deviceId;
  final StreamController<List<int>> controller;
}
