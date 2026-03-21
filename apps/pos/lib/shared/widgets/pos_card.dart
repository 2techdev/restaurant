/// Card variants following the Stitch "Precision POS Framework".
///
/// Provides two card types:
///
/// - [PosCard] — General-purpose container with no border ("No-Line" rule).
///   Background shifts express hierarchy instead of 1px borders.
///
/// - [PosStatCard] — Compact stat display for shift summaries, reports,
///   and dashboard KPIs.
///
/// Both follow the Stitch surface hierarchy:
/// - Default: [AppColors.surfaceContainerLow]
/// - Active:  [AppColors.surfaceBright]
library;

import 'package:flutter/material.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';

// ---------------------------------------------------------------------------
// PosCard
// ---------------------------------------------------------------------------

/// A borderless surface card following the Stitch "No-Line" philosophy.
///
/// Hierarchy is expressed through background color shifts rather than
/// 1px borders. Supports tap interaction and active state.
///
/// ```dart
/// PosCard(
///   padding: EdgeInsets.all(16),
///   onTap: () => selectItem(),
///   isActive: isSelected,
///   child: Text('Table 5'),
/// )
/// ```
class PosCard extends StatefulWidget {
  const PosCard({
    super.key,
    required this.child,
    this.padding,
    this.color,
    this.borderRadius = 12,
    this.onTap,
    this.isActive = false,
  });

  /// Card content.
  final Widget child;

  /// Inner padding. Defaults to `EdgeInsets.all(16)` when null.
  final EdgeInsets? padding;

  /// Background color. Defaults to [AppColors.surfaceContainerLow].
  /// When [isActive] is true, overridden to [AppColors.surfaceBright].
  final Color? color;

  /// Corner radius. Defaults to 12 (Stitch medium radius).
  final double borderRadius;

  /// Tap callback. When non-null the card becomes tappable with ripple
  /// and scale-down feedback.
  final VoidCallback? onTap;

  /// Whether the card is in its active/selected state. When true, the
  /// background shifts to [AppColors.surfaceBright].
  final bool isActive;

  @override
  State<PosCard> createState() => _PosCardState();
}

class _PosCardState extends State<PosCard> with SingleTickerProviderStateMixin {
  late final AnimationController _scaleController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      reverseDuration: const Duration(milliseconds: 140),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isActive
        ? AppColors.surfaceBright
        : (widget.color ?? AppColors.surfaceContainerLow);

    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(widget.borderRadius),
      ),
      child: widget.onTap != null
          ? Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(widget.borderRadius),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: widget.onTap,
                splashColor: AppColors.textPrimary.withValues(alpha: 0.06),
                highlightColor: AppColors.textPrimary.withValues(alpha: 0.03),
                child: Padding(
                  padding: widget.padding ?? const EdgeInsets.all(16),
                  child: widget.child,
                ),
              ),
            )
          : Padding(
              padding: widget.padding ?? const EdgeInsets.all(16),
              child: widget.child,
            ),
    );

    // Only apply scale animation when tappable.
    if (widget.onTap == null) return card;

    return ScaleTransition(
      scale: _scaleAnimation,
      child: GestureDetector(
        onTapDown: (_) => _scaleController.forward(),
        onTapUp: (_) => _scaleController.reverse(),
        onTapCancel: () => _scaleController.reverse(),
        child: card,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PosStatCard
// ---------------------------------------------------------------------------

/// A compact stat display card for KPIs, shift summaries, and reports.
///
/// Shows a large [value] with a smaller [label] underneath, and an optional
/// icon. Follows the "No-Line" rule with surfaceContainerLow background.
///
/// ```dart
/// PosStatCard(
///   value: 'CHF 2,450.00',
///   label: 'Total Revenue',
///   valueColor: AppColors.green,
///   icon: Icons.trending_up,
/// )
/// ```
class PosStatCard extends StatelessWidget {
  const PosStatCard({
    super.key,
    required this.value,
    required this.label,
    this.valueColor,
    this.icon,
    this.borderRadius = 12,
  });

  /// The primary value text (e.g. "CHF 2,450.00", "42", "87%").
  final String value;

  /// Descriptive label shown below the value.
  final String label;

  /// Color for the value text. Defaults to [AppColors.textPrimary].
  final Color? valueColor;

  /// Optional icon displayed to the left of the value.
  final IconData? icon;

  /// Corner radius. Defaults to 12.
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 20,
                  color: valueColor ?? AppColors.textDim,
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: valueColor ?? AppColors.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
