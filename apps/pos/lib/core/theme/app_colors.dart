/// Design-system color palette for GastroCore POS.
///
/// Stitch "Klein Professional POS" dark design system.
/// Ultra-dense tablet UI with surface-layering depth hierarchy.
/// No borders — tonal surfaces express depth.
library;

import 'dart:ui';

abstract final class AppColors {
  // ---------------------------------------------------------------------------
  // Surface Hierarchy — dark tonal system (no borders)
  // Background shifts express depth through surface elevation.
  // ---------------------------------------------------------------------------

  /// Base scaffold background — deepest dark
  static const Color surfaceDim = Color(0xFF0B0E14);

  /// Standard surface — containers, panels
  static const Color surface = Color(0xFF161A21);

  /// Low surface — nav, order panel background
  static const Color surfaceContainerLow = Color(0xFF10131A);

  /// Standard container
  static const Color surfaceContainer = Color(0xFF161A21);

  /// Card surface — product tiles, bill items
  static const Color surfaceContainerHigh = Color(0xFF1C2028);

  /// Most elevated — numpad keys, input fields
  static const Color surfaceContainerHighest = Color(0xFF22262F);

  /// Hover / pressed state surface
  static const Color surfaceBright = Color(0xFF282C36);

  /// Input field background
  static const Color bgInput = Color(0xFF1C2028);

  /// Modal overlay
  static const Color bgOverlay = Color(0x80000000);

  // Legacy aliases kept for backward compatibility
  static const Color bgPrimary = surfaceDim;
  static const Color bgSecondary = surface;
  static const Color bgCard = surfaceContainerHigh;
  static const Color bgCardHover = surfaceBright;

  // ---------------------------------------------------------------------------
  // Navigation — always dark, matches surfaceContainerLow
  // ---------------------------------------------------------------------------

  static const Color navSurface = Color(0xFF10131A);
  static const Color navSurfaceHover = Color(0xFF1C2028);
  static const Color navSurfaceActive = Color(0xFF316BF3);
  static const Color navText = Color(0xFF73757D);
  static const Color navTextActive = Color(0xFF90ABFF);
  static const Color navDivider = Color(0xFF1C2028);

  // ---------------------------------------------------------------------------
  // Primary — Stitch periwinkle blue
  // ---------------------------------------------------------------------------

  /// Primary action color — periwinkle
  static const Color primary = Color(0xFF90ABFF);

  /// Primary dim — button backgrounds, price badges
  static const Color primaryContainer = Color(0xFF316BF3);

  /// Primary light — highlights
  static const Color primaryLight = Color(0xFF90ABFF);

  /// Alias for primary
  static const Color accent = Color(0xFF90ABFF);

  /// Primary hover
  static const Color accentHover = Color(0xFFAAC0FF);

  /// Tinted primary background — ~20% opacity
  static const Color accentDim = Color(0x3390ABFF);

  // ---------------------------------------------------------------------------
  // Secondary — Ready / Sent green
  // ---------------------------------------------------------------------------

  /// Success — available, paid, completed, sent to kitchen
  static const Color green = Color(0xFF69F6B8);

  /// On green (text on green bg)
  static const Color onGreen = Color(0xFF003822);

  /// Secondary container green
  static const Color greenContainer = Color(0xFF69F6B8);

  // ---------------------------------------------------------------------------
  // Tertiary / Error — warning red-pink
  // ---------------------------------------------------------------------------

  /// Coral / error — void, destructive, error states
  static const Color coral = Color(0xFFFF6F7E);

  /// Darker coral for pressed states
  static const Color coralDark = Color(0xFFE55A6A);

  /// Tinted coral background
  static const Color coralDim = Color(0x33FF6F7E);

  // ---------------------------------------------------------------------------
  // Semantic colors
  // ---------------------------------------------------------------------------

  /// Warning / amber — reserved, pending
  static const Color orange = Color(0xFFFFAB4E);

  /// Error (alias for coral)
  static const Color red = Color(0xFFFF6F7E);

  /// Info / highlight
  static const Color yellow = Color(0xFFFFD166);

  /// Special / promo
  static const Color purple = Color(0xFFB794FF);

  // ---------------------------------------------------------------------------
  // Dim semantic — tinted badge backgrounds
  // ---------------------------------------------------------------------------

  static const Color greenDim = Color(0x2269F6B8);
  static const Color orangeDim = Color(0x22FFAB4E);
  static const Color redDim = Color(0x22FF6F7E);
  static const Color yellowDim = Color(0x22FFD166);
  static const Color purpleDim = Color(0x22B794FF);

  // ---------------------------------------------------------------------------
  // Text Hierarchy
  // ---------------------------------------------------------------------------

  /// Primary text — near white
  static const Color textPrimary = Color(0xFFECEDF6);

  /// Secondary text — muted
  static const Color textSecondary = Color(0xFFA9ABB3);

  /// Dim / placeholder / disabled
  static const Color textDim = Color(0xFF73757D);

  // ---------------------------------------------------------------------------
  // Borders & Dividers — very subtle on dark system
  // ---------------------------------------------------------------------------

  /// Default border — ~10% white
  static const Color border = Color(0x1AECEDF6);

  /// Focused / active element border
  static const Color borderFocused = Color(0xFF90ABFF);

  /// Subtle separators
  static const Color outlineVariant = Color(0x0FECEDF6);
}
