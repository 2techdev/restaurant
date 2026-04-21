/// Unit tests for [HappyHourRulesNotifier].
///
/// The notifier backs the POS order-panel hot path synchronously, so every
/// mutation must:
///   * return an unmodifiable list (defensive against grid-side mutation),
///   * persist to the injected repository BEFORE publishing new state, and
///   * survive first-run (empty blob) by seeding [happyHourDefaultRules].
///
/// Run with:
///   flutter test test/features/pricing/happy_hour_rules_notifier_test.dart
library;

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/features/pricing/domain/happy_hour_rule.dart';
import 'package:gastrocore_pos/features/pricing/providers/happy_hour_provider.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/app_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/happy_hour_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/payment_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/printer_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/receipt_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/restaurant_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/tax_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/theme_customization.dart';
import 'package:gastrocore_pos/features/settings/domain/repositories/settings_repository.dart';

// ---------------------------------------------------------------------------
// Test double: in-memory repository with seedable happy-hour blob.
// ---------------------------------------------------------------------------

class _FakeSettingsRepository implements SettingsRepository {
  _FakeSettingsRepository({HappyHourSettings? initial})
      : _happyHour = initial ?? const HappyHourSettings();

  HappyHourSettings _happyHour;
  int loadCalls = 0;
  int saveCalls = 0;
  HappyHourSettings? lastSaved;

  @override
  Future<HappyHourSettings> loadHappyHourSettings() async {
    loadCalls += 1;
    return _happyHour;
  }

  @override
  Future<void> saveHappyHourSettings(HappyHourSettings settings) async {
    saveCalls += 1;
    lastSaved = settings;
    _happyHour = settings;
  }

  // --- Unused stubs ---------------------------------------------------------
  @override
  Future<RestaurantSettings> loadRestaurantSettings() async =>
      const RestaurantSettings();
  @override
  Future<void> saveRestaurantSettings(RestaurantSettings s) async {}
  @override
  Future<PrinterSettings> loadPrinterSettings() async =>
      const PrinterSettings();
  @override
  Future<void> savePrinterSettings(PrinterSettings s) async {}
  @override
  Future<PaymentSettings> loadPaymentSettings() async =>
      const PaymentSettings();
  @override
  Future<void> savePaymentSettings(PaymentSettings s) async {}
  @override
  Future<ReceiptSettings> loadReceiptSettings() async =>
      const ReceiptSettings();
  @override
  Future<void> saveReceiptSettings(ReceiptSettings s) async {}
  @override
  Future<TaxSettings> loadTaxSettings() async => TaxSettings();
  @override
  Future<void> saveTaxSettings(TaxSettings s) async {}
  @override
  Future<AppSettings> loadAppSettings() async => const AppSettings();
  @override
  Future<void> saveAppSettings(AppSettings s) async {}
  @override
  Future<ThemeCustomization> loadThemeCustomization() async =>
      const ThemeCustomization();
  @override
  Future<void> saveThemeCustomization(ThemeCustomization s) async {}

  @override
  Future<String> getDatabasePath() async => '';
  @override
  Future<String> exportDatabase(String targetDirectory) async => '';
  @override
  Future<void> importDatabase(String sourcePath) async {}
  @override
  Future<void> clearAll() async {}
}

HappyHourRule _rule({
  String id = 'r-test',
  String name = 'Test Rule',
  int discount = 15,
  bool active = true,
  String? categoryId = 'beverages',
  String? productNameContains,
}) {
  return HappyHourRule(
    id: id,
    name: name,
    categoryId: categoryId,
    productNameContains: productNameContains,
    discountPercent: discount,
    startTime: const TimeOfDay(hour: 17, minute: 0),
    endTime: const TimeOfDay(hour: 19, minute: 0),
    daysOfWeek: const [1, 2, 3, 4, 5],
    active: active,
  );
}

void main() {
  group('HappyHourRulesNotifier — initial state', () {
    test('starts from happyHourDefaultRules before hydrate', () {
      final notifier = HappyHourRulesNotifier();
      expect(notifier.state, equals(happyHourDefaultRules));
      // Unmodifiable so the POS grid can't mutate shared rule objects.
      expect(() => notifier.state.add(_rule()), throwsUnsupportedError);
    });
  });

  group('HappyHourRulesNotifier — hydrate', () {
    test('empty blob seeds defaults and persists them back', () async {
      final repo = _FakeSettingsRepository();
      final notifier = HappyHourRulesNotifier();

      await notifier.hydrate(repo);

      expect(repo.loadCalls, 1);
      expect(repo.saveCalls, 1,
          reason: 'first-run must write defaults to the repo');
      expect(repo.lastSaved?.rules, equals(happyHourDefaultRules));
      expect(notifier.state, equals(happyHourDefaultRules));
    });

    test('stored blob replaces state without overwriting the repo', () async {
      final stored = HappyHourSettings(rules: [
        _rule(id: 'stored-1', name: 'Stored', discount: 30),
      ]);
      final repo = _FakeSettingsRepository(initial: stored);
      final notifier = HappyHourRulesNotifier();

      await notifier.hydrate(repo);

      expect(repo.loadCalls, 1);
      expect(repo.saveCalls, 0,
          reason: 'non-empty blob must not be rewritten on hydrate');
      expect(notifier.state.map((r) => r.id).toList(), ['stored-1']);
      expect(notifier.state.first.discountPercent, 30);
    });

    test('second hydrate call is a no-op (idempotent)', () async {
      final repo = _FakeSettingsRepository();
      final notifier = HappyHourRulesNotifier();

      await notifier.hydrate(repo);
      await notifier.hydrate(repo);

      expect(repo.loadCalls, 1,
          reason: 'hydrate must only read the blob once per notifier');
    });

    test('load failure keeps defaults so the POS grid stays usable', () async {
      final repo = _ThrowingRepository();
      final notifier = HappyHourRulesNotifier();

      await notifier.hydrate(repo);

      expect(notifier.state, equals(happyHourDefaultRules));
    });
  });

  group('HappyHourRulesNotifier — upsert', () {
    test('adds a new rule when id is unknown', () async {
      final repo = _FakeSettingsRepository();
      final notifier = HappyHourRulesNotifier();
      await notifier.hydrate(repo);

      final newRule = _rule(id: 'new-1', name: 'Yeni');
      await notifier.upsert(newRule);

      expect(notifier.state.any((r) => r.id == 'new-1'), isTrue);
      expect(repo.lastSaved?.rules.any((r) => r.id == 'new-1'), isTrue);
      // State must remain unmodifiable.
      expect(() => notifier.state.add(_rule(id: 'x')), throwsUnsupportedError);
    });

    test('replaces an existing rule in place when id matches', () async {
      final repo = _FakeSettingsRepository(
        initial: HappyHourSettings(rules: [
          _rule(id: 'r1', name: 'Old', discount: 10),
          _rule(id: 'r2', name: 'Keep', discount: 20),
        ]),
      );
      final notifier = HappyHourRulesNotifier();
      await notifier.hydrate(repo);

      await notifier.upsert(_rule(id: 'r1', name: 'New', discount: 25));

      expect(notifier.state.length, 2);
      final r1 = notifier.state.firstWhere((r) => r.id == 'r1');
      expect(r1.name, 'New');
      expect(r1.discountPercent, 25);
      // Order preserved — replacement is in place, not append.
      expect(notifier.state.map((r) => r.id).toList(), ['r1', 'r2']);
    });
  });

  group('HappyHourRulesNotifier — remove', () {
    test('drops the matching rule and persists the new list', () async {
      final repo = _FakeSettingsRepository(
        initial: HappyHourSettings(rules: [
          _rule(id: 'r1'),
          _rule(id: 'r2'),
        ]),
      );
      final notifier = HappyHourRulesNotifier();
      await notifier.hydrate(repo);

      await notifier.remove('r1');

      expect(notifier.state.map((r) => r.id).toList(), ['r2']);
      expect(
        repo.lastSaved?.rules.map((r) => r.id).toList(),
        ['r2'],
      );
    });

    test('silently ignores unknown ids', () async {
      final repo = _FakeSettingsRepository(
        initial: HappyHourSettings(rules: [_rule(id: 'r1')]),
      );
      final notifier = HappyHourRulesNotifier();
      await notifier.hydrate(repo);

      await notifier.remove('does-not-exist');

      expect(notifier.state.map((r) => r.id).toList(), ['r1']);
    });
  });

  group('HappyHourRulesNotifier — toggleActive', () {
    test('flips the active flag without touching other fields', () async {
      final repo = _FakeSettingsRepository(
        initial: HappyHourSettings(rules: [
          _rule(id: 'r1', name: 'Bira', discount: 20, active: true),
        ]),
      );
      final notifier = HappyHourRulesNotifier();
      await notifier.hydrate(repo);

      await notifier.toggleActive('r1');

      var r1 = notifier.state.firstWhere((r) => r.id == 'r1');
      expect(r1.active, isFalse);
      expect(r1.name, 'Bira');
      expect(r1.discountPercent, 20);

      await notifier.toggleActive('r1');
      r1 = notifier.state.firstWhere((r) => r.id == 'r1');
      expect(r1.active, isTrue);
    });
  });
}

/// Repository that blows up on load. Used to verify [hydrate] keeps the
/// in-memory default state so the POS grid's synchronous reads never return
/// null / empty during a disk failure.
class _ThrowingRepository extends _FakeSettingsRepository {
  @override
  Future<HappyHourSettings> loadHappyHourSettings() async {
    throw StateError('disk unavailable');
  }
}
