/// Animated list-item entry widget for GastroCore POS.
///
/// Wraps any [child] in a staggered fade + slide-up entrance animation that
/// starts after an [index]-based [staggerDelay]. Use in [ListView.builder]
/// or [GridView] to give lists a polished, sequential reveal effect.
///
/// Usage:
/// ```dart
/// ListView.builder(
///   itemBuilder: (context, index) {
///     return PosAnimatedListItem(
///       index: index,
///       child: OrderCard(order: orders[index]),
///     );
///   },
/// )
/// ```
library;

import 'package:flutter/material.dart';

/// A wrapper that animates its [child] into view with a fade + slide-up
/// entrance, staggered by [index] × [staggerDelay].
class PosAnimatedListItem extends StatefulWidget {
  const PosAnimatedListItem({
    super.key,
    required this.index,
    required this.child,
    this.staggerDelay = const Duration(milliseconds: 40),
    this.duration = const Duration(milliseconds: 320),
    this.slideOffset = const Offset(0, 0.06),
    this.curve = Curves.easeOutCubic,
  });

  /// Position in the list — drives the stagger offset.
  final int index;

  /// Widget to animate.
  final Widget child;

  /// Delay multiplied by [index] to create a staggered effect.
  /// Defaults to 40 ms — 10 items enter over ~400 ms.
  final Duration staggerDelay;

  /// Duration of each item's animation.
  final Duration duration;

  /// Initial translation offset (normalised). Defaults to slight upward slide.
  final Offset slideOffset;

  /// Easing curve.
  final Curve curve;

  @override
  State<PosAnimatedListItem> createState() => _PosAnimatedListItemState();
}

class _PosAnimatedListItemState extends State<PosAnimatedListItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _fade = CurvedAnimation(parent: _controller, curve: widget.curve);

    _slide = Tween<Offset>(
      begin: widget.slideOffset,
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: widget.curve));

    // Cap stagger at 20 items to prevent very long delays on large lists.
    final clampedIndex = widget.index.clamp(0, 20);
    final delay = widget.staggerDelay * clampedIndex;

    if (delay == Duration.zero) {
      _controller.forward();
    } else {
      Future<void>.delayed(delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: widget.child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PosAnimatedSwitcher — cross-fade between different states
// ---------------------------------------------------------------------------

/// A convenience wrapper around [AnimatedSwitcher] tuned for the POS
/// surface hierarchy: smooth cross-fade (220 ms) between loading, empty,
/// and data states.
///
/// ```dart
/// PosAnimatedSwitcher(
///   child: isLoading
///       ? const PosShimmerCard(key: ValueKey('loading'))
///       : DataWidget(key: ValueKey('data')),
/// )
/// ```
class PosAnimatedSwitcher extends StatelessWidget {
  const PosAnimatedSwitcher({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 220),
  });

  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// PosSlideInWidget — directional slide-in for drawers / panels
// ---------------------------------------------------------------------------

/// Slides a widget in from a given [direction] when it first mounts.
/// Useful for side panels, detail drawers, and bottom sheets that render
/// inside the widget tree rather than as overlay routes.
class PosSlideInWidget extends StatefulWidget {
  const PosSlideInWidget({
    super.key,
    required this.child,
    this.direction = AxisDirection.up,
    this.duration = const Duration(milliseconds: 280),
    this.curve = Curves.easeOutCubic,
    this.delay = Duration.zero,
  });

  final Widget child;

  /// Direction from which the widget slides in.
  final AxisDirection direction;

  final Duration duration;
  final Curve curve;

  /// Optional delay before the animation starts.
  final Duration delay;

  @override
  State<PosSlideInWidget> createState() => _PosSlideInWidgetState();
}

class _PosSlideInWidgetState extends State<PosSlideInWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  Offset _beginOffset() => switch (widget.direction) {
        AxisDirection.up => const Offset(0, 0.08),
        AxisDirection.down => const Offset(0, -0.08),
        AxisDirection.left => const Offset(0.08, 0),
        AxisDirection.right => const Offset(-0.08, 0),
      };

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _slide = Tween<Offset>(begin: _beginOffset(), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: widget.curve),
    );
    _fade = CurvedAnimation(parent: _controller, curve: widget.curve);

    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
