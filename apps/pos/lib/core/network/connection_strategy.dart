/// Connection strategy — the state machine that sits between
/// [NetworkLocator] (decides which endpoint to use) and the WebSocket
/// client (consumes the endpoint). The strategy:
///
///   1. Watches the locator's [NetworkPeerState] stream.
///   2. Owns the WebSocket re-connect debounce: when the socket reports
///      a disconnect, wait 5 s and re-resolve. If the previous endpoint
///      is still healthy we just reconnect to it; if not, the locator
///      hands back a different endpoint (possibly cloud).
///   3. Tracks consecutive failures so unstable links don't burn the
///      retry budget — backs off to 30 s after 3 quick failures.
///
/// The actual WebSocket connection lives in `lib/features/sync/data/...`
/// (`websocket_sync_client.dart`). This strategy is a thin coordinator
/// that exposes a "should we reconnect now?" signal so the WS client can
/// stay simple. The two are wired together via Riverpod in a follow-up
/// commit; this commit ships the state machine + tests.
library;

import 'dart:async';

import 'package:gastrocore_pos/core/network/network_locator.dart';

/// What the connection strategy is currently doing — finer-grained than
/// [NetworkPeerState] so the Settings UI can distinguish "WS connected"
/// from "WS waiting 5 s before retry".
enum ConnectionPhase {
  /// Initial state — no connect attempt yet.
  idle,

  /// Locator is resolving the endpoint (first time or after a disconnect).
  resolving,

  /// WebSocket is live on the active endpoint.
  connected,

  /// WS dropped, 5-s back-off timer running.
  reconnecting,

  /// Repeated failures — extended back-off (30 s).
  cooldown,

  /// Strategy was disposed (e.g. tenant switch).
  closed,
}

class ConnectionSnapshot {
  const ConnectionSnapshot({
    required this.phase,
    required this.peerState,
    this.endpoint,
    this.consecutiveFailures = 0,
    this.nextRetryAt,
  });

  final ConnectionPhase phase;
  final NetworkPeerState peerState;
  final ResolvedEndpoint? endpoint;
  final int consecutiveFailures;
  final DateTime? nextRetryAt;

  ConnectionSnapshot copyWith({
    ConnectionPhase? phase,
    NetworkPeerState? peerState,
    ResolvedEndpoint? endpoint,
    int? consecutiveFailures,
    DateTime? nextRetryAt,
    bool clearNextRetry = false,
  }) =>
      ConnectionSnapshot(
        phase: phase ?? this.phase,
        peerState: peerState ?? this.peerState,
        endpoint: endpoint ?? this.endpoint,
        consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
        nextRetryAt: clearNextRetry ? null : (nextRetryAt ?? this.nextRetryAt),
      );
}

class ConnectionStrategy {
  ConnectionStrategy({
    required NetworkLocator locator,
    Duration shortBackoff = const Duration(seconds: 5),
    Duration longBackoff = const Duration(seconds: 30),
    int failuresBeforeLongBackoff = 3,
  })  : _locator = locator,
        _shortBackoff = shortBackoff,
        _longBackoff = longBackoff,
        _failuresBeforeLong = failuresBeforeLongBackoff {
    _sub = _locator.stateChanges.listen((next) {
      _snapshot = _snapshot.copyWith(
        peerState: next,
        endpoint: _locator.current,
      );
      _snapshotCtrl.add(_snapshot);
    });
  }

  final NetworkLocator _locator;
  final Duration _shortBackoff;
  final Duration _longBackoff;
  final int _failuresBeforeLong;

  StreamSubscription<NetworkPeerState>? _sub;
  Timer? _retryTimer;
  final _snapshotCtrl = StreamController<ConnectionSnapshot>.broadcast();

  ConnectionSnapshot _snapshot = const ConnectionSnapshot(
    phase: ConnectionPhase.idle,
    peerState: NetworkPeerState.discovering,
  );

  ConnectionSnapshot get snapshot => _snapshot;
  Stream<ConnectionSnapshot> get snapshots => _snapshotCtrl.stream;

  /// Mark the WS as freshly connected — resets failure counter and arms
  /// the "connected" phase. Callers (the WS client) invoke this on a
  /// successful handshake.
  void markConnected() {
    _retryTimer?.cancel();
    _snapshot = _snapshot.copyWith(
      phase: ConnectionPhase.connected,
      consecutiveFailures: 0,
      clearNextRetry: true,
    );
    _snapshotCtrl.add(_snapshot);
  }

  /// Mark the WS as disconnected — schedules a back-off retry. Callers
  /// invoke this when the socket emits an error or close frame. The
  /// strategy decides whether to re-resolve (LAN→cloud swap) or just
  /// reconnect to the existing endpoint based on the locator's most
  /// recent state.
  void markDisconnected({Object? error}) {
    if (_snapshot.phase == ConnectionPhase.closed) return;
    final failures = _snapshot.consecutiveFailures + 1;
    final backoff =
        failures >= _failuresBeforeLong ? _longBackoff : _shortBackoff;
    final retryAt = DateTime.now().add(backoff);
    final phase = failures >= _failuresBeforeLong
        ? ConnectionPhase.cooldown
        : ConnectionPhase.reconnecting;

    _snapshot = _snapshot.copyWith(
      phase: phase,
      consecutiveFailures: failures,
      nextRetryAt: retryAt,
    );
    _snapshotCtrl.add(_snapshot);

    _retryTimer?.cancel();
    _retryTimer = Timer(backoff, _retry);
  }

  /// Manually force a re-resolve + connect attempt (Settings → Şimdi yenile).
  Future<void> forceRetry() async {
    _retryTimer?.cancel();
    await _retry();
  }

  Future<void> _retry() async {
    if (_snapshot.phase == ConnectionPhase.closed) return;
    _snapshot = _snapshot.copyWith(
      phase: ConnectionPhase.resolving,
      clearNextRetry: true,
    );
    _snapshotCtrl.add(_snapshot);
    // Trigger a fresh resolve — the locator's stateChanges listener will
    // update the snapshot's peerState + endpoint. WS client should react
    // to that and call markConnected / markDisconnected accordingly.
    await _locator.resolve();
  }

  Future<void> dispose() async {
    _snapshot =
        _snapshot.copyWith(phase: ConnectionPhase.closed, clearNextRetry: true);
    _retryTimer?.cancel();
    await _sub?.cancel();
    if (!_snapshotCtrl.isClosed) await _snapshotCtrl.close();
  }
}
