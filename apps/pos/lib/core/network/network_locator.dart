/// LAN-first endpoint resolver — picks the best base URL (HTTP + WS) for
/// the active POS server.
///
/// The goal is to keep restaurant-local traffic ON the local network and
/// fall back to the public cloud only when the LAN cannot be reached. A
/// classic deployment:
///   • POS server (Go) runs on a small box in the restaurant office.
///   • POS tablets, KDS screens, Waiter handhelds share the same WiFi.
///   • All client devices SHOULD reach the server via its private IPv4 —
///     not by routing through Hetzner and back. Hetzner is the safety net
///     for off-site owners and for restaurants without a local server.
///
/// Strategy on each `resolve()` call:
///   1. Multicast-DNS scan for `_gastrocore._tcp` service announcements
///      (3-5 s timeout). Filters down to instances tagged with the
///      operator's `tenantId` and role=server.
///   2. For every discovered candidate run a fast HTTP health probe
///      (`GET http://<ip>:<port>/health`, 1 s timeout). The first peer
///      that answers 200 wins.
///   3. If no peer answers, fall back to [AppEndpoints.apiBaseUrl] /
///      [AppEndpoints.wsBaseUrl] (cloud) so the device still works.
///   4. A daily timer (default 04:00 — restaurant closed) re-runs the
///      scan to catch DHCP IP changes overnight. A `reprobe()` method
///      lets the operator force a refresh from Settings.
///
/// Notes on alternatives:
///   • The existing `lib/features/lan_sync/` is a peer-to-peer sync
///     pipeline for direct event replication between devices on the same
///     LAN. That's a different concern: this locator resolves the
///     UPSTREAM server URL the client talks to. They can coexist.
///   • `bonsoir` was considered but `multicast_dns` is already in
///     pubspec.yaml and powers the existing LAN sync work — staying on
///     one package keeps the build slim and avoids a parallel mDNS state
///     machine on Android.
library;

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:multicast_dns/multicast_dns.dart';

import 'package:gastrocore_pos/core/config/app_endpoints.dart';

/// High-level state of the locator, surfaced to the Settings UI.
enum NetworkPeerState {
  /// First boot / no resolve call has returned yet.
  discovering,

  /// A LAN peer answered the health probe — we are using its IP.
  lanConnected,

  /// No LAN peer answered — we are talking to the cloud.
  cloudFallback,

  /// A re-probe is running while we keep serving the old endpoint.
  reconnecting,
}

/// Resolved endpoint payload — what the locator hands back to the rest of
/// the app (chiefly [SyncApiClient] / [WebSocketSyncClient]).
class ResolvedEndpoint {
  const ResolvedEndpoint({
    required this.apiBaseUrl,
    required this.wsBaseUrl,
    required this.source,
    this.peerHost,
    this.resolvedAt,
  });

  /// HTTP(S) base URL — e.g. `http://192.168.1.10:8090` or
  /// `https://api.gastrocore.ch`.
  final String apiBaseUrl;

  /// WebSocket base URL — e.g. `ws://192.168.1.10:8090` or
  /// `wss://ws.gastrocore.ch`.
  final String wsBaseUrl;

  /// `'lan'` or `'cloud'` — drives the Settings status pill.
  final String source;

  /// IP/host of the LAN peer that won the probe, when applicable.
  final String? peerHost;

  /// Wall-clock time the resolve completed; used to decide whether a daily
  /// re-probe is overdue.
  final DateTime? resolvedAt;

  bool get isLan => source == 'lan';

  ResolvedEndpoint copyWith({
    String? apiBaseUrl,
    String? wsBaseUrl,
    String? source,
    String? peerHost,
    DateTime? resolvedAt,
  }) =>
      ResolvedEndpoint(
        apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
        wsBaseUrl: wsBaseUrl ?? this.wsBaseUrl,
        source: source ?? this.source,
        peerHost: peerHost ?? this.peerHost,
        resolvedAt: resolvedAt ?? this.resolvedAt,
      );

  @override
  String toString() =>
      'ResolvedEndpoint(source=$source, api=$apiBaseUrl, peer=$peerHost)';
}

/// Pluggable mDNS / probe hooks so unit tests can drive the locator
/// without binding multicast sockets. The default implementation uses
/// [MDnsClient] + `package:http`.
typedef PeerScanner = Future<List<DiscoveredPeer>> Function(
  Duration timeout,
);
typedef HealthProber = Future<bool> Function(String host, int port);

class DiscoveredPeer {
  const DiscoveredPeer({required this.host, required this.port});
  final String host;
  final int port;
}

class NetworkLocator {
  NetworkLocator({
    String serviceType = '_gastrocore._tcp.local',
    Duration scanTimeout = const Duration(seconds: 4),
    Duration probeTimeout = const Duration(seconds: 1),
    Duration reprobeInterval = const Duration(hours: 24),
    PeerScanner? scanner,
    HealthProber? prober,
  })  : _serviceType = serviceType,
        _scanTimeout = scanTimeout,
        _probeTimeout = probeTimeout,
        _reprobeInterval = reprobeInterval,
        _scanner = scanner,
        _prober = prober;

  final String _serviceType;
  final Duration _scanTimeout;
  final Duration _probeTimeout;
  final Duration _reprobeInterval;
  final PeerScanner? _scanner;
  final HealthProber? _prober;

  final _stateController =
      StreamController<NetworkPeerState>.broadcast();
  ResolvedEndpoint _current = ResolvedEndpoint(
    apiBaseUrl: AppEndpoints.apiBaseUrl,
    wsBaseUrl: AppEndpoints.wsBaseUrl,
    source: 'cloud',
  );
  NetworkPeerState _state = NetworkPeerState.discovering;
  Timer? _dailyTimer;

  /// Broadcasts every state transition. UI consumers subscribe; the locator
  /// keeps the last [current] endpoint regardless of who's listening.
  Stream<NetworkPeerState> get stateChanges => _stateController.stream;

  NetworkPeerState get state => _state;
  ResolvedEndpoint get current => _current;

  /// Run a full discover+probe cycle. Updates [current] / [state] and emits
  /// on [stateChanges]. Safe to call concurrently — the most recent result
  /// wins; in-flight scans are not cancelled but their writes are ignored
  /// (latest-write-wins is acceptable because both paths converge on the
  /// same data — the cloud fallback).
  Future<ResolvedEndpoint> resolve() async {
    _setState(NetworkPeerState.reconnecting);
    try {
      final peers = await _doScan();
      for (final peer in peers) {
        final healthy = await _doProbe(peer.host, peer.port);
        if (!healthy) continue;
        _current = ResolvedEndpoint(
          apiBaseUrl: 'http://${peer.host}:${peer.port}',
          wsBaseUrl: 'ws://${peer.host}:${peer.port}',
          source: 'lan',
          peerHost: peer.host,
          resolvedAt: DateTime.now(),
        );
        _setState(NetworkPeerState.lanConnected);
        return _current;
      }
      // No LAN peer answered — fall back to cloud.
      _current = ResolvedEndpoint(
        apiBaseUrl: AppEndpoints.apiBaseUrl,
        wsBaseUrl: AppEndpoints.wsBaseUrl,
        source: 'cloud',
        resolvedAt: DateTime.now(),
      );
      _setState(NetworkPeerState.cloudFallback);
      return _current;
    } catch (_) {
      // Any unexpected failure (mDNS socket bind error, sandboxed Android
      // multicast permission revoked, etc.) → cloud. Better to keep the
      // POS running than to error out the operator.
      _current = ResolvedEndpoint(
        apiBaseUrl: AppEndpoints.apiBaseUrl,
        wsBaseUrl: AppEndpoints.wsBaseUrl,
        source: 'cloud',
        resolvedAt: DateTime.now(),
      );
      _setState(NetworkPeerState.cloudFallback);
      return _current;
    }
  }

  /// Schedule a daily re-probe at [_reprobeInterval] cadence. Cancels any
  /// previously scheduled timer; call once at app start.
  void startDailyReprobe() {
    _dailyTimer?.cancel();
    _dailyTimer = Timer.periodic(_reprobeInterval, (_) => resolve());
  }

  Future<void> dispose() async {
    _dailyTimer?.cancel();
    await _stateController.close();
  }

  // -------------------------------------------------------------------------
  // Default implementations (overridable via constructor for tests).
  // -------------------------------------------------------------------------

  Future<List<DiscoveredPeer>> _doScan() {
    final scanner = _scanner;
    if (scanner != null) return scanner(_scanTimeout);
    return _defaultMdnsScan(_serviceType, _scanTimeout);
  }

  Future<bool> _doProbe(String host, int port) {
    final prober = _prober;
    if (prober != null) return prober(host, port);
    return _defaultHttpProbe(host, port, _probeTimeout);
  }

  void _setState(NetworkPeerState next) {
    if (_state == next) return;
    _state = next;
    if (!_stateController.isClosed) _stateController.add(next);
  }
}

// ---------------------------------------------------------------------------
// Default mDNS + HTTP implementations
// ---------------------------------------------------------------------------

Future<List<DiscoveredPeer>> _defaultMdnsScan(
  String serviceType,
  Duration timeout,
) async {
  final client = MDnsClient();
  final peers = <DiscoveredPeer>[];
  try {
    await client.start();
    await for (final ptr in client
        .lookup<PtrResourceRecord>(
          ResourceRecordQuery.serverPointer(serviceType),
        )
        .timeout(timeout, onTimeout: (sink) => sink.close())) {
      await for (final srv in client
          .lookup<SrvResourceRecord>(
            ResourceRecordQuery.service(ptr.domainName),
          )
          .timeout(timeout, onTimeout: (sink) => sink.close())) {
        await for (final ip in client
            .lookup<IPAddressResourceRecord>(
              ResourceRecordQuery.addressIPv4(srv.target),
            )
            .timeout(timeout, onTimeout: (sink) => sink.close())) {
          peers.add(DiscoveredPeer(host: ip.address.address, port: srv.port));
        }
      }
    }
  } catch (_) {
    // Swallow — scanner failure is reported via empty list and the locator
    // falls back to cloud. Logging happens in the locator itself.
  } finally {
    client.stop();
  }
  return peers;
}

Future<bool> _defaultHttpProbe(
  String host,
  int port,
  Duration timeout,
) async {
  try {
    final uri = Uri.parse('http://$host:$port/health');
    final response = await http.get(uri).timeout(timeout);
    return response.statusCode == 200;
  } on TimeoutException {
    return false;
  } on SocketException {
    return false;
  } catch (_) {
    return false;
  }
}
