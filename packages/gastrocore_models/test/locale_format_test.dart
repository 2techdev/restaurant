/// Tests for the locale-aware Money and date formatters used on receipts
/// and in the UI.
library;

import 'package:gastrocore_models/gastrocore_models.dart';
import 'package:test/test.dart';

void main() {
  group('Money locale formatting', () {
    test('Swiss apostrophe grouping', () {
      expect(const Money(123456789).formatSwiss(), "1'234'567.89");
      expect(const Money(150000).formatSwiss(), "1'500.00");
      expect(const Money(50).formatSwiss(), "0.50");
      expect(const Money(-150000).formatSwiss(), "-1'500.00");
    });

    test('formatForLocale — de/fr/it use apostrophe + dot', () {
      for (final code in ['de', 'fr', 'it']) {
        expect(const Money(123456).formatForLocale(code), "1'234.56",
            reason: code);
      }
    });

    test('formatForLocale — en uses comma + dot', () {
      expect(const Money(123456).formatForLocale('en'), '1,234.56');
    });

    test('formatForLocale — tr uses dot + comma', () {
      expect(const Money(123456).formatForLocale('tr'), '1.234,56');
    });

    test('5 Rappen rounding preserved', () {
      expect(const Money(142).roundTo5Rappen().cents, 140);
      expect(const Money(143).roundTo5Rappen().cents, 145);
      expect(const Money(148).roundTo5Rappen().cents, 150);
    });
  });

  group('Date formatting', () {
    final dt = DateTime(2026, 4, 17, 14, 5);

    test('shortDate per locale', () {
      expect(formatDate(dt, 'de'), '17.04.2026');
      expect(formatDate(dt, 'tr'), '17.04.2026');
      expect(formatDate(dt, 'fr'), '17.04.2026');
      expect(formatDate(dt, 'it'), '17.04.2026');
      expect(formatDate(dt, 'en'), '2026-04-17');
    });

    test('longDate per locale', () {
      expect(formatDate(dt, 'de', DateStyle.longDate), '17. April 2026');
      expect(formatDate(dt, 'tr', DateStyle.longDate), '17 Nisan 2026');
      expect(formatDate(dt, 'en', DateStyle.longDate), 'April 17, 2026');
      expect(formatDate(dt, 'fr', DateStyle.longDate), '17 avril 2026');
      expect(formatDate(dt, 'it', DateStyle.longDate), '17 aprile 2026');
    });

    test('time24 identical across locales', () {
      expect(formatDate(dt, 'de', DateStyle.time24), '14:05');
      expect(formatDate(dt, 'tr', DateStyle.time24), '14:05');
      expect(formatDate(dt, 'en', DateStyle.time24), '14:05');
    });

    test('dateTime combines date + time', () {
      expect(formatDate(dt, 'de', DateStyle.dateTime), '17.04.2026 14:05');
      expect(formatDate(dt, 'en', DateStyle.dateTime), '2026-04-17 14:05');
    });
  });
}
