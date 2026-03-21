/// Empty state placeholder following the Stitch "Precision POS Framework".
///
/// A centered placeholder widget for screens or sections with no data.
/// Shows a large dim icon, secondary-colored title, optional subtitle,
/// and an optional action button.
///
/// ```dart
/// PosEmptyState(
///   icon: Icons.receipt_long_outlined,
///   title: 'No Orders Yet',
///   subtitle: 'Orders will appear here once created.',
///   actionLabel: 'New Order',
///   onAction: () => createNewOrder(),
/// )
/// ```
library;

import 'package:flutter/material.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';

/// An empty state placeholder widget.
///
/// Designed to fill empty content areas with a meaningful message and
/// an optional call-to-action. All text uses the Stitch text hierarchy:
/// dim icon, secondary title, dim subtitle.
class PosEmptyState extends StatelessWidget {
  const PosEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.iconSize = 56,
  });

  /// Large icon displayed at the top of the empty state.
  final IconData icon;

  /// Primary message, e.g. "No Orders Yet".
  final String title;

  /// Optional secondary message with more context.
  final String? subtitle;

  /// Optional action button label. Only shown when [onAction] is non-null.
  final String? actionLabel;

  /// Callback for the action button.
  final VoidCallback? onAction;

  /// Size of the leading icon. Defaults to 56.
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon
            Icon(
              icon,
              size: iconSize,
              color: AppColors.textDim,
            ),
            const SizedBox(height: 20),

            // Title
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),

            // Subtitle
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textDim,
                  height: 1.5,
                ),
              ),
            ],

            // Action button
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              Material(
                color: AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onAction,
                  splashColor: AppColors.accent.withValues(alpha: 0.1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    child: Text(
                      actionLabel!,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
