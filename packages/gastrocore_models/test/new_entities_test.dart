import 'package:gastrocore_models/gastrocore_models.dart';
import 'package:test/test.dart';

/// Round-trip helper: [original.toJson] → [fromJson] must preserve equality.
void _rt<T>(T original, T Function(Map<String, dynamic>) fromJson) {
  final json = (original as dynamic).toJson() as Map<String, dynamic>;
  final revived = fromJson(json);
  expect(revived, original, reason: 'JSON round-trip lost equality');
}

void main() {
  final now = DateTime.utc(2026, 4, 17, 10, 0, 0);

  group('RoleEntity', () {
    test('JSON round-trip preserves permissions set', () {
      final r = RoleEntity(
        id: 'role-1',
        tenantId: 't1',
        name: 'Shift lead',
        baseRole: UserRole.manager,
        permissions: {
          Permission.posVoidTicket,
          Permission.posApplyDiscount,
          Permission.backofficeReportsView,
        },
        createdAt: now,
        updatedAt: now,
      );
      final json = r.toJson();
      final revived = RoleEntity.fromJson(json);
      expect(revived.permissions, r.permissions);
      expect(revived.hasPermission(Permission.posApplyDiscount), isTrue);
      expect(revived.hasPermission(Permission.backofficeStaffEdit), isFalse);
    });
  });

  group('Gang / GangEntity', () {
    test('baseline enum labels default to Gang 1/2/3', () {
      // Runtime label is resolved through [GangPolicy] / [RestaurantSettings];
      // the enum itself carries the canonical defaults.
      expect(Gang.first.displayLabel, 'Gang 1');
      expect(Gang.second.displayLabel, 'Gang 2');
      expect(Gang.third.displayLabel, 'Gang 3');
      expect(Gang.values.map((g) => g.position).toList(), [1, 2, 3]);
    });

    test('fromPosition round-trip', () {
      expect(Gang.fromPosition(1), Gang.first);
      expect(Gang.fromPosition(3), Gang.third);
      expect(Gang.fromPosition(4), isNull);
    });

    test('GangEntity JSON round-trip preserves timestamps', () {
      final g = GangEntity(
        gang: Gang.second,
        firedAt: now,
        readyAt: now.add(const Duration(minutes: 12)),
      );
      _rt<GangEntity>(g, GangEntity.fromJson);
      expect(g.displayLabel, 'Gang 2');
      expect(g.isFired, isTrue);
      expect(g.isReady, isTrue);
    });
  });

  group('DiscountEntity', () {
    test('JSON round-trip', () {
      final d = DiscountEntity(
        id: 'disc-1',
        tenantId: 't1',
        name: 'Staff 20%',
        code: 'STAFF',
        discountType: DiscountType.percentage,
        value: 2000,
        scope: DiscountScope.ticket,
        startsAt: now,
        endsAt: now.add(const Duration(days: 30)),
        createdAt: now,
        updatedAt: now,
      );
      _rt<DiscountEntity>(d, DiscountEntity.fromJson);
    });

    test('isApplicableAt honours window', () {
      final d = DiscountEntity(
        id: 'disc-1',
        tenantId: 't1',
        name: 'Promo',
        discountType: DiscountType.fixed,
        value: 500,
        startsAt: now,
        endsAt: now.add(const Duration(days: 1)),
        createdAt: now,
        updatedAt: now,
      );
      expect(d.isApplicableAt(now.add(const Duration(hours: 2))), isTrue);
      expect(d.isApplicableAt(now.subtract(const Duration(hours: 1))), isFalse);
      expect(d.isApplicableAt(now.add(const Duration(days: 2))), isFalse);
    });
  });

  group('ServiceChargeEntity', () {
    test('JSON round-trip', () {
      final s = ServiceChargeEntity(
        id: 'sc-1',
        tenantId: 't1',
        name: 'Cover',
        chargeType: ServiceChargeType.fixed,
        value: 200,
        trigger: ServiceChargeTrigger.perGuest,
        createdAt: now,
        updatedAt: now,
      );
      _rt<ServiceChargeEntity>(s, ServiceChargeEntity.fromJson);
    });
  });

  group('TaxEntity', () {
    test('swissStandard baseline', () {
      final tax = TaxEntity.swissStandard(tenantId: 't1');
      expect(tax.rate, 8.1);
      expect(tax.bucket, SwissMwstBucket.standard);
      expect(tax.countryCode, 'CH');
      expect(tax.inclusive, isTrue);
    });

    test('JSON round-trip', () {
      final t = TaxEntity(
        id: 'tx-1',
        tenantId: 't1',
        name: 'MWST 2.6%',
        rate: 2.6,
        bucket: SwissMwstBucket.reduced,
        createdAt: now,
        updatedAt: now,
      );
      _rt<TaxEntity>(t, TaxEntity.fromJson);
    });

    test('SwissMwstBucket default rates match published values', () {
      expect(SwissMwstBucket.standard.defaultRate, 8.1);
      expect(SwissMwstBucket.reduced.defaultRate, 2.6);
      expect(SwissMwstBucket.accommodation.defaultRate, 3.8);
      expect(SwissMwstBucket.exempt.defaultRate, 0.0);
    });
  });

  group('RestaurantEntity', () {
    test('JSON round-trip with defaults', () {
      final r = RestaurantEntity(
        id: 't1',
        name: 'Gasthof Rössli',
        legalName: 'Rössli GmbH',
        uid: 'CHE-123.456.789',
        plan: RestaurantPlan.pro,
        createdAt: now,
        updatedAt: now,
      );
      _rt<RestaurantEntity>(r, RestaurantEntity.fromJson);
      expect(r.currency, 'CHF');
      expect(r.timezone, 'Europe/Zurich');
    });
  });

  group('StoreEntity', () {
    test('JSON round-trip with nested address', () {
      final s = StoreEntity(
        id: 's1',
        tenantId: 't1',
        name: 'Bahnhofstrasse',
        code: 'ZH01',
        address: const StoreAddress(
          street: 'Bahnhofstrasse 1',
          postalCode: '8001',
          city: 'Zürich',
        ),
        createdAt: now,
        updatedAt: now,
      );
      _rt<StoreEntity>(s, StoreEntity.fromJson);
    });
  });

  group('SettingsEntity', () {
    test('read<T> returns typed value or fallback', () {
      final s = SettingsEntity(
        id: 'set-1',
        tenantId: 't1',
        values: {
          'receipt.footer': const SettingValue(
            type: SettingType.string,
            raw: 'Danke für Ihren Besuch!',
          ),
          'print.copies': const SettingValue(type: SettingType.int, raw: 2),
          'ui.dark_mode': const SettingValue(type: SettingType.bool, raw: true),
        },
        updatedAt: now,
      );
      expect(s.read<String>('receipt.footer', ''),
          'Danke für Ihren Besuch!');
      expect(s.read<int>('print.copies', 1), 2);
      expect(s.read<bool>('ui.dark_mode', false), isTrue);
      expect(s.read<int>('missing.key', 42), 42);
    });

    test('JSON round-trip preserves every key', () {
      final s = SettingsEntity(
        id: 'set-1',
        tenantId: 't1',
        storeId: 'store-1',
        values: {
          'k1': const SettingValue(type: SettingType.string, raw: 'hello'),
          'k2': const SettingValue(type: SettingType.int, raw: 7),
        },
        updatedAt: now,
      );
      final revived = SettingsEntity.fromJson(s.toJson());
      expect(revived.values.keys.toSet(), s.values.keys.toSet());
      expect(revived.read<String>('k1', ''), 'hello');
      expect(revived.read<int>('k2', 0), 7);
    });
  });

  group('PaymentMethodEntity', () {
    test('JSON round-trip', () {
      final pm = PaymentMethodEntity(
        id: 'pm-twint',
        tenantId: 't1',
        name: 'TWINT',
        method: PaymentMethod.other,
        code: 'TWINT',
        iconKey: 'twint',
        requiresTender: false,
        createdAt: now,
        updatedAt: now,
      );
      _rt<PaymentMethodEntity>(pm, PaymentMethodEntity.fromJson);
    });
  });
}
