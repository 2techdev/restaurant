/// Unit tests for [UpdateChannelSettings].
///
/// The settings blob is persisted through [SettingsRepository.saveUpdateChannelSettings],
/// so the JSON contract must stay stable as new fields arrive.
///
/// Run with:
///   flutter test test/features/updates/update_channel_settings_test.dart
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/features/settings/domain/entities/update_channel_settings.dart';

void main() {
  group('UpdateChannelSettings', () {
    test('defaults match "no URL, stable, manual" posture', () {
      const s = UpdateChannelSettings();
      expect(s.manifestUrl, isEmpty);
      expect(s.channel, UpdateChannel.stable);
      expect(s.autoCheck, isFalse);
      expect(s.lastCheckEpochMs, isNull);
      expect(s.lastSeenBuild, isNull);
    });

    test('JSON round-trip keeps every field', () {
      final original = const UpdateChannelSettings(
        manifestUrl: 'https://dl.example.com/manifest.json',
        channel: UpdateChannel.beta,
        autoCheck: true,
        lastCheckEpochMs: 1714000000000,
        lastSeenBuild: 141,
      );
      final round =
          UpdateChannelSettings.fromJsonString(original.toJsonString());
      expect(round, equals(original));
    });

    test('fromJson tolerates a blob written by an older build', () {
      final partial = UpdateChannelSettings.fromJson({
        'manifestUrl': 'https://dl.example.com/manifest.json',
      });
      expect(partial.manifestUrl, 'https://dl.example.com/manifest.json');
      expect(partial.channel, UpdateChannel.stable); // default
      expect(partial.autoCheck, isFalse); // default
    });

    test('copyWith clear flags erase lastCheck / lastSeen', () {
      const s = UpdateChannelSettings(
        lastCheckEpochMs: 1,
        lastSeenBuild: 100,
      );
      final cleared = s.copyWith(clearLastCheck: true, clearLastSeen: true);
      expect(cleared.lastCheckEpochMs, isNull);
      expect(cleared.lastSeenBuild, isNull);
    });
  });
}
