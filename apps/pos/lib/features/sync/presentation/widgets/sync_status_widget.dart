/// Small status indicator showing the current sync state.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gastrocore_pos/core/providers/connectivity_provider.dart';
import 'package:gastrocore_pos/features/sync/domain/repositories/sync_repository.dart';
import 'package:gastrocore_pos/features/sync/presentation/providers/sync_provider.dart';

/// A small icon + tooltip showing sync health.
/// Green dot = synced, yellow = syncing/pending, red = offline or error.
class SyncStatusWidget extends ConsumerWidget {
  const SyncStatusWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectivity = ref.watch(connectivityProvider);
    final syncState = ref.watch(syncProvider);

    final (color, icon, label) = switch (connectivity) {
      ConnectivityState.offline => (
          Colors.red.shade400,
          Icons.cloud_off_rounded,
          'Offline',
        ),
      ConnectivityState.syncing => (
          Colors.amber.shade400,
          Icons.sync_rounded,
          'Syncing…',
        ),
      ConnectivityState.online => switch (syncState.status) {
          SyncStatus.syncing => (
              Colors.amber.shade400,
              Icons.sync_rounded,
              'Syncing…',
            ),
          SyncStatus.error => (
              Colors.orange.shade400,
              Icons.sync_problem_rounded,
              'Sync error',
            ),
          _ when syncState.pendingCount > 0 => (
              Colors.amber.shade300,
              Icons.cloud_upload_outlined,
              '${syncState.pendingCount} pending',
            ),
          _ => (
              Colors.green.shade400,
              Icons.cloud_done_rounded,
              'Synced',
            ),
        },
    };

    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: connectivity == ConnectivityState.online
            ? () => ref.read(syncProvider.notifier).sync()
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 4,
            children: [
              connectivity == ConnectivityState.syncing ||
                      syncState.status == SyncStatus.syncing
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: color,
                      ),
                    )
                  : Icon(icon, size: 16, color: color),
              if (syncState.pendingCount > 0)
                Text(
                  '${syncState.pendingCount}',
                  style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
