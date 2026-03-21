/// Persistent sync/online status indicator for GastroCore POS.
///
/// Embeddable in any screen to show connectivity state, pending sync count,
/// and provide a quick-action panel for manual sync. Follows the Stitch
/// "Precision POS Framework" design system.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/core/providers/connectivity_provider.dart';

// ---------------------------------------------------------------------------
// PosSyncIndicator
// ---------------------------------------------------------------------------

/// A compact sync/connectivity indicator widget.
///
/// Shows:
/// - Green dot + "ONLINE" when connected
/// - Orange dot + "OFFLINE" when disconnected
/// - Spinning icon + "SYNCING..." during active sync
/// - Red dot + pending count when items are waiting to sync
///
/// Tap to expand a detail panel with last sync time, pending count,
/// and a manual sync button.
class PosSyncIndicator extends ConsumerStatefulWidget {
  const PosSyncIndicator({super.key});

  @override
  ConsumerState<PosSyncIndicator> createState() => _PosSyncIndicatorState();
}

class _PosSyncIndicatorState extends ConsumerState<PosSyncIndicator>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late final AnimationController _syncSpinController;

  @override
  void initState() {
    super.initState();
    _syncSpinController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
  }

  @override
  void dispose() {
    _syncSpinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connectivity = ref.watch(connectivityProvider);
    final pendingAsync = ref.watch(pendingSyncCountProvider);
    final lastSync = ref.watch(lastSyncTimeProvider);
    final pendingCount = pendingAsync.valueOrNull ?? 0;

    // Manage spin animation.
    if (connectivity == ConnectivityState.syncing) {
      _syncSpinController.repeat();
    } else {
      _syncSpinController.stop();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // -- Compact badge --
        GestureDetector(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: _buildBadge(connectivity, pendingCount),
        ),

        // -- Expanded detail panel --
        if (_isExpanded)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _buildDetailPanel(connectivity, pendingCount, lastSync),
          ),
      ],
    );
  }

  Widget _buildBadge(ConnectivityState state, int pendingCount) {
    final Color dotColor;
    final String label;
    final Color bgColor;

    switch (state) {
      case ConnectivityState.online:
        dotColor = AppColors.green;
        label = pendingCount > 0 ? '$pendingCount bekliyor' : 'ONLINE';
        bgColor = pendingCount > 0 ? AppColors.orangeDim : AppColors.greenDim;
      case ConnectivityState.offline:
        dotColor = AppColors.orange;
        label = pendingCount > 0 ? 'OFFLINE \u2022 $pendingCount' : 'OFFLINE';
        bgColor = AppColors.orangeDim;
      case ConnectivityState.syncing:
        dotColor = AppColors.primary;
        label = 'SYNCING...';
        bgColor = AppColors.accentDim;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state == ConnectivityState.syncing)
            RotationTransition(
              turns: _syncSpinController,
              child: Icon(Icons.sync_rounded, size: 12, color: dotColor),
            )
          else
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: state == ConnectivityState.online && pendingCount == 0
                  ? AppColors.green
                  : state == ConnectivityState.syncing
                      ? AppColors.primary
                      : AppColors.orange,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            _isExpanded
                ? Icons.keyboard_arrow_up_rounded
                : Icons.keyboard_arrow_down_rounded,
            size: 14,
            color: AppColors.textDim,
          ),
        ],
      ),
    );
  }

  Widget _buildDetailPanel(
    ConnectivityState connectivity,
    int pendingCount,
    DateTime? lastSync,
  ) {
    final lastSyncText = lastSync != null
        ? _formatTimeDifference(lastSync)
        : 'Henuz senkronize edilmedi';

    return Container(
      width: 240,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Connection status row
          Row(
            children: [
              Icon(
                connectivity == ConnectivityState.online
                    ? Icons.cloud_done_rounded
                    : connectivity == ConnectivityState.syncing
                        ? Icons.cloud_sync_rounded
                        : Icons.cloud_off_rounded,
                size: 18,
                color: connectivity == ConnectivityState.online
                    ? AppColors.green
                    : connectivity == ConnectivityState.syncing
                        ? AppColors.primary
                        : AppColors.orange,
              ),
              const SizedBox(width: 8),
              Text(
                connectivity == ConnectivityState.online
                    ? 'Baglanti aktif'
                    : connectivity == ConnectivityState.syncing
                        ? 'Senkronize ediliyor...'
                        : 'Cevrimdisi mod',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Last sync time
          _buildInfoRow(
            Icons.schedule_rounded,
            'Son senkronizasyon',
            lastSyncText,
          ),
          const SizedBox(height: 8),

          // Pending count
          _buildInfoRow(
            Icons.pending_actions_rounded,
            'Bekleyen islem',
            '$pendingCount islem',
          ),
          const SizedBox(height: 14),

          // Sync button
          SizedBox(
            width: double.infinity,
            child: Material(
              color: AppColors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {
                  // Phase 2: trigger actual sync.
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Senkronizasyon Phase 2 ile aktif olacak'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                splashColor: AppColors.accent.withValues(alpha: 0.1),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.sync_rounded,
                          size: 16, color: AppColors.accent),
                      SizedBox(width: 8),
                      Text(
                        'Senkronize Et',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.textDim),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textDim,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  String _formatTimeDifference(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inSeconds < 60) return 'Az once';
    if (diff.inMinutes < 60) return '${diff.inMinutes} dakika once';
    if (diff.inHours < 24) return '${diff.inHours} saat once';
    return '${diff.inDays} gun once';
  }
}
