/// Typographic scale for the GastroCore design system.
///
/// Mirrors the Material 3 role names used by `GastrocoreTheme.dart()` so an
/// app can either consume the ambient `Theme.of(context).textTheme` or pull a
/// style directly from `GcTextStyles` for a non-themed context (tests,
/// embedded previews, PDF builders).
library;

import 'package:flutter/material.dart';
import 'gc_colors.dart';

abstract final class GcTextStyles {
  static const TextStyle displayLarge = TextStyle(
    color: GcColors.textPrimary,
    fontSize: 32,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
  );

  static const TextStyle displayMedium = TextStyle(
    color: GcColors.textPrimary,
    fontSize: 24,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4,
  );

  static const TextStyle headline = TextStyle(
    color: GcColors.textPrimary,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
  );

  static const TextStyle titleLarge = TextStyle(
    color: GcColors.textPrimary,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
  );

  static const TextStyle titleMedium = TextStyle(
    color: GcColors.textPrimary,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.2,
  );

  static const TextStyle titleSmall = TextStyle(
    color: GcColors.textPrimary,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.1,
  );

  static const TextStyle bodyLarge = TextStyle(
    color: GcColors.textPrimary,
    fontSize: 15,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle bodyMedium = TextStyle(
    color: GcColors.textSecondary,
    fontSize: 13,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle bodySmall = TextStyle(
    color: GcColors.textDim,
    fontSize: 11,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle labelLarge = TextStyle(
    color: GcColors.textPrimary,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.2,
  );

  static const TextStyle labelMedium = TextStyle(
    color: GcColors.textSecondary,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.2,
  );

  /// Tabular numeric style for prices and totals — enables `tnum` so digit
  /// columns stay aligned across rows.
  static const TextStyle priceTabular = TextStyle(
    color: GcColors.textPrimary,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Large emphasized total used on bill / Z-report summaries.
  static const TextStyle totalEmphasis = TextStyle(
    color: GcColors.textPrimary,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}
