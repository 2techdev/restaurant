import 'package:flutter_test/flutter_test.dart';
import 'package:gastrocore_pos/features/license/license_models.dart';

void main() {
  // ---------------------------------------------------------------------------
  // LicenseEdition
  // ---------------------------------------------------------------------------

  group('LicenseEdition.fromString', () {
    test('parses "free"', () {
      expect(LicenseEdition.fromString('free'), LicenseEdition.free);
    });

    test('parses "starter"', () {
      expect(LicenseEdition.fromString('starter'), LicenseEdition.starter);
    });

    test('parses "pro"', () {
      expect(LicenseEdition.fromString('pro'), LicenseEdition.pro);
    });

    test('parses legacy "professional"', () {
      expect(LicenseEdition.fromString('professional'), LicenseEdition.pro);
    });

    test('parses "enterprise"', () {
      expect(
          LicenseEdition.fromString('enterprise'), LicenseEdition.enterprise);
    });

    test('unknown value defaults to free', () {
      expect(LicenseEdition.fromString('unknown'), LicenseEdition.free);
      expect(LicenseEdition.fromString(''), LicenseEdition.free);
    });

    test('is case-insensitive', () {
      expect(LicenseEdition.fromString('PRO'), LicenseEdition.pro);
      expect(LicenseEdition.fromString('ENTERPRISE'), LicenseEdition.enterprise);
    });
  });

  group('LicenseEdition.isAtLeast', () {
    test('free is at least free', () {
      expect(LicenseEdition.free.isAtLeast(LicenseEdition.free), isTrue);
    });

    test('pro is at least starter', () {
      expect(LicenseEdition.pro.isAtLeast(LicenseEdition.starter), isTrue);
    });

    test('enterprise is at least pro', () {
      expect(
          LicenseEdition.enterprise.isAtLeast(LicenseEdition.pro), isTrue);
    });

    test('free is NOT at least starter', () {
      expect(LicenseEdition.free.isAtLeast(LicenseEdition.starter), isFalse);
    });

    test('starter is NOT at least pro', () {
      expect(LicenseEdition.starter.isAtLeast(LicenseEdition.pro), isFalse);
    });

    test('pro is NOT at least enterprise', () {
      expect(LicenseEdition.pro.isAtLeast(LicenseEdition.enterprise), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // FeatureFlag.requiredEdition
  // ---------------------------------------------------------------------------

  group('FeatureFlag.requiredEdition', () {
    test('analytics requires starter', () {
      expect(FeatureFlag.analytics.requiredEdition, LicenseEdition.starter);
    });

    test('printing requires starter', () {
      expect(FeatureFlag.printing.requiredEdition, LicenseEdition.starter);
    });

    test('kds requires pro', () {
      expect(FeatureFlag.kds.requiredEdition, LicenseEdition.pro);
    });

    test('inventory requires pro', () {
      expect(FeatureFlag.inventory.requiredEdition, LicenseEdition.pro);
    });

    test('crm requires pro', () {
      expect(FeatureFlag.crm.requiredEdition, LicenseEdition.pro);
    });

    test('cloudSync requires enterprise', () {
      expect(FeatureFlag.cloudSync.requiredEdition, LicenseEdition.enterprise);
    });

    test('multiDevice requires enterprise', () {
      expect(
          FeatureFlag.multiDevice.requiredEdition, LicenseEdition.enterprise);
    });
  });

  // ---------------------------------------------------------------------------
  // LicenseToken
  // ---------------------------------------------------------------------------

  group('LicenseToken.hasFlag', () {
    LicenseToken makeToken({
      required LicenseEdition edition,
      List<FeatureFlag> features = const [],
      bool expired = false,
    }) {
      final now = DateTime.now().toUtc();
      return LicenseToken(
        edition: edition,
        features: features,
        expiresAt: expired
            ? now.subtract(const Duration(days: 30))
            : now.add(const Duration(days: 365)),
        deviceLimit: 1,
        customerName: 'Test',
        issuedAt: now.subtract(const Duration(days: 1)),
      );
    }

    test('free edition has no flags', () {
      final token = makeToken(edition: LicenseEdition.free);
      for (final flag in FeatureFlag.values) {
        expect(token.hasFlag(flag), isFalse,
            reason: '${flag.name} should be locked on Free');
      }
    });

    test('starter enables analytics, printing, reports', () {
      final token = makeToken(edition: LicenseEdition.starter);
      expect(token.hasFlag(FeatureFlag.analytics), isTrue);
      expect(token.hasFlag(FeatureFlag.printing), isTrue);
      expect(token.hasFlag(FeatureFlag.reports), isTrue);
    });

    test('starter does NOT enable kds, inventory, crm', () {
      final token = makeToken(edition: LicenseEdition.starter);
      expect(token.hasFlag(FeatureFlag.kds), isFalse);
      expect(token.hasFlag(FeatureFlag.inventory), isFalse);
      expect(token.hasFlag(FeatureFlag.crm), isFalse);
    });

    test('pro enables kds, inventory, crm', () {
      final token = makeToken(edition: LicenseEdition.pro);
      expect(token.hasFlag(FeatureFlag.kds), isTrue);
      expect(token.hasFlag(FeatureFlag.inventory), isTrue);
      expect(token.hasFlag(FeatureFlag.crm), isTrue);
    });

    test('pro does NOT enable cloudSync or multiDevice', () {
      final token = makeToken(edition: LicenseEdition.pro);
      expect(token.hasFlag(FeatureFlag.cloudSync), isFalse);
      expect(token.hasFlag(FeatureFlag.multiDevice), isFalse);
    });

    test('enterprise enables all flags', () {
      final token = makeToken(edition: LicenseEdition.enterprise);
      for (final flag in FeatureFlag.values) {
        expect(token.hasFlag(flag), isTrue,
            reason: '${flag.name} should be enabled on Enterprise');
      }
    });

    test('explicit feature override grants flag below edition level', () {
      // A free-tier token with an explicit kds grant.
      final token = makeToken(
        edition: LicenseEdition.free,
        features: [FeatureFlag.kds],
      );
      expect(token.hasFlag(FeatureFlag.kds), isTrue);
    });

    test('expired token (past grace) returns false for all flags', () {
      final token = makeToken(
          edition: LicenseEdition.enterprise, expired: true);
      for (final flag in FeatureFlag.values) {
        expect(token.hasFlag(flag), isFalse,
            reason: '${flag.name} should be locked when expired');
      }
    });
  });

  group('LicenseToken.effectiveEdition', () {
    test('active token returns nominal edition', () {
      final token = LicenseToken(
        edition: LicenseEdition.pro,
        features: const [],
        expiresAt: DateTime.now().toUtc().add(const Duration(days: 30)),
        deviceLimit: 1,
        customerName: '',
        issuedAt: DateTime.now().toUtc(),
      );
      expect(token.effectiveEdition, LicenseEdition.pro);
    });

    test('hard-expired token returns free', () {
      final token = LicenseToken(
        edition: LicenseEdition.enterprise,
        features: const [],
        // Expired 10 days ago — past the 7-day grace window.
        expiresAt:
            DateTime.now().toUtc().subtract(const Duration(days: 10)),
        deviceLimit: 1,
        customerName: '',
        issuedAt: DateTime.now().toUtc().subtract(const Duration(days: 400)),
      );
      expect(token.effectiveEdition, LicenseEdition.free);
    });

    test('token in grace period keeps nominal edition', () {
      final token = LicenseToken(
        edition: LicenseEdition.pro,
        features: const [],
        // Expired 3 days ago — within 7-day grace window.
        expiresAt:
            DateTime.now().toUtc().subtract(const Duration(days: 3)),
        deviceLimit: 1,
        customerName: '',
        issuedAt: DateTime.now().toUtc().subtract(const Duration(days: 370)),
      );
      expect(token.effectiveEdition, LicenseEdition.pro);
    });
  });
}
