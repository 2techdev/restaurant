/// Generic typed dropdown styled to match GcTextField.
library;

import 'package:flutter/material.dart';
import '../theme/gc_colors.dart';
import '../theme/gc_spacing.dart';
import '../theme/gc_text_styles.dart';

/// A single dropdown option. The generic `T` is the value stored on the form;
/// the `label` is what the user sees.
class GcDropdownItem<T> {
  final T value;
  final String label;
  final IconData? icon;

  const GcDropdownItem({
    required this.value,
    required this.label,
    this.icon,
  });
}

class GcDropdown<T> extends StatelessWidget {
  final String? label;
  final String? helperText;
  final String? errorText;
  final T? value;
  final List<GcDropdownItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? hint;
  final bool enabled;

  const GcDropdown({
    super.key,
    required this.items,
    required this.onChanged,
    this.label,
    this.helperText,
    this.errorText,
    this.value,
    this.hint,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null && errorText!.isNotEmpty;
    final borderColor = hasError ? GcColors.danger : GcColors.border;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(label!, style: GcTextStyles.labelLarge),
          const SizedBox(height: GcSpacing.xs),
        ],
        DropdownButtonFormField<T>(
          initialValue: value,
          onChanged: enabled ? onChanged : null,
          isExpanded: true,
          dropdownColor: GcColors.surfaceHigh,
          borderRadius: GcRadius.allMd,
          style: GcTextStyles.bodyLarge,
          icon: const Icon(Icons.expand_more, color: GcColors.textSecondary),
          hint: hint != null
              ? Text(hint!,
                  style: GcTextStyles.bodyLarge
                      .copyWith(color: GcColors.textDim))
              : null,
          decoration: InputDecoration(
            filled: true,
            fillColor: GcColors.inputFill,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: GcSpacing.md,
              vertical: GcSpacing.md,
            ),
            border: OutlineInputBorder(
              borderRadius: GcRadius.allMd,
              borderSide: BorderSide(color: borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: GcRadius.allMd,
              borderSide: BorderSide(color: borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: GcRadius.allMd,
              borderSide: BorderSide(
                color: hasError ? GcColors.danger : GcColors.borderFocused,
                width: 1.5,
              ),
            ),
          ),
          items: [
            for (final it in items)
              DropdownMenuItem<T>(
                value: it.value,
                child: Row(
                  children: [
                    if (it.icon != null) ...[
                      Icon(it.icon,
                          size: 18, color: GcColors.textSecondary),
                      const SizedBox(width: GcSpacing.sm),
                    ],
                    Expanded(
                      child: Text(it.label,
                          style: GcTextStyles.bodyLarge,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
          ],
        ),
        if (hasError) ...[
          const SizedBox(height: GcSpacing.xs),
          Text(errorText!,
              style:
                  GcTextStyles.labelMedium.copyWith(color: GcColors.danger)),
        ] else if (helperText != null) ...[
          const SizedBox(height: GcSpacing.xs),
          Text(helperText!, style: GcTextStyles.labelMedium),
        ],
      ],
    );
  }
}
