/// Settings pane: shows the current [NetworkLocator] state and gives the
/// operator a "Şimdi yenile" button to force a re-probe.
///
/// Visible across pos / waiter / kds flavors — each one boots a locator
/// at startup and overrides [networkLocatorProvider]. Renders cloud-only
/// safely (no LAN peer found yet → cloud pill with a "Yenile" CTA).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/network/network_locator.dart';
import 'package:gastrocore_pos/core/network/network_locator_provider.dart';

class NetworkStatusPane extends ConsumerStatefulWidget {
  const NetworkStatusPane({super.key});

  @override
  ConsumerState<NetworkStatusPane> createState() => _NetworkStatusPaneState();
}

class _NetworkStatusPaneState extends ConsumerState<NetworkStatusPane> {
  bool _refreshing = false;

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(networkEndpointStateProvider);
    final endpoint = snapshot.endpoint;
    final isLan = endpoint.isLan;

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
          _ExplainCard(),
        ],
      ),
    );
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
