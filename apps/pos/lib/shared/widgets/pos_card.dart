/// Card variants — Lightspeed-inspired professional UI.
///
/// White cards with subtle shadow on a light gray background.
/// Depth is expressed through elevation (shadow), not borders.
///
/// - [PosCard] — General-purpose container with ripple and scale feedback.
/// - [PosStatCard] — Compact KPI display for dashboard and shift summaries.
library;

import 'package:flutter/material.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/core/theme/app_theme.dart';

// ---------------------------------------------------------------------------
// PosCard
// ---------------------------------------------------------------------------

/// A white card with subtle shadow and optional tap interaction.
///
/// Hierarchy is expressed through shadow depth, not borders.
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
    this.elevation = true,
  });

  final Widget child;

  /// Inner padding. Defaults to `EdgeInsets.all(16)` when null.
  final EdgeInsets? padding;

  /// Background color. Defaults to [AppColors.surface] (white).
  /// When [isActive] is true, overridden to [AppColors.accentDim].
  final Color? color;

  /// Corner radius. Defaults to 12.
  final double borderRadius;

  /// Tap callback — card becomes tappable with ripple + scale feedback.
  final VoidCallback? onTap;

  /// When true, background shifts to [AppColors.accentDim] (teal tint).
  final bool isActive;

  /// Whether to show the card shadow. Set to false for nested cards.
  final bool elevation;

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
        ? AppColors.accentDim
        : (widget.color ?? AppColors.surface);

    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(widget.borderRadius),
        border: widget.isActive
            ? Border.all(color: AppColors.primary.withValues(alpha: 0.3))
            : null,
        boxShadow: widget.elevation ? kCardShadow : null,
      ),
      child: widget.onTap != null
          ? Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(widget.borderRadius),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: widget.onTap,
                splashColor: AppColors.primary.withValues(alpha: 0.06),
                highlightColor: AppColors.primary.withValues(alpha: 0.03),
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

/// Compact KPI card for dashboards, shift summaries, and reports.
///
/// Shows a large [value] with a [label] underneath and an optional [icon].
///
/// ```dart
/// PosStatCard(
///   value: 'CHF 2,450.00',
///   label: 'Revenue',
///   valueColor: AppColors.primary,
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
    this.iconColor,
    this.borderRadius = 12,
  });

  final String value;
  final String label;
  final Color? valueColor;
  final IconData? icon;
  final Color? iconColor;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final vColor = valueColor ?? AppColors.textPrimary;
    final iColor = iconColor ?? vColor;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: kCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Icon(icon, size: 20, color: iColor),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: vColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
