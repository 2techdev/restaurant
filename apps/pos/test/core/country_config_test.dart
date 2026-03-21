import 'package:flutter_test/flutter_test.dart';
import 'package:gastrocore_pos/core/country_config.dart';

void main() {
  group('CountryConfig — Switzerland', () {
    test('has correct ISO code', () {
      expect(CountryConfig.ch.isoCode, equals('CH'));
    });

    test('has correct currency', () {
      expect(CountryConfig.ch.currency, equals('CHF'));
    });

    test('does not require TSE', () {
      expect(CountryConfig.ch.requiresTse, isFalse);
    });

    test('requires QR-Bill', () {
      expect(CountryConfig.ch.requiresQrBill, isTrue);
    });

    test('has standard rate 8.1%', () {
      expect(CountryConfig.ch.standardRate, equals(8.1));
    });

    test('has reduced rate 2.6%', () {
      expect(CountryConfig.ch.reducedRate, equals(2.6));
    });

    test('has accommodation rate 3.8%', () {
      expect(CountryConfig.ch.taxSettings.accommodationRate, equals(3.8));
    });

    test('uses Rappen rounding', () {
      expect(CountryConfig.ch.taxSettings.rappenRounding, isTrue);
    });

    test('tax label is MWST', () {
      expect(CountryConfig.ch.taxLabel, equals('MWST'));
    });
  });

  group('CountryConfig — Germany', () {
    test('has correct ISO code', () {
      expect(CountryConfig.de.isoCode, equals('DE'));
    });

    test('has correct currency', () {
      expect(CountryConfig.de.currency, equals('EUR'));
    });

    test('requires TSE', () {
      expect(CountryConfig.de.requiresTse, isTrue);
    });

    test('does not require QR-Bill', () {
      expect(CountryConfig.de.requiresQrBill, isFalse);
    });

    test('has standard rate 19%', () {
      expect(CountryConfig.de.standardRate, equals(19.0));
    });

    test('has reduced rate 7%', () {
      expect(CountryConfig.de.reducedRate, equals(7.0));
    });

    test('does not use Rappen rounding', () {
      expect(CountryConfig.de.taxSettings.rappenRounding, isFalse);
    });

    test('tax label is MwSt', () {
      expect(CountryConfig.de.taxLabel, equals('MwSt'));
    });
  });

  group('CountryConfig.forCode', () {
    test('CH returns Swiss config', () {
      expect(CountryConfig.forCode('CH').isoCode, equals('CH'));
      expect(CountryConfig.forCode('ch').isoCode, equals('CH'));
    });

    test('DE returns German config', () {
      expect(CountryConfig.forCode('DE').isoCode, equals('DE'));
      expect(CountryConfig.forCode('de').isoCode, equals('DE'));
    });

    test('unknown code defaults to CH', () {
      expect(CountryConfig.forCode('US').isoCode, equals('CH'));
      expect(CountryConfig.forCode('').isoCode, equals('CH'));
    });
  });
}
