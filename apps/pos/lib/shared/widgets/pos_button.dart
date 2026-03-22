/// POS Button variants — Klein Professional POS dark theme.
///
/// Four button types covering all POS interaction contexts:
///
/// - [PosGradientButton] — Primary CTA (Pay, Confirm, Submit).
///   primaryDim solid color, white text, tight 4px radius. Full-width by default.
///
/// - [PosSolidButton] — Semantic action (Send = secondary green,
///   Void = error red, Accept = green). Single solid color background.
///
/// - [PosGhostButton] — Tertiary actions (Cancel, Dismiss).
///   Transparent background, primary-colored text.
///
/// - [PosSurfaceButton] — Secondary actions (Category tabs, toggles).
///   surfaceContainerHighest bg with primaryDim active state.
///
/// All buttons enforce 48px minimum touch targets, scale-down press
/// feedback (0.97), and 150ms transitions.
library;

import 'package:flutter/material.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';

// ---------------------------------------------------------------------------
// Gradient Primary Button
// ---------------------------------------------------------------------------

/// Primary call-to-action with a teal gradient.
/// Use for: Pay, Confirm, Submit, Place Order.
class PosGradientButton extends StatefulWidget {
  const PosGradientButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.height = 52,
    this.isLoading = false,
    this.borderRadius = 4,
    this.expand = true,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final double height;
  final bool isLoading;
  final double borderRadius;
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

  void _onTapUp(TapUpDetails _) => _scaleController.reverse();
  void _onTapCancel() => _scaleController.reverse();

  @override
  Widget build(BuildContext context) {
    final effectiveHeight = widget.height.clamp(48.0, double.infinity);

    return ScaleTransition(
      scale: _scaleAnimation,
      child: GestureDetector(
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: _enabled ? 1.0 : 0.35,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.primaryDim,
              borderRadius: BorderRadius.circular(widget.borderRadius),
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(widget.borderRadius),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _enabled ? widget.onPressed : null,
                splashColor: Colors.white.withValues(alpha: 0.15),
                highlightColor: Colors.white.withValues(alpha: 0.05),
                child: SizedBox(
                  height: effectiveHeight,
                  width: widget.expand ? double.infinity : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Center(
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
                                  Icon(widget.icon,
                                      size: 20, color: Colors.white),
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
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Solid Color Button
// ---------------------------------------------------------------------------

/// Solid-colored button for semantic actions.
///
/// Use [AppColors.coral] for "Send to Kitchen",
/// [AppColors.red] for "Void", [AppColors.green] for "Accept".
class PosSolidButton extends StatefulWidget {
  const PosSolidButton({
    super.key,
    required this.label,
    this.icon,
    required this.color,
    this.onPressed,
    this.height = 52,
    this.borderRadius = 4,
    this.expand = true,
    this.isLoading = false,
  });

  final String label;
  final IconData? icon;
  final Color color;
  final VoidCallback? onPressed;
  final double height;
  final double borderRadius;
  final bool expand;
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
    final effectiveHeight = widget.height.clamp(48.0, double.infinity);

    return ScaleTransition(
      scale: _scaleAnimation,
      child: GestureDetector(
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: _enabled ? 1.0 : 0.45,
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

/// Transparent button for tertiary actions (Cancel, Dismiss, Back).
class PosGhostButton extends StatefulWidget {
  const PosGhostButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.color,
    this.height = 48,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  /// Text/icon color. Defaults to [AppColors.textSecondary].
  final Color? color;
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
    final effectiveHeight = widget.height.clamp(48.0, double.infinity);
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
              splashColor: color.withValues(alpha: 0.08),
              highlightColor: color.withValues(alpha: 0.04),
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
// Surface Button — category tabs, mode toggles
// ---------------------------------------------------------------------------

/// Light gray button with teal active state.
/// Use for category tabs, order type toggles, mode selectors.
class PosSurfaceButton extends StatefulWidget {
  const PosSurfaceButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.isActive = false,
    this.height = 48,
    this.borderRadius = 20,
    this.expand = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isActive;
  final double height;

  /// Defaults to 20 for pill-shaped category tabs.
  final double borderRadius;
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
    final effectiveHeight = widget.height.clamp(48.0, double.infinity);
    final bgColor = widget.isActive
        ? AppColors.primaryDim
        : AppColors.surfaceContainerHighest;
    final textColor =
        widget.isActive ? Colors.white : AppColors.textSecondary;

    return ScaleTransition(
      scale: _scaleAnimation,
      child: GestureDetector(
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: _enabled ? 1.0 : 0.45,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: Material(
              color: bgColor,
              borderRadius: BorderRadius.circular(widget.borderRadius),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _enabled ? widget.onPressed : null,
                splashColor: widget.isActive
                    ? Colors.white.withValues(alpha: 0.1)
                    : AppColors.primary.withValues(alpha: 0.06),
                highlightColor: widget.isActive
                    ? Colors.white.withValues(alpha: 0.05)
                    : AppColors.primary.withValues(alpha: 0.03),
                child: Container(
                  height: effectiveHeight,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize:
                        widget.expand ? MainAxisSize.max : MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (widget.icon != null) ...[
                        Icon(widget.icon, size: 16, color: textColor),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        widget.label,
                        style: TextStyle(
                          fontSize: 13,
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
