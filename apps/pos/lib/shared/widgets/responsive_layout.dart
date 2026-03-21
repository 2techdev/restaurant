/// Responsive layout utilities for GastroCore POS.
///
/// Provides breakpoint-aware helpers that make screens adapt to both
/// phone (≤ 600 dp) and tablet / landscape (> 600 dp) viewports.
///
/// Usage:
/// ```dart
/// // 1. Branch widget trees by breakpoint
/// ResponsiveLayout(
///   phone: PhoneLayout(),
///   tablet: TabletLayout(),
/// )
///
/// // 2. Query from any widget via context extension
/// if (context.isTablet) { ... }
/// final cols = context.responsiveValue(phone: 2, tablet: 4);
/// ```
library;

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Breakpoints
// ---------------------------------------------------------------------------

/// Width threshold above which the layout switches to "tablet" mode.
const double kTabletBreakpoint = 600.0;

/// Width threshold for "large tablet / desktop" mode.
const double kDesktopBreakpoint = 1024.0;

// ---------------------------------------------------------------------------
// ResponsiveLayout widget
// ---------------------------------------------------------------------------

/// Switches between [phone] and [tablet] widget trees based on screen width.
///
/// [tablet] is optional — falls back to [phone] on tablet when omitted.
/// [desktop] is optional — falls back to [tablet] on desktop when omitted.
class ResponsiveLayout extends StatelessWidget {
  const ResponsiveLayout({
    super.key,
    required this.phone,
    this.tablet,
    this.desktop,
  });

  final Widget phone;
  final Widget? tablet;
  final Widget? desktop;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width >= kDesktopBreakpoint && desktop != null) {
          return desktop!;
        }
        if (width >= kTabletBreakpoint && tablet != null) {
          return tablet!;
        }
        return phone;
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Context extension for inline breakpoint queries
// ---------------------------------------------------------------------------

extension ResponsiveContext on BuildContext {
  /// True when the screen width is >= [kTabletBreakpoint].
  bool get isTablet =>
      MediaQuery.of(this).size.width >= kTabletBreakpoint;

  /// True when the screen width is >= [kDesktopBreakpoint].
  bool get isDesktop =>
      MediaQuery.of(this).size.width >= kDesktopBreakpoint;

  /// True when the device is in landscape orientation.
  bool get isLandscape =>
      MediaQuery.of(this).orientation == Orientation.landscape;

  /// Returns [tablet] value on tablet, [phone] value on phone.
  /// Optionally returns [desktop] on desktop (falls back to [tablet]).
  T responsiveValue<T>({
    required T phone,
    required T tablet,
    T? desktop,
  }) {
    final width = MediaQuery.of(this).size.width;
    if (width >= kDesktopBreakpoint && desktop != null) return desktop;
    if (width >= kTabletBreakpoint) return tablet;
    return phone;
  }

  /// Returns a horizontal content padding appropriate for the screen width.
  ///
  /// - Phone: 16 dp
  /// - Tablet: 32 dp
  /// - Desktop: 64 dp
  double get contentPadding => responsiveValue<double>(
        phone: 16,
        tablet: 32,
        desktop: 64,
      );

  /// Returns the number of grid columns appropriate for the screen width.
  ///
  /// Useful for product grids, dashboard tiles, etc.
  int gridColumns({int phoneCols = 2, int tabletCols = 3, int desktopCols = 4}) =>
      responsiveValue<int>(
        phone: phoneCols,
        tablet: tabletCols,
        desktop: desktopCols,
      );
}

// ---------------------------------------------------------------------------
// ResponsivePadding convenience wrapper
// ---------------------------------------------------------------------------

/// Wraps [child] with horizontal padding that scales with screen width.
class ResponsivePadding extends StatelessWidget {
  const ResponsivePadding({super.key, required this.child, this.vertical = 0});

  final Widget child;
  final double vertical;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: context.contentPadding,
        vertical: vertical,
      ),
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// AdaptiveGridView
// ---------------------------------------------------------------------------

/// A GridView that automatically switches column count based on screen width.
///
/// ```dart
/// AdaptiveGridView(
///   phoneCols: 2,
///   tabletCols: 4,
///   children: products.map((p) => ProductTile(p)).toList(),
/// )
/// ```
class AdaptiveGridView extends StatelessWidget {
  const AdaptiveGridView({
    super.key,
    required this.children,
    this.phoneCols = 2,
    this.tabletCols = 3,
    this.desktopCols = 4,
    this.mainAxisSpacing = 12,
    this.crossAxisSpacing = 12,
    this.childAspectRatio = 1.0,
    this.padding,
    this.shrinkWrap = false,
    this.physics,
  });

  final List<Widget> children;
  final int phoneCols;
  final int tabletCols;
  final int desktopCols;
  final double mainAxisSpacing;
  final double crossAxisSpacing;
  final double childAspectRatio;
  final EdgeInsetsGeometry? padding;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    final cols = context.gridColumns(
      phoneCols: phoneCols,
      tabletCols: tabletCols,
      desktopCols: desktopCols,
    );

    return GridView.count(
      crossAxisCount: cols,
      mainAxisSpacing: mainAxisSpacing,
      crossAxisSpacing: crossAxisSpacing,
      childAspectRatio: childAspectRatio,
      padding: padding,
      shrinkWrap: shrinkWrap,
      physics: physics,
      children: children,
    );
  }
}
