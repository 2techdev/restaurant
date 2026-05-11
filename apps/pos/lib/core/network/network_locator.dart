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
  const DiscoveredPeer({
    required this.host,
    required this.port,
    this.roleRaw,
    this.tenantId,
    this.version,
  });
  final String host;
  final int port;

  /// Raw value of the `role` TXT record (e.g. `server`, `kds`, `waiter`).
  /// Stored as a string so the locator stays free of [PeerRole] coupling;
  /// callers parse via `PeerRole.parse(roleRaw)` if they need the enum.
  final String? roleRaw;

  /// Tenant the peer claims to belong to. The locator filters non-matching
  /// peers out before the registry sees them.
  final String? tenantId;

  /// Optional build version from TXT records — surfaced in the Settings
  /// peer-list for quick mismatch debugging.
  final String? version;
}

/// Callback fired after every discover+probe cycle so the [PeerRegistry]
/// can be refreshed. Receives ALL peers from the scan, plus the healthy
/// flag the locator computed (true for the winner, false for others).
typedef PeersObserver = void Function(List<DiscoveredPeer> peers, Set<String> healthyHosts);

class NetworkLocator {
  NetworkLocator({
    String serviceType = '_gastrocore._tcp.local',
    Duration scanTimeout = const Duration(seconds: 4),
    Duration probeTimeout = const Duration(seconds: 1),
    Duration reprobeInterval = const Duration(hours: 24),
    int reprobeHourLocal = 4,
    String? tenantFilter,
    PeerScanner? scanner,
    HealthProber? prober,
    PeersObserver? onPeersDiscovered,
  })  : _serviceType = serviceType,
        _scanTimeout = scanTimeout,
        _probeTimeout = probeTimeout,
        _reprobeInterval = reprobeInterval,
        _reprobeHourLocal = reprobeHourLocal,
        _tenantFilter = tenantFilter,
        _scanner = scanner,
        _prober = prober,
        _onPeersDiscovered = onPeersDiscovered;

  final String _serviceType;
  final Duration _scanTimeout;
  final Duration _probeTimeout;
  final Duration _reprobeInterval;

  /// Local hour-of-day (0-23) to fire the daily re-probe. Default 04:00 —
  /// every reasonable Swiss / TR restaurant is closed by then so the
  /// scan happens with no operator load.
  final int _reprobeHourLocal;

  /// When non-null, the locator drops any scanned peer whose TXT-record
  /// tenant doesn't match. Prevents a sibling restaurant on the same
  /// shared WiFi (mall food court) from poisoning the registry.
  final String? _tenantFilter;

  final PeerScanner? _scanner;
  final HealthProber? _prober;
  final PeersObserver? _onPeersDiscovered;

  /// Manual override — when set, [resolve()] skips mDNS and trusts this
  /// host:port directly (still HTTP-probes to verify reachability before
  /// declaring lanConnected). Lets an operator type the POS server IP into
  /// Settings when broadcast is blocked (corporate WiFi, etc.).
  String? _manualHost;
  int _manualPort = 8090;

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
      // Priority 1: operator-set manual override. mDNS still runs in the
      // background to keep the peer registry fresh for the Settings list,
      // but the locator commits to the manual host as soon as it answers.
      final manualHost = _manualHost;
      if (manualHost != null && manualHost.isNotEmpty) {
        final ok = await _doProbe(manualHost, _manualPort);
        if (ok) {
          _current = ResolvedEndpoint(
            apiBaseUrl: 'http://$manualHost:$_manualPort',
            wsBaseUrl: 'ws://$manualHost:$_manualPort',
            source: 'lan',
            peerHost: manualHost,
            resolvedAt: DateTime.now(),
          );
          _setState(NetworkPeerState.lanConnected);
          // Notify the registry so the manually-typed peer appears in
          // the Settings list as healthy.
          _onPeersDiscovered?.call(
            [DiscoveredPeer(host: manualHost, port: _manualPort, roleRaw: 'server')],
            {manualHost},
          );
          return _current;
        }
        // Manual override unreachable → fall through to mDNS / cloud.
      }

      // Priority 2: mDNS discovery + parallel HTTP probes.
      final peers = await _doScan();
      // Filter out other tenants if a filter is set (TXT record match).
      final scoped = _tenantFilter == null
          ? peers
          : peers.where((p) => p.tenantId == null || p.tenantId == _tenantFilter).toList();
      final healthyHosts = <String>{};
      DiscoveredPeer? winner;
      for (final peer in scoped) {
        final ok = await _doProbe(peer.host, peer.port);
        if (!ok) continue;
        healthyHosts.add(peer.host);
        // Prefer role=server above all others, otherwise first healthy.
        if (winner == null) {
          winner = peer;
        } else if (peer.roleRaw == 'server' && winner.roleRaw != 'server') {
          winner = peer;
        }
      }
      // Surface every discovered peer (healthy or not) to the registry.
      _onPeersDiscovered?.call(scoped, healthyHosts);

      if (winner != null) {
        _current = ResolvedEndpoint(
          apiBaseUrl: 'http://${winner.host}:${winner.port}',
          wsBaseUrl: 'ws://${winner.host}:${winner.port}',
          source: 'lan',
          peerHost: winner.host,
          resolvedAt: DateTime.now(),
        );
        _setState(NetworkPeerState.lanConnected);
        return _current;
      }

      // Priority 3: cloud.
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
  ///
  /// Use [scheduleDailyReprobeAt] for wall-clock-aligned scheduling
  /// (e.g. always 04:00 local time) — the preferred path on pilot
  /// tablets that may have been booted at random hours.
  void startDailyReprobe() {
    _dailyTimer?.cancel();
    _dailyTimer = Timer.periodic(_reprobeInterval, (_) => resolve());
  }

  /// Align the daily re-probe with a wall-clock hour (default constructor
  /// value: 04:00 local). The first fire is at the next occurrence of that
  /// hour, then every 24h. Survives DST shifts because the timer reschedules
  /// itself after each fire — pure `Timer.periodic` would drift by an hour.
  void scheduleDailyReprobeAt({int? hourLocal}) {
    _dailyTimer?.cancel();
    final hour = hourLocal ?? _reprobeHourLocal;
    final next = _nextOccurrenceOfHour(hour);
    final delay = next.difference(DateTime.now());
    _dailyTimer = Timer(delay, () async {
      await resolve();
      // Reschedule for tomorrow — wall-clock aligned, DST safe.
      scheduleDailyReprobeAt(hourLocal: hour);
    });
  }

  /// Next wall-clock occurrence of [hour]:00 local time, strictly in the
  /// future. If it's currently 03:59 and hour=4, returns today 04:00; if
  /// it's 05:00, returns tomorrow 04:00.
  DateTime _nextOccurrenceOfHour(int hour) {
    final now = DateTime.now();
    var target = DateTime(now.year, now.month, now.day, hour);
    if (!target.isAfter(now)) {
      target = target.add(const Duration(days: 1));
    }
    return target;
  }

  /// Returns the next scheduled re-probe time, or null if no timer is
  /// armed. Used by the Settings pane to show "next re-probe: 04:00".
  DateTime? get nextReprobeAt {
    if (_dailyTimer == null || !_dailyTimer!.isActive) return null;
    return _nextOccurrenceOfHour(_reprobeHourLocal);
  }

  /// Operator-typed override (Settings → Sunucu IP). Pass `null` to clear.
  /// Triggers a [resolve()] so the new endpoint takes effect immediately.
  Future<ResolvedEndpoint> setManualOverride({String? host, int port = 8090}) {
    _manualHost = (host != null && host.trim().isEmpty) ? null : host?.trim();
    _manualPort = port;
    return resolve();
  }

  /// Current manual override, or null when none is set. Surfaced in the
  /// Settings pane so the operator can see what they typed.
  ({String host, int port})? get manualOverride {
    final host = _manualHost;
    if (host == null) return null;
    return (host: host, port: _manualPort);
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
