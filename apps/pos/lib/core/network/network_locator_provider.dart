/// Riverpod wiring for [NetworkLocator] — exposes the singleton + a
/// reactive [ResolvedEndpoint] state that other providers (sync HTTP /
/// WebSocket) can watch instead of the static [AppEndpoints] constants.
///
/// Wire-up pattern at app boot (main_waiter / main_kds / main):
///   ```dart
///   final locator = NetworkLocator();
///   await locator.resolve();           // bootstrap once before runApp
///   locator.startDailyReprobe();       // schedule the 24h refresh
///   container = ProviderContainer(overrides: [
///     networkLocatorProvider.overrideWithValue(locator),
///     ...
///   ]);
///   ```
///
/// Settings UI reads [networkEndpointStateProvider] for the live state and
/// can call `ref.read(networkLocatorProvider).resolve()` to force-refresh.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/config/app_endpoints.dart';
import 'package:gastrocore_pos/core/network/network_locator.dart';

/// The shared [NetworkLocator] singleton.
///
/// Must be overridden at the app root — the default UnimplementedError
/// is a fail-fast so a forgotten override is loud rather than silently
/// shipping cloud-only.
final networkLocatorProvider = Provider<NetworkLocator>((ref) {
  throw UnimplementedError(
    'networkLocatorProvider must be overridden in main_{flavor}.dart with '
    'a bootstrapped NetworkLocator instance. See core/network/network_locator.dart.',
  );
});

/// StateNotifier-style provider that mirrors the locator's [stateChanges]
/// stream + current endpoint as a single [NetworkEndpointSnapshot]. UI
/// widgets watch this to render the connection pill.
final networkEndpointStateProvider =
    StateNotifierProvider<NetworkEndpointNotifier, NetworkEndpointSnapshot>(
  (ref) {
    final locator = ref.watch(networkLocatorProvider);
    return NetworkEndpointNotifier(locator);
  },
);

/// Convenience derived providers — these override the existing
/// `syncServerUrlProvider` / `wsServerUrlProvider` so SyncApiClient and
/// WebSocketSyncClient automatically pick up the resolved endpoint. The
/// override is wired in the flavor boot code (main_waiter, main_kds).
final resolvedApiBaseUrlProvider = Provider<String>((ref) {
  return ref.watch(networkEndpointStateProvider).endpoint.apiBaseUrl;
});

final resolvedWsBaseUrlProvider = Provider<String>((ref) {
  return ref.watch(networkEndpointStateProvider).endpoint.wsBaseUrl;
});

// ---------------------------------------------------------------------------
// State + notifier
// ---------------------------------------------------------------------------

class NetworkEndpointSnapshot {
  const NetworkEndpointSnapshot({
    required this.state,
    required this.endpoint,
  });

  final NetworkPeerState state;
  final ResolvedEndpoint endpoint;

  NetworkEndpointSnapshot copyWith({
    NetworkPeerState? state,
    ResolvedEndpoint? endpoint,
  }) =>
      NetworkEndpointSnapshot(
        state: state ?? this.state,
        endpoint: endpoint ?? this.endpoint,
      );

  bool get isLan => endpoint.isLan;
}

class NetworkEndpointNotifier extends StateNotifier<NetworkEndpointSnapshot> {
  NetworkEndpointNotifier(this._locator)
      : super(NetworkEndpointSnapshot(
          state: _locator.state,
          endpoint: _locator.current,
        )) {
    _sub = _locator.stateChanges.listen((peerState) {
      state = state.copyWith(
        state: peerState,
        endpoint: _locator.current,
      );
    });
  }

  final NetworkLocator _locator;
  StreamSubscription<NetworkPeerState>? _sub;

  /// Manually force a re-probe — wired to the "Şimdi yenile" button on the
  /// Settings → Bağlantı Durumu pane.
  Future<void> reprobe() async {
    await _locator.resolve();
    state = state.copyWith(
      state: _locator.state,
      endpoint: _locator.current,
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Cloud-only fallback (development / tests without an override).
// ---------------------------------------------------------------------------

/// A no-op locator that always reports "cloud" — used as the dev default
/// when a flavor boot file hasn't been migrated yet. NOT injected by
/// default (the provider above throws on read); flavors must opt in.
NetworkLocator cloudOnlyLocator() {
  return NetworkLocator(
    scanner: (_) async => const [],
    prober: (_, __) async => false,
  )..resolve();
}

/// Sentinel constants reused across the Settings UI + tests so a refactor
/// of the source string only touches one place.
class NetworkEndpointSources {
  static const lan = 'lan';
  static const cloud = 'cloud';
}

/// Re-export to keep callers in one import line.
String get cloudApiBase => AppEndpoints.apiBaseUrl;
String get cloudWsBase => AppEndpoints.wsBaseUrl;
