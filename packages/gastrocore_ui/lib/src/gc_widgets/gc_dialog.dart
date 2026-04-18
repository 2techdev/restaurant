/// Branded modal dialog with title, body, and an action row.
library;

import 'package:flutter/material.dart';
import '../theme/gc_colors.dart';
import '../theme/gc_spacing.dart';
import '../theme/gc_text_styles.dart';
import 'gc_button.dart';

class GcDialog extends StatelessWidget {
  final String title;
  final Widget? content;
  final String? message;
  final List<Widget> actions;
  final IconData? icon;
  final Color? iconColor;

  const GcDialog({
    super.key,
    required this.title,
    this.content,
    this.message,
    this.actions = const [],
    this.icon,
    this.iconColor,
  });

  /// Show a confirm dialog with `Cancel` + `Confirm` actions. Returns `true`
  /// when the user confirms, `false` (or `null`) when they dismiss.
  static Future<bool?> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    bool destructive = false,
    IconData? icon,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => GcDialog(
        title: title,
        message: message,
        icon: icon,
        iconColor: destructive ? GcColors.danger : null,
        actions: [
          GcButton.secondary(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(cancelLabel),
          ),
          destructive
              ? GcButton.danger(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(confirmLabel),
                )
              : GcButton.primary(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(confirmLabel),
                ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: GcColors.surfaceMedium,
      shape: const RoundedRectangleBorder(borderRadius: GcRadius.allLg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(GcSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: iconColor ?? GcColors.accent, size: 22),
                    const SizedBox(width: GcSpacing.md),
                  ],
                  Expanded(
                    child: Text(title, style: GcTextStyles.titleLarge),
                  ),
                ],
              ),
              const SizedBox(height: GcSpacing.md),
              if (content != null)
                content!
              else if (message != null)
                Text(message!, style: GcTextStyles.bodyLarge),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: GcSpacing.xl),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: GcSpacing.sm),
                      actions[i],
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
