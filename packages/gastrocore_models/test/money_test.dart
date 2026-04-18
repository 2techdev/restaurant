import 'package:gastrocore_models/gastrocore_models.dart';
import 'package:test/test.dart';

void main() {
  group('Money', () {
    test('integer construction preserves cents', () {
      expect(const Money(1500).cents, 1500);
      expect(const Money.zero().cents, 0);
    });

    test('fromDouble rounds to nearest cent', () {
      expect(Money.fromDouble(15.00).cents, 1500);
      expect(Money.fromDouble(15.005).cents, 1501);
      expect(Money.fromDouble(-1.23).cents, -123);
    });

    test('addition, subtraction, multiplication are integer exact', () {
      const a = Money(1000);
      const b = Money(250);
      expect((a + b).cents, 1250);
      expect((a - b).cents, 750);
      expect((a * 3).cents, 3000);
      expect(a.multiplyBy(1.5).cents, 1500);
    });

    test('formatCompact pads and signs correctly', () {
      expect(const Money(1500).formatCompact(), '15.00');
      expect(const Money(305).formatCompact(), '3.05');
      expect(const Money(-42).formatCompact(), '-0.42');
      expect(const Money(1500).format('CHF'), 'CHF 15.00');
    });

    test('Swiss 5-Rappen rounding matches reference cases', () {
      // 1.42 -> 1.40, 1.43 -> 1.45, 1.47 -> 1.45, 1.48 -> 1.50
      expect(const Money(142).roundTo5Rappen().cents, 140);
      expect(const Money(143).roundTo5Rappen().cents, 145);
      expect(const Money(147).roundTo5Rappen().cents, 145);
      expect(const Money(148).roundTo5Rappen().cents, 150);
      expect(const Money(150).roundTo5Rappen().cents, 150);
    });

    test('addTax / extractTax round-trip is exact within rounding', () {
      const net = Money(10000); // CHF 100.00
      final gross = net.addTax(8.1); // +8.10 -> 10810
      expect(gross.cents, 10810);
      final tax = gross.extractTax(8.1);
      expect(tax.cents, 810);
      expect(gross.netFromGross(8.1).cents, 10000);
    });

    test('split distributes remainder to first portions', () {
      final parts = const Money(1001).split(3);
      expect(parts.map((m) => m.cents).toList(), [334, 334, 333]);
      expect(parts.fold<int>(0, (sum, m) => sum + m.cents), 1001);
    });

    test('equality is by value', () {
      expect(const Money(500) == const Money(500), isTrue);
      expect(const Money(500) == const Money(501), isFalse);
      expect(const Money(500).hashCode, const Money(500).hashCode);
    });
  });
}
