/// FlagGate — widget-level feature gating for GastroCore POS.
///
/// Usage:
/// ```dart
/// FlagGate(
///   flag: FeatureFlag.kds,
///   child: KitchenDisplayScreen(),
/// )
/// ```
///
/// When the flag is disabled the widget renders [fallback] if provided,
/// otherwise [_LockedFlagPlaceholder] — a full-area locked state card
/// with the required edition displayed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/license/license_models.dart';
import 'package:gastrocore_pos/features/license/license_provider.dart';

// ---------------------------------------------------------------------------
// FlagGate
// ---------------------------------------------------------------------------

/// Shows [child] when the current license enables [flag]; renders a locked
/// placeholder (or [fallback]) otherwise.
///
/// All reactive updates are automatic — the widget rebuilds whenever the
/// active license changes.
class FlagGate extends ConsumerWidget {
  const FlagGate({
    super.key,
    required this.flag,
    required this.child,
    this.fallback,
  });

  /// The feature flag that must be enabled for [child] to be shown.
  final FeatureFlag flag;

  /// The widget to show when the flag is active.
  final Widget child;

  /// Optional widget to show when the flag is locked. Defaults to
  /// [_LockedFlagPlaceholder] which displays the required edition.
  final Widget? fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(isFlagEnabledProvider(flag));
    if (enabled) return child;
    return fallback ?? _LockedFlagPlaceholder(flag: flag);
  }
}

// ---------------------------------------------------------------------------
// _LockedFlagPlaceholder
// ---------------------------------------------------------------------------

class _LockedFlagPlaceholder extends StatelessWidget {
  const _LockedFlagPlaceholder({required this.flag});

  final FeatureFlag flag;

  @override
  Widget build(BuildContext context) {
    final required = flag.requiredEdition;
    final color = _editionColor(required);

    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.surfaceContainerHigh),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.lock_rounded, size: 36, color: color),
            ),
            const SizedBox(height: 16),
            Text(
              flag.displayName,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Requires the ${required.displayName} plan',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: color.withValues(alpha: 0.5)),
              ),
              child: Text(
                required.badge,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _editionColor(LicenseEdition edition) => switch (edition) {
        LicenseEdition.free => AppColors.textDim,
        LicenseEdition.starter => const Color(0xFF4CAF50),
        LicenseEdition.pro => const Color(0xFF4C9EFF),
        LicenseEdition.enterprise => const Color(0xFFB06EFF),
      };
}

// ---------------------------------------------------------------------------
// FlagBadge  (compact edition badge for status bars / settings)
// ---------------------------------------------------------------------------

/// A small chip displaying the current license edition.
class FlagBadge extends ConsumerWidget {
  const FlagBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final edition = ref.watch(licenseEditionProvider);
    final color = _editionColor(edition);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        edition.badge,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Color _editionColor(LicenseEdition edition) => switch (edition) {
        LicenseEdition.free => AppColors.textDim,
        LicenseEdition.starter => const Color(0xFF4CAF50),
        LicenseEdition.pro => const Color(0xFF4C9EFF),
        LicenseEdition.enterprise => const Color(0xFFB06EFF),
      };
}
