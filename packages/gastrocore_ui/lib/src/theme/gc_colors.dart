/// Semantic color tokens for the GastroCore design system.
///
/// `GcColors` is the public, stable color API consumed by `Gc*` widgets and
/// apps. It is a thin semantic overlay on top of `AppColors` — widgets should
/// reference `GcColors.surface` / `GcColors.textPrimary` instead of the raw
/// palette so we can evolve the palette without rewriting every call site.
library;

import 'package:flutter/material.dart';
import 'app_colors.dart';

abstract final class GcColors {
  // ---------------------------------------------------------------------------
  // Surfaces
  // ---------------------------------------------------------------------------

  static const Color surface = AppColors.surface;
  static const Color surfaceDim = AppColors.surfaceDim;
  static const Color surfaceLow = AppColors.surfaceContainerLow;
  static const Color surfaceMedium = AppColors.surfaceContainer;
  static const Color surfaceHigh = AppColors.surfaceContainerHigh;
  static const Color surfaceHighest = AppColors.surfaceContainerHighest;
  static const Color surfaceBright = AppColors.surfaceBright;
  static const Color overlay = AppColors.bgOverlay;
  static const Color inputFill = AppColors.bgInput;

  // ---------------------------------------------------------------------------
  // Brand
  // ---------------------------------------------------------------------------

  static const Color brand = AppColors.primary;
  static const Color brandStrong = AppColors.primaryContainer;
  static const Color accent = AppColors.accent;
  static const Color accentHover = AppColors.accentHover;
  static const Color accentSoft = AppColors.accentDim;

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  static const Color success = AppColors.green;
  static const Color successSoft = AppColors.greenDim;
  static const Color onSuccess = AppColors.onGreen;
  static const Color warning = AppColors.orange;
  static const Color warningSoft = AppColors.orangeDim;
  static const Color danger = AppColors.red;
  static const Color dangerSoft = AppColors.redDim;
  static const Color info = AppColors.accent;
  static const Color infoSoft = AppColors.accentDim;
  static const Color highlight = AppColors.yellow;
  static const Color highlightSoft = AppColors.yellowDim;
  static const Color premium = AppColors.purple;
  static const Color premiumSoft = AppColors.purpleDim;

  // ---------------------------------------------------------------------------
  // Text
  // ---------------------------------------------------------------------------

  static const Color textPrimary = AppColors.textPrimary;
  static const Color textSecondary = AppColors.textSecondary;
  static const Color textDim = AppColors.textDim;
  static const Color textOnBrand = Color(0xFF00174A);
  static const Color textOnAccent = Colors.white;

  // ---------------------------------------------------------------------------
  // Borders
  // ---------------------------------------------------------------------------

  static const Color border = AppColors.border;
  static const Color borderStrong = AppColors.outlineVariant;
  static const Color borderFocused = AppColors.borderFocused;
}
