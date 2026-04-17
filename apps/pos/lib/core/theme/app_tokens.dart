/// Centralised design tokens for the fine-dining POS shell.
///
/// Extracted from the SambaPOS-esque redesign plan
/// (see Obsidian: "Restaurant - POS UI Redesign Plan 2026-04-17").
///
/// Tokens are intentionally surface-agnostic (spacing, radius, sizing). Colours
/// remain in [AppColors] so the existing theme continues to own palette state.
/// These tokens are an additive layer — old widgets keep working, new shell
/// widgets can opt in via `AppTokens.*`.
library;

import 'package:flutter/widgets.dart';

abstract final class AppTokens {
  // ---------------------------------------------------------------------------
  // Spacing scale (8pt grid)
  // ---------------------------------------------------------------------------

  static const double space2 = 2.0;
  static const double space4 = 4.0;
  static const double space8 = 8.0;
  static const double space12 = 12.0;
  static const double space16 = 16.0;
  static const double space20 = 20.0;
  static const double space24 = 24.0;
  static const double space32 = 32.0;
  static const double space48 = 48.0;

  // ---------------------------------------------------------------------------
  // Radius
  // ---------------------------------------------------------------------------

  static const double radiusXs = 4.0;
  static const double radiusSm = 6.0;
  static const double radiusMd = 10.0;
  static const double radiusLg = 14.0;

  // ---------------------------------------------------------------------------
  // Touch targets (min)
  // ---------------------------------------------------------------------------

  /// Minimum interactive height for icon-only chips / seat selectors.
  static const double touchSmall = 44.0;

  /// Default interactive height for action buttons / nav items.
  static const double touchMedium = 48.0;

  /// Primary action height for the bottom bar, payment CTA etc.
  static const double touchLarge = 56.0;

  // ---------------------------------------------------------------------------
  // Panel sizing — fine-dining three-column shell
  // ---------------------------------------------------------------------------

  /// Left OrderPanel min/max width on 1280-wide tablets.
  static const double orderPanelWidth = 320.0;

  /// Right ActionRail width.
  static const double actionRailWidth = 88.0;

  /// Top bar height.
  static const double topBarHeight = 56.0;

  /// Bottom action bar height.
  static const double bottomBarHeight = 64.0;

  /// Height of the category strip above the product grid.
  static const double categoryStripHeight = 56.0;

  /// Product card aspect ratio — wide landscape tile for food names.
  static const double productCardAspect = 1.15;

  // ---------------------------------------------------------------------------
  // Elevation / borders (tokens, not values — values live in theme)
  // ---------------------------------------------------------------------------

  static const Duration animFast = Duration(milliseconds: 120);
  static const Duration animBase = Duration(milliseconds: 200);
}

/// Convenience [EdgeInsets] presets built from [AppTokens].
abstract final class AppInsets {
  static const EdgeInsets all8 = EdgeInsets.all(AppTokens.space8);
  static const EdgeInsets all12 = EdgeInsets.all(AppTokens.space12);
  static const EdgeInsets all16 = EdgeInsets.all(AppTokens.space16);

  static const EdgeInsets h12v8 =
      EdgeInsets.symmetric(horizontal: AppTokens.space12, vertical: AppTokens.space8);
  static const EdgeInsets h16v12 =
      EdgeInsets.symmetric(horizontal: AppTokens.space16, vertical: AppTokens.space12);
}
