/// Settings pane: shows the current [NetworkLocator] state and gives the
/// operator a "Şimdi yenile" button to force a re-probe.
///
/// Visible across pos / waiter / kds flavors — each one boots a locator
/// at startup and overrides [networkLocatorProvider]. Renders cloud-only
/// safely (no LAN peer found yet → cloud pill with a "Yenile" CTA).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gastrocore_pos/core/network/network_locator.dart';
import 'package:gastrocore_pos/core/network/network_locator_provider.dart';
import 'package:gastrocore_pos/core/network/peer_registry.dart';

class NetworkStatusPane extends ConsumerStatefulWidget {
  const NetworkStatusPane({super.key});

  @override
  ConsumerState<NetworkStatusPane> createState() => _NetworkStatusPaneState();
}

class _NetworkStatusPaneState extends ConsumerState<NetworkStatusPane> {
  bool _refreshing = false;
  final _manualCtrl = TextEditingController();
  final _portCtrl = TextEditingController(text: '8090');

  @override
  void initState() {
    super.initState();
    // Pre-populate the input from whatever the locator currently has —
    // visible immediately so the operator can confirm the current override.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final loc = ref.read(networkLocatorProvider);
      final mo = loc.manualOverride;
      if (mo != null) {
        _manualCtrl.text = mo.host;
        _portCtrl.text = '${mo.port}';
        if (mounted) setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _manualCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(networkEndpointStateProvider);
    final endpoint = snapshot.endpoint;
    final isLan = endpoint.isLan;
    final peers = ref.watch(peerRegistryProvider);
    final locator = ref.watch(networkLocatorProvider);
    final nextReprobe = locator.nextReprobeAt;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatePill(state: snapshot.state, isLan: isLan),
          const SizedBox(height: 16),
          _DetailCard(
            children: [
              _row(
                label: 'Mod',
                value: isLan ? 'LAN (yerel ağ)' : 'Bulut (cloud)',
                icon: isLan ? Icons.wifi : Icons.cloud,
              ),
              if (endpoint.peerHost != null)
                _row(
                  label: 'Sunucu IP',
                  value: endpoint.peerHost!,
                  icon: Icons.dns_outlined,
                ),
              _row(
                label: 'API',
                value: endpoint.apiBaseUrl,
                icon: Icons.api_outlined,
              ),
              _row(
                label: 'WebSocket',
                value: endpoint.wsBaseUrl,
                icon: Icons.bolt_outlined,
              ),
              _row(
                label: 'Son keşif',
                value: endpoint.resolvedAt != null
                    ? _fmtDate(endpoint.resolvedAt!)
                    : 'Henüz tarama yok',
                icon: Icons.history,
              ),
              if (nextReprobe != null)
                _row(
                  label: 'Sonraki tarama',
                  value: _fmtDate(nextReprobe),
                  icon: Icons.schedule,
                ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _refreshing ? null : _reprobe,
            icon: _refreshing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            label: Text(_refreshing
                ? 'LAN taranıyor…'
                : 'Şimdi yenile (LAN re-probe)'),
          ),
          const SizedBox(height: 24),
          _ManualOverrideCard(
            hostCtrl: _manualCtrl,
            portCtrl: _portCtrl,
            onApply: _applyManualOverride,
            onClear: _clearManualOverride,
            currentOverride: locator.manualOverride,
          ),
          const SizedBox(height: 16),
          _PeerListCard(peers: peers, activeHost: endpoint.peerHost),
          const SizedBox(height: 16),
          _ExplainCard(),
        ],
      ),
    );
  }

  Future<void> _applyManualOverride() async {
    final host = _manualCtrl.text.trim();
    if (host.isEmpty) return;
    final port = int.tryParse(_portCtrl.text.trim()) ?? 8090;
    setState(() => _refreshing = true);
    try {
      // Persist BEFORE applying so a crash mid-resolve still survives a
      // restart — the prefs entry is the source of truth on next boot.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('network_manual_host', host);
      await prefs.setInt('network_manual_port', port);

      await ref
          .read(networkLocatorProvider)
          .setManualOverride(host: host, port: port);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Manual override aktif: $host:$port')),
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _clearManualOverride() async {
    _manualCtrl.clear();
    _portCtrl.text = '8090';
    setState(() => _refreshing = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('network_manual_host');
      await prefs.remove('network_manual_port');

      await ref
          .read(networkLocatorProvider)
          .setManualOverride(host: null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Manual override kaldırıldı')),
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _reprobe() async {
    setState(() => _refreshing = true);
    try {
      await ref.read(networkEndpointStateProvider.notifier).reprobe();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Widget _row({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 10),
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime d) {
    final local = d.toLocal();
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${pad(local.month)}-${pad(local.day)} '
        '${pad(local.hour)}:${pad(local.minute)}';
  }
}

class _StatePill extends StatelessWidget {
  const _StatePill({required this.state, required this.isLan});
  final NetworkPeerState state;
  final bool isLan;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (state) {
      NetworkPeerState.discovering => (
          'LAN taranıyor…',
          Colors.blue,
          Icons.radar,
        ),
      NetworkPeerState.lanConnected => (
          'LAN bağlı',
          Colors.green,
          Icons.wifi,
        ),
      NetworkPeerState.cloudFallback => (
          'Bulut fallback (LAN bulunamadı)',
          Colors.orange,
          Icons.cloud_outlined,
        ),
      NetworkPeerState.reconnecting => (
          'Yeniden bağlanıyor…',
          Colors.blueGrey,
          Icons.sync,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: color.withValues(alpha: 0.9),
              ),
            ),
          ),
          if (state == NetworkPeerState.lanConnected && isLan)
            const Icon(Icons.check_circle, color: Colors.green, size: 18),
        ],
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _ManualOverrideCard extends StatelessWidget {
  const _ManualOverrideCard({
    required this.hostCtrl,
    required this.portCtrl,
    required this.onApply,
    required this.onClear,
    required this.currentOverride,
  });

  final TextEditingController hostCtrl;
  final TextEditingController portCtrl;
  final Future<void> Function() onApply;
  final Future<void> Function() onClear;
  final ({String host, int port})? currentOverride;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.edit_rounded,
                  size: 18, color: Color(0xFF666666)),
              const SizedBox(width: 8),
              const Text(
                'Manual sunucu IP (opsiyonel)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              if (currentOverride != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Aktif',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.green.shade900,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'mDNS broadcast blokluysa (örn. corporate WiFi) POS sunucusunun '
            'IP adresini buraya yazın. Boş bırakırsanız otomatik keşif.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: hostCtrl,
                  decoration: const InputDecoration(
                    labelText: 'IP veya hostname',
                    hintText: '192.168.1.50',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: TextField(
                  controller: portCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Port',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton.icon(
                onPressed: onApply,
                icon: const Icon(Icons.save_rounded, size: 16),
                label: const Text('Uygula'),
              ),
              const SizedBox(width: 8),
              if (currentOverride != null)
                OutlinedButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.clear_rounded, size: 16),
                  label: const Text('Temizle'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PeerListCard extends StatelessWidget {
  const _PeerListCard({required this.peers, required this.activeHost});

  final List<LanPeer> peers;
  final String? activeHost;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.devices_other_rounded,
                  size: 18, color: Color(0xFF666666)),
              const SizedBox(width: 8),
              const Text(
                'LAN\'da bulunan cihazlar',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                '${peers.length}',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (peers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Bu ağda başka GastroCore cihazı görünmüyor. '
                'Sunucu mDNS broadcast yapmıyor olabilir veya cihazlar '
                'farklı WiFi\'ye bağlı.',
                style:
                    TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            )
          else
            ...peers.map((p) => _PeerRow(peer: p, isActive: p.host == activeHost)),
        ],
      ),
    );
  }
}

class _PeerRow extends StatelessWidget {
  const _PeerRow({required this.peer, required this.isActive});

  final LanPeer peer;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            peer.healthy ? Icons.circle : Icons.circle_outlined,
            size: 10,
            color: peer.healthy ? Colors.green : Colors.grey.shade400,
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.blueGrey.shade50,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              peer.role.label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Colors.blueGrey.shade700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${peer.host}:${peer.port}',
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isActive)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Icon(Icons.check_circle, size: 14, color: Colors.green),
            ),
        ],
      ),
    );
  }
}

class _ExplainCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue.shade700, size: 18),
              const SizedBox(width: 8),
              Text(
                'LAN-first nasıl çalışır',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.blue.shade900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Cihaz açılırken yerel WiFi\'de POS sunucusunu (mDNS — '
            '_gastrocore._tcp) aranır. Bulursa o IP\'ye doğrudan bağlanır '
            '(restoran içi trafik bulut sunucusuna gitmez). Bulamazsa '
            'api.gastrocore.ch / ws.gastrocore.ch üzerinden buluta düşer. '
            'Her gün 04:00\'te otomatik yeniden tarama yapılır; IP değişirse '
            'tekrar LAN\'a bağlanır.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.blue.shade900,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
