/// SSE client for secondary devices — subscribes to the primary's event stream.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'lan_sync_models.dart';

/// Connects to the primary device's SSE endpoint and delivers [SyncMessage]s.
///
/// Features:
/// - Automatic reconnect with exponential backoff (1 s → 64 s cap)
/// - Skips SSE comment lines (`: ping`)
/// - Handles partial line buffering across chunks
///
/// Usage:
/// ```dart
/// final client = SseClient(
///   primaryBaseUrl: 'http://192.168.1.10:52374',
///   deviceId: 'DEV-WAITER-01',
///   onMessage: (msg) => applyMessage(msg),
/// );
/// client.start();
/// // ...
/// client.stop();
/// ```
class SseClient {
  SseClient({
    required this.primaryBaseUrl,
    required this.deviceId,
    required this.onMessage,
    this.onConnected,
    this.onDisconnected,
    this.onError,
    this.maxBackoffSeconds = 64,
  });

  final String primaryBaseUrl;
  final String deviceId;

  /// Called for each decoded [SyncMessage] received from the primary.
  final void Function(SyncMessage message) onMessage;

  final void Function()? onConnected;
  final void Function()? onDisconnected;
  final void Function(Object error)? onError;

  /// Maximum reconnect wait time in seconds.
  final int maxBackoffSeconds;

  bool _active = false;
  int _retryCount = 0;
  Timer? _reconnectTimer;
  StreamSubscription<String>? _lineSub;
  http.Client? _httpClient;

  // SSE line-buffer state.
  final StringBuffer _dataBuffer = StringBuffer();

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  bool get isConnected => _lineSub != null;

  void start() {
    _active = true;
    _connect();
  }

  void stop() {
    _active = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _lineSub?.cancel();
    _lineSub = null;
    _httpClient?.close();
    _httpClient = null;
    onDisconnected?.call();
  }

  // ---------------------------------------------------------------------------
  // Connection logic
  // ---------------------------------------------------------------------------

  Future<void> _connect() async {
    if (!_active) return;

    _dataBuffer.clear();

    try {
      final uri = Uri.parse('$primaryBaseUrl/sync/events').replace(
        queryParameters: {'device_id': deviceId},
      );

      _httpClient = http.Client();
      final request = http.Request('GET', uri)
        ..headers['Accept'] = 'text/event-stream'
        ..headers['Cache-Control'] = 'no-cache';

      final response = await _httpClient!.send(request);

      if (response.statusCode != 200) {
        throw Exception('SSE connect failed: HTTP ${response.statusCode}');
      }

      _retryCount = 0;
      onConnected?.call();

      _lineSub = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            _onLine,
            onDone: _onStreamDone,
            onError: _onStreamError,
            cancelOnError: true,
          );
    } catch (e) {
      onError?.call(e);
      _scheduleReconnect();
    }
  }

  // ---------------------------------------------------------------------------
  // SSE line parsing
  // ---------------------------------------------------------------------------

  void _onLine(String line) {
    if (line.startsWith(': ')) {
      // SSE comment (keep-alive ping) — ignore.
      return;
    }

    if (line.startsWith('data: ')) {
      _dataBuffer.write(line.substring(6));
    } else if (line.isEmpty) {
      // Blank line = end of SSE event.
      final raw = _dataBuffer.toString().trim();
      _dataBuffer.clear();
      if (raw.isNotEmpty) _dispatch(raw);
    }
    // Ignore `event:`, `id:`, `retry:` fields for now.
  }

  void _dispatch(String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final message = SyncMessage.fromJson(json);
      onMessage(message);
    } catch (_) {
      // Malformed event — silently drop.
    }
  }

  // ---------------------------------------------------------------------------
  // Reconnect
  // ---------------------------------------------------------------------------

  void _onStreamDone() {
    _cleanup();
    _scheduleReconnect();
  }

  void _onStreamError(Object error) {
    onError?.call(error);
    _cleanup();
    _scheduleReconnect();
  }

  void _cleanup() {
    _lineSub?.cancel();
    _lineSub = null;
    _httpClient?.close();
    _httpClient = null;
    onDisconnected?.call();
  }

  void _scheduleReconnect() {
    if (!_active) return;
    // Exponential backoff: 1, 2, 4, 8, 16, 32, 64 seconds.
    final seconds = (1 << _retryCount).clamp(1, maxBackoffSeconds);
    _retryCount = (_retryCount + 1).clamp(0, 7);
    _reconnectTimer = Timer(Duration(seconds: seconds), _connect);
  }
}
