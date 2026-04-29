/// Update manifest fetched from the update channel URL.
///
/// The manifest is a small JSON document hosted alongside the APK. The POS
/// polls it, compares `buildNumber` against the running build and surfaces a
/// "Update available" card in Settings → Güncelleme. The pilot is sideloaded
/// so we never auto-install — operators download the APK through their
/// default browser after tapping "İndir".
///
/// Example payload:
/// ```json
/// {
///   "versionName": "1.4.0",
///   "buildNumber": 140,
///   "apkUrl": "https://dl.gastrocore.ch/pilot/app-pos-release.apk",
///   "sha256": "0a12…",
///   "changelog": "Mesai molaları, sadakat editörü, Türkçe çeviri",
///   "minSupportedBuild": 100,
///   "releasedAt": "2026-04-20T10:00:00Z"
/// }
/// ```
library;

import 'dart:convert';

class UpdateManifest {
  const UpdateManifest({
    required this.versionName,
    required this.buildNumber,
    required this.apkUrl,
    this.sha256,
    this.changelog = '',
    this.minSupportedBuild = 0,
    this.releasedAt,
  });

  /// Human-readable version string shown in the UI ("1.4.0").
  final String versionName;

  /// Monotonic build number used for comparison against the running build.
  final int buildNumber;

  /// Absolute https URL of the APK. Opened through the system browser.
  final String apkUrl;

  /// Optional SHA256 of the APK so the operator can verify integrity.
  final String? sha256;

  /// Free-form changelog shown inline under the "İndir" button.
  final String changelog;

  /// Oldest build allowed to fetch updates. Builds below this should be
  /// forced to re-install from scratch — we surface a louder warning but
  /// still let the operator dismiss it.
  final int minSupportedBuild;

  /// ISO-8601 UTC timestamp when the release went out. Optional because
  /// very early manifests did not include it.
  final DateTime? releasedAt;

  /// Returns true when this manifest represents a version newer than
  /// [currentBuild]. Equal builds are considered not-newer on purpose so
  /// re-running the check after installing does not keep nagging.
  bool isNewerThan(int currentBuild) => buildNumber > currentBuild;

  /// True when [currentBuild] is below [minSupportedBuild] — render a
  /// "mandatory update" banner instead of a dismissable one.
  bool isMandatoryFor(int currentBuild) =>
      minSupportedBuild > 0 && currentBuild < minSupportedBuild;

  Map<String, dynamic> toJson() => {
        'versionName': versionName,
        'buildNumber': buildNumber,
        'apkUrl': apkUrl,
        if (sha256 != null) 'sha256': sha256,
        'changelog': changelog,
        'minSupportedBuild': minSupportedBuild,
        if (releasedAt != null) 'releasedAt': releasedAt!.toIso8601String(),
      };

  String toJsonString() => jsonEncode(toJson());

  factory UpdateManifest.fromJson(Map<String, dynamic> json) {
    final versionName = (json['versionName'] as String?)?.trim();
    final build = (json['buildNumber'] as num?)?.toInt();
    final apkUrl = (json['apkUrl'] as String?)?.trim();
    if (versionName == null || versionName.isEmpty) {
      throw const FormatException('UpdateManifest: versionName is required');
    }
    if (build == null) {
      throw const FormatException('UpdateManifest: buildNumber is required');
    }
    if (apkUrl == null || apkUrl.isEmpty) {
      throw const FormatException('UpdateManifest: apkUrl is required');
    }
    final released = json['releasedAt'] as String?;
    return UpdateManifest(
      versionName: versionName,
      buildNumber: build,
      apkUrl: apkUrl,
      sha256: (json['sha256'] as String?)?.trim(),
      changelog: (json['changelog'] as String?) ?? '',
      minSupportedBuild: (json['minSupportedBuild'] as num?)?.toInt() ?? 0,
      releasedAt: released == null ? null : DateTime.tryParse(released),
    );
  }

  factory UpdateManifest.fromJsonString(String s) =>
      UpdateManifest.fromJson(jsonDecode(s) as Map<String, dynamic>);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UpdateManifest &&
          versionName == other.versionName &&
          buildNumber == other.buildNumber &&
          apkUrl == other.apkUrl &&
          sha256 == other.sha256 &&
          changelog == other.changelog &&
          minSupportedBuild == other.minSupportedBuild &&
          releasedAt == other.releasedAt;

  @override
  int get hashCode => Object.hash(versionName, buildNumber, apkUrl, sha256,
      changelog, minSupportedBuild, releasedAt);
}
