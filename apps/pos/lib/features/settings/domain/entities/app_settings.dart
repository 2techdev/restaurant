/// Application-level UI settings entity.
///
/// Controls theme (dark / light / system) and UI language.
/// Switzerland is officially quadrilingual: German, French, Italian, Romansh.
/// We support the three major + English for international staff.
library;

import 'dart:convert';

/// UI display language.
enum AppLanguage {
  de,
  fr,
  it,
  en;

  String get label => switch (this) {
        de => 'Deutsch',
        fr => 'Français',
        it => 'Italiano',
        en => 'English',
      };

  String get flag => switch (this) {
        de => '🇩🇪',
        fr => '🇫🇷',
        it => '🇮🇹',
        en => '🇬🇧',
      };

  static AppLanguage fromString(String s) =>
      AppLanguage.values.firstWhere(
        (e) => e.name == s,
        orElse: () => AppLanguage.de,
      );
}

/// Application theme mode.
enum AppThemeMode {
  dark,
  light,
  system;

  String get label => switch (this) {
        dark => 'Dark',
        light => 'Light',
        system => 'System default',
      };

  static AppThemeMode fromString(String s) =>
      AppThemeMode.values.firstWhere(
        (e) => e.name == s,
        orElse: () => AppThemeMode.light,
      );
}

/// Which hand the operator uses to tap the POS. Right-handed (default)
/// keeps the rail on the left and the order column between rail and menu.
/// Left-handed mirrors the layout so the most-tapped controls sit under
/// the operator's thumb without crossing their body.
enum AppHandedness {
  right,
  left;

  String get label => switch (this) {
        right => 'Sağ el (varsayılan)',
        left => 'Sol el (ayna)',
      };

  static AppHandedness fromString(String s) =>
      AppHandedness.values.firstWhere(
        (e) => e.name == s,
        orElse: () => AppHandedness.right,
      );
}

/// Discrete text-size presets applied via MediaQuery.textScaler. Matches
/// how iOS / Android ship their a11y controls so operators already know
/// the metaphor, and keeps us away from a free-form slider that can
/// produce unreadable rows when pushed too far.
enum AppTextScale {
  small,
  medium,
  large,
  extraLarge;

  /// Multiplier applied to every body text size.
  double get scale => switch (this) {
        small => 0.9,
        medium => 1.0,
        large => 1.15,
        extraLarge => 1.3,
      };

  String get label => switch (this) {
        small => 'Küçük',
        medium => 'Orta (varsayılan)',
        large => 'Büyük',
        extraLarge => 'Çok büyük',
      };

  static AppTextScale fromString(String s) =>
      AppTextScale.values.firstWhere(
        (e) => e.name == s,
        orElse: () => AppTextScale.medium,
      );
}

class AppSettings {
  const AppSettings({
    this.themeMode = AppThemeMode.light,
    this.language = AppLanguage.de,
    this.handedness = AppHandedness.right,
    this.highContrast = false,
    this.textScale = AppTextScale.medium,
  });

  /// Active color theme.
  final AppThemeMode themeMode;

  /// Active UI language.
  final AppLanguage language;

  /// Operator handedness — drives the POS shell layout mirroring.
  final AppHandedness handedness;

  /// When true the shell overlays a high-contrast ColorScheme so the POS
  /// stays legible in bright-window restaurants and for operators with
  /// low vision. Applied on top of light or dark mode.
  final bool highContrast;

  /// User-chosen text size preset. Feeds into MediaQuery.textScaler.
  final AppTextScale textScale;

  AppSettings copyWith({
    AppThemeMode? themeMode,
    AppLanguage? language,
    AppHandedness? handedness,
    bool? highContrast,
    AppTextScale? textScale,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        language: language ?? this.language,
        handedness: handedness ?? this.handedness,
        highContrast: highContrast ?? this.highContrast,
        textScale: textScale ?? this.textScale,
      );

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode.name,
        'language': language.name,
        'handedness': handedness.name,
        'highContrast': highContrast,
        'textScale': textScale.name,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        themeMode:
            AppThemeMode.fromString((json['themeMode'] as String?) ?? 'light'),
        language:
            AppLanguage.fromString((json['language'] as String?) ?? 'de'),
        handedness: AppHandedness.fromString(
          (json['handedness'] as String?) ?? 'right',
        ),
        highContrast: (json['highContrast'] as bool?) ?? false,
        textScale: AppTextScale.fromString(
          (json['textScale'] as String?) ?? 'medium',
        ),
      );

  String toJsonString() => jsonEncode(toJson());

  factory AppSettings.fromJsonString(String s) =>
      AppSettings.fromJson(jsonDecode(s) as Map<String, dynamic>);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettings &&
          themeMode == other.themeMode &&
          language == other.language &&
          handedness == other.handedness &&
          highContrast == other.highContrast &&
          textScale == other.textScale;

  @override
  int get hashCode =>
      Object.hash(themeMode, language, handedness, highContrast, textScale);
}
