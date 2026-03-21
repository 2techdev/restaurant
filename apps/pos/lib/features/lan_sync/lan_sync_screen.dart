/// LAN sync settings and status screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'lan_sync_models.dart';
import 'lan_sync_provider.dart';

/// Full-page screen for managing LAN sync.
///
/// Allows the operator to:
/// - See the current role (primary / secondary / undecided)
/// - Start acting as the primary POS device
/// - Discover primary devices and connect as a secondary
/// - View real-time peer list and sync status
class LanSyncScreen extends ConsumerWidget {
  const LanSyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(lanSyncProvider);
    final notifier = ref.read(lanSyncProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('LAN Sync'),
        actions: [
          if (state.isRunning)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: _StatusBadge(status: state.status, role: state.role),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ----------------------------------------------------------------
          // Role selection
          // ----------------------------------------------------------------
          _SectionHeader('Device Role'),
          const SizedBox(height: 8),
          _RoleSelector(state: state, notifier: notifier),
          const SizedBox(height: 24),

          // ----------------------------------------------------------------
          // Primary info
          // ----------------------------------------------------------------
          if (state.role == DeviceRole.primary) ...[
            _SectionHeader('Server'),
            const SizedBox(height: 8),
            _PrimaryInfo(state: state),
            const SizedBox(height: 24),
          ],

          // ----------------------------------------------------------------
          // Connected primary info (secondary view)
          // ----------------------------------------------------------------
          if (state.role == DeviceRole.secondary &&
              state.primaryPeer != null) ...[
            _SectionHeader('Connected Primary'),
            const SizedBox(height: 8),
            _PrimaryConnectionCard(peer: state.primaryPeer!),
            const SizedBox(height: 24),
          ],

          // ----------------------------------------------------------------
          // Peer list
          // ----------------------------------------------------------------
          _SectionHeader(
            state.role == DeviceRole.primary
                ? 'Connected Secondaries (${state.peers.where((p) => p.status == PeerConnectionStatus.connected).length})'
                : 'Discovered Primaries (${state.peers.length})',
          ),
          const SizedBox(height: 8),
          if (state.peers.isEmpty)
            _EmptyPeers(role: state.role)
          else
            ...state.peers.map(
              (peer) => _PeerCard(
                peer: peer,
                isSelf: false,
                onConnect: state.role == DeviceRole.secondary &&
                        peer.status != PeerConnectionStatus.connected
                    ? () => notifier.connectToPeer(peer)
                    : null,
              ),
            ),

          const SizedBox(height: 24),

          // ----------------------------------------------------------------
          // Error
          // ----------------------------------------------------------------
          if (state.lastError != null)
            _ErrorCard(error: state.lastError!),

          // ----------------------------------------------------------------
          // Last sync
          // ----------------------------------------------------------------
          if (state.lastSyncAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Last sync: ${_formatTime(state.lastSyncAt!)}',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ),

          // ----------------------------------------------------------------
          // Stop button
          // ----------------------------------------------------------------
          if (state.isRunning) ...[
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: notifier.stop,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('Stop LAN Sync'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    final s = local.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

// ---------------------------------------------------------------------------
// Role selector
// ---------------------------------------------------------------------------

class _RoleSelector extends StatelessWidget {
  const _RoleSelector({required this.state, required this.notifier});

  final LanSyncState state;
  final LanSyncNotifier notifier;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _RoleButton(
            label: 'Primary',
            subtitle: 'Host — all others sync to me',
            icon: Icons.hub,
            selected: state.role == DeviceRole.primary,
            loading: state.role == DeviceRole.primary &&
                state.status == LanSyncStatus.starting,
            onTap: state.status == LanSyncStatus.starting
                ? null
                : notifier.becomePrimary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _RoleButton(
            label: 'Secondary',
            subtitle: 'Client — discover and connect',
            icon: Icons.tablet_android,
            selected: state.role == DeviceRole.secondary,
            loading: state.role == DeviceRole.secondary &&
                state.status == LanSyncStatus.starting,
            onTap: state.status == LanSyncStatus.starting
                ? null
                : notifier.becomeSecondary,
          ),
        ),
      ],
    );
  }
}

class _RoleButton extends StatelessWidget {
  const _RoleButton({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.loading,
    this.onTap,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? colorScheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  color: selected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                if (loading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: selected
                        ? colorScheme.primary
                        : colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Primary info card
// ---------------------------------------------------------------------------

class _PrimaryInfo extends StatelessWidget {
  const _PrimaryInfo({required this.state});

  final LanSyncState state;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InfoRow(
              label: 'Status',
              value: state.status.name.toUpperCase(),
            ),
            if (state.port != null)
              _InfoRow(label: 'Port', value: '${state.port}'),
            _InfoRow(
              label: 'SSE subscribers',
              value: '${state.peers.where((p) => p.status == PeerConnectionStatus.connected).length}',
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Primary connection card (secondary view)
// ---------------------------------------------------------------------------

class _PrimaryConnectionCard extends StatelessWidget {
  const _PrimaryConnectionCard({required this.peer});

  final SyncPeer peer;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InfoRow(label: 'Device', value: peer.deviceName),
            _InfoRow(label: 'Address', value: '${peer.ipAddress}:${peer.port}'),
            _InfoRow(
              label: 'Status',
              value: peer.status.name.toUpperCase(),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Peer card
// ---------------------------------------------------------------------------

class _PeerCard extends StatelessWidget {
  const _PeerCard({
    required this.peer,
    required this.isSelf,
    this.onConnect,
  });

  final SyncPeer peer;
  final bool isSelf;
  final VoidCallback? onConnect;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final connected = peer.status == PeerConnectionStatus.connected;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          peer.role == DeviceRole.primary ? Icons.hub : Icons.tablet_android,
          color: connected ? colorScheme.primary : colorScheme.onSurfaceVariant,
        ),
        title: Text(peer.deviceName),
        subtitle: Text('${peer.ipAddress}:${peer.port} · ${peer.status.name}'),
        trailing: onConnect != null
            ? TextButton(
                onPressed: onConnect,
                child: peer.status == PeerConnectionStatus.connecting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Connect'),
              )
            : connected
                ? Icon(Icons.check_circle, color: colorScheme.primary)
                : null,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyPeers extends StatelessWidget {
  const _EmptyPeers({required this.role});

  final DeviceRole role;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(
            Icons.wifi_tethering,
            size: 48,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 8),
          Text(
            role == DeviceRole.secondary
                ? 'Searching for primary devices…'
                : 'No secondaries connected yet',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.primary,
          ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, required this.role});

  final LanSyncStatus status;
  final DeviceRole role;

  @override
  Widget build(BuildContext context) {
    final color = status == LanSyncStatus.running
        ? Colors.green
        : status == LanSyncStatus.error
            ? Colors.red
            : Colors.orange;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 10, color: color),
        const SizedBox(width: 4),
        Text(
          role.name.toUpperCase(),
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: color, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                error,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
