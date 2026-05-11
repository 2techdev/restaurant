/// Catalogue of LAN peers the NetworkLocator has seen during the current
/// session. Surfaced in Settings → Bağlantı Durumu so an operator can see
/// every other GastroCore device on the same WiFi (POS terminals, KDS
/// screens, waiter handhelds, kiosks) and confirm that the server they're
/// talking to is the right one.
///
/// Roles are read from the mDNS TXT records the POS server / siblings
/// advertise (`role=server`, `role=kds`, ...). When no TXT record is
/// present the role is `unknown` — the registry still lists the host so
/// an admin can ping it manually.
///
/// The registry is intentionally small and synchronous; it's not the
/// place for ticket data — only network coordinates.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Roles broadcasted in the `_gastrocore._tcp` mDNS TXT records.
/// `server` is the canonical Go API node every client talks to.
enum PeerRole {
  server,
  pos,
  kds,
  waiter,
  kiosk,
  ods,
  unknown;

  static PeerRole parse(String? raw) => switch (raw?.toLowerCase()) {
        'server' => PeerRole.server,
        'pos' => PeerRole.pos,
        'kds' => PeerRole.kds,
        'waiter' => PeerRole.waiter,
        'kiosk' => PeerRole.kiosk,
        'ods' => PeerRole.ods,
        _ => PeerRole.unknown,
      };

  /// Display label for the Settings pane.
  String get label => switch (this) {
        PeerRole.server => 'POS Server',
        PeerRole.pos => 'POS Terminal',
        PeerRole.kds => 'KDS Mutfak',
        PeerRole.waiter => 'Garson',
        PeerRole.kiosk => 'Kiosk',
        PeerRole.ods => 'Sipariş Ekranı',
        PeerRole.unknown => 'Bilinmiyor',
      };
}

class LanPeer {
  const LanPeer({
    required this.host,
    required this.port,
    required this.role,
    this.tenantId,
    this.version,
    this.lastSeenAt,
    this.healthy = false,
  });

  /// Resolved IPv4 (or hostname) the peer is reachable at on the LAN.
  final String host;

  /// TCP port from the mDNS SRV record.
  final int port;

  /// Role advertised in the TXT record (server / kds / waiter / kiosk / ...).
  final PeerRole role;

  /// Tenant ID the peer claims (TXT record). Filtered by the locator so
  /// peers belonging to another tenant on the same WiFi never reach the
  /// registry.
  final String? tenantId;

  /// Optional version string from TXT records (e.g. "1.2.3"). Useful for
  /// the admin diagnostic view.
  final String? version;

  /// Wall-clock timestamp of the last scan that confirmed this peer.
  final DateTime? lastSeenAt;

  /// True when the HTTP health probe answered 200 within the budget.
  /// The "winner" peer chosen by the locator is always healthy=true; the
  /// rest are listed so admins can see what's around.
  final bool healthy;

  LanPeer copyWith({
    String? host,
    int? port,
    PeerRole? role,
    String? tenantId,
    String? version,
    DateTime? lastSeenAt,
    bool? healthy,
  }) =>
      LanPeer(
        host: host ?? this.host,
        port: port ?? this.port,
        role: role ?? this.role,
        tenantId: tenantId ?? this.tenantId,
        version: version ?? this.version,
        lastSeenAt: lastSeenAt ?? this.lastSeenAt,
        healthy: healthy ?? this.healthy,
      );

  /// Two peers are the same network identity when host+port match. The
  /// role / version / lastSeenAt are layered on top via [copyWith] so a
  /// new mDNS reply updates a row in place rather than creating
  /// duplicates.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LanPeer && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);

  @override
  String toString() =>
      'LanPeer($host:$port, role=${role.name}, healthy=$healthy)';
}

/// Mutable in-memory list of LAN peers seen during the session.
class PeerRegistry extends StateNotifier<List<LanPeer>> {
  PeerRegistry() : super(const []);

  /// Replace the entire snapshot — used by the locator after a full
  /// discover+probe cycle. Sorted: server first (the one we care about),
  /// then by role, then by host. Stable order makes the Settings list
  /// non-jumpy across re-probes.
  void replaceAll(List<LanPeer> peers) {
    final sorted = [...peers]..sort((a, b) {
        if (a.role == PeerRole.server && b.role != PeerRole.server) return -1;
        if (b.role == PeerRole.server && a.role != PeerRole.server) return 1;
        final byRole = a.role.index.compareTo(b.role.index);
        if (byRole != 0) return byRole;
        return a.host.compareTo(b.host);
      });
    state = sorted;
  }

  /// Update or insert a single peer — used by the LAN-sync side channel
  /// when a peer announces / un-announces itself between full scans.
  void upsert(LanPeer peer) {
    final idx = state.indexWhere((p) => p == peer);
    if (idx == -1) {
      state = [...state, peer];
    } else {
      final next = [...state];
      next[idx] = peer;
      state = next;
    }
  }

  /// Drop everything (e.g. on tenant switch).
  void clear() => state = const [];

  /// The peer the locator picked as the active LAN endpoint. Returns null
  /// when no LAN connection is in use.
  LanPeer? get activeServer => state
      .where((p) => p.role == PeerRole.server && p.healthy)
      .cast<LanPeer?>()
      .firstWhere((_) => true, orElse: () => null);
}

/// Provider for the registry singleton. Read it via `ref.watch(...)`
/// from the Settings pane and the connection strategy.
final peerRegistryProvider =
    StateNotifierProvider<PeerRegistry, List<LanPeer>>((ref) {
  return PeerRegistry();
});
