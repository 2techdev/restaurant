/// Settings section for cloud sync configuration.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/features/sync/domain/repositories/sync_repository.dart';
import 'package:gastrocore_pos/features/sync/presentation/providers/sync_provider.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Settings widget for configuring cloud sync: server URL, device ID,
/// current sync status, and a manual sync trigger button.
class SyncSettingsSection extends ConsumerStatefulWidget {
  const SyncSettingsSection({super.key});

  @override
  ConsumerState<SyncSettingsSection> createState() =>
      _SyncSettingsSectionState();
}

class _SyncSettingsSectionState extends ConsumerState<SyncSettingsSection> {
  late final TextEditingController _urlController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(
      text: ref.read(syncServerUrlProvider),
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _saveUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    setState(() => _saving = true);
    try {
      ref.read(syncServerUrlProvider.notifier).state = url;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('sync_server_url', url);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Server URL saved')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final syncState = ref.watch(syncProvider);
    final deviceId = ref.watch(deviceIdProvider);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Cloud Sync',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),

        // ── Server URL ──────────────────────────────────────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'Sync server URL',
                  hintText: 'http://your-server:8080',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _saving ? null : _saveUrl,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ── Device ID ────────────────────────────────────────────────────────
        _InfoRow(
          label: 'Device ID',
          value: deviceId,
          valueStyle: theme.textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),

        // ── Status ───────────────────────────────────────────────────────────
        _InfoRow(
          label: 'Status',
          value: _statusLabel(syncState.status),
          valueColor: _statusColor(context, syncState.status),
        ),
        const SizedBox(height: 8),

        // ── Pending events ───────────────────────────────────────────────────
        _InfoRow(
          label: 'Pending events',
          value: '${syncState.pendingCount}',
        ),
        const SizedBox(height: 8),

        // ── Last sync ────────────────────────────────────────────────────────
        _InfoRow(
          label: 'Last sync',
          value: syncState.lastSyncAt != null
              ? DateFormat('dd MMM HH:mm:ss').format(syncState.lastSyncAt!)
              : '—',
        ),

        if (syncState.lastError != null) ...[
          const SizedBox(height: 8),
          _InfoRow(
            label: 'Last error',
            value: syncState.lastError!,
            valueColor: theme.colorScheme.error,
          ),
        ],

        const SizedBox(height: 20),

        // ── Manual sync button ───────────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: syncState.status == SyncStatus.syncing
                ? null
                : () => ref.read(syncProvider.notifier).sync(),
            icon: syncState.status == SyncStatus.syncing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded, size: 18),
            label: Text(
              syncState.status == SyncStatus.syncing
                  ? 'Syncing…'
                  : 'Sync now',
            ),
          ),
        ),
      ],
    );
  }

  String _statusLabel(SyncStatus status) => switch (status) {
        SyncStatus.idle => 'Idle',
        SyncStatus.syncing => 'Syncing…',
        SyncStatus.error => 'Error',
        SyncStatus.offline => 'Offline',
      };

  Color _statusColor(BuildContext context, SyncStatus status) {
    final cs = Theme.of(context).colorScheme;
    return switch (status) {
      SyncStatus.idle => Colors.green.shade600,
      SyncStatus.syncing => Colors.amber.shade700,
      SyncStatus.error => cs.error,
      SyncStatus.offline => cs.onSurfaceVariant,
    };
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.valueStyle,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: valueStyle ??
                theme.textTheme.bodySmall?.copyWith(
                  color: valueColor ?? theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
