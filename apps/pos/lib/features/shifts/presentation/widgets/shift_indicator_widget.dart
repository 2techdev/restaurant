/// Active-shift indicator widget for the POS header / status bar.
///
/// Displays:
/// - A coloured status dot + "SHIFT OPEN" / "NO SHIFT" label
/// - Cashier name (from the logged-in user)
/// - Duration the shift has been open (live, updates every minute)
/// - Quick-action buttons: open cash drawer and close shift
///
/// Suitable for embedding in the [HomeScreen] top bar or [PosTopBar].
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/core/router/app_router.dart';
import 'package:gastrocore_pos/core/printing/printing_provider.dart';
import 'package:gastrocore_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:gastrocore_pos/features/shifts/presentation/providers/shift_provider.dart';
import 'package:gastrocore_pos/l10n/app_localizations.dart';

// ---------------------------------------------------------------------------
// Shift Indicator Widget
// ---------------------------------------------------------------------------

class ShiftIndicatorWidget extends ConsumerStatefulWidget {
  const ShiftIndicatorWidget({super.key});

  @override
  ConsumerState<ShiftIndicatorWidget> createState() =>
      _ShiftIndicatorWidgetState();
}

class _ShiftIndicatorWidgetState
    extends ConsumerState<ShiftIndicatorWidget> {
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    // Update the live duration every minute.
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final shift = ref.watch(currentShiftProvider);
    final user = ref.watch(currentUserProvider);

    if (shift == null) {
      return _NoShiftBadge(
        label: l10n.shiftNoShiftTapToOpen,
        onOpenShift: () => context.go(AppRoutes.shiftOpen),
      );
    }

    final duration = _now.difference(shift.openedAt);
    final h = duration.inHours;
    final m = duration.inMinutes % 60;
    final durationStr = h > 0 ? '${h}h ${m}m' : '${m}m';
    final cashierName = user?.name ?? shift.userId;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Status pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Pulsing dot
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.green,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                l10n.shiftStatusOpen.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.green,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                durationStr,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppColors.green.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // Cashier name chip
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.person_outline,
                size: 13,
                color: AppColors.textDim,
              ),
              const SizedBox(width: 5),
              Text(
                cashierName,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // Cash drawer button
        _ActionButton(
          icon: Icons.point_of_sale,
          tooltip: l10n.shiftOpenCashDrawer,
          onTap: () async {
            await ref
                .read(printerActionsProvider.notifier)
                .openCashDrawer();
          },
        ),
        const SizedBox(width: 6),
        // Close shift button
        _ActionButton(
          icon: Icons.lock_outline_rounded,
          tooltip: l10n.shiftCloseShift,
          onTap: () => context.go(AppRoutes.shiftClose),
          color: AppColors.red.withValues(alpha: 0.15),
          iconColor: AppColors.red,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// No-shift badge
// ---------------------------------------------------------------------------

class _NoShiftBadge extends StatelessWidget {
  const _NoShiftBadge({required this.label, required this.onOpenShift});

  final String label;
  final VoidCallback onOpenShift;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onOpenShift,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.orange.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.orange.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.orange,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.orange,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small icon action button
// ---------------------------------------------------------------------------

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
    this.iconColor,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color ?? AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(
              icon,
              size: 16,
              color: iconColor ?? AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
