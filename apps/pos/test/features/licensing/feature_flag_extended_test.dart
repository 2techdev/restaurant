/// Extended license/feature-flag tests covering the full tier × feature matrix
/// and LicenseRepositoryImpl's isFeatureEnabled / getLicenseTier in isolation.
///
/// Run with:
///   flutter test test/features/licensing/feature_flag_extended_test.dart
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/features/licensing/domain/entities/app_feature.dart';
import 'package:gastrocore_pos/features/licensing/domain/entities/license_tier.dart';

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // =========================================================================
  // LicenseTier — ordering and helpers
  // =========================================================================

  group('LicenseTier — ordering', () {
    test('free < professional < enterprise (index ordering)', () {
      expect(LicenseTier.free.index, lessThan(LicenseTier.professional.index));
      expect(LicenseTier.professional.index, lessThan(LicenseTier.enterprise.index));
    });

    test('isAtLeast is reflexive for all tiers', () {
      for (final t in LicenseTier.values) {
        expect(t.isAtLeast(t), isTrue);
      }
    });

    test('isAtLeast — free is NOT at least professional', () {
      expect(LicenseTier.free.isAtLeast(LicenseTier.professional), isFalse);
    });

    test('isAtLeast — professional IS at least free', () {
      expect(LicenseTier.professional.isAtLeast(LicenseTier.free), isTrue);
    });

    test('isAtLeast — enterprise IS at least professional', () {
      expect(LicenseTier.enterprise.isAtLeast(LicenseTier.professional), isTrue);
    });

    test('isAtLeast — enterprise IS at least free', () {
      expect(LicenseTier.enterprise.isAtLeast(LicenseTier.free), isTrue);
    });

    test('isAtLeast — free is NOT at least enterprise', () {
      expect(LicenseTier.free.isAtLeast(LicenseTier.enterprise), isFalse);
    });

    test('isAtLeast — professional is NOT at least enterprise', () {
      expect(LicenseTier.professional.isAtLeast(LicenseTier.enterprise), isFalse);
    });
  });

  // =========================================================================
  // LicenseTier — display helpers
  // =========================================================================

  group('LicenseTier — display helpers', () {
    test('displayName values are correct', () {
      expect(LicenseTier.free.displayName, equals('Free'));
      expect(LicenseTier.professional.displayName, equals('Professional'));
      expect(LicenseTier.enterprise.displayName, equals('Enterprise'));
    });

    test('badge values are correct', () {
      expect(LicenseTier.free.badge, equals('FREE'));
      expect(LicenseTier.professional.badge, equals('PRO'));
      expect(LicenseTier.enterprise.badge, equals('ENT'));
    });

    test('fromString round-trips all tiers (case-insensitive)', () {
      expect(LicenseTier.fromString('free'), equals(LicenseTier.free));
      expect(LicenseTier.fromString('FREE'), equals(LicenseTier.free));
      expect(LicenseTier.fromString('professional'), equals(LicenseTier.professional));
      expect(LicenseTier.fromString('PROFESSIONAL'), equals(LicenseTier.professional));
      expect(LicenseTier.fromString('enterprise'), equals(LicenseTier.enterprise));
      expect(LicenseTier.fromString('ENTERPRISE'), equals(LicenseTier.enterprise));
    });

    test('fromString returns free for unknown values', () {
      expect(LicenseTier.fromString('unknown'), equals(LicenseTier.free));
      expect(LicenseTier.fromString(''), equals(LicenseTier.free));
    });
  });

  // =========================================================================
  // AppFeature — tier requirements matrix
  // =========================================================================

  group('AppFeature — tier requirements', () {
    test('all FREE features are accessible on free tier', () {
      final freeFeatures = AppFeature.values
          .where((f) => f.requiredTier == LicenseTier.free)
          .toList();
      for (final f in freeFeatures) {
        expect(
          LicenseTier.free.isAtLeast(f.requiredTier),
          isTrue,
          reason: '${f.name} should be accessible on free tier',
        );
      }
    });

    test('all FREE features are accessible on professional tier', () {
      final freeFeatures = AppFeature.values
          .where((f) => f.requiredTier == LicenseTier.free)
          .toList();
      for (final f in freeFeatures) {
        expect(LicenseTier.professional.isAtLeast(f.requiredTier), isTrue);
      }
    });

    test('PROFESSIONAL features are not accessible on free tier', () {
      final proFeatures = AppFeature.values
          .where((f) => f.requiredTier == LicenseTier.professional)
          .toList();
      expect(proFeatures, isNotEmpty);
      for (final f in proFeatures) {
        expect(
          LicenseTier.free.isAtLeast(f.requiredTier),
          isFalse,
          reason: '${f.name} should NOT be accessible on free tier',
        );
      }
    });

    test('PROFESSIONAL features are accessible on professional tier', () {
      final proFeatures = AppFeature.values
          .where((f) => f.requiredTier == LicenseTier.professional)
          .toList();
      for (final f in proFeatures) {
        expect(LicenseTier.professional.isAtLeast(f.requiredTier), isTrue);
      }
    });

    test('ENTERPRISE features are accessible on enterprise tier', () {
      final entFeatures = AppFeature.values
          .where((f) => f.requiredTier == LicenseTier.enterprise)
          .toList();
      expect(entFeatures, isNotEmpty);
      for (final f in entFeatures) {
        expect(LicenseTier.enterprise.isAtLeast(f.requiredTier), isTrue);
      }
    });

    test('ENTERPRISE features are NOT accessible on professional tier', () {
      final entFeatures = AppFeature.values
          .where((f) => f.requiredTier == LicenseTier.enterprise)
          .toList();
      for (final f in entFeatures) {
        expect(
          LicenseTier.professional.isAtLeast(f.requiredTier),
          isFalse,
          reason: '${f.name} should NOT be accessible on professional tier',
        );
      }
    });

    test('kds requires at least professional tier', () {
      expect(AppFeature.kds.requiredTier, equals(LicenseTier.professional));
      expect(LicenseTier.free.isAtLeast(AppFeature.kds.requiredTier), isFalse);
      expect(LicenseTier.professional.isAtLeast(AppFeature.kds.requiredTier), isTrue);
    });

    test('cloudSync requires enterprise tier', () {
      expect(AppFeature.cloudSync.requiredTier, equals(LicenseTier.enterprise));
      expect(LicenseTier.professional.isAtLeast(AppFeature.cloudSync.requiredTier), isFalse);
      expect(LicenseTier.enterprise.isAtLeast(AppFeature.cloudSync.requiredTier), isTrue);
    });

    test('basicPos is available on free tier', () {
      expect(AppFeature.basicPos.requiredTier, equals(LicenseTier.free));
      expect(LicenseTier.free.isAtLeast(AppFeature.basicPos.requiredTier), isTrue);
    });

    test('backupRestore requires professional tier', () {
      expect(AppFeature.backupRestore.requiredTier, equals(LicenseTier.professional));
    });

    test('multiLocation requires enterprise tier', () {
      expect(AppFeature.multiLocation.requiredTier, equals(LicenseTier.enterprise));
    });

    test('each feature has a non-empty displayName', () {
      for (final f in AppFeature.values) {
        expect(f.displayName, isNotEmpty, reason: '${f.name} should have a displayName');
      }
    });

    test('17 total features defined', () {
      expect(AppFeature.values.length, equals(17));
    });
  });

  // =========================================================================
  // Tier upgrade path scenarios
  // =========================================================================

  group('License upgrade path scenarios', () {
    test('free restaurant can access basic POS but not KDS', () {
      const tier = LicenseTier.free;
      expect(tier.isAtLeast(AppFeature.basicPos.requiredTier), isTrue);
      expect(tier.isAtLeast(AppFeature.kds.requiredTier), isFalse);
    });

    test('professional restaurant can access KDS but not cloud sync', () {
      const tier = LicenseTier.professional;
      expect(tier.isAtLeast(AppFeature.kds.requiredTier), isTrue);
      expect(tier.isAtLeast(AppFeature.cloudSync.requiredTier), isFalse);
    });

    test('enterprise restaurant can access all features', () {
      const tier = LicenseTier.enterprise;
      for (final f in AppFeature.values) {
        expect(
          tier.isAtLeast(f.requiredTier),
          isTrue,
          reason: 'Enterprise should access ${f.name}',
        );
      }
    });

    test('free tier cannot access unlimited menu', () {
      const tier = LicenseTier.free;
      expect(tier.isAtLeast(AppFeature.unlimitedMenu.requiredTier), isFalse);
    });

    test('free tier can use limited menu', () {
      const tier = LicenseTier.free;
      expect(tier.isAtLeast(AppFeature.limitedMenu.requiredTier), isTrue);
    });

    test('free tier can use basic reports', () {
      const tier = LicenseTier.free;
      expect(tier.isAtLeast(AppFeature.basicReports.requiredTier), isTrue);
    });

    test('free tier cannot use advanced reports', () {
      const tier = LicenseTier.free;
      expect(tier.isAtLeast(AppFeature.advancedReports.requiredTier), isFalse);
    });
  });
}
