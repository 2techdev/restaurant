/// Unit tests for [LoyaltySettings] + [resolveLoyaltyTier].
///
/// The entity backs a Back-Office editor, so we pin:
///   * JSON round-trip (future migrations must not silently drop a field),
///   * default values (match the legacy hard-coded constants),
///   * validation (Gold > Silber, all knobs positive),
///   * tier resolution on boundary values.
///
/// Run with:
///   flutter test test/features/settings/domain/loyalty_settings_test.dart
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/features/settings/domain/entities/loyalty_settings.dart';

void main() {
  group('LoyaltySettings', () {
    test('defaults match legacy hard-coded Swiss rules', () {
      const s = LoyaltySettings();
      expect(s.isActive, isTrue);
      expect(s.pointsPerChfSpent, 1);
      expect(s.centsPerPoint, 1);
      expect(s.silverThresholdCents, 20000); // CHF 200
      expect(s.goldThresholdCents, 50000); // CHF 500
    });

    test('isValid accepts default and rejects reversed tier thresholds', () {
      const good = LoyaltySettings();
      expect(good.isValid, isTrue);

      final bad = good.copyWith(
        silverThresholdCents: 60000,
        goldThresholdCents: 50000, // gold < silver
      );
      expect(bad.isValid, isFalse);
    });

    test('isValid rejects non-positive economic knobs', () {
      expect(
        const LoyaltySettings(pointsPerChfSpent: 0).isValid,
        isFalse,
      );
      expect(
        const LoyaltySettings(centsPerPoint: 0).isValid,
        isFalse,
      );
    });

    test('JSON round-trip preserves every field', () {
      const original = LoyaltySettings(
        isActive: false,
        pointsPerChfSpent: 3,
        centsPerPoint: 2,
        silverThresholdCents: 30000,
        goldThresholdCents: 80000,
      );
      final encoded = original.toJsonString();
      final decoded = LoyaltySettings.fromJsonString(encoded);
      expect(decoded, equals(original));
    });

    test('fromJson tolerates a blob written by an older build', () {
      // Earlier builds never persisted the isActive field; missing keys
      // must fall back to the factory defaults.
      final partial = LoyaltySettings.fromJson({
        'pointsPerChfSpent': 2,
      });
      expect(partial.pointsPerChfSpent, 2);
      expect(partial.isActive, isTrue); // default
      expect(partial.silverThresholdCents, 20000);
    });
  });

  group('resolveLoyaltyTier', () {
    const s = LoyaltySettings(); // silver: CHF 200, gold: CHF 500

    test('bronze below silver threshold', () {
      expect(resolveLoyaltyTier(0, s), LoyaltyTier.bronze);
      expect(resolveLoyaltyTier(19999, s), LoyaltyTier.bronze);
    });

    test('silver at exactly silver threshold', () {
      expect(resolveLoyaltyTier(20000, s), LoyaltyTier.silver);
    });

    test('silver below gold threshold', () {
      expect(resolveLoyaltyTier(49999, s), LoyaltyTier.silver);
    });

    test('gold at exactly gold threshold', () {
      expect(resolveLoyaltyTier(50000, s), LoyaltyTier.gold);
    });

    test('gold well above threshold', () {
      expect(resolveLoyaltyTier(1000000, s), LoyaltyTier.gold);
    });

    test('honours operator-tuned thresholds', () {
      const tuned = LoyaltySettings(
        silverThresholdCents: 10000, // CHF 100
        goldThresholdCents: 25000, // CHF 250
      );
      expect(resolveLoyaltyTier(9999, tuned), LoyaltyTier.bronze);
      expect(resolveLoyaltyTier(10000, tuned), LoyaltyTier.silver);
      expect(resolveLoyaltyTier(24999, tuned), LoyaltyTier.silver);
      expect(resolveLoyaltyTier(25000, tuned), LoyaltyTier.gold);
    });
  });
}
