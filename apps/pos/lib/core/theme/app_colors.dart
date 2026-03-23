/// Design-system color palette for GastroCore POS.
///
/// Based on Stitch "Precision POS Framework" design system.
/// Uses "Midnight Navy" spectrum with "No-Line" philosophy.
/// Boundaries defined by background shifts and negative space, not borders.
library;

import 'dart:ui';

abstract final class AppColors {
  // ---------------------------------------------------------------------------
  // Surface Hierarchy (Stitch "Physical Stack of Materials")
  // ---------------------------------------------------------------------------

  /// Base layer - "The Tabletop" (main background, darkest)
  static const Color surfaceDim = Color(0xFF0B0E14);

  /// Intermediate layer - "The Tray" (sidebar, panels)
  static const Color surface = Color(0xFF151720);

  /// Container low - cards, product tiles
  static const Color surfaceContainerLow = Color(0xFF191B22);

  /// Container - elevated elements
  static const Color surfaceContainer = Color(0xFF1E1F26);

  /// Container high - PIN pad keys, active elements
  static const Color surfaceContainerHigh = Color(0xFF282A30);

  /// Container highest - modals, active product cards
  static const Color surfaceContainerHighest = Color(0xFF33343B);

  /// Bright surface - hover/active states
  static const Color surfaceBright = Color(0xFF373940);

  /// Input field background
  static const Color bgInput = Color(0xFF1A1C24);

  /// Modal overlay (80% opacity)
  static const Color bgOverlay = Color(0xCC111319);

  // Legacy aliases for backward compatibility
  static const Color bgPrimary = surfaceDim;
  static const Color bgSecondary = surfaceContainer;
  static const Color bgCard = surfaceContainerLow;
  static const Color bgCardHover = surfaceBright;

  // ---------------------------------------------------------------------------
  // Primary / Accent
  // ---------------------------------------------------------------------------

  /// Primary accent - action blue
  static const Color primary = Color(0xFF90ABFF);

  /// Primary container - deeper blue for gradients
  static const Color primaryContainer = Color(0xFF528DFF);

  /// Classic accent (alias)
  static const Color accent = Color(0xFF4F8CFF);

  /// Accent hover
  static const Color accentHover = Color(0xFF6DA0FF);

  /// Accent dim (tinted background for selected states)
  static const Color accentDim = Color(0x1A4F8CFF);

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

  /// Primary text (high emphasis) - NEVER use pure #FFFFFF
  static const Color textPrimary = Color(0xFFF0F0F5);

  /// Secondary text (medium emphasis)
  static const Color textSecondary = Color(0xFF8E8E9A);

  /// Dim / placeholder / disabled text
  static const Color textDim = Color(0xFF5A5A6A);

  // ---------------------------------------------------------------------------
  // Borders (use sparingly - prefer "No-Line" philosophy)
  // ---------------------------------------------------------------------------

  /// Ghost border - 15% opacity outline-variant per Stitch design
  static const Color border = Color(0x26424753);

  /// Focused / active element border (only when necessary)
  static const Color borderFocused = Color(0xFF4F8CFF);

  /// Outline variant for subtle separators
  static const Color outlineVariant = Color(0xFF424753);
}
