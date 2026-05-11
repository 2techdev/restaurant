/// Tests for [ConnectionStrategy] — the WS reconnect state machine that
/// sits on top of [NetworkLocator].
///
/// Stubs the locator's scanner so the resolve cycle is hermetic; the
/// strategy's own back-off timers are driven via `tester.async` /
/// `FakeAsync`-style direct calls.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/core/network/connection_strategy.dart';
import 'package:gastrocore_pos/core/network/network_locator.dart';

NetworkLocator _cloudOnly() => NetworkLocator(scanner: (_) async => []);

void main() {
  group('ConnectionStrategy', () {
    test('initial snapshot is idle + discovering', () {
      final loc = _cloudOnly();
      final strat = ConnectionStrategy(locator: loc);
      addTearDown(strat.dispose);
      addTearDown(loc.dispose);

      expect(strat.snapshot.phase, ConnectionPhase.idle);
      expect(strat.snapshot.peerState, NetworkPeerState.discovering);
      expect(strat.snapshot.consecutiveFailures, 0);
    });

    test('markConnected clears failures and lands on connected', () {
      final loc = _cloudOnly();
      final strat = ConnectionStrategy(locator: loc);
      addTearDown(strat.dispose);
      addTearDown(loc.dispose);

      strat.markDisconnected();
      strat.markDisconnected();
      expect(strat.snapshot.consecutiveFailures, 2);

      strat.markConnected();
      expect(strat.snapshot.phase, ConnectionPhase.connected);
      expect(strat.snapshot.consecutiveFailures, 0);
      expect(strat.snapshot.nextRetryAt, isNull);
    });

    test('markDisconnected stays in reconnecting under failure threshold', () {
      final loc = _cloudOnly();
      final strat = ConnectionStrategy(
        locator: loc,
        // Use very long back-offs so the timer never fires mid-test.
        shortBackoff: const Duration(hours: 1),
        longBackoff: const Duration(hours: 1),
        failuresBeforeLongBackoff: 3,
      );
      addTearDown(strat.dispose);
      addTearDown(loc.dispose);

      strat.markDisconnected();
      expect(strat.snapshot.phase, ConnectionPhase.reconnecting);
      expect(strat.snapshot.consecutiveFailures, 1);
      expect(strat.snapshot.nextRetryAt, isNotNull);

      strat.markDisconnected();
      expect(strat.snapshot.consecutiveFailures, 2);
      expect(strat.snapshot.phase, ConnectionPhase.reconnecting);
    });

    test('markDisconnected escalates to cooldown after threshold', () {
      final loc = _cloudOnly();
      final strat = ConnectionStrategy(
        locator: loc,
        shortBackoff: const Duration(hours: 1),
        longBackoff: const Duration(hours: 1),
        failuresBeforeLongBackoff: 3,
      );
      addTearDown(strat.dispose);
      addTearDown(loc.dispose);

      strat.markDisconnected();
      strat.markDisconnected();
      strat.markDisconnected(); // 3rd → cooldown
      expect(strat.snapshot.phase, ConnectionPhase.cooldown);
      expect(strat.snapshot.consecutiveFailures, 3);
    });

    test('snapshots stream emits on every transition', () async {
      final loc = _cloudOnly();
      final strat = ConnectionStrategy(
        locator: loc,
        shortBackoff: const Duration(hours: 1),
        longBackoff: const Duration(hours: 1),
      );
      addTearDown(strat.dispose);
      addTearDown(loc.dispose);

      final phases = <ConnectionPhase>[];
      final sub = strat.snapshots.listen((s) => phases.add(s.phase));
      addTearDown(sub.cancel);

      strat.markDisconnected();
      strat.markConnected();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(phases, containsAll([
        ConnectionPhase.reconnecting,
        ConnectionPhase.connected,
      ]));
    });

    test('forceRetry resolves immediately', () async {
      var scanCalls = 0;
      final loc = NetworkLocator(scanner: (_) async {
        scanCalls++;
        return [];
      });
      final strat = ConnectionStrategy(locator: loc);
      addTearDown(strat.dispose);
      addTearDown(loc.dispose);

      // Drive the locator at least once first so the baseline is cloud.
      await loc.resolve();
      final baseline = scanCalls;

      await strat.forceRetry();
      expect(scanCalls, baseline + 1,
          reason: 'forceRetry should trigger one extra scan');
      expect(strat.snapshot.peerState, NetworkPeerState.cloudFallback);
    });

    test('dispose() closes the stream + leaves phase=closed', () async {
      final loc = _cloudOnly();
      final strat = ConnectionStrategy(locator: loc);
      addTearDown(loc.dispose);

      await strat.dispose();
      expect(strat.snapshot.phase, ConnectionPhase.closed);
      // Marking disconnected after dispose must be a no-op.
      strat.markDisconnected();
      expect(strat.snapshot.phase, ConnectionPhase.closed);
    });
  });

  group('NetworkLocator — manual override + tenant filter + 04:00 cron', () {
    test('manualOverride bypasses mDNS when probe answers', () async {
      var scanCalls = 0;
      final loc = NetworkLocator(
        scanner: (_) async {
          scanCalls++;
          return [
            const DiscoveredPeer(
              host: '10.0.0.99',
              port: 8090,
              roleRaw: 'server',
            ),
          ];
        },
        prober: (host, port) async => host == '192.168.42.42',
      );
      addTearDown(loc.dispose);

      final ep = await loc.setManualOverride(
        host: '192.168.42.42',
        port: 8090,
      );
      expect(ep.source, 'lan');
      expect(ep.peerHost, '192.168.42.42');
      // No mDNS scan was needed — the manual override won outright.
      expect(scanCalls, 0);
    });

    test('manualOverride falling probe falls through to mDNS', () async {
      final loc = NetworkLocator(
        scanner: (_) async => [
          const DiscoveredPeer(
            host: '10.0.0.50',
            port: 8090,
            roleRaw: 'server',
          ),
        ],
        prober: (host, _) async => host == '10.0.0.50',
      );
      addTearDown(loc.dispose);

      final ep = await loc.setManualOverride(host: '192.168.99.99');
      expect(ep.source, 'lan');
      expect(ep.peerHost, '10.0.0.50');
    });

    test('tenantFilter drops peers from other tenants', () async {
      final probed = <String>[];
      final loc = NetworkLocator(
        tenantFilter: 'tenant-A',
        scanner: (_) async => const [
          DiscoveredPeer(
              host: '10.0.0.10', port: 8090, tenantId: 'tenant-A', roleRaw: 'server'),
          DiscoveredPeer(
              host: '10.0.0.20', port: 8090, tenantId: 'tenant-B', roleRaw: 'server'),
        ],
        prober: (host, _) async {
          probed.add(host);
          return true;
        },
      );
      addTearDown(loc.dispose);

      await loc.resolve();
      // Only tenant-A peer reached the prober.
      expect(probed, ['10.0.0.10']);
    });

    test('onPeersDiscovered fires with full scan + healthy set', () async {
      List<DiscoveredPeer>? captured;
      Set<String>? capturedHealthy;
      final loc = NetworkLocator(
        scanner: (_) async => const [
          DiscoveredPeer(host: '10.0.0.5', port: 8090, roleRaw: 'server'),
          DiscoveredPeer(host: '10.0.0.6', port: 8090, roleRaw: 'kds'),
        ],
        prober: (host, _) async => host == '10.0.0.5',
        onPeersDiscovered: (peers, healthy) {
          captured = peers;
          capturedHealthy = healthy;
        },
      );
      addTearDown(loc.dispose);

      await loc.resolve();
      expect(captured, hasLength(2));
      expect(capturedHealthy, {'10.0.0.5'});
    });

    test('nextReprobeAt is null before scheduling', () {
      final loc = NetworkLocator(scanner: (_) async => []);
      addTearDown(loc.dispose);
      expect(loc.nextReprobeAt, isNull);
    });

    test('scheduleDailyReprobeAt computes a future 04:00 by default', () {
      final loc = NetworkLocator(scanner: (_) async => []);
      addTearDown(loc.dispose);
      loc.scheduleDailyReprobeAt();
      final next = loc.nextReprobeAt;
      expect(next, isNotNull);
      expect(next!.hour, 4);
      expect(next.isAfter(DateTime.now()), isTrue,
          reason: 'next 04:00 must always be in the future');
    });
  });
}
