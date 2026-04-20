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
