/// Back Office "Mesai" tab - per-user clock in / clock out panel.
///
/// Lists every user that has at least one recent clock event plus every
/// currently-active user; a manager can toggle their state with a single
/// tap. The source of truth is the audit log, so this panel never
/// "loses" state across restarts.
///
/// Shown data per row:
///   * Avatar + role chip
///   * Status ("ON SHIFT" / "OFF SHIFT") with live timer while on shift
///   * Today's worked total (H:MM)
///   * Last event timestamp
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/auth/domain/entities/user_entity.dart';
import 'package:gastrocore_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:gastrocore_pos/features/shifts/domain/entities/clock_status.dart';
import 'package:gastrocore_pos/features/shifts/presentation/providers/clock_provider.dart';

// ---------------------------------------------------------------------------
// ClockManagementTab
// ---------------------------------------------------------------------------

class ClockManagementTab extends ConsumerStatefulWidget {
  const ClockManagementTab({super.key});

  @override
  ConsumerState<ClockManagementTab> createState() =>
      _ClockManagementTabState();
}

class _ClockManagementTabState extends ConsumerState<ClockManagementTab> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Repaint every 30s so the live timer for clocked-in users stays fresh.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(usersListProvider);
    final statusesAsync = ref.watch(clockStatusesProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Row(
                children: [
                  const Text(
                    'Mesai Takibi',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Yenile',
                    onPressed: () => ref
                        .read(clockStatusesProvider.notifier)
                        .refresh(),
                    icon: const Icon(Icons.refresh_rounded,
                        color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Expanded(
              child: usersAsync.when(
                data: (users) => statusesAsync.when(
                  data: (statuses) => _buildList(users, statuses),
                  loading: _loadingSpinner,
                  error: _errorBox,
                ),
                loading: _loadingSpinner,
                error: _errorBox,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _loadingSpinner() => const Center(
        child: CircularProgressIndicator(
          color: AppColors.primary,
          strokeWidth: 2,
        ),
      );

  Widget _errorBox(Object e, StackTrace _) => Center(
        child: Text(
          'Hata: $e',
          style: const TextStyle(color: AppColors.red, fontSize: 13),
        ),
      );

  Widget _buildList(List<UserEntity> users, List<ClockStatus> statuses) {
    // Index statuses for O(1) lookup by userId.
    final byId = {for (final s in statuses) s.userId: s};
    // Only show active users — but do NOT hide users that have a clock entry
    // but are currently inactive (manager can still clock them out).
    final rows = <_Row>[];
    for (final u in users.where((u) => u.isActive)) {
      rows.add(_Row(user: u, status: byId[u.id]));
    }
    // Tack on any status whose userId no longer maps to an active user —
    // usually means the account was deactivated while on shift.
    final knownIds = users.map((u) => u.id).toSet();
    for (final s in statuses) {
      if (!knownIds.contains(s.userId) && s.isClockedIn) {
        rows.add(_Row(user: null, status: s));
      }
    }

    if (rows.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule_rounded, size: 48, color: AppColors.textDim),
            SizedBox(height: 16),
            Text(
              'Henuz personel yok',
              style: TextStyle(color: AppColors.textDim, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      itemCount: rows.length,
      itemBuilder: (context, i) => _buildRow(rows[i]),
    );
  }

  Widget _buildRow(_Row row) {
    final user = row.user;
    final status = row.status;
    final userId = user?.id ?? status!.userId;
    final userName = user?.name ?? status!.userName;
    final isOn = status?.isClockedIn ?? false;

    final tile = ClockTileViewModel(
      status: status ??
          ClockStatus(
            userId: userId,
            userName: userName,
            isClockedIn: false,
          ),
      now: DateTime.now(),
    );

    final isOnBreak = status?.isOnBreak ?? false;
    final hasOvertime = tile.overtime > Duration.zero;
    final accent = isOnBreak
        ? AppColors.yellow
        : isOn
            ? AppColors.green
            : AppColors.textDim;
    final initials = userName.isNotEmpty
        ? userName
            .split(' ')
            .take(2)
            .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
            .join()
        : '?';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOn
              ? AppColors.green.withValues(alpha: 0.35)
              : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                initials,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Name + status + worked
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  userName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _chip(
                      isOnBreak
                          ? 'PAUSE'
                          : isOn
                              ? 'MESAIDE'
                              : 'OFF',
                      accent,
                    ),
                    Text(
                      'Bugun: ${tile.workedLabel}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (tile.totalBreak > Duration.zero)
                      Text(
                        'Mola: ${tile.breakLabel}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.yellow,
                        ),
                      ),
                    if (hasOvertime)
                      _chip('+${tile.overtimeLabel} OT', AppColors.red),
                  ],
                ),
              ],
            ),
          ),
          // Break toggle — only visible while clocked in.
          if (isOn) ...[
            OutlinedButton.icon(
              onPressed: () =>
                  _toggleBreak(userId, userName, isOnBreak),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.yellow,
                side: BorderSide(
                  color: AppColors.yellow.withValues(alpha: 0.6),
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: Icon(
                isOnBreak
                    ? Icons.play_circle_outline_rounded
                    : Icons.pause_circle_outline_rounded,
                size: 18,
              ),
              label: Text(
                isOnBreak ? 'Devam' : 'Mola',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          // Clock toggle
          ElevatedButton.icon(
            onPressed: () => _toggle(userId, userName, isOn),
            style: ElevatedButton.styleFrom(
              backgroundColor: isOn ? AppColors.redDim : AppColors.greenDim,
              foregroundColor: isOn ? AppColors.red : AppColors.green,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: Icon(
              isOn ? Icons.stop_rounded : Icons.play_arrow_rounded,
              size: 18,
            ),
            label: Text(
              isOn ? 'Mesai Bitir' : 'Mesai Baslat',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: color,
            letterSpacing: 0.5,
          ),
        ),
      );

  Future<void> _toggle(String userId, String userName, bool isOn) async {
    await ref.read(clockStatusesProvider.notifier).toggle(
          userId: userId,
          userName: userName,
          currentlyClockedIn: isOn,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isOn
            ? '$userName mesaiden cikti'
            : '$userName mesaiye girdi'),
        backgroundColor: AppColors.surfaceContainer,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _toggleBreak(
      String userId, String userName, bool onBreak) async {
    await ref.read(clockStatusesProvider.notifier).toggleBreak(
          userId: userId,
          userName: userName,
          currentlyOnBreak: onBreak,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(onBreak
            ? '$userName molayi bitirdi'
            : '$userName molaya cikti'),
        backgroundColor: AppColors.surfaceContainer,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

class _Row {
  const _Row({required this.user, required this.status});
  final UserEntity? user;
  final ClockStatus? status;
}
