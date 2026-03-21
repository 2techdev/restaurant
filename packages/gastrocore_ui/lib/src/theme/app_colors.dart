/// Design-system color palette for GastroCore.
///
/// Based on Stitch "Precision POS Framework" design system.
/// Uses "Midnight Navy" spectrum with "No-Line" philosophy.
library;

import 'package:flutter/material.dart';

abstract final class AppColors {
  // ---------------------------------------------------------------------------
  // Surface Hierarchy
  // ---------------------------------------------------------------------------

  static const Color surfaceDim = Color(0xFF111319);
  static const Color surface = Color(0xFF151720);
  static const Color surfaceContainerLow = Color(0xFF191B22);
  static const Color surfaceContainer = Color(0xFF1E1F26);
  static const Color surfaceContainerHigh = Color(0xFF282A30);
  static const Color surfaceContainerHighest = Color(0xFF33343B);
  static const Color surfaceBright = Color(0xFF373940);
  static const Color bgInput = Color(0xFF1A1C24);
  static const Color bgOverlay = Color(0xCC111319);

  // Legacy aliases
  static const Color bgPrimary = surfaceDim;
  static const Color bgSecondary = surfaceContainer;
  static const Color bgCard = surfaceContainerLow;
  static const Color bgCardHover = surfaceBright;

  // ---------------------------------------------------------------------------
  // Primary / Accent
  // ---------------------------------------------------------------------------

  static const Color primary = Color(0xFFAFC6FF);
  static const Color primaryContainer = Color(0xFF528DFF);
  static const Color accent = Color(0xFF4F8CFF);
  static const Color accentHover = Color(0xFF6DA0FF);
  static const Color accentDim = Color(0x1A4F8CFF);

  // ---------------------------------------------------------------------------
  // Semantic Colors
  // ---------------------------------------------------------------------------

  static const Color green = Color(0xFF05B046);
  static const Color onGreen = Color(0xFF003A11);
  static const Color greenContainer = Color(0xFF05B046);
  static const Color orange = Color(0xFFFF9F0A);
  static const Color red = Color(0xFFFF3B30);
  static const Color yellow = Color(0xFFFFD60A);
  static const Color purple = Color(0xFFBF5AF2);

  // Dim variants (for badge backgrounds)
  static const Color greenDim = Color(0x1A05B046);
  static const Color orangeDim = Color(0x1AFF9F0A);
  static const Color redDim = Color(0x1AFF3B30);
  static const Color yellowDim = Color(0x1AFFD60A);
  static const Color purpleDim = Color(0x1ABF5AF2);

  // ---------------------------------------------------------------------------
  // Text Hierarchy
  // ---------------------------------------------------------------------------

  static const Color textPrimary = Color(0xFFF0F0F5);
  static const Color textSecondary = Color(0xFF8E8E9A);
  static const Color textDim = Color(0xFF5A5A6A);

  // ---------------------------------------------------------------------------
  // Borders
  // ---------------------------------------------------------------------------

  static const Color border = Color(0x26424753);
  static const Color borderFocused = Color(0xFF4F8CFF);
  static const Color outlineVariant = Color(0xFF424753);
}
