/// Light theme for GastroCore Online Ordering.
/// Customer-facing, mobile-first, clean and warm — inspired by Just Eat style
/// but simpler and Swiss-appropriate.
library;

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Color palette
// ---------------------------------------------------------------------------

abstract final class OnlineColors {
  /// Primary action color — warm deep orange (restaurant-appropriate).
  static const Color primary = Color(0xFFFF5722);
  static const Color primaryDark = Color(0xFFE64A19);
  static const Color primaryLight = Color(0xFFFBE9E7);

  /// Background layers.
  static const Color bgPage = Color(0xFFF5F5F5);
  static const Color bgCard = Color(0xFFFFFFFF);
  static const Color bgInput = Color(0xFFF8F8F8);

  /// Text.
  static const Color textPrimary = Color(0xFF1A1A2E);
  static const Color textSecondary = Color(0xFF6B6B80);
  static const Color textDim = Color(0xFFAAAAAA);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  /// Status.
  static const Color green = Color(0xFF00C853);
  static const Color orange = Color(0xFFFF9800);
  static const Color red = Color(0xFFE53935);

  /// Divider.
  static const Color divider = Color(0xFFEEEEEE);
  static const Color border = Color(0xFFE0E0E0);

  /// Chip / badge.
  static const Color chipBg = Color(0xFFF0F0F0);
  static const Color selectedChipBg = Color(0xFFFBE9E7);
}

// ---------------------------------------------------------------------------
// Border radius
// ---------------------------------------------------------------------------
const double kRadiusSmall = 8.0;
const double kRadiusMedium = 12.0;
const double kRadiusLarge = 16.0;
const double kRadiusXl = 24.0;

// ---------------------------------------------------------------------------
// Theme builder
// ---------------------------------------------------------------------------

ThemeData buildOnlineTheme() {
  const colorScheme = ColorScheme.light(
    primary: OnlineColors.primary,
    onPrimary: OnlineColors.textOnPrimary,
    secondary: OnlineColors.primary,
    onSecondary: OnlineColors.textOnPrimary,
    error: OnlineColors.red,
    onError: OnlineColors.textOnPrimary,
    surface: OnlineColors.bgCard,
    onSurface: OnlineColors.textPrimary,
    surfaceContainerHighest: OnlineColors.bgPage,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: OnlineColors.bgPage,
    canvasColor: OnlineColors.bgCard,
    cardColor: OnlineColors.bgCard,
    dividerColor: OnlineColors.divider,
    fontFamily: 'Roboto',

    textTheme: const TextTheme(
      displayLarge: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        color: OnlineColors.textPrimary,
        letterSpacing: -0.5,
      ),
      displayMedium: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: OnlineColors.textPrimary,
      ),
      headlineLarge: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: OnlineColors.textPrimary,
      ),
      headlineMedium: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: OnlineColors.textPrimary,
      ),
      headlineSmall: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: OnlineColors.textPrimary,
      ),
      titleLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: OnlineColors.textPrimary,
      ),
      titleMedium: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: OnlineColors.textPrimary,
      ),
      titleSmall: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: OnlineColors.textSecondary,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: OnlineColors.textPrimary,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: OnlineColors.textPrimary,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: OnlineColors.textSecondary,
      ),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: OnlineColors.textPrimary,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: OnlineColors.textSecondary,
      ),
    ),

    cardTheme: CardThemeData(
      color: OnlineColors.bgCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadiusMedium),
      ),
      margin: EdgeInsets.zero,
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: OnlineColors.bgInput,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusMedium),
        borderSide: const BorderSide(color: OnlineColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusMedium),
        borderSide: const BorderSide(color: OnlineColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusMedium),
        borderSide: const BorderSide(color: OnlineColors.primary, width: 2),
      ),
      hintStyle: const TextStyle(
        color: OnlineColors.textDim,
        fontSize: 14,
      ),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: OnlineColors.primary,
        foregroundColor: OnlineColors.textOnPrimary,
        elevation: 0,
        padding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusLarge),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: OnlineColors.primary,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        minimumSize: const Size(double.infinity, 48),
        side: const BorderSide(color: OnlineColors.primary, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusLarge),
        ),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: OnlineColors.primary,
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    appBarTheme: const AppBarTheme(
      backgroundColor: OnlineColors.bgCard,
      foregroundColor: OnlineColors.textPrimary,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: OnlineColors.textPrimary,
      ),
    ),

    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: OnlineColors.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(kRadiusXl)),
      ),
    ),

    dividerTheme: const DividerThemeData(
      color: OnlineColors.divider,
      thickness: 1,
      space: 1,
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: OnlineColors.textPrimary,
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadiusMedium),
      ),
      behavior: SnackBarBehavior.floating,
    ),

    chipTheme: ChipThemeData(
      backgroundColor: OnlineColors.chipBg,
      selectedColor: OnlineColors.selectedChipBg,
      labelStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: OnlineColors.textPrimary,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    ),
  );
}
