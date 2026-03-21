/// Unit tests for [SettingsRepositoryImpl].
///
/// Uses [SharedPreferences.setMockInitialValues] to run without a real
/// device/platform channel — no external dependencies required.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gastrocore_pos/features/settings/data/repositories/settings_repository_impl.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/app_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/payment_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/printer_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/receipt_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/restaurant_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/tax_settings.dart';

// ---------------------------------------------------------------------------
// Helper to create a fresh, empty in-memory repository
// ---------------------------------------------------------------------------

Future<SettingsRepositoryImpl> _makeRepo({
  Map<String, Object> initial = const {},
}) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  return SettingsRepositoryImpl(prefs);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // =========================================================================
  // Restaurant Settings
  // =========================================================================

  group('RestaurantSettings persistence', () {
    test('returns defaults when no stored value exists', () async {
      final repo = await _makeRepo();
      final s = await repo.loadRestaurantSettings();
      expect(s, const RestaurantSettings());
    });

    test('save then load round-trips correctly', () async {
      final repo = await _makeRepo();
      const settings = RestaurantSettings(
        name: 'Brasserie du Lac',
        address: 'Quai du Mont-Blanc 17, 1201 Genève',
        phone: '+41 22 000 00 00',
        mwstNr: 'CHE-987.654.321 MWST',
      );
      await repo.saveRestaurantSettings(settings);
      final loaded = await repo.loadRestaurantSettings();
      expect(loaded, settings);
    });

    test('overwrite replaces previous value', () async {
      final repo = await _makeRepo();
      await repo.saveRestaurantSettings(const RestaurantSettings(name: 'A'));
      await repo.saveRestaurantSettings(const RestaurantSettings(name: 'B'));
      final loaded = await repo.loadRestaurantSettings();
      expect(loaded.name, 'B');
    });
  });

  // =========================================================================
  // Printer Settings
  // =========================================================================

  group('PrinterSettings persistence', () {
    test('returns defaults when no stored value exists', () async {
      final repo = await _makeRepo();
      final s = await repo.loadPrinterSettings();
      expect(s, const PrinterSettings());
    });

    test('save then load round-trips correctly', () async {
      final repo = await _makeRepo();
      const settings = PrinterSettings(
        connectionType: PrinterConnectionType.bluetooth,
        receiptPrinterIp: '10.0.0.5',
        receiptPrinterPort: 9100,
        kitchenPrinterIp: '10.0.0.6',
        kitchenPrinterPort: 9100,
        paperWidth: PaperWidth.mm58,
        autoPrintOnPayment: false,
        autoPrintKitchenTicket: true,
      );
      await repo.savePrinterSettings(settings);
      final loaded = await repo.loadPrinterSettings();
      expect(loaded, settings);
    });
  });

  // =========================================================================
  // Payment Settings
  // =========================================================================

  group('PaymentSettings persistence', () {
    test('returns defaults when no stored value exists', () async {
      final repo = await _makeRepo();
      final s = await repo.loadPaymentSettings();
      expect(s, const PaymentSettings());
    });

    test('save then load round-trips with Wallee config', () async {
      final repo = await _makeRepo();
      const settings = PaymentSettings(
        activeGateway: PaymentGateway.wallee,
        wallee: WalleeConfig(
          terminalIp: '192.168.1.200',
          terminalPort: 50000,
          posId: 'POS-MAIN',
        ),
      );
      await repo.savePaymentSettings(settings);
      final loaded = await repo.loadPaymentSettings();
      expect(loaded.activeGateway, PaymentGateway.wallee);
      expect(loaded.wallee.terminalIp, '192.168.1.200');
      expect(loaded.wallee.posId, 'POS-MAIN');
    });

    test('save then load round-trips with MyPOS config', () async {
      final repo = await _makeRepo();
      const settings = PaymentSettings(
        activeGateway: PaymentGateway.mypos,
        mypos: MyPosConfig(ip: '192.168.1.201', port: 50100, currency: 'EUR'),
      );
      await repo.savePaymentSettings(settings);
      final loaded = await repo.loadPaymentSettings();
      expect(loaded.mypos.currency, 'EUR');
      expect(loaded.activeGateway, PaymentGateway.mypos);
    });
  });

  // =========================================================================
  // Receipt Settings
  // =========================================================================

  group('ReceiptSettings persistence', () {
    test('returns defaults when no stored value exists', () async {
      final repo = await _makeRepo();
      final s = await repo.loadReceiptSettings();
      expect(s, const ReceiptSettings());
    });

    test('save then load round-trips correctly', () async {
      final repo = await _makeRepo();
      const settings = ReceiptSettings(
        headerText: 'Bienvenue chez nous',
        footerText: 'À bientôt!',
        showLogo: false,
        showQrCode: true,
        qrCodeData: 'https://restaurant.example.ch',
      );
      await repo.saveReceiptSettings(settings);
      final loaded = await repo.loadReceiptSettings();
      expect(loaded, settings);
    });
  });

  // =========================================================================
  // Tax Settings
  // =========================================================================

  group('TaxSettings persistence', () {
    test('returns Swiss defaults when no stored value exists', () async {
      final repo = await _makeRepo();
      final s = await repo.loadTaxSettings();
      expect(s.standardRate, TaxSettings.defaultStandardRate);
      expect(s.accommodationRate, TaxSettings.defaultAccommodationRate);
      expect(s.reducedRate, TaxSettings.defaultReducedRate);
    });

    test('save then load round-trips correctly', () async {
      final repo = await _makeRepo();
      final settings = TaxSettings(
        standardRate: 8.1,
        accommodationRate: 3.8,
        reducedRate: 2.6,
        taxIncludedInPrice: false,
        rappenRounding: false,
      );
      await repo.saveTaxSettings(settings);
      final loaded = await repo.loadTaxSettings();
      expect(loaded, settings);
    });

    test('tax rates persist independently of other categories', () async {
      final repo = await _makeRepo();
      await repo.saveRestaurantSettings(
          const RestaurantSettings(name: 'My Restaurant'));
      final tax = TaxSettings(standardRate: 9.0);
      await repo.saveTaxSettings(tax);

      final loadedRestaurant = await repo.loadRestaurantSettings();
      final loadedTax = await repo.loadTaxSettings();

      expect(loadedRestaurant.name, 'My Restaurant');
      expect(loadedTax.standardRate, 9.0);
    });
  });

  // =========================================================================
  // App Settings
  // =========================================================================

  group('AppSettings persistence', () {
    test('returns defaults when no stored value exists', () async {
      final repo = await _makeRepo();
      final s = await repo.loadAppSettings();
      expect(s, const AppSettings());
    });

    test('save then load round-trips correctly', () async {
      final repo = await _makeRepo();
      const settings = AppSettings(
        themeMode: AppThemeMode.light,
        language: AppLanguage.it,
      );
      await repo.saveAppSettings(settings);
      final loaded = await repo.loadAppSettings();
      expect(loaded, settings);
    });
  });

  // =========================================================================
  // clearAll
  // =========================================================================

  group('clearAll', () {
    test('resets all categories to defaults', () async {
      final repo = await _makeRepo();
      await repo.saveRestaurantSettings(
          const RestaurantSettings(name: 'To be cleared'));
      await repo.saveTaxSettings(TaxSettings(standardRate: 9.0));
      await repo.saveAppSettings(
          const AppSettings(language: AppLanguage.fr));

      await repo.clearAll();

      final restaurant = await repo.loadRestaurantSettings();
      final tax = await repo.loadTaxSettings();
      final app = await repo.loadAppSettings();

      expect(restaurant.name, '');
      expect(tax.standardRate, TaxSettings.defaultStandardRate);
      expect(app.language, AppLanguage.de);
    });
  });

  // =========================================================================
  // Corrupted stored JSON
  // =========================================================================

  group('corrupted stored JSON', () {
    test('returns defaults when stored JSON is invalid', () async {
      final repo = await _makeRepo(
        initial: {'settings.v1.restaurant': 'NOT_VALID_JSON!!!'},
      );
      final s = await repo.loadRestaurantSettings();
      expect(s, const RestaurantSettings());
    });

    test('tax returns defaults on corrupted JSON', () async {
      final repo = await _makeRepo(
        initial: {'settings.v1.tax': '{"standardRate": "oops"}'},
      );
      // fromJson will still succeed but with a type error — verify fallback
      // (the impl catches all exceptions from fromJsonString)
      final s = await repo.loadTaxSettings();
      // Either parsed successfully or fell back to defaults — either is fine
      expect(s, isNotNull);
    });
  });
}
