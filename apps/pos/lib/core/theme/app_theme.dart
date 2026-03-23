/// Complete dark theme for GastroCore POS.
///
/// Stitch "Klein Professional POS" design system.
/// Material 3 dark theme — ultra-dense tablet UI,
/// surface-layering depth hierarchy (no borders, no shadows on cards).
library;

import 'package:flutter/material.dart';

import 'app_colors.dart';

// ---------------------------------------------------------------------------
// Border radius constants — tight 4px Stitch design system
// ---------------------------------------------------------------------------

/// Small radius — chips, badges, small buttons, cards.
const double kRadiusSmall = 4.0;

/// Medium radius — inputs, action buttons.
const double kRadiusMedium = 4.0;

/// Large radius — sheets, modals, prominent panels.
const double kRadiusLarge = 8.0;

// ---------------------------------------------------------------------------
// Shadow presets — minimal in dark tonal system
// ---------------------------------------------------------------------------

/// No shadows on cards — tonal surface layering expresses depth.
const List<BoxShadow> kCardShadow = [];

/// Subtle separator shadow for the order panel.
const List<BoxShadow> kPanelShadow = [
  BoxShadow(
    color: Color(0x40000000),
    blurRadius: 16,
    offset: Offset(-2, 0),
  ),
];

/// Primary action button glow.
const List<BoxShadow> kButtonShadow = [
  BoxShadow(
    color: Color(0x5090ABFF),
    blurRadius: 12,
    offset: Offset(0, 4),
  ),
];

// ---------------------------------------------------------------------------
// Theme
// ---------------------------------------------------------------------------

/// Builds the application-wide dark [ThemeData] (Stitch design system).
ThemeData buildAppTheme() {
  final colorScheme = ColorScheme.dark(
    primary: AppColors.primary,
    onPrimary: const Color(0xFF0B0E14),
    primaryContainer: AppColors.primaryContainer,
    onPrimaryContainer: AppColors.primary,
    secondary: AppColors.green,
    onSecondary: AppColors.onGreen,
    tertiary: AppColors.coral,
    onTertiary: Colors.white,
    error: AppColors.red,
    onError: Colors.white,
    surface: AppColors.surface,
    onSurface: AppColors.textPrimary,
    surfaceDim: AppColors.surfaceDim,
    surfaceContainerLowest: AppColors.surfaceDim,
    surfaceContainerLow: AppColors.surfaceContainerLow,
    surfaceContainer: AppColors.surfaceContainer,
    surfaceContainerHigh: AppColors.surfaceContainerHigh,
    surfaceContainerHighest: AppColors.surfaceContainerHighest,
    onSurfaceVariant: AppColors.textSecondary,
    outline: AppColors.border,
    outlineVariant: AppColors.outlineVariant,
    scrim: AppColors.bgOverlay,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.surfaceDim,
    canvasColor: AppColors.surface,
    cardColor: AppColors.surfaceContainerHigh,
    dividerColor: AppColors.border,

    // -- Extensions ----------------------------------------------------------
    extensions: const <ThemeExtension<dynamic>>[
      PosColors(),
    ],

    // -- Typography — Inter font, weight contrast 400 vs 800 ----------------
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
        letterSpacing: -0.5,
      ),
      displayMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
      ),
      displaySmall: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      headlineMedium: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      headlineSmall: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      titleLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      titleMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      titleSmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: AppColors.textPrimary,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColors.textPrimary,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
      ),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
      ),
      labelSmall: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: AppColors.textDim,
        letterSpacing: 0.5,
      ),
    ),

    // -- Card — no elevation, tonal surface ------------------------------------
    cardTheme: CardThemeData(
      color: AppColors.surfaceContainerHigh,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadiusSmall),
      ),
      margin: EdgeInsets.zero,
    ),

    // -- Input decoration -------------------------------------------------------
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.bgInput,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusSmall),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusSmall),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusSmall),
        borderSide: const BorderSide(color: AppColors.borderFocused, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusSmall),
        borderSide: const BorderSide(color: AppColors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusSmall),
        borderSide: const BorderSide(color: AppColors.red, width: 1.5),
      ),
      hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 13),
      labelStyle: const TextStyle(color: AppColors.textSecondary),
    ),

    // -- Elevated button -------------------------------------------------------
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primaryContainer,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        minimumSize: const Size(0, 44),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusSmall),
        ),
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    ),

    // -- Text button ----------------------------------------------------------
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusSmall),
        ),
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    // -- Outlined button ------------------------------------------------------
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        minimumSize: const Size(0, 44),
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusSmall),
        ),
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    // -- Dialog ---------------------------------------------------------------
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surfaceContainerHigh,
      elevation: 8,
      shadowColor: const Color(0x40000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadiusLarge),
      ),
    ),

    // -- Bottom sheet --------------------------------------------------------
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(kRadiusLarge)),
      ),
    ),

    // -- Divider -------------------------------------------------------------
    dividerTheme: const DividerThemeData(
      color: AppColors.border,
      thickness: 1,
      space: 1,
    ),

    // -- Snackbar ------------------------------------------------------------
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.surfaceContainerHighest,
      contentTextStyle: const TextStyle(color: AppColors.textPrimary),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadiusSmall),
      ),
      behavior: SnackBarBehavior.floating,
    ),

    // -- AppBar (used sparingly) ---------------------------------------------
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surfaceContainerLow,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),

    // -- Chip ----------------------------------------------------------------
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surfaceContainerHigh,
      selectedColor: AppColors.accentDim,
      labelStyle: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        letterSpacing: 0.3,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadiusSmall),
      ),
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    ),
  );
}

// ---------------------------------------------------------------------------
// Custom theme extension for POS-specific colours
// ---------------------------------------------------------------------------

/// Additional colours that don't map to Material's [ColorScheme].
class PosColors extends ThemeExtension<PosColors> {
  const PosColors({
    this.green = AppColors.green,
    this.orange = AppColors.orange,
    this.red = AppColors.red,
    this.yellow = AppColors.yellow,
    this.purple = AppColors.purple,
    this.coral = AppColors.coral,
    this.greenDim = AppColors.greenDim,
    this.orangeDim = AppColors.orangeDim,
    this.redDim = AppColors.redDim,
    this.yellowDim = AppColors.yellowDim,
    this.purpleDim = AppColors.purpleDim,
    this.bgCard = AppColors.bgCard,
    this.bgCardHover = AppColors.bgCardHover,
    this.bgInput = AppColors.bgInput,
    this.textSecondary = AppColors.textSecondary,
    this.textDim = AppColors.textDim,
    this.border = AppColors.border,
    this.navSurface = AppColors.navSurface,
  });

  final Color green;
  final Color orange;
  final Color red;
  final Color yellow;
  final Color purple;
  final Color coral;
  final Color greenDim;
  final Color orangeDim;
  final Color redDim;
  final Color yellowDim;
  final Color purpleDim;
  final Color bgCard;
  final Color bgCardHover;
  final Color bgInput;
  final Color textSecondary;
  final Color textDim;
  final Color border;
  final Color navSurface;

  @override
  PosColors copyWith({
    Color? green,
    Color? orange,
    Color? red,
    Color? yellow,
    Color? purple,
    Color? coral,
    Color? greenDim,
    Color? orangeDim,
    Color? redDim,
    Color? yellowDim,
    Color? purpleDim,
    Color? bgCard,
    Color? bgCardHover,
    Color? bgInput,
    Color? textSecondary,
    Color? textDim,
    Color? border,
    Color? navSurface,
  }) {
    return PosColors(
      green: green ?? this.green,
      orange: orange ?? this.orange,
      red: red ?? this.red,
      yellow: yellow ?? this.yellow,
      purple: purple ?? this.purple,
      coral: coral ?? this.coral,
      greenDim: greenDim ?? this.greenDim,
      orangeDim: orangeDim ?? this.orangeDim,
      redDim: redDim ?? this.redDim,
      yellowDim: yellowDim ?? this.yellowDim,
      purpleDim: purpleDim ?? this.purpleDim,
      bgCard: bgCard ?? this.bgCard,
      bgCardHover: bgCardHover ?? this.bgCardHover,
      bgInput: bgInput ?? this.bgInput,
      textSecondary: textSecondary ?? this.textSecondary,
      textDim: textDim ?? this.textDim,
      border: border ?? this.border,
      navSurface: navSurface ?? this.navSurface,
    );
  }

  @override
  PosColors lerp(ThemeExtension<PosColors>? other, double t) {
    if (other is! PosColors) return this;
    return PosColors(
      green: Color.lerp(green, other.green, t)!,
      orange: Color.lerp(orange, other.orange, t)!,
      red: Color.lerp(red, other.red, t)!,
      yellow: Color.lerp(yellow, other.yellow, t)!,
      purple: Color.lerp(purple, other.purple, t)!,
      coral: Color.lerp(coral, other.coral, t)!,
      greenDim: Color.lerp(greenDim, other.greenDim, t)!,
      orangeDim: Color.lerp(orangeDim, other.orangeDim, t)!,
      redDim: Color.lerp(redDim, other.redDim, t)!,
      yellowDim: Color.lerp(yellowDim, other.yellowDim, t)!,
      purpleDim: Color.lerp(purpleDim, other.purpleDim, t)!,
      bgCard: Color.lerp(bgCard, other.bgCard, t)!,
      bgCardHover: Color.lerp(bgCardHover, other.bgCardHover, t)!,
      bgInput: Color.lerp(bgInput, other.bgInput, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textDim: Color.lerp(textDim, other.textDim, t)!,
      border: Color.lerp(border, other.border, t)!,
      navSurface: Color.lerp(navSurface, other.navSurface, t)!,
    );
  }
}

/// Convenience extension to access [PosColors] from any [BuildContext].
extension PosColorsExtension on BuildContext {
  PosColors get posColors => Theme.of(this).extension<PosColors>()!;
}
