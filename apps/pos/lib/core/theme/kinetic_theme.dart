/// Kinetic Grid design system — light, zero-radius, tonal-layered.
///
/// Applied as a local [Theme] override around the POS sales shells only —
/// the rest of the app still runs on [buildAppTheme] (dark Stitch). Keeping
/// the two side-by-side lets us redesign the sales surface without
/// repainting Settings / Tables / Reports on a pilot deadline.
///
/// Palette follows the "Industrial Precision + Editorial Authority" brief:
///   * `#3841e9` primary, `#2931de` primary-dim — used for the Pay CTA, the
///     selected ticket item's left border, and active chip fills.
///   * `#f4f7f9` canvas, surface-container-lowest / low / high / highest —
///     depth is expressed via tonal nesting instead of shadows or 1px lines.
///   * SambaPOS warm category palette (catRed / catOrange / catYellow /
///     catGreen / catTeal / catCyan) — saturated, scan-optimized tiles.
///
/// Typography: Work Sans for headlines / labels UPPERCASE, Inter for body.
/// `google_fonts` is NOT currently in pubspec (pilot deadline), so these
/// resolve to platform defaults with weight contrast carrying the style.
/// Swap-in via `GoogleFonts.workSans()` / `GoogleFonts.inter()` is trivial
/// later — [GcText] is the single caller surface.
library;

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// GcColors — the Kinetic palette. Static Color constants; no theme lookup.
// ---------------------------------------------------------------------------

/// GastroCore Kinetic color tokens.
///
/// Pure constants so widgets that read `GcColors.primary` don't pay a
/// `Theme.of(context)` traversal per rebuild. Named after the brief's
/// CSS variables so cross-referencing with the design spec is trivial.
abstract final class GcColors {
  // Primary / brand
  static const Color primary = Color(0xFF3841E9);
  static const Color primaryDim = Color(0xFF2931DE);
  static const Color primaryContainer = Color(0xFF9097FF);
  static const Color onPrimary = Color(0xFFF3F1FF);

  // Secondary — cash / gifted / drinks accent
  static const Color secondary = Color(0xFF176A21);
  static const Color secondaryDim = Color(0xFF025D16);
  static const Color onSecondary = Color(0xFFD1FFC8);

  // Tertiary — desserts accent
  static const Color tertiary = Color(0xFF984200);
  static const Color tertiaryDim = Color(0xFF853900);
  static const Color tertiaryFixed = Color(0xFFFF9658);

  // Error — void / destructive
  static const Color error = Color(0xFFB41340);
  static const Color errorDim = Color(0xFFA70138);

  // Surface layering — tonal depth, no shadows
  static const Color surface = Color(0xFFF4F7F9);
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color surfaceContainerLow = Color(0xFFEEF1F3);
  static const Color surfaceContainer = Color(0xFFE4E9EB);
  static const Color surfaceContainerHigh = Color(0xFFDEE3E6);
  static const Color surfaceContainerHighest = Color(0xFFD8DEE1);

  // Text
  static const Color onSurface = Color(0xFF2B2F31);
  static const Color onSurfaceVariant = Color(0xFF585C5E);
  static const Color outline = Color(0xFF737779);
  static const Color outlineVariant = Color(0xFFAAAEB0);

  // Ghost border — translucent outline-variant (alpha 0.2)
  static const Color ghostBorder = Color(0x33AAAEB0);

  // Ambient shadow — tonal, never pure black
  static const Color ambientShadow = Color(0x142B2F31);

  // ---- SambaPOS warm category palette ------------------------------------

  static const Color catRed = Color(0xFFE53935);
  static const Color catOrange = Color(0xFFF57C00);
  static const Color catYellow = Color(0xFFFBC02D);
  static const Color catGreen = Color(0xFF43A047);
  static const Color catTeal = Color(0xFF00838F);
  static const Color catCyan = Color(0xFF00ACC1);
  static const Color catDarkGreen = Color(0xFF2E7D32);
  static const Color catPurple = Color(0xFF7B1FA2);
}

// ---------------------------------------------------------------------------
// Category color resolution — SambaPOS default mapping + contrast helpers
// ---------------------------------------------------------------------------

/// Resolve a category fill color by human-readable name.
///
/// Used when the restaurant hasn't set a per-category override in
/// `RestaurantSettings.categoryColorMap` (future P1). Comparison is
/// case-insensitive and matches on both the seed English names and the
/// Turkish menu the pilot uses day-one.
///
/// Falls back to [GcColors.primaryContainer] so unknown categories still
/// render a legible tile rather than a naked surface.
Color resolveCategoryColor(String name, {Color? fallback}) {
  final key = name.trim().toLowerCase();
  for (final (match, color) in _categoryDefaults) {
    if (key.contains(match)) return color;
  }
  return fallback ?? GcColors.primaryContainer;
}

/// Pick a foreground color that reads over [bg]. Uses the perceptual
/// luminance rule — yellows / light oranges flip to dark text, everything
/// else stays white.
Color onCategoryColor(Color bg) {
  final lum = bg.computeLuminance();
  return lum > 0.55 ? GcColors.onSurface : GcColors.onPrimary;
}

// Ordered because 'sandwiches' would match both "sandwich" and "salad" if
// we didn't scan the more specific token first.
const List<(String, Color)> _categoryDefaults = [
  ('starter', GcColors.catRed),
  ('wing', GcColors.catRed),
  ('salad', GcColors.catYellow),
  ('side', GcColors.catYellow),
  ('burger', GcColors.catOrange),
  ('wrap', GcColors.catOrange),
  ('sandwich', GcColors.catYellow),
  ('pizza', GcColors.catRed),
  ('rib', GcColors.catOrange),
  ('chicken', GcColors.catOrange),
  ('seafood', GcColors.catRed),
  ('dessert', GcColors.tertiaryFixed),
  ('tatl', GcColors.tertiaryFixed), // tr: tatlı
  ('beverage', GcColors.catRed),
  ('frozen', GcColors.catOrange),
  ('kebab', GcColors.catOrange),
  ('kebap', GcColors.catOrange), // tr
  ('drink', GcColors.catCyan),
  ('içecek', GcColors.catCyan), // tr
  ('içki', GcColors.catPurple), // tr: alkol
  ('alcohol', GcColors.catPurple),
  ('starter & wing', GcColors.catRed),
  ('vorspeise', GcColors.catRed), // de
  ('hauptgang', GcColors.catOrange), // de
  ('nachspeise', GcColors.tertiaryFixed), // de
  ('getränk', GcColors.catCyan), // de
];

// ---------------------------------------------------------------------------
// GcText — typography presets. Opaque TextStyles; callers pick the size.
// ---------------------------------------------------------------------------

/// Typography presets. Inter for body, Work Sans for labels / totals.
abstract final class GcText {
  static const String _workSans = 'WorkSans';
  static const String _inter = 'Inter';

  /// Headline (Balance Due, running totals) — Work Sans black.
  static const TextStyle displayBlack = TextStyle(
    fontFamily: _workSans,
    fontSize: 28,
    fontWeight: FontWeight.w900,
    color: GcColors.onSurface,
    letterSpacing: -0.5,
    height: 1.1,
  );

  /// Section header — Work Sans bold, UPPERCASE by caller.
  static const TextStyle headline = TextStyle(
    fontFamily: _workSans,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: GcColors.onSurface,
    letterSpacing: 0.6,
  );

  /// Tiny UPPERCASE label (TOPLAM, TABLE, ticket header).
  static const TextStyle labelTiny = TextStyle(
    fontFamily: _workSans,
    fontSize: 10,
    fontWeight: FontWeight.w800,
    color: GcColors.onSurfaceVariant,
    letterSpacing: 1.2,
  );

  /// Body / product name.
  static const TextStyle body = TextStyle(
    fontFamily: _inter,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: GcColors.onSurface,
  );

  /// Small body — modifier notes, seat labels.
  static const TextStyle bodySmall = TextStyle(
    fontFamily: _inter,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: GcColors.onSurfaceVariant,
  );

  /// Price rendering — Inter, tabular feel.
  static const TextStyle price = TextStyle(
    fontFamily: _inter,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: GcColors.onSurface,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Button label (primary / secondary action bar).
  static const TextStyle button = TextStyle(
    fontFamily: _workSans,
    fontSize: 13,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.8,
  );
}

// ---------------------------------------------------------------------------
// Theme builder — light Material 3 with zero radius across the board.
// ---------------------------------------------------------------------------

/// Builds a light [ThemeData] wired to the Kinetic palette.
///
/// Every shape override is [BorderRadius.zero]. Widgets that hard-code their
/// own `BorderRadius.circular(N)` inline still win — callers in the sales
/// shells have been updated to ask this theme for shapes instead.
ThemeData buildKineticTheme() {
  const colorScheme = ColorScheme.light(
    primary: GcColors.primary,
    onPrimary: GcColors.onPrimary,
    primaryContainer: GcColors.primaryContainer,
    onPrimaryContainer: GcColors.primary,
    secondary: GcColors.secondary,
    onSecondary: GcColors.onSecondary,
    secondaryContainer: GcColors.catGreen,
    tertiary: GcColors.tertiary,
    onTertiary: GcColors.onPrimary,
    tertiaryContainer: GcColors.tertiaryFixed,
    error: GcColors.error,
    onError: GcColors.onPrimary,
    surface: GcColors.surface,
    onSurface: GcColors.onSurface,
    surfaceContainerLowest: GcColors.surfaceContainerLowest,
    surfaceContainerLow: GcColors.surfaceContainerLow,
    surfaceContainer: GcColors.surfaceContainer,
    surfaceContainerHigh: GcColors.surfaceContainerHigh,
    surfaceContainerHighest: GcColors.surfaceContainerHighest,
    onSurfaceVariant: GcColors.onSurfaceVariant,
    outline: GcColors.outline,
    outlineVariant: GcColors.outlineVariant,
  );

  const zero = RoundedRectangleBorder(borderRadius: BorderRadius.zero);

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: GcColors.surface,
    canvasColor: GcColors.surface,
    cardColor: GcColors.surfaceContainerLowest,
    dividerColor: GcColors.ghostBorder,
    fontFamily: 'Inter',

    cardTheme: const CardThemeData(
      color: GcColors.surfaceContainerLowest,
      elevation: 0,
      shape: zero,
      margin: EdgeInsets.zero,
    ),

    appBarTheme: const AppBarTheme(
      backgroundColor: GcColors.surfaceContainer,
      foregroundColor: GcColors.onSurface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: zero,
      centerTitle: false,
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: GcColors.primary,
        foregroundColor: GcColors.onPrimary,
        elevation: 0,
        shape: zero,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        textStyle: GcText.button,
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: GcColors.primary,
        foregroundColor: GcColors.onPrimary,
        elevation: 0,
        shape: zero,
        minimumSize: const Size(0, 48),
        textStyle: GcText.button,
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: GcColors.onSurface,
        side: const BorderSide(color: GcColors.outlineVariant),
        shape: zero,
        minimumSize: const Size(0, 48),
        textStyle: GcText.button,
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: GcColors.primary,
        shape: zero,
        textStyle: GcText.button,
      ),
    ),

    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        shape: zero,
        foregroundColor: GcColors.onSurface,
      ),
    ),

    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: GcColors.primary,
      foregroundColor: GcColors.onPrimary,
      elevation: 0,
      shape: zero,
    ),

    chipTheme: const ChipThemeData(
      backgroundColor: GcColors.surfaceContainerLowest,
      selectedColor: GcColors.primary,
      labelStyle: GcText.button,
      side: BorderSide(color: GcColors.ghostBorder),
      shape: zero,
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    ),

    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: GcColors.surfaceContainerLowest,
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      // Bottom-only border per brief — full outlines are banned.
      border: UnderlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: GcColors.outlineVariant),
      ),
      enabledBorder: UnderlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: GcColors.outlineVariant),
      ),
      focusedBorder: UnderlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: GcColors.primary, width: 2),
      ),
      errorBorder: UnderlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: GcColors.error),
      ),
      hintStyle: TextStyle(color: GcColors.outline, fontSize: 13),
    ),

    dialogTheme: const DialogThemeData(
      backgroundColor: GcColors.surfaceContainerLowest,
      elevation: 0,
      shape: zero,
    ),

    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: GcColors.surfaceContainerLowest,
      elevation: 0,
      shape: zero,
      surfaceTintColor: Colors.transparent,
    ),

    menuTheme: const MenuThemeData(
      style: MenuStyle(
        shape: WidgetStatePropertyAll(zero),
      ),
    ),

    popupMenuTheme: const PopupMenuThemeData(
      shape: zero,
      color: GcColors.surfaceContainerLowest,
    ),

    dividerTheme: const DividerThemeData(
      color: GcColors.ghostBorder,
      thickness: 0,
      space: 0,
    ),

    snackBarTheme: const SnackBarThemeData(
      backgroundColor: GcColors.surfaceContainerHighest,
      contentTextStyle: TextStyle(color: GcColors.onSurface),
      shape: zero,
      behavior: SnackBarBehavior.fixed,
    ),

    textTheme: const TextTheme(
      displayLarge: GcText.displayBlack,
      headlineMedium: GcText.headline,
      titleMedium: GcText.headline,
      bodyLarge: GcText.body,
      bodyMedium: GcText.body,
      bodySmall: GcText.bodySmall,
      labelLarge: GcText.button,
      labelMedium: GcText.labelTiny,
      labelSmall: GcText.labelTiny,
    ),
  );
}

// ---------------------------------------------------------------------------
// Gradient helpers
// ---------------------------------------------------------------------------

/// Primary CTA gradient — top-to-bottom primary → primary-dim. Paired with
/// an inset white 0.2 top highlight on the rendering side.
const LinearGradient kPrimaryGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [GcColors.primary, GcColors.primaryDim],
);

/// Cash gradient for the bottom action bar (semantic = money in).
const LinearGradient kCashGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [GcColors.catGreen, GcColors.catDarkGreen],
);

/// Inset top highlight — a thin strip of translucent white on a filled
/// button so the edge reads as a raised surface without a shadow.
const Color kInsetHighlight = Color(0x33FFFFFF);
