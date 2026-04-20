/// Operator-configurable theme colour overrides.
///
/// Lives alongside [AppSettings] but persists independently so picking a
/// custom primary colour doesn't churn the main settings blob. Every field
/// is nullable — null means "use the design-system default", so the
/// on-disk payload stays empty on a fresh install and no migration is
/// needed when we extend the shape later.
library;

import 'dart:convert';

class ThemeCustomization {
  const ThemeCustomization({
    this.lightPrimaryHex,
    this.darkPrimaryHex,
    this.lightSurfaceHex,
    this.darkSurfaceHex,
  });

  final String? lightPrimaryHex;
  final String? darkPrimaryHex;
  final String? lightSurfaceHex;
  final String? darkSurfaceHex;

  bool get isDefault =>
      lightPrimaryHex == null &&
      darkPrimaryHex == null &&
      lightSurfaceHex == null &&
      darkSurfaceHex == null;

  ThemeCustomization copyWith({
    String? lightPrimaryHex,
    String? darkPrimaryHex,
    String? lightSurfaceHex,
    String? darkSurfaceHex,
    bool clearLightPrimary = false,
    bool clearDarkPrimary = false,
    bool clearLightSurface = false,
    bool clearDarkSurface = false,
  }) =>
      ThemeCustomization(
        lightPrimaryHex: clearLightPrimary
            ? null
            : (lightPrimaryHex ?? this.lightPrimaryHex),
        darkPrimaryHex: clearDarkPrimary
            ? null
            : (darkPrimaryHex ?? this.darkPrimaryHex),
        lightSurfaceHex: clearLightSurface
            ? null
            : (lightSurfaceHex ?? this.lightSurfaceHex),
        darkSurfaceHex: clearDarkSurface
            ? null
            : (darkSurfaceHex ?? this.darkSurfaceHex),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (lightPrimaryHex != null) 'lightPrimaryHex': lightPrimaryHex,
        if (darkPrimaryHex != null) 'darkPrimaryHex': darkPrimaryHex,
        if (lightSurfaceHex != null) 'lightSurfaceHex': lightSurfaceHex,
        if (darkSurfaceHex != null) 'darkSurfaceHex': darkSurfaceHex,
      };

  factory ThemeCustomization.fromJson(Map<String, dynamic> json) =>
      ThemeCustomization(
        lightPrimaryHex: json['lightPrimaryHex'] as String?,
        darkPrimaryHex: json['darkPrimaryHex'] as String?,
        lightSurfaceHex: json['lightSurfaceHex'] as String?,
        darkSurfaceHex: json['darkSurfaceHex'] as String?,
      );

  String toJsonString() => jsonEncode(toJson());

  factory ThemeCustomization.fromJsonString(String s) =>
      ThemeCustomization.fromJson(jsonDecode(s) as Map<String, dynamic>);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ThemeCustomization &&
          lightPrimaryHex == other.lightPrimaryHex &&
          darkPrimaryHex == other.darkPrimaryHex &&
          lightSurfaceHex == other.lightSurfaceHex &&
          darkSurfaceHex == other.darkSurfaceHex;

  @override
  int get hashCode => Object.hash(
        lightPrimaryHex,
        darkPrimaryHex,
        lightSurfaceHex,
        darkSurfaceHex,
      );
}
