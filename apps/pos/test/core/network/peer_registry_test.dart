/// Tests for [PeerRegistry] — the in-memory list of LAN peers surfaced
/// in Settings → Bağlantı Durumu.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/core/network/peer_registry.dart';

LanPeer _peer({
  required String host,
  PeerRole role = PeerRole.unknown,
  bool healthy = false,
}) {
  return LanPeer(host: host, port: 8090, role: role, healthy: healthy);
}

void main() {
  group('PeerRole.parse', () {
    test('maps known role strings (case-insensitive)', () {
      expect(PeerRole.parse('server'), PeerRole.server);
      expect(PeerRole.parse('KDS'), PeerRole.kds);
      expect(PeerRole.parse('Waiter'), PeerRole.waiter);
      expect(PeerRole.parse('kiosk'), PeerRole.kiosk);
      expect(PeerRole.parse('pos'), PeerRole.pos);
      expect(PeerRole.parse('ods'), PeerRole.ods);
    });

    test('falls back to unknown for null or unrecognised', () {
      expect(PeerRole.parse(null), PeerRole.unknown);
      expect(PeerRole.parse(''), PeerRole.unknown);
      expect(PeerRole.parse('printer'), PeerRole.unknown);
    });
  });

  group('LanPeer equality', () {
    test('equal when host+port match (ignores role/version/healthy)', () {
      final a = _peer(host: '10.0.0.5');
      final b = _peer(host: '10.0.0.5', role: PeerRole.kds, healthy: true);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('not equal when host differs', () {
      expect(_peer(host: '10.0.0.5'),
          isNot(equals(_peer(host: '10.0.0.6'))));
    });
  });

  group('PeerRegistry.replaceAll', () {
    test('puts server peers first, then sorts by role then host', () {
      final reg = PeerRegistry();
      reg.replaceAll([
        _peer(host: '10.0.0.30', role: PeerRole.waiter),
        _peer(host: '10.0.0.10', role: PeerRole.kds),
        _peer(host: '10.0.0.5', role: PeerRole.server),
        _peer(host: '10.0.0.20', role: PeerRole.kds),
      ]);
      expect(reg.state.map((p) => p.host).toList(),
          ['10.0.0.5', '10.0.0.10', '10.0.0.20', '10.0.0.30']);
      expect(reg.state.first.role, PeerRole.server);
    });

    test('replaces existing entries', () {
      final reg = PeerRegistry();
      reg.replaceAll([_peer(host: '10.0.0.1')]);
      reg.replaceAll([_peer(host: '10.0.0.2'), _peer(host: '10.0.0.3')]);
      expect(reg.state.map((p) => p.host).toList(),
          ['10.0.0.2', '10.0.0.3']);
    });
  });

  group('PeerRegistry.upsert', () {
    test('inserts when host:port not seen yet', () {
      final reg = PeerRegistry();
      reg.upsert(_peer(host: '10.0.0.1'));
      expect(reg.state, hasLength(1));
    });

    test('updates in place when same host:port re-appears', () {
      final reg = PeerRegistry();
      reg.upsert(_peer(host: '10.0.0.1'));
      reg.upsert(_peer(host: '10.0.0.1', role: PeerRole.server, healthy: true));
      expect(reg.state, hasLength(1));
      expect(reg.state.first.role, PeerRole.server);
      expect(reg.state.first.healthy, isTrue);
    });
  });

  test('clear() empties the list', () {
    final reg = PeerRegistry();
    reg.upsert(_peer(host: '10.0.0.1'));
    reg.upsert(_peer(host: '10.0.0.2'));
    reg.clear();
    expect(reg.state, isEmpty);
  });
}
