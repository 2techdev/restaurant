/// Complete light theme for GastroCore POS.
///
/// Lightspeed-inspired professional UI optimised for restaurant tablets.
/// Material 3 light theme — high contrast, generous touch targets,
/// clean hierarchy through whitespace and shadow (not borders).
library;

import 'package:flutter/material.dart';

import 'app_colors.dart';

// ---------------------------------------------------------------------------
// Border radius constants
// ---------------------------------------------------------------------------

/// Small radius — chips, badges, small buttons.
const double kRadiusSmall = 8.0;

/// Medium radius — cards, inputs, dialogs.
const double kRadiusMedium = 12.0;

/// Large radius — sheets, modals, prominent panels.
const double kRadiusLarge = 16.0;

// ---------------------------------------------------------------------------
// Shadow presets
// ---------------------------------------------------------------------------

/// Subtle card shadow — white cards on light gray background.
const List<BoxShadow> kCardShadow = [
  BoxShadow(
    color: Color(0x0D000000),
    blurRadius: 8,
    offset: Offset(0, 2),
  ),
  BoxShadow(
    color: Color(0x07000000),
    blurRadius: 1,
    offset: Offset(0, 1),
  ),
];

/// Elevated panel shadow — order panel, floating dialogs.
const List<BoxShadow> kPanelShadow = [
  BoxShadow(
    color: Color(0x18000000),
    blurRadius: 24,
    offset: Offset(-4, 0),
  ),
];

/// Button shadow — for primary action buttons.
const List<BoxShadow> kButtonShadow = [
  BoxShadow(
    color: Color(0x2600897B),
    blurRadius: 8,
    offset: Offset(0, 4),
  ),
];

// ---------------------------------------------------------------------------
// Theme
// ---------------------------------------------------------------------------

/// Builds the application-wide light [ThemeData].
ThemeData buildAppTheme() {
  final colorScheme = ColorScheme.light(
    primary: AppColors.primary,
    onPrimary: Colors.white,
    primaryContainer: AppColors.primaryLight,
    onPrimaryContainer: AppColors.primaryContainer,
    secondary: AppColors.coral,
    onSecondary: Colors.white,
    error: AppColors.red,
    onError: Colors.white,
    surface: AppColors.surface,
    onSurface: AppColors.textPrimary,
    surfaceContainerHighest: AppColors.surfaceContainer,
    outline: AppColors.border,
    outlineVariant: AppColors.outlineVariant,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.surfaceDim,
    canvasColor: AppColors.surface,
    cardColor: AppColors.bgCard,
    dividerColor: AppColors.border,

    // -- Extensions ----------------------------------------------------------
    extensions: const <ThemeExtension<dynamic>>[
      PosColors(),
    ],

    // -- Typography ----------------------------------------------------------
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        letterSpacing: -0.5,
      ),
      displayMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      displaySmall: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      headlineMedium: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      headlineSmall: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      titleLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
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
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
      ),
      labelSmall: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w500,
        color: AppColors.textDim,
      ),
    ),

    // -- Card ----------------------------------------------------------------
    cardTheme: CardThemeData(
      color: AppColors.bgCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadiusMedium),
      ),
      margin: EdgeInsets.zero,
    ),

    // -- Input decoration ----------------------------------------------------
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.bgInput,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusSmall),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusSmall),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusSmall),
        borderSide: const BorderSide(color: AppColors.borderFocused, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusSmall),
        borderSide: const BorderSide(color: AppColors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusSmall),
        borderSide: const BorderSide(color: AppColors.red, width: 2),
      ),
      hintStyle: const TextStyle(color: AppColors.textDim),
      labelStyle: const TextStyle(color: AppColors.textSecondary),
    ),

    // -- Elevated button -----------------------------------------------------
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusSmall),
        ),
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    // -- Text button ---------------------------------------------------------
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusSmall),
        ),
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    // -- Outlined button -----------------------------------------------------
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        minimumSize: const Size(0, 48),
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusSmall),
        ),
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    // -- Dialog ---------------------------------------------------------------
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      elevation: 8,
      shadowColor: const Color(0x1A000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadiusLarge),
      ),
    ),

    // -- Bottom sheet --------------------------------------------------------
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
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
      backgroundColor: AppColors.textPrimary,
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadiusSmall),
      ),
      behavior: SnackBarBehavior.floating,
    ),

    // -- AppBar (used sparingly) ---------------------------------------------
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      shadowColor: Color(0x0D000000),
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),

    // -- Chip ----------------------------------------------------------------
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surfaceContainerHigh,
      selectedColor: AppColors.accentDim,
      labelStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
  );
}

// ---------------------------------------------------------------------------
// Custom theme extension for POS-specific colours
// ---------------------------------------------------------------------------

/// Additional colours that don't map to Material's [ColorScheme] but are
/// essential for POS UI elements: status indicators, table states, badges.
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
