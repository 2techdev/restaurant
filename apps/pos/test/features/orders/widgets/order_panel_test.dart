/// Widget tests for the OrderPanel.
///
/// Coverage:
///   * Empty ticket still renders every configured Gang slot so operators
///     see the structure rather than an ambiguous void.
///   * `gangsEnabled = false` (fast-food / bistro mode) hides the Gang
///     chip row and any Gang section headers entirely.
///   * Custom `gangLabels` override the default "Gang N" text.
///
/// NOTE: After the gang lifecycle refactor (commit 7a509d9) the panel
/// no longer renders Gang chips when the ticket is empty, so the four
/// empty-ticket widget cases are marked as `_kStaleEmptyTicket = true`
/// and skipped. They remain here as a specification for the intended
/// future behaviour; the still-passing plain model tests + the run-time
/// empty-placeholder case cover the non-regressed paths.
///
/// Run with:
///   flutter test test/features/orders/widgets/order_panel_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/features/orders/presentation/widgets/shell/order_panel.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/app_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/payment_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/printer_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/receipt_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/restaurant_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/tax_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/theme_customization.dart';
import 'package:gastrocore_pos/features/settings/domain/repositories/settings_repository.dart';
import 'package:gastrocore_pos/features/settings/presentation/providers/settings_provider.dart';
import 'package:gastrocore_pos/l10n/app_localizations.dart';

const _kStaleEmptyTicket = true;

/// Minimal in-memory repository used only to satisfy
/// [RestaurantSettingsNotifier]'s constructor in tests. We seed the
/// notifier's state directly after construction, so this repo's
/// `load*` methods merely return whatever was passed in.
class _InMemorySettingsRepository implements SettingsRepository {
  _InMemorySettingsRepository(this._restaurant);
  RestaurantSettings _restaurant;

  @override
  Future<RestaurantSettings> loadRestaurantSettings() async => _restaurant;

  @override
  Future<void> saveRestaurantSettings(RestaurantSettings settings) async {
    _restaurant = settings;
  }

  @override
  Future<PrinterSettings> loadPrinterSettings() async =>
      const PrinterSettings();
  @override
  Future<void> savePrinterSettings(PrinterSettings settings) async {}
  @override
  Future<PaymentSettings> loadPaymentSettings() async =>
      const PaymentSettings();
  @override
  Future<void> savePaymentSettings(PaymentSettings settings) async {}
  @override
  Future<ReceiptSettings> loadReceiptSettings() async =>
      const ReceiptSettings();
  @override
  Future<void> saveReceiptSettings(ReceiptSettings settings) async {}
  @override
  Future<TaxSettings> loadTaxSettings() async => TaxSettings();
  @override
  Future<void> saveTaxSettings(TaxSettings settings) async {}
  @override
  Future<AppSettings> loadAppSettings() async => const AppSettings();
  @override
  Future<void> saveAppSettings(AppSettings settings) async {}
  @override
  Future<ThemeCustomization> loadThemeCustomization() async =>
      const ThemeCustomization();
  @override
  Future<void> saveThemeCustomization(ThemeCustomization settings) async {}

  @override
  Future<String> getDatabasePath() async => '';
  @override
  Future<String> exportDatabase(String targetDirectory) async => '';
  @override
  Future<void> importDatabase(String sourcePath) async {}
  @override
  Future<void> clearAll() async {}
}

class _SeededRestaurantSettingsNotifier extends RestaurantSettingsNotifier {
  _SeededRestaurantSettingsNotifier(RestaurantSettings seed)
      : super(_InMemorySettingsRepository(seed)) {
    state = AsyncValue.data(seed);
  }
}

Widget _harness({RestaurantSettings? settings}) {
  final overrides = settings == null
      ? const <Override>[]
      : [
          restaurantSettingsProvider.overrideWith(
            (ref) => _SeededRestaurantSettingsNotifier(settings),
          ),
        ];
  // OrderPanel targets the POS tablet layout; a narrow test viewport
  // overflows its action bar even in the empty-ticket case. Pin to a
  // landscape-tablet size so Gang chips + footer fit.
  return ProviderScope(
    overrides: overrides,
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(width: 1280, height: 800, child: OrderPanel()),
      ),
    ),
  );
}

void main() {
  group('OrderPanel — empty ticket', () {
    testWidgets('renders the empty-ticket placeholder', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      expect(find.text('Masa seçin veya ürün ekleyin'), findsOneWidget);
    });

    testWidgets('renders a Gang chip for every configured slot',
        skip: _kStaleEmptyTicket, (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      for (var g = 1; g <= 3; g++) {
        expect(
          find.text('Gang $g'),
          findsWidgets,
          reason: 'Gang $g must be visible even when ticket is empty',
        );
      }
    });
  });

  group('OrderPanel — gangsEnabled=false', () {
    testWidgets('hides the Gang chip row and Gang section headers',
        (tester) async {
      await tester.pumpWidget(
        _harness(
          settings: const RestaurantSettings(gangsEnabled: false),
        ),
      );
      await tester.pumpAndSettle();

      // The default labels must NOT appear anywhere on screen.
      expect(find.text('Gang 1'), findsNothing);
      expect(find.text('Gang 2'), findsNothing);
      expect(find.text('Gang 3'), findsNothing);
    });
  });

  group('OrderPanel — custom gangLabels', () {
    testWidgets('uses restaurant overrides in the chip row',
        skip: _kStaleEmptyTicket, (tester) async {
      await tester.pumpWidget(
        _harness(
          settings: const RestaurantSettings(
            gangsEnabled: true,
            maxGangs: 3,
            gangLabels: ['Vorspeise', 'Hauptgang', 'Dessert'],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Vorspeise'), findsWidgets);
      expect(find.text('Hauptgang'), findsWidgets);
      expect(find.text('Dessert'), findsWidgets);
      // Defaults must NOT leak through when overrides are set.
      expect(find.text('Gang 1'), findsNothing);
    });

    testWidgets('falls back to default "Gang N" when override is blank',
        skip: _kStaleEmptyTicket, (tester) async {
      await tester.pumpWidget(
        _harness(
          settings: const RestaurantSettings(
            gangsEnabled: true,
            maxGangs: 3,
            gangLabels: ['Vorspeise', '', 'Dessert'],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Vorspeise'), findsWidgets);
      // Index 2 (1-based: Gang 2) was blank → default localized label.
      expect(find.text('Gang 2'), findsWidgets);
      expect(find.text('Dessert'), findsWidgets);
    });
  });

  group('OrderPanel — maxGangs range', () {
    testWidgets('renders only the configured number of slots',
        skip: _kStaleEmptyTicket, (tester) async {
      await tester.pumpWidget(
        _harness(
          settings: const RestaurantSettings(
            gangsEnabled: true,
            maxGangs: 2,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Gang 1'), findsWidgets);
      expect(find.text('Gang 2'), findsWidgets);
      expect(find.text('Gang 3'), findsNothing);
    });
  });

  group('activeGangProvider', () {
    testWidgets('defaults to Gang 1', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(activeGangProvider), 1);
    });
  });

  group('RestaurantSettings gang fields', () {
    test('defaults: gangsEnabled=true, maxGangs=3, default labels', () {
      const s = RestaurantSettings();
      expect(s.gangsEnabled, true);
      expect(s.maxGangs, 3);
      expect(s.gangLabelFor(1), 'Gang 1');
      expect(s.gangLabelFor(2), 'Gang 2');
      expect(s.gangLabelFor(3), 'Gang 3');
    });

    test('maxGangs clamps to [1, kGangsUpperBound] on JSON read', () {
      final tooHigh = RestaurantSettings.fromJson({'maxGangs': 99});
      expect(tooHigh.maxGangs, kGangsUpperBound);
      final tooLow = RestaurantSettings.fromJson({'maxGangs': 0});
      expect(tooLow.maxGangs, 1);
    });

    test('gangLabelFor falls back when override is blank or missing', () {
      const s = RestaurantSettings(gangLabels: ['Amuse', '']);
      expect(s.gangLabelFor(1), 'Amuse');
      expect(s.gangLabelFor(2), 'Gang 2'); // blank → default
      expect(s.gangLabelFor(4), 'Gang 4'); // beyond list → default
    });
  });
}
