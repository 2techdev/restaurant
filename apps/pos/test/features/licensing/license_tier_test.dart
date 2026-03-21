/// Unit tests for license tier logic, grace period, effective tier,
/// FeatureFlagService gating, and AppFeature tier assignments.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/features/licensing/domain/entities/app_feature.dart';
import 'package:gastrocore_pos/features/licensing/domain/entities/license_entity.dart';
import 'package:gastrocore_pos/features/licensing/domain/entities/license_tier.dart';
import 'package:gastrocore_pos/features/licensing/presentation/providers/license_provider.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

LicenseEntity _makeLicense({
  required LicenseTier tier,
  required DateTime expiresAt,
}) {
  return LicenseEntity(
    id: 'test-id',
    businessId: 'biz-test',
    tier: tier,
    issuedAt: DateTime.utc(2026, 1, 1),
    expiresAt: expiresAt,
    tokenRaw: 'mock-token',
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  group('LicenseTier', () {
    test('isAtLeast returns true for same tier', () {
      expect(LicenseTier.free.isAtLeast(LicenseTier.free), isTrue);
      expect(
          LicenseTier.professional.isAtLeast(LicenseTier.professional),
          isTrue);
      expect(LicenseTier.enterprise.isAtLeast(LicenseTier.enterprise),
          isTrue);
    });

    test('isAtLeast returns true for higher tiers', () {
      expect(
          LicenseTier.professional.isAtLeast(LicenseTier.free), isTrue);
      expect(
          LicenseTier.enterprise.isAtLeast(LicenseTier.professional),
          isTrue);
      expect(LicenseTier.enterprise.isAtLeast(LicenseTier.free), isTrue);
    });

    test('isAtLeast returns false for lower tiers', () {
      expect(
          LicenseTier.free.isAtLeast(LicenseTier.professional), isFalse);
      expect(LicenseTier.free.isAtLeast(LicenseTier.enterprise), isFalse);
      expect(
          LicenseTier.professional.isAtLeast(LicenseTier.enterprise),
          isFalse);
    });

    test('fromString parses known values case-insensitively', () {
      expect(LicenseTier.fromString('professional'),
          LicenseTier.professional);
      expect(LicenseTier.fromString('ENTERPRISE'), LicenseTier.enterprise);
      expect(LicenseTier.fromString('free'), LicenseTier.free);
      expect(
          LicenseTier.fromString('unknown'), LicenseTier.free); // default
    });
  });

  // -------------------------------------------------------------------------
  group('LicenseEntity — expiry and grace period', () {
    test('isExpired is false when license is active', () {
      final license = _makeLicense(
        tier: LicenseTier.professional,
        expiresAt: DateTime.now().toUtc().add(const Duration(days: 30)),
      );
      expect(license.isExpired, isFalse);
      expect(license.isInGracePeriod, isFalse);
      expect(license.effectiveTier, LicenseTier.professional);
    });

    test('effectiveTier equals nominal tier during active period', () {
      final license = _makeLicense(
        tier: LicenseTier.enterprise,
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      );
      expect(license.effectiveTier, LicenseTier.enterprise);
    });

    test('isInGracePeriod is true within 7 days after expiry', () {
      final license = _makeLicense(
        tier: LicenseTier.professional,
        expiresAt: DateTime.now().toUtc().subtract(const Duration(days: 3)),
      );
      expect(license.isExpired, isTrue);
      expect(license.isInGracePeriod, isTrue);
      // Still gets the nominal tier during grace.
      expect(license.effectiveTier, LicenseTier.professional);
    });

    test('effectiveTier downgrades to FREE after grace period ends', () {
      final license = _makeLicense(
        tier: LicenseTier.professional,
        expiresAt: DateTime.now().toUtc().subtract(const Duration(days: 8)),
      );
      expect(license.isExpired, isTrue);
      expect(license.isInGracePeriod, isFalse);
      expect(license.effectiveTier, LicenseTier.free);
    });

    test('daysUntilDowngrade is 0 after grace period', () {
      final license = _makeLicense(
        tier: LicenseTier.professional,
        expiresAt: DateTime.now().toUtc().subtract(const Duration(days: 8)),
      );
      expect(license.daysUntilDowngrade, 0);
    });

    test('daysUntilDowngrade is clamped to 0–7', () {
      final license = _makeLicense(
        tier: LicenseTier.professional,
        expiresAt: DateTime.now().toUtc().subtract(const Duration(days: 2)),
      );
      expect(license.daysUntilDowngrade, inInclusiveRange(0, 7));
    });
  });

  // -------------------------------------------------------------------------
  group('AppFeature tier requirements', () {
    test('basic POS features require FREE tier', () {
      final freeFeatures = AppFeature.values
          .where((f) => f.requiredTier == LicenseTier.free)
          .toList();
      expect(freeFeatures, isNotEmpty);
      expect(freeFeatures, contains(AppFeature.basicPos));
      expect(freeFeatures, contains(AppFeature.basicReports));
    });

    test('KDS requires PROFESSIONAL tier', () {
      expect(AppFeature.kds.requiredTier, LicenseTier.professional);
    });

    test('Backup/Restore requires PROFESSIONAL tier', () {
      expect(
          AppFeature.backupRestore.requiredTier, LicenseTier.professional);
    });

    test('Cloud sync requires ENTERPRISE tier', () {
      expect(AppFeature.cloudSync.requiredTier, LicenseTier.enterprise);
    });

    test('no feature requires a tier below FREE', () {
      for (final feature in AppFeature.values) {
        expect(feature.requiredTier.index, greaterThanOrEqualTo(0));
      }
    });
  });

  // -------------------------------------------------------------------------
  group('FeatureFlagService', () {
    test('FREE tier enables only FREE features', () {
      final service = FeatureFlagService(LicenseTier.free);

      expect(service.isEnabled(AppFeature.basicPos), isTrue);
      expect(service.isEnabled(AppFeature.kds), isFalse);
      expect(service.isEnabled(AppFeature.cloudSync), isFalse);
    });

    test('PROFESSIONAL tier enables FREE and PRO features', () {
      final service = FeatureFlagService(LicenseTier.professional);

      expect(service.isEnabled(AppFeature.basicPos), isTrue);
      expect(service.isEnabled(AppFeature.kds), isTrue);
      expect(service.isEnabled(AppFeature.advancedReports), isTrue);
      expect(service.isEnabled(AppFeature.backupRestore), isTrue);
      expect(service.isEnabled(AppFeature.cloudSync), isFalse);
      expect(service.isEnabled(AppFeature.apiAccess), isFalse);
    });

    test('ENTERPRISE tier enables all features', () {
      final service = FeatureFlagService(LicenseTier.enterprise);

      for (final feature in AppFeature.values) {
        expect(service.isEnabled(feature), isTrue,
            reason: '${feature.name} should be enabled for enterprise');
      }
    });

    test('enabledFeatures returns correct count for each tier', () {
      final freeCount =
          FeatureFlagService(LicenseTier.free).enabledFeatures.length;
      final proCount =
          FeatureFlagService(LicenseTier.professional).enabledFeatures.length;
      final entCount =
          FeatureFlagService(LicenseTier.enterprise).enabledFeatures.length;

      expect(freeCount, lessThan(proCount));
      expect(proCount, lessThan(entCount));
      expect(entCount, AppFeature.values.length);
    });
  });
}
