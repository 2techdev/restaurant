/// Design-system color palette for GastroCore POS.
///
/// Lightspeed-inspired professional UI.
/// Light theme optimised for 12+ hour daily restaurant use.
/// High contrast, easy on the eyes, clear hierarchy.
library;

import 'dart:ui';

abstract final class AppColors {
  // ---------------------------------------------------------------------------
  // Surface Hierarchy (Light theme)
  // Background shifts express depth — no harsh borders needed.
  // ---------------------------------------------------------------------------

  /// Base scaffold background — light gray workspace
  static const Color surfaceDim = Color(0xFFF4F5F7);

  /// Default panel / card surface — pure white
  static const Color surface = Color(0xFFFFFFFF);

  /// Cards, product tiles — pure white
  static const Color surfaceContainerLow = Color(0xFFFFFFFF);

  /// Neutral content areas — light gray
  static const Color surfaceContainer = Color(0xFFF4F5F7);

  /// Quantity controls, toggle tracks, dividers
  static const Color surfaceContainerHigh = Color(0xFFEAECEF);

  /// Most elevated (numpad keys, active states)
  static const Color surfaceContainerHighest = Color(0xFFDDE0E6);

  /// Hover / pressed state surface
  static const Color surfaceBright = Color(0xFFEDF0F3);

  /// Input field background
  static const Color bgInput = Color(0xFFF9FAFB);

  /// Modal overlay (50% dark)
  static const Color bgOverlay = Color(0x80000000);

  // Legacy aliases kept for backward compatibility
  static const Color bgPrimary = surfaceDim;
  static const Color bgSecondary = surface;
  static const Color bgCard = surfaceContainerLow;
  static const Color bgCardHover = surfaceBright;

  // ---------------------------------------------------------------------------
  // Navigation Sidebar — always dark navy regardless of theme
  // ---------------------------------------------------------------------------

  /// Sidebar background — dark navy
  static const Color navSurface = Color(0xFF1B2838);

  /// Hover state on sidebar items
  static const Color navSurfaceHover = Color(0xFF243447);

  /// Active sidebar item highlight (uses primary teal)
  static const Color navSurfaceActive = Color(0xFF00897B);

  /// Default icon/text on sidebar
  static const Color navText = Color(0xFF8FA0B4);

  /// Active icon/text on sidebar — white
  static const Color navTextActive = Color(0xFFFFFFFF);

  /// Divider inside sidebar
  static const Color navDivider = Color(0xFF2C3A4A);

  // ---------------------------------------------------------------------------
  // Primary — Deep Teal (Lightspeed-inspired professional feel)
  // ---------------------------------------------------------------------------

  /// Primary action color — deep teal
  static const Color primary = Color(0xFF00897B);

  /// Darker teal for gradients / pressed states
  static const Color primaryContainer = Color(0xFF00695C);

  /// Light teal for chips / highlights
  static const Color primaryLight = Color(0xFF4DB6AC);

  /// Alias for primary
  static const Color accent = Color(0xFF00897B);

  /// Primary hover (slightly lighter)
  static const Color accentHover = Color(0xFF00A693);

  /// Tinted teal background (selected chips, active indicators)
  static const Color accentDim = Color(0xFFE0F2F1);

  // ---------------------------------------------------------------------------
  // Coral — CTA Actions (Send to Kitchen, Pay with urgency)
  // ---------------------------------------------------------------------------

  /// Coral / orange — primary CTA color (send to kitchen, urgent actions)
  static const Color coral = Color(0xFFFF6B35);

  /// Darker coral for pressed / gradient end
  static const Color coralDark = Color(0xFFE55A27);

  /// Tinted coral background for badges / tags
  static const Color coralDim = Color(0xFFFFF0EB);

  // ---------------------------------------------------------------------------
  // Semantic Colors
  // ---------------------------------------------------------------------------

  /// Success — available, paid, completed
  static const Color green = Color(0xFF43A047);

  /// On green (text on green bg)
  static const Color onGreen = Color(0xFFFFFFFF);

  /// Secondary container green
  static const Color greenContainer = Color(0xFF43A047);

  /// Warning — pending, attention (amber)
  static const Color orange = Color(0xFFFFA726);

  /// Error — void, destructive, occupied
  static const Color red = Color(0xFFE53935);

  /// Info / highlight / notes
  static const Color yellow = Color(0xFFFFC107);

  /// Special / promo / VIP
  static const Color purple = Color(0xFF9C27B0);

  // ---------------------------------------------------------------------------
  // Dim Semantic — tinted badge / chip backgrounds (light theme)
  // ---------------------------------------------------------------------------

  static const Color greenDim = Color(0xFFE8F5E9);
  static const Color orangeDim = Color(0xFFFFF8E1);
  static const Color redDim = Color(0xFFFFEBEE);
  static const Color yellowDim = Color(0xFFFFFDE7);
  static const Color purpleDim = Color(0xFFF3E5F5);

  // ---------------------------------------------------------------------------
  // Text Hierarchy
  // ---------------------------------------------------------------------------

  /// Primary text — high contrast on white (near-black)
  static const Color textPrimary = Color(0xFF1A1A1A);

  /// Secondary text — medium emphasis
  static const Color textSecondary = Color(0xFF6B7280);

  /// Dim / placeholder / disabled
  static const Color textDim = Color(0xFF9CA3AF);

  // ---------------------------------------------------------------------------
  // Borders & Dividers
  // ---------------------------------------------------------------------------

  /// Default border — very subtle
  static const Color border = Color(0xFFE5E7EB);

  /// Focused / active element border
  static const Color borderFocused = Color(0xFF00897B);

  /// Subtle separators
  static const Color outlineVariant = Color(0xFFD1D5DB);
}
