/// Surface container used across lists, panels, and detail views.
library;

import 'package:flutter/material.dart';
import '../theme/gc_colors.dart';
import '../theme/gc_spacing.dart';

enum GcCardVariant {
  /// Default surface card with a subtle border.
  standard,

  /// Elevated-looking card (brighter surface) for floating panels.
  elevated,

  /// Low-emphasis card used inside lists.
  muted,
}

class GcCard extends StatelessWidget {
  final Widget child;
  final GcCardVariant variant;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool selected;

  const GcCard({
    super.key,
    required this.child,
    this.variant = GcCardVariant.standard,
    this.padding = GcSpacing.paddingLg,
    this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = switch (variant) {
      GcCardVariant.standard => GcColors.surfaceLow,
      GcCardVariant.elevated => GcColors.surfaceHigh,
      GcCardVariant.muted => GcColors.surfaceMedium,
    };

    final border = selected
        ? Border.all(color: GcColors.accent, width: 1.5)
        : Border.all(color: GcColors.border);

    final content = Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: GcRadius.allMd,
        border: border,
      ),
      padding: padding,
      child: child,
    );

    if (onTap == null) return content;

    return Material(
      color: Colors.transparent,
      borderRadius: GcRadius.allMd,
      child: InkWell(
        onTap: onTap,
        borderRadius: GcRadius.allMd,
        child: content,
      ),
    );
  }
}
