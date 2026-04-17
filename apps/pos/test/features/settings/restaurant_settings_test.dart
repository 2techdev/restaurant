/// Unit tests for [RestaurantSettings] — focused on the new service-charge
/// fields and their JSON round-trip.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/features/settings/domain/entities/restaurant_settings.dart';

void main() {
  group('RestaurantSettings service charge', () {
    test('defaults to disabled with 10% fallback', () {
      const s = RestaurantSettings();
      expect(s.serviceChargeEnabled, isFalse);
      expect(s.serviceChargePercent, 10.0);
    });

    test('round-trips serviceChargeEnabled + serviceChargePercent via JSON',
        () {
      const original = RestaurantSettings(
        name: 'Zum Löwen',
        serviceChargeEnabled: true,
        serviceChargePercent: 12.5,
      );
      final decoded =
          RestaurantSettings.fromJsonString(original.toJsonString());
      expect(decoded.serviceChargeEnabled, isTrue);
      expect(decoded.serviceChargePercent, 12.5);
      expect(decoded, equals(original));
    });

    test(
        'fromJson falls back to defaults when service charge fields are missing',
        () {
      // Simulates a settings blob persisted before the feature landed.
      final legacy = {
        'name': 'Legacy',
        'address': 'Old Street 1',
        'phone': '',
        'mwstNr': '',
        'logoPath': null,
      };
      final decoded = RestaurantSettings.fromJson(legacy);
      expect(decoded.serviceChargeEnabled, isFalse);
      expect(decoded.serviceChargePercent, 10.0);
    });

    test('copyWith toggles serviceChargeEnabled without touching percent',
        () {
      const s = RestaurantSettings(serviceChargePercent: 7.5);
      final enabled = s.copyWith(serviceChargeEnabled: true);
      expect(enabled.serviceChargeEnabled, isTrue);
      expect(enabled.serviceChargePercent, 7.5);
    });
  });
}
