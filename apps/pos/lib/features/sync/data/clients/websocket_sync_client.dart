/// WebSocket client for real-time sync notifications.
library;

import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Callback when new events are available to pull.
typedef OnNewEventsCallback = void Function(int count);

/// WebSocket client that maintains a connection to the sync hub.
///
/// Features:
///  - Auto-reconnect with [reconnectDelay] on any error or disconnect.
///  - Heartbeat: sends `{"type":"ping"}` every [heartbeatInterval] and
///    expects either a `{"type":"pong"}` or any server message within that
///    window. If the server goes silent for two consecutive intervals the
///    connection is torn down and reconnected.
///  - When the server pushes a "new_events" notification, [onNewEvents] is
///    called so the sync engine can pull immediately.
class WebSocketSyncClient {
  WebSocketSyncClient({
    required this.baseUrl,
    required this.deviceId,
    required this.tenantId,
    required this.onNewEvents,
    this.reconnectDelay = const Duration(seconds: 5),
    this.heartbeatInterval = const Duration(seconds: 30),
  });

  final String baseUrl;
  final String deviceId;
  final String tenantId;
  final OnNewEventsCallback onNewEvents;
  final Duration reconnectDelay;
  final Duration heartbeatInterval;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  bool _disposed = false;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;

  /// Timestamp of the last received message (any type).
  DateTime? _lastMessageAt;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Connect to the WebSocket sync hub.
  void connect() {
    if (_disposed) return;
    _subscription?.cancel();
    _reconnectTimer?.cancel();
    _stopHeartbeat();

    try {
      final wsBase = baseUrl.replaceFirst(RegExp(r'^http'), 'ws');
      final uri = Uri.parse(
        '$wsBase/ws/sync?device_id=$deviceId&tenant_id=$tenantId',
      );

      _channel = WebSocketChannel.connect(uri);
      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );

      _startHeartbeat();
    } catch (e) {
      _scheduleReconnect();
    }
  }

  /// Disconnect and release resources.
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _stopHeartbeat();
    _subscription?.cancel();
    _channel?.sink.close();
  }

  // ---------------------------------------------------------------------------
  // Heartbeat
  // ---------------------------------------------------------------------------

  void _startHeartbeat() {
    _lastMessageAt = DateTime.now();
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) => _sendPing());
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _sendPing() {
    if (_disposed || _channel == null) return;

    // If the server has been silent for more than two heartbeat intervals,
    // the connection is stale — reconnect.
    final lastMsg = _lastMessageAt;
    if (lastMsg != null &&
        DateTime.now().difference(lastMsg) > heartbeatInterval * 2) {
      _stopHeartbeat();
      _subscription?.cancel();
      _channel?.sink.close();
      _scheduleReconnect();
      return;
    }

    try {
      _channel!.sink.add(jsonEncode({'type': 'ping'}));
    } catch (_) {
      _scheduleReconnect();
    }
  }

  // ---------------------------------------------------------------------------
  // Stream callbacks
  // ---------------------------------------------------------------------------

  void _onMessage(dynamic data) {
    _lastMessageAt = DateTime.now();

    try {
      final json = jsonDecode(data as String) as Map<String, dynamic>;
      final type = json['type'] as String?;

      if (type == 'new_events') {
        final count = (json['count'] as num?)?.toInt() ?? 1;
        onNewEvents(count);
      }
      // pong and other control messages are handled implicitly by updating
      // _lastMessageAt above — no further action needed.
    } catch (_) {
      // Ignore malformed messages.
    }
  }

  void _onError(Object error) => _scheduleReconnect();

  void _onDone() {
    if (!_disposed) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _stopHeartbeat();
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(reconnectDelay, connect);
  }
}
