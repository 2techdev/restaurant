/// Toast-style notifications anchored to a `ScaffoldMessenger`.
library;

import 'package:flutter/material.dart';
import '../theme/gc_colors.dart';
import '../theme/gc_spacing.dart';
import '../theme/gc_text_styles.dart';

enum GcSnackbarKind { info, success, warning, error }

abstract final class GcSnackbar {
  static void show(
    BuildContext context,
    String message, {
    GcSnackbarKind kind = GcSnackbarKind.info,
    Duration duration = const Duration(seconds: 3),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final (bg, fg, icon) = switch (kind) {
      GcSnackbarKind.info => (GcColors.surfaceHigh, GcColors.accent, Icons.info_outline),
      GcSnackbarKind.success => (GcColors.successSoft, GcColors.success, Icons.check_circle_outline),
      GcSnackbarKind.warning => (GcColors.warningSoft, GcColors.warning, Icons.warning_amber_outlined),
      GcSnackbarKind.error => (GcColors.dangerSoft, GcColors.danger, Icons.error_outline),
    };

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: bg,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: GcRadius.allMd),
        duration: duration,
        margin: const EdgeInsets.all(GcSpacing.lg),
        padding: const EdgeInsets.symmetric(
          horizontal: GcSpacing.lg,
          vertical: GcSpacing.md,
        ),
        content: Row(
          children: [
            Icon(icon, color: fg, size: 20),
            const SizedBox(width: GcSpacing.md),
            Expanded(
              child: Text(
                message,
                style: GcTextStyles.bodyLarge.copyWith(color: GcColors.textPrimary),
              ),
            ),
          ],
        ),
        action: (actionLabel != null && onAction != null)
            ? SnackBarAction(
                label: actionLabel,
                textColor: fg,
                onPressed: onAction,
              )
            : null,
      ),
    );
  }

  static void info(BuildContext c, String m) =>
      show(c, m, kind: GcSnackbarKind.info);
  static void success(BuildContext c, String m) =>
      show(c, m, kind: GcSnackbarKind.success);
  static void warning(BuildContext c, String m) =>
      show(c, m, kind: GcSnackbarKind.warning);
  static void error(BuildContext c, String m) =>
      show(c, m, kind: GcSnackbarKind.error);
}
