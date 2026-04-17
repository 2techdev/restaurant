import 'package:gastrocore_models/gastrocore_models.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 4, 17);

  group('RestaurantSettings.defaults', () {
    test('matches the baseline 3-gang contract', () {
      const s = RestaurantSettings.defaults;
      expect(s.gangsEnabled, isTrue);
      expect(s.maxGangs, 3);
      expect(s.gangLabels, ['Gang 1', 'Gang 2', 'Gang 3']);
      expect(s.serviceChargeEnabled, isFalse);
      expect(s.serviceChargePercent, 0.0);
    });
  });

  group('RestaurantSettings.normalized', () {
    test('clamps maxGangs to 1..5', () {
      final low = const RestaurantSettings(
        gangsEnabled: true,
        maxGangs: 0,
        gangLabels: [],
        serviceChargeEnabled: false,
        serviceChargePercent: 0.0,
      ).normalized();
      expect(low.maxGangs, RestaurantSettingsLimits.minGangs);
      expect(low.gangLabels, ['Gang 1']);

      final high = const RestaurantSettings(
        gangsEnabled: true,
        maxGangs: 9,
        gangLabels: ['a', 'b'],
        serviceChargeEnabled: false,
        serviceChargePercent: 0.0,
      ).normalized();
      expect(high.maxGangs, RestaurantSettingsLimits.maxGangs);
      expect(high.gangLabels.length, 5);
      expect(high.gangLabels.first, 'a');
      expect(high.gangLabels.last, 'Gang 5'); // padded
    });

    test('pads missing labels and trims extras', () {
      final padded = const RestaurantSettings(
        gangsEnabled: true,
        maxGangs: 4,
        gangLabels: ['Starter'],
        serviceChargeEnabled: false,
        serviceChargePercent: 0.0,
      ).normalized();
      expect(padded.gangLabels, ['Starter', 'Gang 2', 'Gang 3', 'Gang 4']);

      final trimmed = const RestaurantSettings(
        gangsEnabled: true,
        maxGangs: 2,
        gangLabels: ['A', 'B', 'C', 'D'],
        serviceChargeEnabled: false,
        serviceChargePercent: 0.0,
      ).normalized();
      expect(trimmed.gangLabels, ['A', 'B']);
    });

    test('blank labels are replaced with Gang N placeholders', () {
      final fixed = const RestaurantSettings(
        gangsEnabled: true,
        maxGangs: 3,
        gangLabels: ['', '  ', 'Dessert'],
        serviceChargeEnabled: false,
        serviceChargePercent: 0.0,
      ).normalized();
      expect(fixed.gangLabels, ['Gang 1', 'Gang 2', 'Dessert']);
    });
  });

  group('RestaurantSettings JSON round-trip', () {
    test('direct JSON', () {
      const original = RestaurantSettings(
        gangsEnabled: true,
        maxGangs: 3,
        gangLabels: ['Entrée', 'Plat', 'Dessert'],
        serviceChargeEnabled: true,
        serviceChargePercent: 10.0,
      );
      final revived = RestaurantSettings.fromJson(original.toJson());
      expect(revived, original);
    });

    test('via SettingsEntity (values bag)', () {
      const source = RestaurantSettings(
        gangsEnabled: false,
        maxGangs: 2,
        gangLabels: ['First', 'Second'],
        serviceChargeEnabled: true,
        serviceChargePercent: 12.5,
      );
      final entity = SettingsEntity(
        id: 'set-1',
        tenantId: 't1',
        values: source.toSettingsMap(),
        updatedAt: now,
      );
      final revived = RestaurantSettings.fromSettings(entity);
      expect(revived, source);
    });

    test('JSONB-as-string labels (backend path) decode correctly', () {
      final entity = SettingsEntity(
        id: 'set-1',
        tenantId: 't1',
        values: {
          SettingsKeys.gangsEnabled:
              const SettingValue(type: SettingType.bool, raw: true),
          SettingsKeys.gangsMax:
              const SettingValue(type: SettingType.int, raw: 3),
          SettingsKeys.gangsLabels: const SettingValue(
            type: SettingType.json,
            raw: '["Apéro","Main","Dessert"]',
          ),
        },
        updatedAt: now,
      );
      final s = RestaurantSettings.fromSettings(entity);
      expect(s.gangLabels, ['Apéro', 'Main', 'Dessert']);
    });

    test('missing keys fall back to defaults', () {
      final entity = SettingsEntity(
        id: 'set-1',
        tenantId: 't1',
        values: const {},
        updatedAt: now,
      );
      final s = RestaurantSettings.fromSettings(entity);
      expect(s, RestaurantSettings.defaults);
    });
  });

  group('GangPolicy', () {
    test('enabled / count reflect settings', () {
      expect(GangPolicy.enabled(RestaurantSettings.defaults), isTrue);
      expect(GangPolicy.count(RestaurantSettings.defaults), 3);

      const off = RestaurantSettings(
        gangsEnabled: false,
        maxGangs: 3,
        gangLabels: ['Gang 1', 'Gang 2', 'Gang 3'],
        serviceChargeEnabled: false,
        serviceChargePercent: 0.0,
      );
      expect(GangPolicy.enabled(off), isFalse);
      expect(GangPolicy.labels(off), isEmpty);
    });

    test('labelFor / labelForPosition resolve custom labels', () {
      const s = RestaurantSettings(
        gangsEnabled: true,
        maxGangs: 3,
        gangLabels: ['Entrée', 'Plat', 'Dessert'],
        serviceChargeEnabled: false,
        serviceChargePercent: 0.0,
      );
      expect(GangPolicy.labelFor(s, 0), 'Entrée');
      expect(GangPolicy.labelForPosition(s, 2), 'Plat');
      expect(GangPolicy.labelForGang(s, Gang.third), 'Dessert');
    });

    test('out-of-range index falls back to Gang N', () {
      const s = RestaurantSettings.defaults;
      expect(GangPolicy.labelFor(s, 7), 'Gang 8');
      expect(GangPolicy.labelFor(s, -1), 'Gang 0');
    });
  });
}
