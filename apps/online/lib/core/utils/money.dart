/// Monetary value in smallest currency unit (Rappen/cents).
/// Mirrors apps/pos/lib/core/utils/money.dart but without POS-specific deps.
library;

class Money implements Comparable<Money> {
  final int cents;
  const Money(this.cents);

  factory Money.fromDouble(double amount) => Money((amount * 100).round());
  const Money.zero() : cents = 0;

  Money operator +(Money other) => Money(cents + other.cents);
  Money operator -(Money other) => Money(cents - other.cents);
  Money operator *(int quantity) => Money(cents * quantity);
  Money multiplyBy(num factor) => Money((cents * factor).round());
  Money operator -() => Money(-cents);

  bool operator <(Money other) => cents < other.cents;
  bool operator >(Money other) => cents > other.cents;
  bool operator <=(Money other) => cents <= other.cents;
  bool operator >=(Money other) => cents >= other.cents;
  @override
  int compareTo(Money other) => cents.compareTo(other.cents);

  bool get isZero => cents == 0;
  bool get isPositive => cents > 0;
  bool get isNegative => cents < 0;

  /// Format as "CHF 15.00".
  String format([String currencyCode = 'CHF']) =>
      '$currencyCode ${formatCompact()}';

  /// Format as "15.00".
  String formatCompact() {
    final isNeg = cents < 0;
    final abs = cents.abs();
    final whole = abs ~/ 100;
    final frac = (abs % 100).toString().padLeft(2, '0');
    return '${isNeg ? '-' : ''}$whole.$frac';
  }

  double toDouble() => cents / 100.0;

  /// Add tax on top of net amount. [rate] in percent, e.g. 8.1.
  Money addTax(double rate) {
    final taxCents = (cents * rate / 100).round();
    return Money(cents + taxCents);
  }

  /// Extract tax portion from gross (tax-inclusive) price.
  Money extractTax(double rate) {
    final divisor = 1.0 + rate / 100.0;
    final netCents = (cents / divisor).round();
    return Money(cents - netCents);
  }

  /// Net amount from gross (tax-inclusive) price.
  Money netFromGross(double rate) => this - extractTax(rate);

  /// Round to nearest 5 Rappen (Swiss cash rounding).
  Money roundTo5Rappen() {
    final remainder = cents % 5;
    if (remainder == 0) return this;
    final rounded =
        remainder >= 3 ? cents + (5 - remainder) : cents - remainder;
    return Money(rounded);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Money && other.cents == cents);
  @override
  int get hashCode => cents.hashCode;
  @override
  String toString() => 'Money($cents)';
}

/// Swiss VAT rates.
abstract final class SwissVat {
  /// Standard rate — dine-in food & beverages.
  static const double standard = 8.1;

  /// Reduced rate — food/drinks to go (takeaway).
  static const double reduced = 2.6;
}
