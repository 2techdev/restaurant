/// POS Button variants following the Stitch "Precision POS Framework".
///
/// Provides four button types for the GastroCore POS surface hierarchy:
///
/// - [PosGradientButton] — Primary actions (pay, confirm, submit).
///   Linear gradient from `AppColors.primary` to `AppColors.primaryContainer`.
///
/// - [PosSolidButton] — Semantic actions (kitchen send = green, void = red).
///   Single solid color background.
///
/// - [PosGhostButton] — Tertiary actions (cancel, dismiss).
///   Transparent background, accent-colored text.
///
/// - [PosSurfaceButton] — Secondary actions (category tabs, mode toggles).
///   Surface-colored background with active state.
///
/// All buttons enforce 44px minimum touch targets, use scale-down press
/// feedback (0.97), and follow the "No-Line" rule (no 1px borders).
library;

import 'package:flutter/material.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';

// ---------------------------------------------------------------------------
// Gradient Primary Button
// ---------------------------------------------------------------------------

/// A prominent call-to-action button with a 135° linear gradient
/// from [AppColors.primary] to [AppColors.primaryContainer].
///
/// Use for primary actions: Pay, Confirm, Submit, Place Order.
///
/// ```dart
/// PosGradientButton(
///   label: 'Pay CHF 28.50',
///   icon: Icons.payment,
///   onPressed: () => handlePayment(),
/// )
/// ```
class PosGradientButton extends StatefulWidget {
  const PosGradientButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.height = 52,
    this.isLoading = false,
    this.borderRadius = 12,
    this.expand = true,
  });

  /// Button label text.
  final String label;

  /// Optional leading icon.
  final IconData? icon;

  /// Tap callback. When `null` the button renders in disabled state.
  final VoidCallback? onPressed;

  /// Button height. Minimum enforced at 44px (touch target).
  final double height;

  /// When `true`, shows a circular progress indicator instead of content.
  final bool isLoading;

  /// Corner radius. Defaults to 12 (Stitch medium radius).
  final double borderRadius;

  /// Whether the button expands to fill available width.
  final bool expand;

  @override
  State<PosGradientButton> createState() => _PosGradientButtonState();
}

class _PosGradientButtonState extends State<PosGradientButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleController;
  late final Animation<double> _scaleAnimation;

  bool get _enabled => widget.onPressed != null && !widget.isLoading;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 150),
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

  void _onTapDown(TapDownDetails _) {
    if (_enabled) _scaleController.forward();
  }

  void _onTapUp(TapUpDetails _) {
    _scaleController.reverse();
  }

  void _onTapCancel() {
    _scaleController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveHeight = widget.height.clamp(44.0, double.infinity);

    return ScaleTransition(
      scale: _scaleAnimation,
      child: GestureDetector(
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: _enabled ? 1.0 : 0.4,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(widget.borderRadius),
            clipBehavior: Clip.antiAlias,
            child: Ink(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primary, AppColors.primaryContainer],
                ),
                borderRadius: BorderRadius.circular(widget.borderRadius),
              ),
              child: InkWell(
                onTap: _enabled ? widget.onPressed : null,
                splashColor: Colors.white.withValues(alpha: 0.15),
                highlightColor: Colors.white.withValues(alpha: 0.05),
                child: Container(
                  height: effectiveHeight,
                  constraints: BoxConstraints(
                    minWidth: widget.expand ? double.infinity : 120,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  alignment: Alignment.center,
                  child: widget.isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Row(
                          mainAxisSize: widget.expand
                              ? MainAxisSize.max
                              : MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (widget.icon != null) ...[
                              Icon(widget.icon, size: 20, color: Colors.white),
                              const SizedBox(width: 10),
                            ],
                            Text(
                              widget.label,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
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

// ---------------------------------------------------------------------------
// Solid Color Button
// ---------------------------------------------------------------------------

/// A solid-colored button for semantic actions.
///
/// Use with [AppColors.green] for "Send to Kitchen", [AppColors.red] for
/// "Void Item", [AppColors.orange] for warnings, etc.
///
/// ```dart
/// PosSolidButton(
///   label: 'Send to Kitchen',
///   icon: Icons.restaurant,
///   color: AppColors.green,
///   onPressed: () => sendToKitchen(),
/// )
/// ```
class PosSolidButton extends StatefulWidget {
  const PosSolidButton({
    super.key,
    required this.label,
    this.icon,
    required this.color,
    this.onPressed,
    this.height = 52,
    this.borderRadius = 12,
    this.expand = true,
    this.isLoading = false,
  });

  /// Button label text.
  final String label;

  /// Optional leading icon.
  final IconData? icon;

  /// Background color. Use semantic colors from [AppColors].
  final Color color;

  /// Tap callback. When `null` the button renders in disabled state.
  final VoidCallback? onPressed;

  /// Button height. Minimum enforced at 44px.
  final double height;

  /// Corner radius. Defaults to 12.
  final double borderRadius;

  /// Whether the button expands to fill available width.
  final bool expand;

  /// When `true`, shows a circular progress indicator instead of content.
  final bool isLoading;

  @override
  State<PosSolidButton> createState() => _PosSolidButtonState();
}

class _PosSolidButtonState extends State<PosSolidButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleController;
  late final Animation<double> _scaleAnimation;

  bool get _enabled => widget.onPressed != null && !widget.isLoading;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 150),
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

  void _onTapDown(TapDownDetails _) {
    if (_enabled) _scaleController.forward();
  }

  void _onTapUp(TapUpDetails _) => _scaleController.reverse();

  void _onTapCancel() => _scaleController.reverse();

  @override
  Widget build(BuildContext context) {
    final effectiveHeight = widget.height.clamp(44.0, double.infinity);

    return ScaleTransition(
      scale: _scaleAnimation,
      child: GestureDetector(
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: _enabled ? 1.0 : 0.4,
          child: Material(
            color: widget.color,
            borderRadius: BorderRadius.circular(widget.borderRadius),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _enabled ? widget.onPressed : null,
              splashColor: Colors.white.withValues(alpha: 0.15),
              highlightColor: Colors.white.withValues(alpha: 0.05),
              child: Container(
                height: effectiveHeight,
                constraints: BoxConstraints(
                  minWidth: widget.expand ? double.infinity : 120,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                alignment: Alignment.center,
                child: widget.isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Row(
                        mainAxisSize: widget.expand
                            ? MainAxisSize.max
                            : MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (widget.icon != null) ...[
                            Icon(widget.icon, size: 20, color: Colors.white),
                            const SizedBox(width: 10),
                          ],
                          Text(
                            widget.label,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ghost / Text Button
// ---------------------------------------------------------------------------

/// A transparent button for tertiary actions such as Cancel or Dismiss.
///
/// No background color — text and optional icon only, using accent color.
/// Follows the "No-Line" rule: no borders, hover state uses a subtle
/// surface-colored overlay.
///
/// ```dart
/// PosGhostButton(
///   label: 'Cancel',
///   onPressed: () => Navigator.pop(context),
/// )
/// ```
class PosGhostButton extends StatefulWidget {
  const PosGhostButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.color,
    this.height = 48,
  });

  /// Button label text.
  final String label;

  /// Optional leading icon.
  final IconData? icon;

  /// Tap callback. When `null` the button renders in disabled state.
  final VoidCallback? onPressed;

  /// Text and icon color. Defaults to [AppColors.textSecondary].
  final Color? color;

  /// Button height. Minimum enforced at 44px.
  final double height;

  @override
  State<PosGhostButton> createState() => _PosGhostButtonState();
}

class _PosGhostButtonState extends State<PosGhostButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleController;
  late final Animation<double> _scaleAnimation;

  bool get _enabled => widget.onPressed != null;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 150),
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

  void _onTapDown(TapDownDetails _) {
    if (_enabled) _scaleController.forward();
  }

  void _onTapUp(TapUpDetails _) => _scaleController.reverse();

  void _onTapCancel() => _scaleController.reverse();

  @override
  Widget build(BuildContext context) {
    final effectiveHeight = widget.height.clamp(44.0, double.infinity);
    final color = widget.color ?? AppColors.textSecondary;

    return ScaleTransition(
      scale: _scaleAnimation,
      child: GestureDetector(
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: _enabled ? 1.0 : 0.4,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _enabled ? widget.onPressed : null,
              splashColor: color.withValues(alpha: 0.1),
              highlightColor: color.withValues(alpha: 0.05),
              child: Container(
                height: effectiveHeight,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.icon != null) ...[
                      Icon(widget.icon, size: 18, color: color),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      widget.label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Surface Button
// ---------------------------------------------------------------------------

/// A surface-colored button for secondary actions, category tabs, and
/// mode toggles.
///
/// Background shifts from [AppColors.surfaceContainerHigh] (default) to
/// [AppColors.surfaceBright] (active) — following the "No-Line" rule.
///
/// ```dart
/// PosSurfaceButton(
///   label: 'Dine In',
///   icon: Icons.restaurant,
///   isActive: selectedMode == OrderMode.dineIn,
///   onPressed: () => setMode(OrderMode.dineIn),
/// )
/// ```
class PosSurfaceButton extends StatefulWidget {
  const PosSurfaceButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.isActive = false,
    this.height = 48,
    this.borderRadius = 10,
    this.expand = false,
  });

  /// Button label text.
  final String label;

  /// Optional leading icon.
  final IconData? icon;

  /// Tap callback. When `null` the button renders in disabled state.
  final VoidCallback? onPressed;

  /// Whether the button is in its active/selected state.
  final bool isActive;

  /// Button height. Minimum enforced at 44px.
  final double height;

  /// Corner radius. Defaults to 10.
  final double borderRadius;

  /// Whether the button expands to fill available width.
  final bool expand;

  @override
  State<PosSurfaceButton> createState() => _PosSurfaceButtonState();
}

class _PosSurfaceButtonState extends State<PosSurfaceButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleController;
  late final Animation<double> _scaleAnimation;

  bool get _enabled => widget.onPressed != null;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 150),
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

  void _onTapDown(TapDownDetails _) {
    if (_enabled) _scaleController.forward();
  }

  void _onTapUp(TapUpDetails _) => _scaleController.reverse();

  void _onTapCancel() => _scaleController.reverse();

  @override
  Widget build(BuildContext context) {
    final effectiveHeight = widget.height.clamp(44.0, double.infinity);
    final bgColor = widget.isActive
        ? AppColors.surfaceBright
        : AppColors.surfaceContainerHigh;
    final textColor =
        widget.isActive ? AppColors.textPrimary : AppColors.textSecondary;

    return ScaleTransition(
      scale: _scaleAnimation,
      child: GestureDetector(
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: _enabled ? 1.0 : 0.4,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: Material(
              color: bgColor,
              borderRadius: BorderRadius.circular(widget.borderRadius),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _enabled ? widget.onPressed : null,
                splashColor: AppColors.textPrimary.withValues(alpha: 0.06),
                highlightColor: AppColors.textPrimary.withValues(alpha: 0.03),
                child: Container(
                  height: effectiveHeight,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: widget.expand
                        ? MainAxisSize.max
                        : MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (widget.icon != null) ...[
                        Icon(widget.icon, size: 18, color: textColor),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        widget.label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                    ],
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
