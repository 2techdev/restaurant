/// POS v2 design-system tokens — 1:1 port of
/// `E:/Project/Restaurant/.design/pos-v2/POS.html` `:root`.
///
/// Every value here corresponds to a CSS custom-property in the design
/// stylesheet. OKLCH colours are approximated to sRGB hex since Flutter
/// ships no native OKLCH colour space; the hex values were generated from
/// the original oklch(…) triples and spot-checked against the design
/// screenshot the user shipped as ground truth.
library;

import 'package:flutter/material.dart';

/// Namespace for the POS v2 colour tokens. Static const fields mirror the
/// `--xxx` CSS variable names on the design root.
abstract final class V2 {
  // --- Surface / line / ink -------------------------------------------------
  /// `--bg`: cool light gray canvas.
  static const Color bg = Color(0xFFF4F5F7);
  /// `--surface`: pure white panels.
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surface2 = Color(0xFFF7F8FA);
  static const Color surface3 = Color(0xFFEEF0F2);
  static const Color line = Color(0xFFDFE2E5);
  static const Color lineStrong = Color(0xFFC4C8CB);

  /// `--ink`: primary text (near-black).
  static const Color ink = Color(0xFF2B2E38);
  static const Color ink2 = Color(0xFF555966);
  static const Color ink3 = Color(0xFF848893);
  static const Color ink4 = Color(0xFFAEB1B8);

  // --- Rail / topbar chrome -------------------------------------------------
  static const Color chrome = Color(0xFF384151);
  static const Color chrome2 = Color(0xFF2A3140);
  static const Color chromeInk = Color(0xFFECEDEF);
  static const Color chromeInkDim = Color(0xFFAEB1B8);

  // --- Selection / focus blue ----------------------------------------------
  /// `--sel`: selection / focus blue (system signal).
  static const Color sel = Color(0xFF486BE1);
  /// `--sel-weak`: tinted selection background.
  static const Color selWeak = Color(0xFFE3E6F7);
  /// `--sel-ink`: dark selection text colour.
  static const Color selInk = Color(0xFF2246C2);

  // --- Legacy aliases (match CSS `--accent` → `--sel`) ---------------------
  static const Color accent = sel;
  static const Color accent2 = selInk;
  static const Color accentWeak = selWeak;
  static const Color accentInk = selInk;
  static const Color brandDark = chrome;
  static const Color brandCream = chromeInk;

  // --- Pay CTA (bold saturated green) --------------------------------------
  static const Color pay = Color(0xFF2BAE66);
  static const Color pay2 = Color(0xFF1D9D4F);
  static const Color payInk = Color(0xFFFFFFFF);

  // --- Category brand palette ----------------------------------------------
  static const Color cVor = Color(0xFF319F68);
  static const Color cVorWk = Color(0xFFDFF0E4);
  static const Color cSalat = Color(0xFF4FB06F);
  static const Color cSalatWk = Color(0xFFE0F2E2);
  static const Color cHaupt = Color(0xFFD3543E);
  static const Color cHauptWk = Color(0xFFF7DFD9);
  static const Color cPasta = Color(0xFFD88B3C);
  static const Color cPastaWk = Color(0xFFF4E4CD);
  static const Color cDessert = Color(0xFFC4539A);
  static const Color cDessertWk = Color(0xFFF2DCEA);
  static const Color cDrink = Color(0xFF467DCB);
  static const Color cDrinkWk = Color(0xFFDCE5F2);

  // --- Status colours ------------------------------------------------------
  static const Color ok = Color(0xFF3A9E60);
  static const Color okWeak = Color(0xFFE0EFE4);
  static const Color warn = Color(0xFFD39842);
  static const Color warnWeak = Color(0xFFF7E8CD);
  static const Color danger = Color(0xFFDF4832);
  static const Color dangerWeak = Color(0xFFF7DED8);
}

/// Palette rotation used when a category has no explicit colour override.
/// Matches the design deck's cycle: vor → haupt → pasta → dessert → drink → salat.
const List<({Color bg, Color bgWk})> _v2PaletteCycle = [
  (bg: V2.cVor, bgWk: V2.cVorWk),
  (bg: V2.cHaupt, bgWk: V2.cHauptWk),
  (bg: V2.cPasta, bgWk: V2.cPastaWk),
  (bg: V2.cDessert, bgWk: V2.cDessertWk),
  (bg: V2.cDrink, bgWk: V2.cDrinkWk),
  (bg: V2.cSalat, bgWk: V2.cSalatWk),
];

/// Parse a `#RRGGBB`, `#AARRGGBB` or `RRGGBB` hex string.
Color? v2ParseHex(String? hex) {
  if (hex == null) return null;
  var s = hex.trim();
  if (s.isEmpty) return null;
  if (s.startsWith('#')) s = s.substring(1);
  if (s.length == 6) s = 'FF$s';
  if (s.length != 8) return null;
  final v = int.tryParse(s, radix: 16);
  if (v == null) return null;
  return Color(v);
}

/// Resolve a category tile colour. When the seed category colour is present
/// (e.g. `#FF6B35`) it is used directly; otherwise the palette cycles by
/// `index` so adjacent tiles never share a fill.
({Color bg, Color bgWk}) v2CategoryPalette(String? hex, int index) {
  final parsed = v2ParseHex(hex);
  if (parsed != null) {
    return (bg: parsed, bgWk: parsed.withValues(alpha: 0.12));
  }
  return _v2PaletteCycle[index % _v2PaletteCycle.length];
}

/// Text helpers — match the POS v2 typographic scale. `Inter` is bundled in
/// the app already (see pubspec/assets).
abstract final class V2Text {
  static const String _inter = 'Inter';

  static const TextStyle brandName = TextStyle(
    fontFamily: _inter,
    fontWeight: FontWeight.w700,
    fontSize: 19,
    letterSpacing: -0.38,
    color: V2.chromeInk,
  );
  static const TextStyle brandAccent = TextStyle(
    fontFamily: _inter,
    fontWeight: FontWeight.w400,
    fontSize: 19,
    letterSpacing: -0.38,
    color: V2.sel,
    fontStyle: FontStyle.normal,
  );
  static const TextStyle brandTag = TextStyle(
    fontFamily: _inter,
    fontWeight: FontWeight.w500,
    fontSize: 9.5,
    letterSpacing: 1.7,
    color: Color(0x73FFFFFF),
  );

  static const TextStyle ticketId = TextStyle(
    fontFamily: _inter,
    fontWeight: FontWeight.w600,
    fontSize: 13,
    color: V2.chromeInk,
    fontFeatures: [FontFeature.tabularFigures()],
  );
  static const TextStyle ticketSub = TextStyle(
    fontFamily: _inter,
    fontWeight: FontWeight.w400,
    fontSize: 11.5,
    color: Color(0x8CFFFFFF),
  );

  static const TextStyle modeOn = TextStyle(
    fontFamily: _inter,
    fontWeight: FontWeight.w700,
    fontSize: 12.5,
    color: Colors.white,
  );
  static const TextStyle modeOff = TextStyle(
    fontFamily: _inter,
    fontWeight: FontWeight.w600,
    fontSize: 12.5,
    color: Color(0xB3FFFFFF),
  );

  static const TextStyle orderH2 = TextStyle(
    fontFamily: _inter,
    fontWeight: FontWeight.w700,
    fontSize: 16,
    letterSpacing: -0.24,
    color: V2.ink,
  );

  static const TextStyle gangLabel = TextStyle(
    fontFamily: _inter,
    fontWeight: FontWeight.w500,
    fontSize: 12,
    color: V2.ink2,
  );
  static const TextStyle gangCount = TextStyle(
    fontFamily: _inter,
    fontWeight: FontWeight.w500,
    fontSize: 10,
    color: V2.ink4,
    height: 1.0,
  );
  static const TextStyle gangOn = TextStyle(
    fontFamily: _inter,
    fontWeight: FontWeight.w700,
    fontSize: 12,
    color: Colors.white,
  );

  static const TextStyle gangHead = TextStyle(
    fontFamily: _inter,
    fontWeight: FontWeight.w600,
    fontSize: 10,
    letterSpacing: 1.0,
    color: V2.ink3,
  );

  static const TextStyle chip = TextStyle(
    fontFamily: _inter,
    fontWeight: FontWeight.w500,
    fontSize: 10,
    letterSpacing: 0.6,
    color: V2.ink2,
    height: 1.0,
  );

  static const TextStyle chipSend = TextStyle(
    fontFamily: _inter,
    fontWeight: FontWeight.w600,
    fontSize: 10,
    letterSpacing: 0.6,
    color: V2.chrome,
    height: 1.0,
  );

  static const TextStyle chipSent = TextStyle(
    fontFamily: _inter,
    fontWeight: FontWeight.w500,
    fontSize: 10,
    letterSpacing: 0.6,
    color: V2.ok,
    height: 1.0,
  );

  static const TextStyle lineQty = TextStyle(
    fontFamily: _inter,
    fontWeight: FontWeight.w500,
    fontSize: 13,
    color: V2.ink3,
    height: 1.0,
  );
  static const TextStyle lineTitle = TextStyle(
    fontFamily: _inter,
    fontWeight: FontWeight.w500,
    fontSize: 14,
    letterSpacing: -0.07,
    color: V2.ink,
  );
  static const TextStyle lineNote = TextStyle(
    fontFamily: _inter,
    fontSize: 11.5,
    color: V2.ink3,
  );
  static const TextStyle linePrice = TextStyle(
    fontFamily: _inter,
    fontWeight: FontWeight.w500,
    fontSize: 13,
    color: V2.ink2,
    height: 1.0,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const TextStyle kv = TextStyle(
    fontFamily: _inter,
    fontSize: 12.5,
    color: V2.ink3,
    fontFeatures: [FontFeature.tabularFigures()],
  );
  static const TextStyle kvTotalK = TextStyle(
    fontFamily: _inter,
    fontWeight: FontWeight.w600,
    fontSize: 11,
    letterSpacing: 1.3,
    color: V2.ink3,
  );
  static const TextStyle kvTotalV = TextStyle(
    fontFamily: _inter,
    fontWeight: FontWeight.w700,
    fontSize: 26,
    letterSpacing: -0.52,
    color: V2.ink,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const TextStyle catH = TextStyle(
    fontFamily: _inter,
    fontWeight: FontWeight.w600,
    fontSize: 10,
    letterSpacing: 1.2,
    color: V2.ink4,
  );
  static const TextStyle catName = TextStyle(
    fontFamily: _inter,
    fontWeight: FontWeight.w600,
    fontSize: 14,
    letterSpacing: -0.07,
    color: Colors.white,
    height: 1.15,
  );
  static const TextStyle catN = TextStyle(
    fontFamily: _inter,
    fontWeight: FontWeight.w600,
    fontSize: 10.5,
    letterSpacing: 0.3,
    color: Color(0xCCFFFFFF),
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const TextStyle pName = TextStyle(
    fontFamily: _inter,
    fontWeight: FontWeight.w600,
    fontSize: 15,
    letterSpacing: -0.075,
    color: Colors.white,
    height: 1.22,
  );
  static const TextStyle pSub = TextStyle(
    fontFamily: _inter,
    fontWeight: FontWeight.w500,
    fontSize: 11.5,
    color: Color(0xD1FFFFFF),
  );
  static const TextStyle pPrice = TextStyle(
    fontFamily: _inter,
    fontWeight: FontWeight.w700,
    fontSize: 15,
    letterSpacing: -0.15,
    color: Colors.white,
    fontFeatures: [FontFeature.tabularFigures()],
  );
  static const TextStyle pCurrency = TextStyle(
    fontFamily: _inter,
    fontWeight: FontWeight.w500,
    fontSize: 10.5,
    letterSpacing: 0.2,
    color: Color(0xCCFFFFFF),
  );
  static const TextStyle inCart = TextStyle(
    fontFamily: _inter,
    fontWeight: FontWeight.w700,
    fontSize: 12,
    fontFeatures: [FontFeature.tabularFigures()],
    height: 1.0,
  );

  static const TextStyle schnellName = TextStyle(
    fontFamily: _inter,
    fontWeight: FontWeight.w600,
    fontSize: 12,
    letterSpacing: -0.06,
    color: V2.ink,
    height: 1.2,
  );
  static const TextStyle schnellPrice = TextStyle(
    fontFamily: _inter,
    fontWeight: FontWeight.w700,
    fontSize: 12,
    letterSpacing: -0.12,
    color: V2.ink,
    fontFeatures: [FontFeature.tabularFigures()],
    height: 1.0,
  );
  static const TextStyle schnellCur = TextStyle(
    fontFamily: _inter,
    fontWeight: FontWeight.w500,
    fontSize: 9,
    letterSpacing: 0.72,
    color: V2.ink4,
  );

  static const TextStyle itemsH = TextStyle(
    fontFamily: _inter,
    fontWeight: FontWeight.w700,
    fontSize: 22,
    letterSpacing: -0.44,
    color: V2.ink,
  );
  static const TextStyle crumb = TextStyle(
    fontFamily: _inter,
    fontWeight: FontWeight.w500,
    fontSize: 11.5,
    letterSpacing: 0.69,
    color: V2.ink3,
  );

  static const TextStyle railLabel = TextStyle(
    fontFamily: _inter,
    fontWeight: FontWeight.w500,
    fontSize: 10,
    letterSpacing: 0.5,
    color: Color(0xFFBCA087),
  );
  static const TextStyle railLabelActive = TextStyle(
    fontFamily: _inter,
    fontWeight: FontWeight.w500,
    fontSize: 10,
    letterSpacing: 0.5,
    color: V2.chromeInk,
  );

  static const TextStyle btn = TextStyle(
    fontFamily: _inter,
    fontWeight: FontWeight.w500,
    fontSize: 13,
    color: V2.ink,
  );
  static const TextStyle btnDanger = TextStyle(
    fontFamily: _inter,
    fontWeight: FontWeight.w500,
    fontSize: 13,
    color: V2.danger,
  );
  static const TextStyle btnAccent = TextStyle(
    fontFamily: _inter,
    fontWeight: FontWeight.w700,
    fontSize: 15,
    color: V2.payInk,
    letterSpacing: 0.0,
  );
}

// ---------------------------------------------------------------------------
// V2Palette — theme-aware surface / line / ink tokens.
// ---------------------------------------------------------------------------

/// Subset of [V2] tokens that flip between light and dark modes.
///
/// The hard-coded [V2] class stays for accent colours (sel, pay, ok, warn,
/// danger, category tiles) — those read well on both themes, so they don't
/// need runtime resolution. Backgrounds, panel surfaces, hairlines and ink
/// tones, on the other hand, break visually when the user switches to dark
/// mode, so they live here and are looked up via `context.v2`.
class V2Palette extends ThemeExtension<V2Palette> {
  const V2Palette({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.line,
    required this.lineStrong,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.ink4,
    required this.chrome,
    required this.chrome2,
    required this.chromeInk,
    required this.chromeInkDim,
    required this.isDark,
  });

  final Color bg;
  final Color surface;
  final Color surface2;
  final Color surface3;
  final Color line;
  final Color lineStrong;
  final Color ink;
  final Color ink2;
  final Color ink3;
  final Color ink4;
  final Color chrome;
  final Color chrome2;
  final Color chromeInk;
  final Color chromeInkDim;
  final bool isDark;

  /// Design-system default palette — matches [V2]'s light tokens exactly.
  static const light = V2Palette(
    bg: V2.bg,
    surface: V2.surface,
    surface2: V2.surface2,
    surface3: V2.surface3,
    line: V2.line,
    lineStrong: V2.lineStrong,
    ink: V2.ink,
    ink2: V2.ink2,
    ink3: V2.ink3,
    ink4: V2.ink4,
    chrome: V2.chrome,
    chrome2: V2.chrome2,
    chromeInk: V2.chromeInk,
    chromeInkDim: V2.chromeInkDim,
    isDark: false,
  );

  /// Dark variant — hand-tuned for WCAG-AA contrast against the same accent
  /// colours (V2.sel, V2.pay, V2.ok, V2.warn, V2.danger) that the sales
  /// shell already uses, so only the neutral layer flips.
  static const dark = V2Palette(
    bg: Color(0xFF0E1116),
    surface: Color(0xFF161A21),
    surface2: Color(0xFF1C2129),
    surface3: Color(0xFF232932),
    line: Color(0xFF2A313B),
    lineStrong: Color(0xFF3A424E),
    ink: Color(0xFFE6E9EE),
    ink2: Color(0xFFB8BDC7),
    ink3: Color(0xFF8A90A0),
    ink4: Color(0xFF5D6472),
    // Chrome (rail + topbar) stays close to its light-mode value since it
    // was already dark — but nudge it a touch cooler so it doesn't look
    // neon against the surface3 panels.
    chrome: Color(0xFF1A1F28),
    chrome2: Color(0xFF101419),
    chromeInk: Color(0xFFECEDEF),
    chromeInkDim: Color(0xFF8A90A0),
    isDark: true,
  );

  @override
  V2Palette copyWith({
    Color? bg,
    Color? surface,
    Color? surface2,
    Color? surface3,
    Color? line,
    Color? lineStrong,
    Color? ink,
    Color? ink2,
    Color? ink3,
    Color? ink4,
    Color? chrome,
    Color? chrome2,
    Color? chromeInk,
    Color? chromeInkDim,
    bool? isDark,
  }) =>
      V2Palette(
        bg: bg ?? this.bg,
        surface: surface ?? this.surface,
        surface2: surface2 ?? this.surface2,
        surface3: surface3 ?? this.surface3,
        line: line ?? this.line,
        lineStrong: lineStrong ?? this.lineStrong,
        ink: ink ?? this.ink,
        ink2: ink2 ?? this.ink2,
        ink3: ink3 ?? this.ink3,
        ink4: ink4 ?? this.ink4,
        chrome: chrome ?? this.chrome,
        chrome2: chrome2 ?? this.chrome2,
        chromeInk: chromeInk ?? this.chromeInk,
        chromeInkDim: chromeInkDim ?? this.chromeInkDim,
        isDark: isDark ?? this.isDark,
      );

  @override
  V2Palette lerp(ThemeExtension<V2Palette>? other, double t) {
    if (other is! V2Palette) return this;
    return V2Palette(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      surface3: Color.lerp(surface3, other.surface3, t)!,
      line: Color.lerp(line, other.line, t)!,
      lineStrong: Color.lerp(lineStrong, other.lineStrong, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      ink2: Color.lerp(ink2, other.ink2, t)!,
      ink3: Color.lerp(ink3, other.ink3, t)!,
      ink4: Color.lerp(ink4, other.ink4, t)!,
      chrome: Color.lerp(chrome, other.chrome, t)!,
      chrome2: Color.lerp(chrome2, other.chrome2, t)!,
      chromeInk: Color.lerp(chromeInk, other.chromeInk, t)!,
      chromeInkDim: Color.lerp(chromeInkDim, other.chromeInkDim, t)!,
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}

/// Pull the active [V2Palette] off a [BuildContext]. Falls back to the
/// light palette when the theme hasn't registered one — keeps unit tests
/// that build bare [MaterialApp]s working without extra plumbing.
extension V2PaletteContext on BuildContext {
  V2Palette get v2 =>
      Theme.of(this).extension<V2Palette>() ?? V2Palette.light;
}

/// Format a Swiss-franc amount from integer cents — matches the
/// `chf()` helper in `parts.jsx` (`toLocaleString('de-CH', { min: 2, max: 2 })`).
String v2Chf(int cents) {
  final whole = (cents.abs() ~/ 100).toString();
  final frac = (cents.abs() % 100).toString().padLeft(2, '0');
  // de-CH thousands grouping with apostrophes.
  final withApos = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    final rev = whole.length - i;
    withApos.write(whole[i]);
    if (rev > 1 && rev % 3 == 1) withApos.write("'");
  }
  final sign = cents < 0 ? '-' : '';
  return '$sign${withApos.toString()}.$frac';
}
