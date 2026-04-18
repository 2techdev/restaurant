/// Application-level UI settings entity.
///
/// Controls theme (dark / light / system) and UI language.
/// Switzerland is officially quadrilingual: German, French, Italian, Romansh.
/// We support the three major + English for international staff.
library;

import 'dart:convert';

/// UI display language.
///
/// Default order reflects the Swiss fine-dining pilot priority: German first
/// (de-CH primary market), Turkish (for the multilingual staff pool), then
/// English as an international fallback. French and Italian round out the
/// Swiss quadrilingual baseline.
enum AppLanguage {
  de,
  tr,
  en,
  fr,
  it;

  String get label => switch (this) {
        de => 'Deutsch',
        tr => 'Türkçe',
        en => 'English',
        fr => 'Français',
        it => 'Italiano',
      };

  String get flag => switch (this) {
        de => '🇨🇭',
        tr => '🇹🇷',
        en => '🇬🇧',
        fr => '🇫🇷',
        it => '🇮🇹',
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
        orElse: () => AppThemeMode.dark,
      );
}

class AppSettings {
  const AppSettings({
    this.themeMode = AppThemeMode.dark,
    this.language = AppLanguage.de,
  });

  /// Active color theme.
  final AppThemeMode themeMode;

  /// Active UI language.
  final AppLanguage language;

  AppSettings copyWith({
    AppThemeMode? themeMode,
    AppLanguage? language,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        language: language ?? this.language,
      );

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode.name,
        'language': language.name,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        themeMode:
            AppThemeMode.fromString((json['themeMode'] as String?) ?? 'dark'),
        language:
            AppLanguage.fromString((json['language'] as String?) ?? 'de'),
      );

  String toJsonString() => jsonEncode(toJson());

  factory AppSettings.fromJsonString(String s) =>
      AppSettings.fromJson(jsonDecode(s) as Map<String, dynamic>);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettings &&
          themeMode == other.themeMode &&
          language == other.language;

  @override
  int get hashCode => Object.hash(themeMode, language);
}
