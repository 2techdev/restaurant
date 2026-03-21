/// Light theme for GastroCore Online Ordering.
/// Customer-facing, mobile-first, warm and appetizing — Just Eat inspired.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ---------------------------------------------------------------------------
// Color palette
// ---------------------------------------------------------------------------

abstract final class OnlineColors {
  /// Primary action color — warm deep orange (Just Eat warmth).
  static const Color primary = Color(0xFFFF5722);
  static const Color primaryDark = Color(0xFFE64A19);
  static const Color primaryLight = Color(0xFFFBE9E7);

  /// Navigation / header — dark charcoal.
  static const Color charcoal = Color(0xFF1A1A2E);

  /// Background layers.
  static const Color bgPage = Color(0xFFFAFAFA);
  static const Color bgCard = Color(0xFFFFFFFF);
  static const Color bgInput = Color(0xFFF8F8F8);

  /// Text.
  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF757575);
  static const Color textDim = Color(0xFFAAAAAA);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  /// Status / semantic.
  static const Color green = Color(0xFF4CAF50);
  static const Color greenLight = Color(0xFFE8F5E9);
  static const Color orange = Color(0xFFFF9800);
  static const Color red = Color(0xFFE53935);

  /// Category pills.
  static const Color pillActiveBg = Color(0xFFFFF3E0);
  static const Color pillInactiveBg = Color(0xFFF5F5F5);

  /// Divider / border.
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

  final baseTextTheme = TextTheme(
    displayLarge: GoogleFonts.plusJakartaSans(
      fontSize: 28,
      fontWeight: FontWeight.w800,
      color: OnlineColors.textPrimary,
      letterSpacing: -0.5,
    ),
    displayMedium: GoogleFonts.plusJakartaSans(
      fontSize: 24,
      fontWeight: FontWeight.w700,
      color: OnlineColors.textPrimary,
    ),
    headlineLarge: GoogleFonts.plusJakartaSans(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      color: OnlineColors.textPrimary,
    ),
    headlineMedium: GoogleFonts.plusJakartaSans(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: OnlineColors.textPrimary,
    ),
    headlineSmall: GoogleFonts.plusJakartaSans(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: OnlineColors.textPrimary,
    ),
    titleLarge: GoogleFonts.plusJakartaSans(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: OnlineColors.textPrimary,
    ),
    titleMedium: GoogleFonts.plusJakartaSans(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: OnlineColors.textPrimary,
    ),
    titleSmall: GoogleFonts.inter(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: OnlineColors.textSecondary,
    ),
    bodyLarge: GoogleFonts.inter(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      color: OnlineColors.textPrimary,
    ),
    bodyMedium: GoogleFonts.inter(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: OnlineColors.textPrimary,
    ),
    bodySmall: GoogleFonts.inter(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: OnlineColors.textSecondary,
    ),
    labelLarge: GoogleFonts.inter(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: OnlineColors.textPrimary,
    ),
    labelMedium: GoogleFonts.inter(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: OnlineColors.textSecondary,
    ),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: OnlineColors.bgPage,
    canvasColor: OnlineColors.bgCard,
    cardColor: OnlineColors.bgCard,
    dividerColor: OnlineColors.divider,
    textTheme: baseTextTheme,

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
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
        borderSide:
            const BorderSide(color: OnlineColors.primary, width: 2),
      ),
      hintStyle: GoogleFonts.inter(
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
        textStyle: GoogleFonts.plusJakartaSans(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: OnlineColors.primary,
        padding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        minimumSize: const Size(double.infinity, 48),
        side: const BorderSide(color: OnlineColors.primary, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusLarge),
        ),
        textStyle: GoogleFonts.plusJakartaSans(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: OnlineColors.primary,
        textStyle: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    appBarTheme: AppBarTheme(
      backgroundColor: OnlineColors.charcoal,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.plusJakartaSans(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
      iconTheme: const IconThemeData(color: Colors.white),
    ),

    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: OnlineColors.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(kRadiusXl)),
      ),
    ),

    dividerTheme: const DividerThemeData(
      color: OnlineColors.divider,
      thickness: 1,
      space: 1,
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: OnlineColors.charcoal,
      contentTextStyle:
          GoogleFonts.inter(color: Colors.white, fontSize: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadiusMedium),
      ),
      behavior: SnackBarBehavior.floating,
    ),

    chipTheme: ChipThemeData(
      backgroundColor: OnlineColors.pillInactiveBg,
      selectedColor: OnlineColors.pillActiveBg,
      labelStyle: GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w600,
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
