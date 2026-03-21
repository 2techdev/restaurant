/// Light, warm theme for the GastroCore Kiosk customer-facing app.
///
/// Designed for high-visibility large-screen kiosk hardware:
/// - Warm whites and cream surfaces (food-photography friendly)
/// - Orange-amber primary (appetizing, high contrast on light)
/// - Extra-large touch targets (min 56 dp)
/// - High contrast text hierarchy
library;

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Kiosk color palette
// ---------------------------------------------------------------------------

abstract final class KioskColors {
  // Backgrounds
  static const Color bgPage = Color(0xFFFAF8F5);
  static const Color bgCard = Color(0xFFFFFFFF);
  static const Color bgCardAlt = Color(0xFFF5F3EF);
  static const Color bgOverlay = Color(0xCC000000);

  // Primary — warm orange-amber
  static const Color primary = Color(0xFFFF6B35);
  static const Color primaryDark = Color(0xFFE55A2B);
  static const Color primaryLight = Color(0xFFFF8C5A);
  static const Color primaryContainer = Color(0xFFFFEDE6);
  static const Color onPrimary = Color(0xFFFFFFFF);

  // Secondary — fresh teal
  static const Color secondary = Color(0xFF2EC4B6);
  static const Color secondaryContainer = Color(0xFFE0F7F5);
  static const Color onSecondary = Color(0xFFFFFFFF);

  // Success green
  static const Color success = Color(0xFF2DBD72);
  static const Color successContainer = Color(0xFFE6F9F0);

  // Error red
  static const Color error = Color(0xFFE53935);
  static const Color errorContainer = Color(0xFFFFEBEB);

  // Text
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF5A5A6A);
  static const Color textDim = Color(0xFF9E9EAE);
  static const Color textOnDark = Color(0xFFFAF8F5);

  // Borders
  static const Color border = Color(0xFFE8E4DC);
  static const Color borderFocus = Color(0xFFFF6B35);

  // Dine-in / Takeaway indicator
  static const Color dineIn = Color(0xFF2EC4B6);
  static const Color takeaway = Color(0xFFFF6B35);
}

// ---------------------------------------------------------------------------
// Border radius constants
// ---------------------------------------------------------------------------

const double kKioskRadiusSmall = 12.0;
const double kKioskRadiusMedium = 16.0;
const double kKioskRadiusLarge = 24.0;
const double kKioskRadiusXL = 32.0;

// ---------------------------------------------------------------------------
// Theme builder
// ---------------------------------------------------------------------------

ThemeData buildKioskTheme() {
  final colorScheme = ColorScheme.light(
    primary: KioskColors.primary,
    onPrimary: KioskColors.onPrimary,
    primaryContainer: KioskColors.primaryContainer,
    secondary: KioskColors.secondary,
    onSecondary: KioskColors.onSecondary,
    secondaryContainer: KioskColors.secondaryContainer,
    error: KioskColors.error,
    onError: Colors.white,
    surface: KioskColors.bgCard,
    onSurface: KioskColors.textPrimary,
    surfaceContainerHighest: KioskColors.bgCardAlt,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: KioskColors.bgPage,
    cardColor: KioskColors.bgCard,
    dividerColor: KioskColors.border,

    // ── Typography — larger than POS for touchscreen readability ───────────
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        fontSize: 48,
        fontWeight: FontWeight.w800,
        color: KioskColors.textPrimary,
        letterSpacing: -1.0,
      ),
      displayMedium: TextStyle(
        fontSize: 36,
        fontWeight: FontWeight.w700,
        color: KioskColors.textPrimary,
        letterSpacing: -0.5,
      ),
      displaySmall: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: KioskColors.textPrimary,
      ),
      headlineLarge: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: KioskColors.textPrimary,
      ),
      headlineMedium: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: KioskColors.textPrimary,
      ),
      headlineSmall: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: KioskColors.textPrimary,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: KioskColors.textPrimary,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: KioskColors.textPrimary,
      ),
      titleSmall: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: KioskColors.textSecondary,
      ),
      bodyLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w400,
        color: KioskColors.textPrimary,
      ),
      bodyMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: KioskColors.textPrimary,
      ),
      bodySmall: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: KioskColors.textSecondary,
      ),
      labelLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: KioskColors.textPrimary,
      ),
      labelMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: KioskColors.textSecondary,
      ),
    ),

    // ── Card ────────────────────────────────────────────────────────────────
    cardTheme: CardThemeData(
      color: KioskColors.bgCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kKioskRadiusMedium),
        side: const BorderSide(color: KioskColors.border, width: 1),
      ),
      margin: EdgeInsets.zero,
    ),

    // ── Elevated button — min 56 dp height for touchscreen ─────────────────
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: KioskColors.primary,
        foregroundColor: KioskColors.onPrimary,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
        minimumSize: const Size(0, 56),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kKioskRadiusMedium),
        ),
        textStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),

    // ── Outlined button ────────────────────────────────────────────────────
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: KioskColors.textPrimary,
        side: const BorderSide(color: KioskColors.border, width: 2),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
        minimumSize: const Size(0, 56),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kKioskRadiusMedium),
        ),
        textStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    // ── Text button ────────────────────────────────────────────────────────
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: KioskColors.primary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        minimumSize: const Size(0, 48),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    // ── AppBar ─────────────────────────────────────────────────────────────
    appBarTheme: const AppBarTheme(
      backgroundColor: KioskColors.bgCard,
      foregroundColor: KioskColors.textPrimary,
      elevation: 0,
      centerTitle: false,
    ),

    // ── Divider ────────────────────────────────────────────────────────────
    dividerTheme: const DividerThemeData(
      color: KioskColors.border,
      thickness: 1,
      space: 1,
    ),

    // ── Snackbar ───────────────────────────────────────────────────────────
    snackBarTheme: SnackBarThemeData(
      backgroundColor: KioskColors.textPrimary,
      contentTextStyle: const TextStyle(
        color: KioskColors.textOnDark,
        fontSize: 16,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kKioskRadiusSmall),
      ),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
