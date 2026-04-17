/// Primary button family for GastroCore apps.
library;

import 'package:flutter/material.dart';
import '../theme/gc_colors.dart';
import '../theme/gc_spacing.dart';

enum GcButtonVariant {
  /// Solid accent background — the main call-to-action.
  primary,

  /// Outlined button on a transparent background.
  secondary,

  /// Destructive action; uses `GcColors.danger`.
  danger,

  /// Tonal/soft variant used for secondary-but-still-branded actions.
  tonal,

  /// Text-only, no fill. For inline actions inside a card or row.
  ghost,
}

enum GcButtonSize { sm, md, lg }

class GcButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final GcButtonVariant variant;
  final GcButtonSize size;
  final IconData? leadingIcon;
  final IconData? trailingIcon;
  final bool loading;
  final bool fullWidth;

  const GcButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.variant = GcButtonVariant.primary,
    this.size = GcButtonSize.md,
    this.leadingIcon,
    this.trailingIcon,
    this.loading = false,
    this.fullWidth = false,
  });

  const GcButton.primary({
    super.key,
    required this.onPressed,
    required this.child,
    this.size = GcButtonSize.md,
    this.leadingIcon,
    this.trailingIcon,
    this.loading = false,
    this.fullWidth = false,
  }) : variant = GcButtonVariant.primary;

  const GcButton.secondary({
    super.key,
    required this.onPressed,
    required this.child,
    this.size = GcButtonSize.md,
    this.leadingIcon,
    this.trailingIcon,
    this.loading = false,
    this.fullWidth = false,
  }) : variant = GcButtonVariant.secondary;

  const GcButton.danger({
    super.key,
    required this.onPressed,
    required this.child,
    this.size = GcButtonSize.md,
    this.leadingIcon,
    this.trailingIcon,
    this.loading = false,
    this.fullWidth = false,
  }) : variant = GcButtonVariant.danger;

  const GcButton.ghost({
    super.key,
    required this.onPressed,
    required this.child,
    this.size = GcButtonSize.md,
    this.leadingIcon,
    this.trailingIcon,
    this.loading = false,
    this.fullWidth = false,
  }) : variant = GcButtonVariant.ghost;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null && !loading;
    final tap = loading ? null : onPressed;

    final pad = switch (size) {
      GcButtonSize.sm => const EdgeInsets.symmetric(
          horizontal: GcSpacing.md, vertical: GcSpacing.xs),
      GcButtonSize.md => const EdgeInsets.symmetric(
          horizontal: GcSpacing.lg, vertical: GcSpacing.sm + 2),
      GcButtonSize.lg => const EdgeInsets.symmetric(
          horizontal: GcSpacing.xl, vertical: GcSpacing.md),
    };

    final textSize = switch (size) {
      GcButtonSize.sm => 12.0,
      GcButtonSize.md => 14.0,
      GcButtonSize.lg => 16.0,
    };
    final iconSize = switch (size) {
      GcButtonSize.sm => 14.0,
      GcButtonSize.md => 18.0,
      GcButtonSize.lg => 20.0,
    };

    final (bg, fg, border) = switch (variant) {
      GcButtonVariant.primary => (GcColors.accent, Colors.white, null),
      GcButtonVariant.secondary => (
          Colors.transparent,
          GcColors.textPrimary,
          GcColors.borderStrong,
        ),
      GcButtonVariant.danger => (GcColors.danger, Colors.white, null),
      GcButtonVariant.tonal => (GcColors.accentSoft, GcColors.accent, null),
      GcButtonVariant.ghost => (Colors.transparent, GcColors.accent, null),
    };

    final content = loading
        ? SizedBox(
            height: iconSize,
            width: iconSize,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(fg),
            ),
          )
        : Row(
            mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (leadingIcon != null) ...[
                Icon(leadingIcon, size: iconSize, color: fg),
                const SizedBox(width: GcSpacing.sm),
              ],
              DefaultTextStyle.merge(
                style: TextStyle(
                  color: fg,
                  fontSize: textSize,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                ),
                child: child,
              ),
              if (trailingIcon != null) ...[
                const SizedBox(width: GcSpacing.sm),
                Icon(trailingIcon, size: iconSize, color: fg),
              ],
            ],
          );

    return Opacity(
      opacity: isEnabled ? 1.0 : 0.45,
      child: Material(
        color: bg,
        borderRadius: GcRadius.allMd,
        child: InkWell(
          onTap: tap,
          borderRadius: GcRadius.allMd,
          child: Container(
            padding: pad,
            decoration: BoxDecoration(
              borderRadius: GcRadius.allMd,
              border: border != null ? Border.all(color: border) : null,
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}
