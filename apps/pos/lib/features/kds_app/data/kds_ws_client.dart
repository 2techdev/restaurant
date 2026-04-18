/// WebSocket client for the KDS real-time hub (`/ws/kds`).
///
/// Subscribes to `new_ticket`, `status_update`, and `ticket_closed`
/// notifications broadcast by the GastroCore Go server. Mirrors the
/// resilience pattern used by [PosWsClient]:
///   - Exponential back-off reconnect (cap: 60s).
///   - Heartbeat ping every [heartbeatInterval]; silence for two intervals
///     tears down and reconnects.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

/// One real-time event pushed by the server to the KDS.
///
/// `type` mirrors the server's [KDSNotification.type] — commonly
/// `new_ticket`, `status_update`, or `ticket_closed`.
class KdsEvent {
  final String type;
  final String? ticketId;
  final String? orderNumber;
  final String? status;
  final DateTime receivedAt;

  const KdsEvent({
    required this.type,
    required this.receivedAt,
    this.ticketId,
    this.orderNumber,
    this.status,
  });

  factory KdsEvent.fromJson(Map<String, dynamic> json) {
    return KdsEvent(
      type: (json['type'] as String?) ?? 'unknown',
      ticketId: json['ticket_id'] as String?,
      orderNumber: json['order_number'] as String?,
      status: json['status'] as String?,
      receivedAt: DateTime.now(),
    );
  }

  @override
  String toString() =>
      'KdsEvent(type: $type, ticketId: $ticketId, status: $status)';
}

/// Connection lifecycle state, surfaced to the UI as a "LIVE" indicator.
enum KdsWsState { disconnected, connecting, connected }

/// Callback invoked for every parsed [KdsEvent].
typedef OnKdsEventCallback = void Function(KdsEvent event);

/// Callback invoked when the connection state changes.
typedef OnKdsStateCallback = void Function(KdsWsState state);

class KdsWsClient {
  KdsWsClient({
    required this.baseUrl,
    required this.tenantId,
    required this.deviceId,
    required this.onEvent,
    this.onState,
    this.station,
    this.heartbeatInterval = const Duration(seconds: 30),
  });

  /// Protocol-agnostic server base URL (http or https). Internally rewritten
  /// to ws/wss for the channel.
  final String baseUrl;
  final String tenantId;
  final String deviceId;
  final String? station;
  final OnKdsEventCallback onEvent;
  final OnKdsStateCallback? onState;
  final Duration heartbeatInterval;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  DateTime? _lastMessageAt;

  bool _disposed = false;
  int _attempt = 0;
  KdsWsState _state = KdsWsState.disconnected;

  KdsWsState get state => _state;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  void connect() {
    if (_disposed) return;
    _cancelAll();
    _setState(KdsWsState.connecting);

    try {
      final wsBase = baseUrl.replaceFirst(RegExp(r'^http'), 'ws');
      final qp = {
        'tenant_id': tenantId,
        'device_id': deviceId,
        if (station != null && station!.isNotEmpty) 'station': station!,
      };
      final query = qp.entries
          .map((e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');
      final uri = Uri.parse('$wsBase/ws/kds?$query');

      _channel = WebSocketChannel.connect(uri);
      _subscription = _channel!.stream.listen(
        _onRawMessage,
        onError: (_) => _scheduleReconnect(),
        onDone: _onDone,
      );
      _startHeartbeat();
      _attempt = 0;
      _setState(KdsWsState.connected);
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void dispose() {
    _disposed = true;
    _cancelAll();
    _channel?.sink.close();
    _setState(KdsWsState.disconnected);
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  void _onRawMessage(dynamic data) {
    _lastMessageAt = DateTime.now();
    try {
      final raw = data is String ? data : data.toString();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final type = json['type'] as String?;
      if (type == 'pong' || type == null) return;
      onEvent(KdsEvent.fromJson(json));
    } catch (_) {
      // Ignore malformed frames — never crash the KDS screen.
    }
  }

  void _onDone() {
    if (_disposed) return;
    _setState(KdsWsState.disconnected);
    _scheduleReconnect();
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
      _setState(KdsWsState.disconnected);
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
    _setState(KdsWsState.disconnected);
    final delaySecs = min(60, pow(2, _attempt).toInt());
    _attempt++;
    _reconnectTimer = Timer(Duration(seconds: delaySecs), connect);
  }

  void _setState(KdsWsState next) {
    if (_state == next) return;
    _state = next;
    onState?.call(next);
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
