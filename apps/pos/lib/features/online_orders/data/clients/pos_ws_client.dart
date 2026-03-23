/// WebSocket client that receives real-time online order pushes from the
/// GastroCore server POS hub.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Callback invoked when a WebSocket message arrives.
typedef OnPOSMessageCallback = void Function(Map<String, dynamic> message);

/// WebSocket client for the POS hub (`/ws/pos`).
///
/// Features:
/// - Auto-reconnect with exponential back-off (cap: 60 s).
/// - Heartbeat: sends `{"type":"ping"}` every [heartbeatInterval]; if the
///   server is silent for two consecutive intervals the socket is torn down
///   and a reconnect is scheduled.
/// - Forwards every decoded JSON message to [onMessage].
class PosWsClient {
  PosWsClient({
    required this.baseUrl,
    required this.tenantId,
    required this.deviceId,
    required this.onMessage,
    this.heartbeatInterval = const Duration(seconds: 30),
  });

  final String baseUrl;
  final String tenantId;
  final String deviceId;
  final OnPOSMessageCallback onMessage;
  final Duration heartbeatInterval;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  DateTime? _lastMessageAt;

  bool _disposed = false;
  int _attempt = 0; // for exponential back-off

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  void connect() {
    if (_disposed) return;
    _cancelAll();

    try {
      final wsBase = baseUrl.replaceFirst(RegExp(r'^http'), 'ws');
      final uri = Uri.parse(
        '$wsBase/ws/pos?tenant_id=$tenantId&device_id=$deviceId',
      );
      _channel = WebSocketChannel.connect(uri);
      _subscription = _channel!.stream.listen(
        _onRawMessage,
        onError: (_) => _scheduleReconnect(),
        onDone: _onDone,
      );
      _startHeartbeat();
      _attempt = 0;
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void dispose() {
    _disposed = true;
    _cancelAll();
    _channel?.sink.close();
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  void _onRawMessage(dynamic data) {
    _lastMessageAt = DateTime.now();
    try {
      final json = jsonDecode(data as String) as Map<String, dynamic>;
      onMessage(json);
    } catch (_) {
      // Ignore malformed frames.
    }
  }

  void _onDone() {
    if (!_disposed) _scheduleReconnect();
  }

  void _startHeartbeat() {
    _lastMessageAt = DateTime.now();
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) => _sendPing());
  }

  void _sendPing() {
    if (_disposed || _channel == null) return;
    final lastMsg = _lastMessageAt;
    if (lastMsg != null &&
        DateTime.now().difference(lastMsg) > heartbeatInterval * 2) {
      _cancelAll();
      _scheduleReconnect();
      return;
    }
    try {
      _channel!.sink.add(jsonEncode({'type': 'ping'}));
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _cancelAll();
    // Exponential back-off: 2^attempt seconds, capped at 60 s.
    final delaySecs = min(60, pow(2, _attempt).toInt());
    _attempt++;
    _reconnectTimer = Timer(Duration(seconds: delaySecs), connect);
  }

  void _cancelAll() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _subscription?.cancel();
    _subscription = null;
  }
}
