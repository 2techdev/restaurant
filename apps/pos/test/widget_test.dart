import 'package:flutter_test/flutter_test.dart';
import 'package:gastrocore_pos/core/utils/money.dart';

void main() {
  group('Money', () {
    test('basic arithmetic', () {
      final a = Money(1500); // 15.00
      final b = Money(2500); // 25.00
      expect((a + b).cents, 4000);
      expect((b - a).cents, 1000);
    });

    test('format', () {
      final price = Money(1550);
      expect(price.format('CHF'), 'CHF 15.50');
    });

    test('roundTo5Rappen', () {
      expect(Money(1723).roundTo5Rappen().cents, 1725);
      expect(Money(1721).roundTo5Rappen().cents, 1720);
      expect(Money(1728).roundTo5Rappen().cents, 1730);
    });

    test('tax calculation', () {
      final net = Money(1000); // 10.00
      final gross = net.addTax(8.1); // +8.1%
      expect(gross.cents, 1081);
    });
  });
}
