/// Design-system color palette for GastroCore POS.
///
/// Klein Professional POS — Organic Brutalism dark theme.
/// Dark surfaces with blue accent, no borders, tonal layering for depth.
/// Optimised for 12+ hour daily restaurant use on dark displays.
library;

import 'dart:ui';

abstract final class AppColors {
  // ---------------------------------------------------------------------------
  // Surface Hierarchy — dark tonal layering (NO borders)
  // Depth is expressed through surface color shifts, not shadows or lines.
  // ---------------------------------------------------------------------------

  /// Base scaffold background — infinite void
  static const Color surfaceDim = Color(0xFF0B0E14);

  /// Default panel surface — navigation / sidebar bg
  static const Color surface = Color(0xFF10131A);

  /// Cards, product tiles — same as surface for order panel
  static const Color surfaceContainerLow = Color(0xFF10131A);

  /// Inset areas, grouping — slightly lighter
  static const Color surfaceContainer = Color(0xFF161A21);

  /// Interactive cards (default state)
  static const Color surfaceContainerHigh = Color(0xFF1C2028);

  /// Active / hover cards — most elevated interactive surface
  static const Color surfaceContainerHighest = Color(0xFF22262F);

  /// Floating / modal states (dialogs, bottom sheets)
  static const Color surfaceBright = Color(0xFF282C36);

  /// Input field background
  static const Color bgInput = Color(0xFF161A21);

  /// Modal overlay (50% dark)
  static const Color bgOverlay = Color(0x80000000);

  // Legacy aliases kept for backward compatibility
  static const Color bgPrimary = surfaceDim;
  static const Color bgSecondary = surface;
  static const Color bgCard = surfaceContainerHigh;
  static const Color bgCardHover = surfaceContainerHighest;

  // ---------------------------------------------------------------------------
  // Navigation — dark surface (same dark palette, no separate treatment)
  // ---------------------------------------------------------------------------

  /// Sidebar / nav background
  static const Color navSurface = Color(0xFF10131A);

  /// Hover state on nav items
  static const Color navSurfaceHover = Color(0xFF1C2028);

  /// Active nav item highlight
  static const Color navSurfaceActive = Color(0xFF316BF3);

  /// Default icon/text on nav
  static const Color navText = Color(0xFFA9ABB3);

  /// Active icon/text on nav
  static const Color navTextActive = Color(0xFFECEDF6);

  /// Divider inside nav
  static const Color navDivider = Color(0xFF45484F);

  // ---------------------------------------------------------------------------
  // Primary — Blue (professional dark POS feel)
  // ---------------------------------------------------------------------------

  /// Primary action color — blue (lighter for dark bg readability)
  static const Color primary = Color(0xFF90ABFF);

  /// Primary CTA / button fill — darker blue (primaryDim)
  static const Color primaryDim = Color(0xFF316BF3);

  /// Primary container — medium blue
  static const Color primaryContainer = Color(0xFF7B9CFF);

  /// On primary — dark text on primary bg
  static const Color onPrimary = Color(0xFF002873);

  /// Light alias (same as container)
  static const Color primaryLight = Color(0xFF7B9CFF);

  /// Alias for primary
  static const Color accent = Color(0xFF90ABFF);

  /// Pressed/hover accent — use primaryDim
  static const Color accentHover = Color(0xFF316BF3);

  /// Tinted blue background (selected states, active indicators)
  static const Color accentDim = Color(0x2090ABFF);

  // ---------------------------------------------------------------------------
  // Secondary — Green (Ready / Sent / Available states)
  // ---------------------------------------------------------------------------

  /// Secondary — mint green (available, sent to kitchen, complete)
  static const Color secondary = Color(0xFF69F6B8);

  /// Secondary dim variant
  static const Color secondaryDim = Color(0xFF58E7AB);

  /// Secondary container background (dark green for badges)
  static const Color secondaryContainer = Color(0xFF006C49);

  // ---------------------------------------------------------------------------
  // Tertiary / Coral — Action colors (Send to Kitchen, urgency)
  // ---------------------------------------------------------------------------

  /// Coral / action red — primary CTA (send to kitchen, urgent actions)
  static const Color coral = Color(0xFFFF6F7E);

  /// Darker coral for pressed / gradient end
  static const Color coralDark = Color(0xFFD7383B);

  /// Tinted coral background for badges / tags
  static const Color coralDim = Color(0x20FF6F7E);

  // Tertiary aliases
  static const Color tertiary = Color(0xFFFF6F7E);
  static const Color tertiaryDim = Color(0xFFFF6F7E);

  // ---------------------------------------------------------------------------
  // Semantic Colors
  // ---------------------------------------------------------------------------

  /// Success — available, paid, completed
  static const Color green = Color(0xFF69F6B8);

  /// On green (text on green bg)
  static const Color onGreen = Color(0xFF003828);

  /// Secondary container green (same as secondaryContainer)
  static const Color greenContainer = Color(0xFF006C49);

  /// Warning — pending, attention
  static const Color orange = Color(0xFFFFB74D);

  /// Error — void, destructive, occupied
  static const Color red = Color(0xFFFF716C);

  /// Error dim variant
  static const Color errorDim = Color(0xFFD7383B);

  /// Info / highlight / notes
  static const Color yellow = Color(0xFFFFD54F);

  /// Special / promo / VIP
  static const Color purple = Color(0xFFCE93D8);

  // error alias
  static const Color error = Color(0xFFFF716C);

  // ---------------------------------------------------------------------------
  // Dim Semantic — tinted badge / chip backgrounds (dark theme)
  // ---------------------------------------------------------------------------

  static const Color greenDim = Color(0xFF006C49);
  static const Color orangeDim = Color(0x30FFB74D);
  static const Color redDim = Color(0x25FF716C);
  static const Color yellowDim = Color(0x25FFD54F);
  static const Color purpleDim = Color(0x25CE93D8);

  // ---------------------------------------------------------------------------
  // Text Hierarchy — NOT pure white (reduces eye strain on dark displays)
  // ---------------------------------------------------------------------------

  /// Primary text — warm white on dark (onSurface)
  static const Color textPrimary = Color(0xFFECEDF6);

  /// Secondary text — muted (onSurfaceVariant)
  static const Color textSecondary = Color(0xFFA9ABB3);

  /// Dim / placeholder / disabled
  static const Color textDim = Color(0xFF73757D);

  // ---------------------------------------------------------------------------
  // Borders & Dividers — ONLY the one-allowed subtle separator
  // No decorative borders. Only structural separators at 5% opacity white.
  // ---------------------------------------------------------------------------

  /// Default divider — very subtle (outlineVariant)
  static const Color border = Color(0xFF45484F);

  /// Focused / active element border
  static const Color borderFocused = Color(0xFF90ABFF);

  /// Subtle separators (slightly lighter than border)
  static const Color outlineVariant = Color(0xFF45484F);

  /// Outline (icons, mid-emphasis)
  static const Color outline = Color(0xFF73757D);
}
