/// Text input with a label, helper/error text, and optional leading/trailing
/// adornments. Thin wrapper around Material's `TextField` so all GastroCore
/// forms look the same and can't drift from the design system.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/gc_colors.dart';
import '../theme/gc_spacing.dart';
import '../theme/gc_text_styles.dart';

class GcTextField extends StatelessWidget {
  final String? label;
  final String? hint;
  final String? helperText;
  final String? errorText;
  final TextEditingController? controller;
  final String? initialValue;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onEditingComplete;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool obscureText;
  final bool enabled;
  final bool autofocus;
  final int? maxLength;
  final int minLines;
  final int? maxLines;
  final Widget? prefix;
  final Widget? suffix;
  final IconData? prefixIcon;
  final IconData? suffixIcon;
  final VoidCallback? onSuffixIconTap;

  const GcTextField({
    super.key,
    this.label,
    this.hint,
    this.helperText,
    this.errorText,
    this.controller,
    this.initialValue,
    this.onChanged,
    this.onEditingComplete,
    this.keyboardType,
    this.inputFormatters,
    this.obscureText = false,
    this.enabled = true,
    this.autofocus = false,
    this.maxLength,
    this.minLines = 1,
    this.maxLines = 1,
    this.prefix,
    this.suffix,
    this.prefixIcon,
    this.suffixIcon,
    this.onSuffixIconTap,
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
        TextField(
          controller: controller,
          // If both controller and initialValue are provided, the controller
          // wins — this mirrors the usual Flutter contract.
          onChanged: onChanged,
          onEditingComplete: onEditingComplete,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          obscureText: obscureText,
          enabled: enabled,
          autofocus: autofocus,
          maxLength: maxLength,
          minLines: minLines,
          maxLines: obscureText ? 1 : maxLines,
          style: GcTextStyles.bodyLarge,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GcTextStyles.bodyLarge.copyWith(color: GcColors.textDim),
            filled: true,
            fillColor: GcColors.inputFill,
            counterText: '',
            contentPadding: const EdgeInsets.symmetric(
              horizontal: GcSpacing.md,
              vertical: GcSpacing.md,
            ),
            prefixIcon: prefixIcon != null
                ? Icon(prefixIcon, color: GcColors.textSecondary, size: 18)
                : null,
            prefix: prefix,
            suffix: suffix,
            suffixIcon: suffixIcon != null
                ? IconButton(
                    icon: Icon(suffixIcon,
                        color: GcColors.textSecondary, size: 18),
                    onPressed: onSuffixIconTap,
                    splashRadius: 18,
                  )
                : null,
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
            disabledBorder: OutlineInputBorder(
              borderRadius: GcRadius.allMd,
              borderSide: BorderSide(color: GcColors.border.withValues(alpha: 0.4)),
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: GcSpacing.xs),
          Text(
            errorText!,
            style: GcTextStyles.labelMedium.copyWith(color: GcColors.danger),
          ),
        ] else if (helperText != null) ...[
          const SizedBox(height: GcSpacing.xs),
          Text(helperText!, style: GcTextStyles.labelMedium),
        ],
      ],
    );
  }
}
