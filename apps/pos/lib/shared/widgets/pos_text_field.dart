/// Custom text field following the Stitch "Precision POS Framework".
///
/// A borderless text input using [AppColors.bgInput] background with 12px
/// radius. Instead of a focus border, shows a subtle accent glow via
/// [BoxShadow] — following the "No-Line" rule.
///
/// ```dart
/// PosTextField(
///   label: 'Table Note',
///   hint: 'Add a note for the kitchen...',
///   prefixIcon: Icons.note_add_outlined,
///   onChanged: (value) => updateNote(value),
/// )
/// ```
library;

import 'package:flutter/material.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';

/// A custom text input field for the POS system.
///
/// Features:
/// - [AppColors.bgInput] background, no border ("No-Line" rule)
/// - 12px corner radius
/// - Focus state: subtle accent glow instead of border
/// - Support for prefix/suffix icons
/// - Password obscuring
/// - Multi-line support
class PosTextField extends StatefulWidget {
  const PosTextField({
    super.key,
    this.label,
    this.hint,
    this.controller,
    this.obscureText = false,
    this.keyboardType,
    this.prefixIcon,
    this.suffixIcon,
    this.onSuffixTap,
    this.onChanged,
    this.onSubmitted,
    this.maxLines = 1,
    this.autofocus = false,
    this.enabled = true,
    this.focusNode,
    this.textInputAction,
  });

  /// Optional label displayed above the input field.
  final String? label;

  /// Placeholder text shown when the field is empty.
  final String? hint;

  /// Text editing controller.
  final TextEditingController? controller;

  /// Whether to obscure text (for PIN/password fields).
  final bool obscureText;

  /// Keyboard type (numeric, email, etc.).
  final TextInputType? keyboardType;

  /// Icon shown at the start of the input field.
  final IconData? prefixIcon;

  /// Icon shown at the end of the input field.
  final IconData? suffixIcon;

  /// Callback when the suffix icon is tapped.
  final VoidCallback? onSuffixTap;

  /// Called when the text changes.
  final ValueChanged<String>? onChanged;

  /// Called when the user submits the field (e.g. pressing Enter).
  final ValueChanged<String>? onSubmitted;

  /// Maximum number of lines. Use `null` for unlimited.
  final int? maxLines;

  /// Whether to auto-focus on build.
  final bool autofocus;

  /// Whether the field is enabled.
  final bool enabled;

  /// Optional external focus node.
  final FocusNode? focusNode;

  /// Text input action (next, done, search, etc.).
  final TextInputAction? textInputAction;

  @override
  State<PosTextField> createState() => _PosTextFieldState();
}

class _PosTextFieldState extends State<PosTextField> {
  late final FocusNode _focusNode;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    // Only dispose if we own it.
    if (widget.focusNode == null) _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    setState(() => _isFocused = _focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
        ],

        // Input container with glow effect on focus
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            color: AppColors.bgInput,
            borderRadius: BorderRadius.circular(12),
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.2),
                      blurRadius: 8,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: TextField(
            controller: widget.controller,
            focusNode: _focusNode,
            obscureText: widget.obscureText,
            keyboardType: widget.keyboardType,
            onChanged: widget.onChanged,
            onSubmitted: widget.onSubmitted,
            maxLines: widget.obscureText ? 1 : widget.maxLines,
            autofocus: widget.autofocus,
            enabled: widget.enabled,
            textInputAction: widget.textInputAction,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: widget.enabled
                  ? AppColors.textPrimary
                  : AppColors.textDim,
            ),
            cursorColor: AppColors.accent,
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: AppColors.textDim,
              ),
              contentPadding: EdgeInsets.symmetric(
                horizontal: widget.prefixIcon != null ? 0 : 16,
                vertical: 14,
              ),
              // Remove all borders — "No-Line" rule.
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              filled: false,
              prefixIcon: widget.prefixIcon != null
                  ? Padding(
                      padding: const EdgeInsets.only(left: 14, right: 10),
                      child: Icon(
                        widget.prefixIcon,
                        size: 20,
                        color: _isFocused
                            ? AppColors.accent
                            : AppColors.textDim,
                      ),
                    )
                  : null,
              prefixIconConstraints: const BoxConstraints(
                minWidth: 44,
                minHeight: 44,
              ),
              suffixIcon: widget.suffixIcon != null
                  ? GestureDetector(
                      onTap: widget.onSuffixTap,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 14),
                        child: Icon(
                          widget.suffixIcon,
                          size: 20,
                          color: AppColors.textDim,
                        ),
                      ),
                    )
                  : null,
              suffixIconConstraints: const BoxConstraints(
                minWidth: 44,
                minHeight: 44,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
