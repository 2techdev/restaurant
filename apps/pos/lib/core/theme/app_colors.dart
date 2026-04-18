/// Design-system color palette for GastroCore POS.
///
/// Pilot v3 rolls out the Kinetic Grid light surface across every screen.
/// The constants in this file used to carry the legacy Stitch "Midnight Navy"
/// dark values; the name/ identifiers are kept so the 60+ existing screens
/// compile unchanged while flipping to the light palette automatically.
/// For new code prefer [GcColors] in `kinetic_theme.dart`.
library;

import 'dart:ui';

abstract final class AppColors {
  // ---------------------------------------------------------------------------
  // Surface Hierarchy — Kinetic Grid light tonal stack
  // ---------------------------------------------------------------------------

  /// Base layer — canvas background.
  static const Color surfaceDim = Color(0xFFF4F7F9);

  /// Intermediate layer — sidebar / panels.
  static const Color surface = Color(0xFFFFFFFF);

  /// Container low — cards, product tiles.
  static const Color surfaceContainerLow = Color(0xFFEEF1F3);

  /// Container — elevated elements.
  static const Color surfaceContainer = Color(0xFFE4E9EB);

  /// Container high — PIN pad keys, active elements.
  static const Color surfaceContainerHigh = Color(0xFFDEE3E6);

  /// Container highest — modals, active product cards.
  static const Color surfaceContainerHighest = Color(0xFFD8DEE1);

  /// Bright surface — hover/active states.
  static const Color surfaceBright = Color(0xFFFFFFFF);

  /// Input field background.
  static const Color bgInput = Color(0xFFFFFFFF);

  /// Modal overlay — translucent onSurface scrim for dialogs.
  static const Color bgOverlay = Color(0xCC2B2F31);

  // Legacy aliases for backward compatibility
  static const Color bgPrimary = surfaceDim;
  static const Color bgSecondary = surfaceContainer;
  static const Color bgCard = surfaceContainerLow;
  static const Color bgCardHover = surfaceBright;

  // ---------------------------------------------------------------------------
  // Primary / Accent
  // ---------------------------------------------------------------------------

  /// Primary accent — Kinetic brand blue.
  static const Color primary = Color(0xFF3841E9);

  /// Primary container — deeper blue for gradients.
  static const Color primaryContainer = Color(0xFF2931DE);

  /// Classic accent (alias).
  static const Color accent = Color(0xFF3841E9);

  /// Accent hover.
  static const Color accentHover = Color(0xFF2931DE);

  /// Accent dim — tinted background for selected states.
  static const Color accentDim = Color(0x1A3841E9);

  // ---------------------------------------------------------------------------
  // Semantic Colors
  // ---------------------------------------------------------------------------

  /// Success / available / paid / completed / KDS ready
  static const Color green = Color(0xFF69F6B8);

  /// On green (text on green bg)
  static const Color onGreen = Color(0xFF003322);

  /// Secondary container green
  static const Color greenContainer = Color(0xFF69F6B8);

  /// Warning / pending / kitchen / attention
  static const Color orange = Color(0xFFFF9F0A);

  /// Error / occupied / void / urgent / destructive / KDS overdue
  static const Color red = Color(0xFFFF6F7E);

  /// Info / highlight / notes / special instructions
  static const Color yellow = Color(0xFFFFD60A);

  /// Special / promo / VIP
  static const Color purple = Color(0xFFBF5AF2);

  // ---------------------------------------------------------------------------
  // Dim Semantic (tinted backgrounds for badges / status chips)
  // ---------------------------------------------------------------------------

  static const Color greenDim = Color(0x1A69F6B8);
  static const Color orangeDim = Color(0x1AFF9F0A);
  static const Color redDim = Color(0x1AFF6F7E);
  static const Color yellowDim = Color(0x1AFFD60A);
  static const Color purpleDim = Color(0x1ABF5AF2);

  // ---------------------------------------------------------------------------
  // Text Hierarchy
  // ---------------------------------------------------------------------------

  /// Coral / tertiary — warm accent for promotions, highlights
  static const Color coral = Color(0xFFFF6B8A);

  /// Nav surface — sidebar / bottom-nav background
  static const Color navSurface = Color(0xFFEEF1F3);

  /// Nav surface hover state
  static const Color navSurfaceHover = Color(0xFFE4E9EB);

  /// Nav divider — subtle separator in sidebar
  static const Color navDivider = Color(0x33AAAEB0);

  /// Nav text — default sidebar label color
  static const Color navText = Color(0xFF585C5E);

  /// Nav text active — selected item label color
  static const Color navTextActive = Color(0xFF2B2F31);

  /// Primary light — lighter variant of primary for gradients and icons
  static const Color primaryLight = Color(0xFF9097FF);

  /// Primary dim — 10% primary tint for hover/pressed states
  static const Color primaryDim = Color(0x1A3841E9);

  /// Error — alias for red, for semantic clarity
  static const Color error = red;

  /// Primary text (high emphasis).
  static const Color textPrimary = Color(0xFF2B2F31);

  /// Secondary text (medium emphasis).
  static const Color textSecondary = Color(0xFF585C5E);

  /// Dim / placeholder / disabled text.
  static const Color textDim = Color(0xFF737779);

  // ---------------------------------------------------------------------------
  // Borders (use sparingly - prefer "No-Line" philosophy)
  // ---------------------------------------------------------------------------

  /// Ghost border — translucent outline-variant (20% alpha).
  static const Color border = Color(0x33AAAEB0);

  /// Focused / active element border.
  static const Color borderFocused = Color(0xFF3841E9);

  /// Outline variant for subtle separators.
  static const Color outlineVariant = Color(0xFFAAAEB0);
}
