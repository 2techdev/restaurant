/// Widgets for gating UI behind license tier requirements.
///
/// Usage — wrap any gated widget:
///
/// ```dart
/// FeatureGate(
///   feature: AppFeature.kds,
///   child: KdsScreen(),
/// )
/// ```
///
/// To check programmatically without rendering a fallback widget use
/// [FeatureGateChecker] or read [featureFlagServiceProvider] directly.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/licensing/domain/entities/app_feature.dart';
import 'package:gastrocore_pos/features/licensing/domain/entities/license_tier.dart';
import 'package:gastrocore_pos/features/licensing/presentation/providers/license_provider.dart';
import 'package:gastrocore_pos/features/licensing/presentation/widgets/upgrade_prompt_dialog.dart';

// ---------------------------------------------------------------------------
// FeatureGate
// ---------------------------------------------------------------------------

/// Shows [child] when the current license tier enables [feature].
///
/// When access is denied:
///   - If [fallback] is provided, renders it instead.
///   - Otherwise renders [LockedFeaturePlaceholder] which lets the user
///     trigger the upgrade dialog inline.
class FeatureGate extends ConsumerWidget {
  const FeatureGate({
    super.key,
    required this.feature,
    required this.child,
    this.fallback,
  });

  final AppFeature feature;
  final Widget child;

  /// Custom widget to show when the feature is locked. When null the default
  /// [LockedFeaturePlaceholder] is used.
  final Widget? fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(featureFlagServiceProvider);
    if (service.isEnabled(feature)) return child;
    return fallback ??
        LockedFeaturePlaceholder(requiredTier: feature.requiredTier);
  }
}

// ---------------------------------------------------------------------------
// LockedFeaturePlaceholder
// ---------------------------------------------------------------------------

/// Full-area placeholder rendered inside [FeatureGate] when a feature is
/// locked. Tapping "Upgrade" opens [UpgradeDialog].
class LockedFeaturePlaceholder extends StatelessWidget {
  const LockedFeaturePlaceholder({
    super.key,
    required this.requiredTier,
    this.message,
  });

  final LicenseTier requiredTier;

  /// Optional custom message. Defaults to a generic upgrade prompt.
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.surfaceContainerHigh),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_rounded,
                  size: 40,
                  color: _tierColor(requiredTier),
                ),
                const SizedBox(height: 12),
                Text(
                  message ??
                      'This feature requires the '
                          '${requiredTier.displayName} plan.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => showUpgradeDialog(
                    context,
                    requiredTier: requiredTier,
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: _tierColor(requiredTier),
                  ),
                  icon: const Icon(Icons.upgrade_rounded, size: 18),
                  label: Text('Upgrade to ${requiredTier.displayName}'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _tierColor(LicenseTier tier) => switch (tier) {
        LicenseTier.free => AppColors.textDim,
        LicenseTier.professional => const Color(0xFF4C9EFF),
        LicenseTier.enterprise => const Color(0xFFB06EFF),
      };
}

// ---------------------------------------------------------------------------
// LockedMenuItem  (sidebar / nav drawer item with lock badge)
// ---------------------------------------------------------------------------

/// A nav-menu tile that shows a lock icon badge when [feature] is gated.
///
/// Tapping a locked item opens [UpgradeDialog] instead of navigating.
class LockedMenuItem extends ConsumerWidget {
  const LockedMenuItem({
    super.key,
    required this.feature,
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final AppFeature feature;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(featureFlagServiceProvider);
    final locked = !service.isEnabled(feature);

    return ListTile(
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(icon,
              color: selected
                  ? AppColors.primary
                  : locked
                      ? AppColors.textDim
                      : AppColors.textSecondary),
          if (locked)
            Positioned(
              right: -4,
              bottom: -4,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: AppColors.surfaceContainer,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_rounded,
                    size: 10, color: Color(0xFF4C9EFF)),
              ),
            ),
        ],
      ),
      title: Text(
        label,
        style: TextStyle(
          color: selected
              ? AppColors.primary
              : locked
                  ? AppColors.textDim
                  : AppColors.textSecondary,
          fontSize: 14,
        ),
      ),
      selected: selected && !locked,
      onTap: locked
          ? () => showUpgradeDialog(context,
              requiredTier: feature.requiredTier)
          : onTap,
    );
  }
}

// ---------------------------------------------------------------------------
// LicenseBadge  (small chip for the settings / about screen)
// ---------------------------------------------------------------------------

/// Compact badge showing the current license tier.
class LicenseBadge extends ConsumerWidget {
  const LicenseBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tier = ref.watch(licenseTierProvider);
    final color = switch (tier) {
      LicenseTier.free => AppColors.textDim,
      LicenseTier.professional => const Color(0xFF4C9EFF),
      LicenseTier.enterprise => const Color(0xFFB06EFF),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        tier.badge,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
