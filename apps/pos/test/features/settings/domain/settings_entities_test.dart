/// Unit tests for Settings domain entities.
///
/// Verifies JSON round-trips, copyWith correctness, equality, and
/// Swiss MWST default values.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/features/settings/domain/entities/app_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/payment_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/printer_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/receipt_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/restaurant_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/tax_settings.dart';

void main() {
  // =========================================================================
  // RestaurantSettings
  // =========================================================================

  group('RestaurantSettings', () {
    const defaults = RestaurantSettings();

    test('default values are empty strings', () {
      expect(defaults.name, '');
      expect(defaults.address, '');
      expect(defaults.phone, '');
      expect(defaults.mwstNr, '');
      expect(defaults.logoPath, isNull);
    });

    test('copyWith updates only specified fields', () {
      final updated = defaults.copyWith(name: 'Zum Löwen', phone: '+41441234567');
      expect(updated.name, 'Zum Löwen');
      expect(updated.phone, '+41441234567');
      expect(updated.address, '');
      expect(updated.mwstNr, '');
    });

    test('clearLogo removes logoPath', () {
      final withLogo = defaults.copyWith(logoPath: '/storage/logo.png');
      final cleared = withLogo.copyWith(clearLogo: true);
      expect(cleared.logoPath, isNull);
    });

    test('JSON round-trip preserves all fields', () {
      const original = RestaurantSettings(
        name: 'Gasthaus Post',
        address: 'Dorfstrasse 1, 9000 St. Gallen',
        phone: '+41 71 222 33 44',
        mwstNr: 'CHE-123.456.789 MWST',
        logoPath: '/data/logo.png',
      );
      final restored = RestaurantSettings.fromJsonString(original.toJsonString());
      expect(restored, original);
    });

    test('fromJsonString with missing keys uses defaults', () {
      final partial = RestaurantSettings.fromJsonString('{}');
      expect(partial.name, '');
      expect(partial.logoPath, isNull);
    });

    test('equality holds for identical objects', () {
      const a = RestaurantSettings(name: 'A');
      const b = RestaurantSettings(name: 'A');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('inequality holds when fields differ', () {
      const a = RestaurantSettings(name: 'A');
      const b = RestaurantSettings(name: 'B');
      expect(a, isNot(equals(b)));
    });
  });

  // =========================================================================
  // PrinterSettings
  // =========================================================================

  group('PrinterSettings', () {
    test('default connection type is WiFi', () {
      const s = PrinterSettings();
      expect(s.connectionType, PrinterConnectionType.wifi);
    });

    test('default ports are 9100', () {
      const s = PrinterSettings();
      expect(s.receiptPrinterPort, 9100);
      expect(s.kitchenPrinterPort, 9100);
    });

    test('default paper width is 80mm', () {
      expect(const PrinterSettings().paperWidth, PaperWidth.mm80);
    });

    test('PrinterConnectionType.fromString falls back to wifi', () {
      expect(
        PrinterConnectionType.fromString('invalid'),
        PrinterConnectionType.wifi,
      );
    });

    test('PaperWidth.fromInt falls back to 80mm', () {
      expect(PaperWidth.fromInt(999), PaperWidth.mm80);
    });

    test('JSON round-trip preserves all fields', () {
      const original = PrinterSettings(
        connectionType: PrinterConnectionType.bluetooth,
        receiptPrinterIp: '10.0.0.10',
        receiptPrinterPort: 9100,
        kitchenPrinterIp: '10.0.0.11',
        kitchenPrinterPort: 9100,
        paperWidth: PaperWidth.mm58,
        autoPrintOnPayment: false,
        autoPrintKitchenTicket: false,
        characterSet: 'CP1252',
      );
      final restored = PrinterSettings.fromJsonString(original.toJsonString());
      expect(restored, original);
    });

    test('copyWith updates connection type', () {
      const s = PrinterSettings();
      final updated = s.copyWith(connectionType: PrinterConnectionType.usb);
      expect(updated.connectionType, PrinterConnectionType.usb);
      expect(updated.receiptPrinterPort, 9100);
    });
  });

  // =========================================================================
  // PaymentSettings
  // =========================================================================

  group('PaymentSettings', () {
    test('default active gateway is none', () {
      expect(const PaymentSettings().activeGateway, PaymentGateway.none);
    });

    test('WalleeConfig default port is 50000', () {
      expect(const WalleeConfig().terminalPort, 50000);
    });

    test('MyPosConfig default currency is CHF', () {
      expect(const MyPosConfig().currency, 'CHF');
    });

    test('MyPosConfig default port is 50100', () {
      expect(const MyPosConfig().port, 50100);
    });

    test('PaymentGateway.fromString falls back to none', () {
      expect(PaymentGateway.fromString('unknown'), PaymentGateway.none);
    });

    test('JSON round-trip preserves gateway selection', () {
      const original = PaymentSettings(
        activeGateway: PaymentGateway.wallee,
        wallee: WalleeConfig(
          terminalIp: '192.168.1.200',
          terminalPort: 50000,
          posId: 'POS-01',
        ),
        mypos: MyPosConfig(ip: '192.168.1.201', port: 50100, currency: 'CHF'),
      );
      final restored = PaymentSettings.fromJsonString(original.toJsonString());
      expect(restored, original);
    });

    test('WalleeConfig copyWith preserves untouched fields', () {
      const cfg = WalleeConfig(terminalIp: '1.2.3.4', posId: 'POS-X');
      final updated = cfg.copyWith(terminalPort: 60000);
      expect(updated.terminalIp, '1.2.3.4');
      expect(updated.posId, 'POS-X');
      expect(updated.terminalPort, 60000);
    });

    test('MyPosConfig equality', () {
      const a = MyPosConfig(ip: '1.1.1.1', port: 50100, currency: 'CHF');
      const b = MyPosConfig(ip: '1.1.1.1', port: 50100, currency: 'CHF');
      expect(a, equals(b));
    });
  });

  // =========================================================================
  // ReceiptSettings
  // =========================================================================

  group('ReceiptSettings', () {
    test('showLogo defaults to true', () {
      expect(const ReceiptSettings().showLogo, isTrue);
    });

    test('showQrCode defaults to false', () {
      expect(const ReceiptSettings().showQrCode, isFalse);
    });

    test('footer has Swiss multilingual default', () {
      final footer = const ReceiptSettings().footerText;
      expect(footer, contains('Merci'));
      expect(footer, contains('Danke'));
    });

    test('JSON round-trip', () {
      const original = ReceiptSettings(
        headerText: 'Willkommen!',
        footerText: 'Auf Wiedersehen',
        showLogo: false,
        showQrCode: true,
        qrCodeData: 'https://restaurant.ch',
      );
      final restored = ReceiptSettings.fromJsonString(original.toJsonString());
      expect(restored, original);
    });

    test('copyWith showQrCode', () {
      const s = ReceiptSettings();
      expect(s.copyWith(showQrCode: true).showQrCode, isTrue);
    });
  });

  // =========================================================================
  // TaxSettings — Swiss MWST
  // =========================================================================

  group('TaxSettings', () {
    test('Swiss MWST standard rate default is 8.1%', () {
      expect(TaxSettings.defaultStandardRate, 8.1);
    });

    test('Swiss MWST accommodation rate default is 3.8%', () {
      expect(TaxSettings.defaultAccommodationRate, 3.8);
    });

    test('Swiss MWST reduced rate default is 2.6%', () {
      expect(TaxSettings.defaultReducedRate, 2.6);
    });

    test('taxIncludedInPrice defaults to true (gross prices)', () {
      expect(TaxSettings().taxIncludedInPrice, isTrue);
    });

    test('rappenRounding defaults to true', () {
      expect(TaxSettings().rappenRounding, isTrue);
    });

    test('rates list contains three entries', () {
      expect(TaxSettings().rates.length, 3);
    });

    test('rateForCode returns correct rate', () {
      final s = TaxSettings();
      expect(s.rateForCode('standard'), 8.1);
      expect(s.rateForCode('accommodation'), 3.8);
      expect(s.rateForCode('reduced'), 2.6);
    });

    test('rateForCode falls back to standard for unknown code', () {
      final s = TaxSettings();
      expect(s.rateForCode('unknown'), 8.1);
    });

    test('JSON round-trip', () {
      final original = TaxSettings(
        standardRate: 8.1,
        accommodationRate: 3.8,
        reducedRate: 2.6,
        taxIncludedInPrice: false,
        rappenRounding: false,
      );
      final restored = TaxSettings.fromJsonString(original.toJsonString());
      expect(restored, original);
    });

    test('copyWith overrides individual rates', () {
      final s = TaxSettings();
      final updated = s.copyWith(standardRate: 9.0);
      expect(updated.standardRate, 9.0);
      expect(updated.reducedRate, TaxSettings.defaultReducedRate);
    });

    test('fromJsonString handles num type (int stored as int)', () {
      // Simulate JSON with integer values instead of doubles
      const json = '{"standardRate":8,"accommodationRate":3,"reducedRate":2}';
      final s = TaxSettings.fromJsonString(json);
      expect(s.standardRate, 8.0);
      expect(s.accommodationRate, 3.0);
      expect(s.reducedRate, 2.0);
    });
  });

  // =========================================================================
  // AppSettings
  // =========================================================================

  group('AppSettings', () {
    test('default theme is light', () {
      expect(const AppSettings().themeMode, AppThemeMode.light);
    });

    test('default language is German', () {
      expect(const AppSettings().language, AppLanguage.de);
    });

    test('default high contrast is off, text scale is medium', () {
      const s = AppSettings();
      expect(s.highContrast, isFalse);
      expect(s.textScale, AppTextScale.medium);
    });

    test('AppLanguage labels are non-empty', () {
      for (final lang in AppLanguage.values) {
        expect(lang.label, isNotEmpty);
        expect(lang.flag, isNotEmpty);
      }
    });

    test('AppThemeMode labels are non-empty', () {
      for (final mode in AppThemeMode.values) {
        expect(mode.label, isNotEmpty);
      }
    });

    test('AppTextScale scale multipliers are monotonic and non-zero', () {
      // Each preset must be larger than the previous so "Büyük > Orta >
      // Küçük" stays truthful if we ever re-tune the numbers.
      var previous = 0.0;
      for (final scale in AppTextScale.values) {
        expect(scale.scale, greaterThan(previous));
        expect(scale.label, isNotEmpty);
        previous = scale.scale;
      }
      // Sanity on the defaults we shipped.
      expect(AppTextScale.medium.scale, 1.0);
    });

    test('AppLanguage.fromString falls back to de', () {
      expect(AppLanguage.fromString('xx'), AppLanguage.de);
    });

    test('AppThemeMode.fromString falls back to light', () {
      expect(AppThemeMode.fromString('rainbow'), AppThemeMode.light);
    });

    test('AppTextScale.fromString falls back to medium', () {
      expect(AppTextScale.fromString('xxl'), AppTextScale.medium);
    });

    test('JSON round-trip preserves all fields including a11y', () {
      const original = AppSettings(
        themeMode: AppThemeMode.light,
        language: AppLanguage.fr,
        handedness: AppHandedness.left,
        highContrast: true,
        textScale: AppTextScale.large,
      );
      final restored = AppSettings.fromJsonString(original.toJsonString());
      expect(restored, original);
    });

    test('fromJson fills in defaults for missing a11y keys', () {
      final legacy = AppSettings.fromJsonString(
        '{"themeMode":"light","language":"de"}',
      );
      expect(legacy.highContrast, isFalse);
      expect(legacy.textScale, AppTextScale.medium);
    });

    test('all four Swiss languages are represented', () {
      expect(AppLanguage.values, containsAll([
        AppLanguage.de,
        AppLanguage.fr,
        AppLanguage.it,
        AppLanguage.en,
      ]));
    });

    test('equality distinguishes highContrast and textScale', () {
      const a = AppSettings(highContrast: true);
      const b = AppSettings();
      expect(a == b, isFalse);
      const c = AppSettings(textScale: AppTextScale.large);
      expect(c == b, isFalse);
    });
  });
}
