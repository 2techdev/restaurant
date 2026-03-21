/// Reusable numeric keypad following the Stitch "Precision POS Framework".
///
/// A 3-column grid of touch-friendly keys for entering amounts, PINs, and
/// quantities. Follows the "No-Line" rule — key boundaries are expressed
/// through background shifts, not borders.
///
/// Layout (default, no decimal, no enter):
/// ```
///  [ 1 ] [ 2 ] [ 3 ]
///  [ 4 ] [ 5 ] [ 6 ]
///  [ 7 ] [ 8 ] [ 9 ]
///  [ C ] [ 0 ] [ ← ]
/// ```
///
/// With [showDecimal] = true, the Clear key is replaced by a `.` key.
/// With [onEnter] provided, an extra bottom row with a full-width Enter
/// button is appended.
library;

import 'package:flutter/material.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';

/// A reusable numeric keypad widget.
///
/// ```dart
/// PosNumpad(
///   onDigit: (d) => controller.addDigit(d),
///   onClear: () => controller.clear(),
///   onBackspace: () => controller.backspace(),
///   showDecimal: true,
///   onEnter: () => controller.submit(),
/// )
/// ```
class PosNumpad extends StatelessWidget {
  const PosNumpad({
    super.key,
    required this.onDigit,
    required this.onClear,
    required this.onBackspace,
    this.onEnter,
    this.showDecimal = false,
    this.keyHeight = 56,
    this.spacing = 8,
  });

  /// Called when a digit key (0-9) is tapped. Also fires for '.' when
  /// [showDecimal] is true.
  final void Function(String digit) onDigit;

  /// Called when the Clear (C) key is tapped.
  final VoidCallback onClear;

  /// Called when the Backspace key is tapped.
  final VoidCallback onBackspace;

  /// When non-null, an Enter row is shown below the grid and this callback
  /// fires on tap.
  final VoidCallback? onEnter;

  /// Whether to show a decimal point key. When true, the bottom-left key
  /// becomes '.' instead of 'C' (Clear).
  final bool showDecimal;

  /// Height of each key. Defaults to 56. Minimum enforced at 44px.
  final double keyHeight;

  /// Gap between keys. Defaults to 8.
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final h = keyHeight.clamp(44.0, double.infinity);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Row 1: 1 2 3
        _digitRow(['1', '2', '3'], h),
        SizedBox(height: spacing),

        // Row 2: 4 5 6
        _digitRow(['4', '5', '6'], h),
        SizedBox(height: spacing),

        // Row 3: 7 8 9
        _digitRow(['7', '8', '9'], h),
        SizedBox(height: spacing),

        // Row 4: C/. 0 Backspace
        _bottomRow(h),

        // Optional Enter row
        if (onEnter != null) ...[
          SizedBox(height: spacing),
          _enterRow(h),
        ],
      ],
    );
  }

  /// Builds a row of three digit keys with [spacing] between them.
  Widget _digitRow(List<String> digits, double h) {
    return Row(
      children: [
        Expanded(
          child: _NumpadKey(
            label: digits[0],
            height: h,
            onTap: () => onDigit(digits[0]),
          ),
        ),
        SizedBox(width: spacing),
        Expanded(
          child: _NumpadKey(
            label: digits[1],
            height: h,
            onTap: () => onDigit(digits[1]),
          ),
        ),
        SizedBox(width: spacing),
        Expanded(
          child: _NumpadKey(
            label: digits[2],
            height: h,
            onTap: () => onDigit(digits[2]),
          ),
        ),
      ],
    );
  }

  /// Builds the bottom row: Clear/Decimal, 0, Backspace.
  Widget _bottomRow(double h) {
    return Row(
      children: [
        // Left: Clear or Decimal
        Expanded(
          child: showDecimal
              ? _NumpadKey(
                  label: '.',
                  height: h,
                  onTap: () => onDigit('.'),
                )
              : _NumpadKey(
                  label: 'C',
                  height: h,
                  textColor: AppColors.orange,
                  onTap: onClear,
                ),
        ),
        SizedBox(width: spacing),

        // Center: 0
        Expanded(
          child: _NumpadKey(
            label: '0',
            height: h,
            onTap: () => onDigit('0'),
          ),
        ),
        SizedBox(width: spacing),

        // Right: Backspace
        Expanded(
          child: _NumpadKey(
            icon: Icons.backspace_outlined,
            height: h,
            textColor: AppColors.textSecondary,
            onTap: onBackspace,
          ),
        ),
      ],
    );
  }

  /// Builds a full-width Enter button.
  Widget _enterRow(double h) {
    return SizedBox(
      height: h,
      width: double.infinity,
      child: Material(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onEnter,
          splashColor: Colors.white.withValues(alpha: 0.15),
          highlightColor: Colors.white.withValues(alpha: 0.05),
          child: const Center(
            child: Text(
              'Enter',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Internal key widget
// ---------------------------------------------------------------------------

/// A single numpad key with surface background and scale-down press effect.
class _NumpadKey extends StatefulWidget {
  const _NumpadKey({
    this.label,
    this.icon,
    required this.height,
    required this.onTap,
    this.textColor,
  });

  final String? label;
  final IconData? icon;
  final double height;
  final VoidCallback onTap;
  final Color? textColor;

  @override
  State<_NumpadKey> createState() => _NumpadKeyState();
}

class _NumpadKeyState extends State<_NumpadKey>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 60),
      reverseDuration: const Duration(milliseconds: 120),
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
    final color = widget.textColor ?? AppColors.textPrimary;

    return ScaleTransition(
      scale: _scaleAnimation,
      child: GestureDetector(
        onTapDown: (_) => _scaleController.forward(),
        onTapUp: (_) => _scaleController.reverse(),
        onTapCancel: () => _scaleController.reverse(),
        child: SizedBox(
          height: widget.height,
          child: Material(
            color: AppColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onTap,
              splashColor: AppColors.textPrimary.withValues(alpha: 0.08),
              highlightColor: AppColors.surfaceBright,
              child: Center(
                child: widget.icon != null
                    ? Icon(widget.icon, size: 22, color: color)
                    : Text(
                        widget.label ?? '',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: color,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
