/// Dark theme for the GastroCore Order Display Screen (ODS).
///
/// Optimised for TV/monitor display visible from 3–5 metres:
/// - Near-black background (easy on the eyes, high contrast)
/// - Extra-large font sizes
/// - Amber/yellow for "Preparing" section, vivid green for "Ready" section
/// - Minimal decorative chrome so the order numbers dominate
library;

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Color palette
// ---------------------------------------------------------------------------

abstract final class OdsColors {
  // Backgrounds
  static const Color bgPage = Color(0xFF0D0D0D);
  static const Color bgCard = Color(0xFF1A1A1A);
  static const Color bgCardAlt = Color(0xFF222222);

  // Header bar
  static const Color bgHeader = Color(0xFF111111);

  // Primary text (white)
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFAAAAAA);
  static const Color textDim = Color(0xFF666666);

  // "Preparing" section — warm amber/orange
  static const Color preparing = Color(0xFFFFAB00);
  static const Color preparingDark = Color(0xFF7A5000);
  static const Color preparingBg = Color(0xFF1F1500);
  static const Color preparingCardBg = Color(0xFF2A1C00);
  static const Color preparingBorder = Color(0xFF3D2A00);

  // "Ready" section — vivid green
  static const Color ready = Color(0xFF00E676);
  static const Color readyDark = Color(0xFF007A3D);
  static const Color readyBg = Color(0xFF001A0D);
  static const Color readyCardBg = Color(0xFF002615);
  static const Color readyBorder = Color(0xFF004022);

  // Divider
  static const Color divider = Color(0xFF2A2A2A);

  // Source icon tints
  static const Color sourceCounter = Color(0xFF64B5F6);
  static const Color sourceKiosk = Color(0xFFCE93D8);
  static const Color sourceOnline = Color(0xFF80CBC4);
}

// ---------------------------------------------------------------------------
// Radius / spacing constants
// ---------------------------------------------------------------------------

const double kOdsRadiusSmall = 8.0;
const double kOdsRadiusMedium = 16.0;
const double kOdsRadiusLarge = 24.0;

// ---------------------------------------------------------------------------
// Theme builder
// ---------------------------------------------------------------------------

ThemeData buildOdsTheme() {
  final colorScheme = ColorScheme.dark(
    primary: OdsColors.preparing,
    onPrimary: Colors.black,
    secondary: OdsColors.ready,
    onSecondary: Colors.black,
    error: const Color(0xFFCF6679),
    surface: OdsColors.bgCard,
    onSurface: OdsColors.textPrimary,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: OdsColors.bgPage,
    cardColor: OdsColors.bgCard,
    dividerColor: OdsColors.divider,

    // ── Typography — huge, readable from metres away ───────────────────────
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        fontSize: 96,
        fontWeight: FontWeight.w900,
        color: OdsColors.textPrimary,
        letterSpacing: -2.0,
      ),
      displayMedium: TextStyle(
        fontSize: 72,
        fontWeight: FontWeight.w800,
        color: OdsColors.textPrimary,
        letterSpacing: -1.5,
      ),
      displaySmall: TextStyle(
        fontSize: 56,
        fontWeight: FontWeight.w800,
        color: OdsColors.textPrimary,
        letterSpacing: -1.0,
      ),
      headlineLarge: TextStyle(
        fontSize: 40,
        fontWeight: FontWeight.w700,
        color: OdsColors.textPrimary,
      ),
      headlineMedium: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: OdsColors.textPrimary,
      ),
      headlineSmall: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: OdsColors.textPrimary,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: OdsColors.textPrimary,
      ),
      bodyLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w400,
        color: OdsColors.textSecondary,
      ),
      bodyMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: OdsColors.textSecondary,
      ),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: OdsColors.textDim,
      ),
    ),

    // ── AppBar ─────────────────────────────────────────────────────────────
    appBarTheme: const AppBarTheme(
      backgroundColor: OdsColors.bgHeader,
      foregroundColor: OdsColors.textPrimary,
      elevation: 0,
      centerTitle: false,
    ),

    // ── Card ────────────────────────────────────────────────────────────────
    cardTheme: CardThemeData(
      color: OdsColors.bgCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kOdsRadiusMedium),
      ),
      margin: EdgeInsets.zero,
    ),

    // ── Divider ────────────────────────────────────────────────────────────
    dividerTheme: const DividerThemeData(
      color: OdsColors.divider,
      thickness: 1,
      space: 1,
    ),
  );
}
