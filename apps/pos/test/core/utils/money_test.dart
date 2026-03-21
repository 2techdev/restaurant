/// Unit tests for the Money value object.
///
/// Covers arithmetic, formatting, tax helpers, 5-Rappen rounding, split,
/// and edge cases.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/core/utils/money.dart';

void main() {
  // =========================================================================
  // Construction
  // =========================================================================

  group('construction', () {
    test('Money(1500) stores 1500 cents', () {
      const m = Money(1500);
      expect(m.cents, 1500);
    });

    test('Money.fromDouble(15.00) equals Money(1500)', () {
      final m = Money.fromDouble(15.00);
      expect(m.cents, 1500);
    });

    test('Money.fromDouble rounds to nearest cent', () {
      final m = Money.fromDouble(15.005);
      expect(m.cents, 1501); // rounds .005 up to 1
    });

    test('Money.fromDouble with negative value', () {
      final m = Money.fromDouble(-7.50);
      expect(m.cents, -750);
    });

    test('Money.zero() has 0 cents', () {
      const m = Money.zero();
      expect(m.cents, 0);
      expect(m.isZero, true);
    });
  });

  // =========================================================================
  // Arithmetic
  // =========================================================================

  group('addition', () {
    test('adds two positive amounts', () {
      const a = Money(1500);
      const b = Money(750);
      expect((a + b).cents, 2250);
    });

    test('adds zero', () {
      const a = Money(1500);
      const b = Money.zero();
      expect((a + b).cents, 1500);
    });

    test('adds negative (effectively subtracts)', () {
      const a = Money(1500);
      const b = Money(-500);
      expect((a + b).cents, 1000);
    });
  });

  group('subtraction', () {
    test('subtracts smaller from larger', () {
      const a = Money(2000);
      const b = Money(750);
      expect((a - b).cents, 1250);
    });

    test('subtracting larger yields negative', () {
      const a = Money(500);
      const b = Money(750);
      expect((a - b).cents, -250);
      expect((a - b).isNegative, true);
    });

    test('subtracting zero gives same amount', () {
      const a = Money(1500);
      const b = Money.zero();
      expect((a - b).cents, 1500);
    });
  });

  group('multiplication', () {
    test('multiplies by integer quantity', () {
      const price = Money(1500);
      expect((price * 3).cents, 4500);
    });

    test('multiplies by 0 gives zero', () {
      const price = Money(1500);
      expect((price * 0).cents, 0);
    });

    test('multiplies by 1 gives same amount', () {
      const price = Money(1500);
      expect((price * 1).cents, 1500);
    });

    test('multiplyBy with fractional factor', () {
      const price = Money(1000);
      expect(price.multiplyBy(1.5).cents, 1500);
    });

    test('multiplyBy rounds to nearest cent', () {
      const price = Money(1000);
      // 1000 * 0.33 = 330
      expect(price.multiplyBy(0.33).cents, 330);
    });

    test('multiplyBy with 0.1 factor', () {
      const price = Money(1999);
      // 1999 * 0.1 = 199.9 -> rounds to 200
      expect(price.multiplyBy(0.1).cents, 200);
    });
  });

  group('unary negation', () {
    test('negates positive', () {
      const m = Money(1500);
      expect((-m).cents, -1500);
    });

    test('negates negative', () {
      const m = Money(-750);
      expect((-m).cents, 750);
    });

    test('negates zero', () {
      const m = Money.zero();
      expect((-m).cents, 0);
    });
  });

  // =========================================================================
  // Comparison
  // =========================================================================

  group('comparison', () {
    test('less than', () {
      expect(const Money(100) < const Money(200), true);
      expect(const Money(200) < const Money(100), false);
    });

    test('greater than', () {
      expect(const Money(200) > const Money(100), true);
    });

    test('less than or equal', () {
      expect(const Money(100) <= const Money(100), true);
      expect(const Money(99) <= const Money(100), true);
    });

    test('greater than or equal', () {
      expect(const Money(100) >= const Money(100), true);
      expect(const Money(101) >= const Money(100), true);
    });

    test('compareTo', () {
      expect(const Money(100).compareTo(const Money(200)), isNegative);
      expect(const Money(200).compareTo(const Money(100)), isPositive);
      expect(const Money(100).compareTo(const Money(100)), isZero);
    });

    test('isZero, isPositive, isNegative', () {
      expect(const Money.zero().isZero, true);
      expect(const Money(100).isPositive, true);
      expect(const Money(-50).isNegative, true);
      expect(const Money(100).isZero, false);
      expect(const Money(100).isNegative, false);
    });
  });

  // =========================================================================
  // Formatting
  // =========================================================================

  group('format display', () {
    test('format with currency code: CHF 15.00', () {
      const m = Money(1500);
      expect(m.format('CHF'), 'CHF 15.00');
    });

    test('format with EUR', () {
      const m = Money(1250);
      expect(m.format('EUR'), 'EUR 12.50');
    });

    test('formatCompact: 15.00', () {
      const m = Money(1500);
      expect(m.formatCompact(), '15.00');
    });

    test('formatCompact with cents: 12.05', () {
      const m = Money(1205);
      expect(m.formatCompact(), '12.05');
    });

    test('format zero: CHF 0.00', () {
      const m = Money.zero();
      expect(m.format('CHF'), 'CHF 0.00');
    });

    test('format negative: -5.50', () {
      const m = Money(-550);
      expect(m.formatCompact(), '-5.50');
    });

    test('format large amount: 10000.00', () {
      const m = Money(1000000);
      expect(m.formatCompact(), '10000.00');
    });

    test('toDouble converts back', () {
      const m = Money(1550);
      expect(m.toDouble(), closeTo(15.50, 0.001));
    });
  });

  // =========================================================================
  // Tax helpers
  // =========================================================================

  group('tax extraction (gross to net)', () {
    test('extractTax at 8.1% from CHF 25.00', () {
      const gross = Money(2500);
      final tax = gross.extractTax(8.1);
      // tax = 2500 - round(2500 / 1.081)
      // = 2500 - round(2312.67) = 2500 - 2313 = 187
      expect(tax.cents, 187);
    });

    test('extractTax at 0% gives zero', () {
      const gross = Money(1000);
      expect(gross.extractTax(0).cents, 0);
    });

    test('netFromGross returns net amount', () {
      const gross = Money(2500);
      final net = gross.netFromGross(8.1);
      // net = 2500 - 187 = 2313
      expect(net.cents, 2313);
    });

    test('addTax at 8.1% on CHF 23.13', () {
      const net = Money(2313);
      final gross = net.addTax(8.1);
      // tax = round(2313 * 8.1 / 100) = round(187.353) = 187
      // gross = 2313 + 187 = 2500
      expect(gross.cents, 2500);
    });

    test('addTax at 19% on EUR 10.00', () {
      const net = Money(1000);
      final gross = net.addTax(19);
      // tax = round(1000 * 19/100) = 190
      expect(gross.cents, 1190);
    });

    test('extractTax at 2.6% (Swiss takeaway)', () {
      const gross = Money(2500);
      final tax = gross.extractTax(2.6);
      // net = round(2500 / 1.026) = round(2436.64) = 2437
      // tax = 2500 - 2437 = 63
      expect(tax.cents, 63);
    });
  });

  // =========================================================================
  // 5-Rappen rounding
  // =========================================================================

  group('5-Rappen rounding', () {
    test('142 -> 140', () {
      expect(const Money(142).roundTo5Rappen().cents, 140);
    });

    test('143 -> 145', () {
      expect(const Money(143).roundTo5Rappen().cents, 145);
    });

    test('147 -> 145', () {
      expect(const Money(147).roundTo5Rappen().cents, 145);
    });

    test('148 -> 150', () {
      expect(const Money(148).roundTo5Rappen().cents, 150);
    });

    test('145 -> 145 (no change)', () {
      expect(const Money(145).roundTo5Rappen().cents, 145);
    });

    test('150 -> 150 (no change)', () {
      expect(const Money(150).roundTo5Rappen().cents, 150);
    });

    test('0 -> 0', () {
      expect(const Money(0).roundTo5Rappen().cents, 0);
    });

    test('1 -> 0', () {
      expect(const Money(1).roundTo5Rappen().cents, 0);
    });

    test('2 -> 0', () {
      expect(const Money(2).roundTo5Rappen().cents, 0);
    });

    test('3 -> 5', () {
      expect(const Money(3).roundTo5Rappen().cents, 5);
    });

    test('4 -> 5', () {
      expect(const Money(4).roundTo5Rappen().cents, 5);
    });

    test('large amount: 99999 -> 100000', () {
      // 99999 % 5 = 4 -> 4 >= 3 -> rounds up to 100000
      expect(const Money(99999).roundTo5Rappen().cents, 100000);
    });
  });

  // =========================================================================
  // Split (divide among N people)
  // =========================================================================

  group('split', () {
    test('splits evenly when divisible', () {
      const total = Money(3000);
      final parts = total.split(3);
      expect(parts.length, 3);
      expect(parts.every((p) => p.cents == 1000), true);
    });

    test('distributes remainder to first portions', () {
      const total = Money(1000);
      final parts = total.split(3);
      // 1000 / 3 = 333 remainder 1
      // parts: [334, 333, 333]
      expect(parts.length, 3);
      expect(parts[0].cents, 334);
      expect(parts[1].cents, 333);
      expect(parts[2].cents, 333);
      // Sum should equal original.
      final sum = parts.fold<int>(0, (s, p) => s + p.cents);
      expect(sum, 1000);
    });

    test('split 1 part returns the original', () {
      const total = Money(2500);
      final parts = total.split(1);
      expect(parts.length, 1);
      expect(parts[0].cents, 2500);
    });

    test('split 2 people on odd amount', () {
      const total = Money(1001);
      final parts = total.split(2);
      // 1001 / 2 = 500 remainder 1
      expect(parts[0].cents, 501);
      expect(parts[1].cents, 500);
    });

    test('split zero amount among 3', () {
      const total = Money.zero();
      final parts = total.split(3);
      expect(parts.every((p) => p.cents == 0), true);
    });

    test('split large remainder distributes correctly', () {
      const total = Money(1004);
      final parts = total.split(5);
      // 1004 / 5 = 200 remainder 4
      // First 4 get 201, last gets 200
      expect(parts[0].cents, 201);
      expect(parts[1].cents, 201);
      expect(parts[2].cents, 201);
      expect(parts[3].cents, 201);
      expect(parts[4].cents, 200);
      final sum = parts.fold<int>(0, (s, p) => s + p.cents);
      expect(sum, 1004);
    });
  });

  // =========================================================================
  // Utility: max, min, clamp
  // =========================================================================

  group('utility', () {
    test('max returns larger', () {
      const a = Money(100);
      const b = Money(200);
      expect(a.max(b).cents, 200);
      expect(b.max(a).cents, 200);
    });

    test('min returns smaller', () {
      const a = Money(100);
      const b = Money(200);
      expect(a.min(b).cents, 100);
      expect(b.min(a).cents, 100);
    });

    test('clamp within range', () {
      const value = Money(150);
      expect(value.clamp(const Money(100), const Money(200)).cents, 150);
    });

    test('clamp below lower bound', () {
      const value = Money(50);
      expect(value.clamp(const Money(100), const Money(200)).cents, 100);
    });

    test('clamp above upper bound', () {
      const value = Money(300);
      expect(value.clamp(const Money(100), const Money(200)).cents, 200);
    });
  });

  // =========================================================================
  // Edge cases
  // =========================================================================

  group('edge cases', () {
    test('zero: all operations on zero', () {
      const z = Money.zero();
      expect((z + z).cents, 0);
      expect((z - z).cents, 0);
      expect((z * 5).cents, 0);
      expect(z.roundTo5Rappen().cents, 0);
      expect(z.extractTax(8.1).cents, 0);
      expect(z.format('CHF'), 'CHF 0.00');
    });

    test('negative amount formatting', () {
      const m = Money(-1550);
      expect(m.format('CHF'), 'CHF -15.50');
      expect(m.isNegative, true);
    });

    test('very small amount (1 cent)', () {
      const m = Money(1);
      expect(m.formatCompact(), '0.01');
      expect(m.roundTo5Rappen().cents, 0);
      expect(m.isPositive, true);
    });

    test('very large amount', () {
      const m = Money(99999999); // CHF 999,999.99
      expect(m.formatCompact(), '999999.99');
      // 99999999 % 5 = 4, which >= 3, rounds up to 100000000
      expect(m.roundTo5Rappen().cents, 100000000);
    });
  });

  // =========================================================================
  // Equality & hashCode
  // =========================================================================

  group('equality', () {
    test('same cents are equal', () {
      expect(const Money(1500), const Money(1500));
    });

    test('different cents are not equal', () {
      expect(const Money(1500) == const Money(1501), false);
    });

    test('hashCode matches for equal values', () {
      expect(const Money(1500).hashCode, const Money(1500).hashCode);
    });

    test('toString', () {
      expect(const Money(1500).toString(), 'Money(1500)');
    });
  });
}
