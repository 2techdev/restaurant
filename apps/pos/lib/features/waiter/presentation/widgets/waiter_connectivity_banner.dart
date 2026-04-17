/// Thin status banner shown above the waiter shell when the device is
/// offline or when sync is unhealthy.
///
/// Fine-dining staff need immediate feedback that an order they just sent
/// "to the kitchen" is queued locally and has not yet reached the KDS.
/// The banner is deliberately compact (20px) so it never competes with the
/// primary content; it simply replaces what would otherwise be invisible
/// failure.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/providers/connectivity_provider.dart';
import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/sync/domain/repositories/sync_repository.dart';
import 'package:gastrocore_pos/features/sync/presentation/providers/sync_provider.dart';

class WaiterConnectivityBanner extends ConsumerWidget {
  const WaiterConnectivityBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectivity = ref.watch(connectivityProvider);
    final syncState = ref.watch(syncProvider);
    final pending = syncState.pendingCount;

    final visual = _resolveVisual(connectivity, syncState.status, pending);
    if (visual == null) return const SizedBox.shrink();

    return Material(
      color: visual.background,
      child: SafeArea(
        top: true,
        bottom: false,
        child: SizedBox(
          height: 22,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(visual.icon, color: visual.foreground, size: 13),
              const SizedBox(width: 6),
              Text(
                visual.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: visual.foreground,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  _BannerVisual? _resolveVisual(
    ConnectivityState connectivity,
    SyncStatus syncStatus,
    int pending,
  ) {
    if (connectivity == ConnectivityState.offline) {
      return _BannerVisual(
        background: AppColors.red,
        foreground: Colors.white,
        icon: Icons.cloud_off_rounded,
        label: pending > 0
            ? 'Offline — $pending order(s) queued locally'
            : 'Offline — orders will sync when back online',
      );
    }
    if (syncStatus == SyncStatus.error) {
      return _BannerVisual(
        background: AppColors.orange,
        foreground: Colors.white,
        icon: Icons.sync_problem_rounded,
        label: 'Sync error — tap My Orders to retry',
      );
    }
    if (pending > 0) {
      return _BannerVisual(
        background: AppColors.yellow,
        foreground: AppColors.surfaceDim,
        icon: Icons.cloud_upload_outlined,
        label: '$pending change(s) pending sync',
      );
    }
    return null;
  }
}

class _BannerVisual {
  final Color background;
  final Color foreground;
  final IconData icon;
  final String label;

  const _BannerVisual({
    required this.background,
    required this.foreground,
    required this.icon,
    required this.label,
  });
}
