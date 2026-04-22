/// Unit tests for [UpdateManifest].
///
/// The manifest is the single contract between the release server and
/// every installed POS, so we pin:
///   * JSON round-trip (future schema bumps must not silently drop a field),
///   * parse-time validation (reject payloads missing required fields),
///   * build-comparison predicates used by the Settings UI.
///
/// Run with:
///   flutter test test/features/updates/update_manifest_test.dart
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/features/updates/domain/entities/update_manifest.dart';

void main() {
  group('UpdateManifest.fromJson', () {
    test('parses a fully-populated manifest', () {
      final manifest = UpdateManifest.fromJson({
        'versionName': '1.4.0',
        'buildNumber': 140,
        'apkUrl': 'https://dl.example.com/pos.apk',
        'sha256': 'deadbeef',
        'changelog': 'Mesai molaları + sadakat editörü',
        'minSupportedBuild': 100,
        'releasedAt': '2026-04-20T10:00:00Z',
      });

      expect(manifest.versionName, '1.4.0');
      expect(manifest.buildNumber, 140);
      expect(manifest.apkUrl, 'https://dl.example.com/pos.apk');
      expect(manifest.sha256, 'deadbeef');
      expect(manifest.changelog, 'Mesai molaları + sadakat editörü');
      expect(manifest.minSupportedBuild, 100);
      expect(manifest.releasedAt, DateTime.utc(2026, 4, 20, 10, 0, 0));
    });

    test('fills defaults for optional fields', () {
      final manifest = UpdateManifest.fromJson({
        'versionName': '1.0.0',
        'buildNumber': 100,
        'apkUrl': 'https://dl.example.com/pos.apk',
      });
      expect(manifest.sha256, isNull);
      expect(manifest.changelog, isEmpty);
      expect(manifest.minSupportedBuild, 0);
      expect(manifest.releasedAt, isNull);
    });

    test('rejects payload missing versionName', () {
      expect(
        () => UpdateManifest.fromJson({
          'buildNumber': 140,
          'apkUrl': 'https://dl.example.com/pos.apk',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects payload missing buildNumber', () {
      expect(
        () => UpdateManifest.fromJson({
          'versionName': '1.4.0',
          'apkUrl': 'https://dl.example.com/pos.apk',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects payload missing apkUrl', () {
      expect(
        () => UpdateManifest.fromJson({
          'versionName': '1.4.0',
          'buildNumber': 140,
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('JSON round-trip', () {
    test('preserves every populated field', () {
      final original = UpdateManifest(
        versionName: '2.0.0',
        buildNumber: 200,
        apkUrl: 'https://dl.example.com/pos.apk',
        sha256: 'feedc0de',
        changelog: 'Büyük yenilik',
        minSupportedBuild: 150,
        releasedAt: DateTime.utc(2026, 5, 1),
      );
      final round = UpdateManifest.fromJsonString(original.toJsonString());
      expect(round, equals(original));
    });

    test('omits optional fields when absent', () {
      const original = UpdateManifest(
        versionName: '1.0.0',
        buildNumber: 100,
        apkUrl: 'https://dl.example.com/pos.apk',
      );
      final encoded = original.toJsonString();
      expect(encoded, isNot(contains('sha256')));
      expect(encoded, isNot(contains('releasedAt')));
    });
  });

  group('isNewerThan', () {
    const manifest = UpdateManifest(
      versionName: '1.4.0',
      buildNumber: 140,
      apkUrl: 'https://dl.example.com/pos.apk',
    );

    test('returns true when current build is lower', () {
      expect(manifest.isNewerThan(130), isTrue);
      expect(manifest.isNewerThan(0), isTrue);
    });

    test('returns false when build matches or is ahead', () {
      expect(manifest.isNewerThan(140), isFalse);
      expect(manifest.isNewerThan(200), isFalse);
    });
  });

  group('isMandatoryFor', () {
    test('false when minSupportedBuild is zero (no floor)', () {
      const manifest = UpdateManifest(
        versionName: '1.4.0',
        buildNumber: 140,
        apkUrl: 'https://dl.example.com/pos.apk',
      );
      expect(manifest.isMandatoryFor(50), isFalse);
    });

    test('true only when current build is below the floor', () {
      const manifest = UpdateManifest(
        versionName: '1.4.0',
        buildNumber: 140,
        apkUrl: 'https://dl.example.com/pos.apk',
        minSupportedBuild: 120,
      );
      expect(manifest.isMandatoryFor(100), isTrue);
      expect(manifest.isMandatoryFor(120), isFalse);
      expect(manifest.isMandatoryFor(130), isFalse);
    });
  });
}
