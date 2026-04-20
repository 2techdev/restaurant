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

class AppSettings {
  const AppSettings({
    this.themeMode = AppThemeMode.light,
    this.language = AppLanguage.de,
    this.handedness = AppHandedness.right,
  });

  /// Active color theme.
  final AppThemeMode themeMode;

  /// Active UI language.
  final AppLanguage language;

  /// Operator handedness — drives the POS shell layout mirroring.
  final AppHandedness handedness;

  AppSettings copyWith({
    AppThemeMode? themeMode,
    AppLanguage? language,
    AppHandedness? handedness,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        language: language ?? this.language,
        handedness: handedness ?? this.handedness,
      );

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode.name,
        'language': language.name,
        'handedness': handedness.name,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        themeMode:
            AppThemeMode.fromString((json['themeMode'] as String?) ?? 'light'),
        language:
            AppLanguage.fromString((json['language'] as String?) ?? 'de'),
        handedness: AppHandedness.fromString(
          (json['handedness'] as String?) ?? 'right',
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
          handedness == other.handedness;

  @override
  int get hashCode => Object.hash(themeMode, language, handedness);
}
