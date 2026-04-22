/// Update channel configuration persisted in SharedPreferences.
///
/// Splits "where to look for updates" from the manifest itself so the
/// operator can flip between stable / beta without losing the manifest
/// cache, and so a pilot customer can retarget to a private URL without
/// a code change. Empty [manifestUrl] disables the check.
library;

import 'dart:convert';

enum UpdateChannel {
  stable,
  beta;

  String get label => switch (this) {
        stable => 'Stable',
        beta => 'Beta (pilot)',
      };

  static UpdateChannel fromString(String s) => UpdateChannel.values.firstWhere(
        (c) => c.name == s,
        orElse: () => UpdateChannel.stable,
      );
}

class UpdateChannelSettings {
  const UpdateChannelSettings({
    this.manifestUrl = '',
    this.channel = UpdateChannel.stable,
    this.autoCheck = false,
    this.lastCheckEpochMs,
    this.lastSeenBuild,
  });

  /// Absolute URL of the update manifest JSON. Empty disables the check.
  final String manifestUrl;

  /// Stable / beta selection surfaced in the UI. Currently advisory: the
  /// manifest URL usually encodes the channel already (…/stable/…).
  final UpdateChannel channel;

  /// When true, the Settings screen triggers a check in the background on
  /// each open. Off by default to keep the pilot deterministic.
  final bool autoCheck;

  /// Epoch millis of the last successful check. Used to render "last
  /// checked: 5 min ago" under the button.
  final int? lastCheckEpochMs;

  /// Last manifest build we rendered to the operator. Lets the Settings
  /// screen skip re-rendering the "new version" card after the operator
  /// has already seen and dismissed it.
  final int? lastSeenBuild;

  UpdateChannelSettings copyWith({
    String? manifestUrl,
    UpdateChannel? channel,
    bool? autoCheck,
    int? lastCheckEpochMs,
    int? lastSeenBuild,
    bool clearLastCheck = false,
    bool clearLastSeen = false,
  }) =>
      UpdateChannelSettings(
        manifestUrl: manifestUrl ?? this.manifestUrl,
        channel: channel ?? this.channel,
        autoCheck: autoCheck ?? this.autoCheck,
        lastCheckEpochMs: clearLastCheck
            ? null
            : (lastCheckEpochMs ?? this.lastCheckEpochMs),
        lastSeenBuild:
            clearLastSeen ? null : (lastSeenBuild ?? this.lastSeenBuild),
      );

  Map<String, dynamic> toJson() => {
        'manifestUrl': manifestUrl,
        'channel': channel.name,
        'autoCheck': autoCheck,
        if (lastCheckEpochMs != null) 'lastCheckEpochMs': lastCheckEpochMs,
        if (lastSeenBuild != null) 'lastSeenBuild': lastSeenBuild,
      };

  String toJsonString() => jsonEncode(toJson());

  factory UpdateChannelSettings.fromJson(Map<String, dynamic> json) =>
      UpdateChannelSettings(
        manifestUrl: (json['manifestUrl'] as String?) ?? '',
        channel:
            UpdateChannel.fromString((json['channel'] as String?) ?? 'stable'),
        autoCheck: (json['autoCheck'] as bool?) ?? false,
        lastCheckEpochMs: (json['lastCheckEpochMs'] as num?)?.toInt(),
        lastSeenBuild: (json['lastSeenBuild'] as num?)?.toInt(),
      );

  factory UpdateChannelSettings.fromJsonString(String s) =>
      UpdateChannelSettings.fromJson(jsonDecode(s) as Map<String, dynamic>);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UpdateChannelSettings &&
          manifestUrl == other.manifestUrl &&
          channel == other.channel &&
          autoCheck == other.autoCheck &&
          lastCheckEpochMs == other.lastCheckEpochMs &&
          lastSeenBuild == other.lastSeenBuild;

  @override
  int get hashCode => Object.hash(
      manifestUrl, channel, autoCheck, lastCheckEpochMs, lastSeenBuild);
}
