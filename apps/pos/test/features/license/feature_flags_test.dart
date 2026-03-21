import 'package:flutter_test/flutter_test.dart';
import 'package:gastrocore_pos/core/feature_flags.dart';
import 'package:gastrocore_pos/features/license/license_models.dart';

void main() {
  group('FeatureFlags.implicitFlags', () {
    test('free edition has no implicit flags', () {
      expect(FeatureFlags.implicitFlags(LicenseEdition.free), isEmpty);
    });

    test('starter includes analytics, printing, reports', () {
      final flags = FeatureFlags.implicitFlags(LicenseEdition.starter);
      expect(flags, containsAll([
        FeatureFlag.analytics,
        FeatureFlag.printing,
        FeatureFlag.reports,
      ]));
    });

    test('starter does NOT include kds or cloudSync', () {
      final flags = FeatureFlags.implicitFlags(LicenseEdition.starter);
      expect(flags, isNot(contains(FeatureFlag.kds)));
      expect(flags, isNot(contains(FeatureFlag.cloudSync)));
    });

    test('pro includes all starter flags plus kds, inventory, crm', () {
      final flags = FeatureFlags.implicitFlags(LicenseEdition.pro);
      expect(flags, containsAll([
        FeatureFlag.analytics,
        FeatureFlag.printing,
        FeatureFlag.reports,
        FeatureFlag.kds,
        FeatureFlag.inventory,
        FeatureFlag.crm,
      ]));
    });

    test('pro does NOT include cloudSync or multiDevice', () {
      final flags = FeatureFlags.implicitFlags(LicenseEdition.pro);
      expect(flags, isNot(contains(FeatureFlag.cloudSync)));
      expect(flags, isNot(contains(FeatureFlag.multiDevice)));
    });

    test('enterprise includes ALL flags', () {
      final flags = FeatureFlags.implicitFlags(LicenseEdition.enterprise);
      for (final flag in FeatureFlag.values) {
        expect(flags, contains(flag),
            reason: '${flag.name} should be in enterprise flags');
      }
    });
  });

  group('FeatureFlags.effectiveFlags', () {
    test('merges implicit and explicit flags', () {
      final flags = FeatureFlags.effectiveFlags(
        LicenseEdition.free,
        [FeatureFlag.kds], // explicit override
      );
      expect(flags, contains(FeatureFlag.kds));
    });

    test('explicit cannot remove implicit flags', () {
      // Explicit list only ADDS — it cannot suppress edition-level flags.
      final flags = FeatureFlags.effectiveFlags(
        LicenseEdition.pro,
        [FeatureFlag.cloudSync], // extra override
      );
      // Pro implicit flags should still be present.
      expect(flags, contains(FeatureFlag.kds));
      // The explicit override was added.
      expect(flags, contains(FeatureFlag.cloudSync));
    });

    test('empty overrides equals implicit flags', () {
      final implicit = FeatureFlags.implicitFlags(LicenseEdition.starter);
      final effective =
          FeatureFlags.effectiveFlags(LicenseEdition.starter, []);
      expect(effective, equals(implicit));
    });
  });

  group('FeatureFlags.defaultsByEdition', () {
    test('free has empty defaults', () {
      expect(FeatureFlags.defaultsByEdition[LicenseEdition.free], isEmpty);
    });

    test('enterprise defaults contain all flags', () {
      final defaults =
          FeatureFlags.defaultsByEdition[LicenseEdition.enterprise]!;
      for (final flag in FeatureFlag.values) {
        expect(defaults, contains(flag),
            reason: '${flag.name} should be in enterprise defaults');
      }
    });
  });
}
