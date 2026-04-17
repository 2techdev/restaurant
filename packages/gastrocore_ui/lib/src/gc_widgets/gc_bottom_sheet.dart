/// Branded modal bottom sheet with an optional title, drag handle, and body.
library;

import 'package:flutter/material.dart';
import '../theme/gc_colors.dart';
import '../theme/gc_spacing.dart';
import '../theme/gc_text_styles.dart';

class GcBottomSheet extends StatelessWidget {
  final String? title;
  final Widget child;
  final bool showDragHandle;
  final EdgeInsetsGeometry padding;

  const GcBottomSheet({
    super.key,
    this.title,
    required this.child,
    this.showDragHandle = true,
    this.padding = GcSpacing.paddingLg,
  });

  /// Convenience wrapper around `showModalBottomSheet` with the branded shape
  /// and background.
  static Future<T?> show<T>(
    BuildContext context, {
    String? title,
    required Widget child,
    bool isScrollControlled = true,
    bool showDragHandle = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      backgroundColor: GcColors.surfaceMedium,
      barrierColor: GcColors.overlay,
      shape: const RoundedRectangleBorder(borderRadius: GcRadius.topLg),
      builder: (ctx) => GcBottomSheet(
        title: title,
        showDragHandle: showDragHandle,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showDragHandle)
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: GcSpacing.sm),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: GcColors.border,
                    borderRadius: GcRadius.allPill,
                  ),
                ),
              ),
            if (title != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  GcSpacing.lg,
                  GcSpacing.lg,
                  GcSpacing.lg,
                  GcSpacing.sm,
                ),
                child: Text(title!, style: GcTextStyles.titleLarge),
              ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }
}
