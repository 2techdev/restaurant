/// Immutable value object representing a monetary amount in the smallest currency
/// unit (cents/Rappen). All arithmetic is integer-based to avoid floating-point
/// rounding errors.
///
/// Example:
/// ```dart
/// final price = Money(1500);            // CHF 15.00
/// final withTax = price.addTax(8.1);   // CHF 16.22
/// final display = price.format('CHF'); // "CHF 15.00"
/// ```
library;

class Money implements Comparable<Money> {
  /// Amount in the smallest currency unit (cents / Rappen).
  final int cents;

  const Money(this.cents);

  /// Create from a double value (e.g. 15.00 -> 1500 cents).
  /// Rounds to the nearest cent to avoid floating-point drift.
  factory Money.fromDouble(double amount) {
    return Money((amount * 100).round());
  }

  /// Zero amount.
  const Money.zero() : cents = 0;

  // ---------------------------------------------------------------------------
  // Arithmetic
  // ---------------------------------------------------------------------------

  Money operator +(Money other) => Money(cents + other.cents);

  Money operator -(Money other) => Money(cents - other.cents);

  /// Multiply by an integer quantity.
  Money operator *(int quantity) => Money(cents * quantity);

  /// Multiply by an arbitrary factor (e.g. 1.5x portion).
  /// Result is rounded to the nearest cent.
  Money multiplyBy(num factor) => Money((cents * factor).round());

  /// Unary negation.
  Money operator -() => Money(-cents);

  // ---------------------------------------------------------------------------
  // Comparison
  // ---------------------------------------------------------------------------

  bool operator <(Money other) => cents < other.cents;

  bool operator >(Money other) => cents > other.cents;

  bool operator <=(Money other) => cents <= other.cents;

  bool operator >=(Money other) => cents >= other.cents;

  @override
  int compareTo(Money other) => cents.compareTo(other.cents);

  bool get isZero => cents == 0;

  bool get isPositive => cents > 0;

  bool get isNegative => cents < 0;

  // ---------------------------------------------------------------------------
  // Display
  // ---------------------------------------------------------------------------

  /// Format with currency code: "CHF 15.00".
  String format(String currencyCode) {
    return '$currencyCode ${formatCompact()}';
  }

  /// Format without currency code: "15.00".
  String formatCompact() {
    final isNeg = cents < 0;
    final absCents = cents.abs();
    final whole = absCents ~/ 100;
    final fractional = (absCents % 100).toString().padLeft(2, '0');
    return '${isNeg ? '-' : ''}$whole.$fractional';
  }

  /// Swiss de-CH number format with apostrophe-grouped thousands:
  /// 1234567 cents -> "12'345.67". Keeps the receipt column aligned for
  /// fine-dining totals that often cross CHF 1'000.
  String formatSwiss() {
    final isNeg = cents < 0;
    final absCents = cents.abs();
    final whole = (absCents ~/ 100).toString();
    final fractional = (absCents % 100).toString().padLeft(2, '0');

    // Group digits in threes from the right with "'" separator.
    final buf = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) buf.write("'");
      buf.write(whole[i]);
    }
    return '${isNeg ? '-' : ''}$buf.$fractional';
  }

  /// Localised compact format. Currently switches only the thousands
  /// separator — de/fr/it-CH use "'", en uses ",", tr uses ".".
  String formatForLocale(String languageCode) {
    if (languageCode == 'de' || languageCode == 'fr' || languageCode == 'it') {
      return formatSwiss();
    }
    final isNeg = cents < 0;
    final absCents = cents.abs();
    final whole = (absCents ~/ 100).toString();
    final fractional = (absCents % 100).toString().padLeft(2, '0');
    final sep = languageCode == 'tr' ? '.' : ',';
    final decimal = languageCode == 'tr' ? ',' : '.';
    final buf = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) buf.write(sep);
      buf.write(whole[i]);
    }
    return '${isNeg ? '-' : ''}$buf$decimal$fractional';
  }

  /// Convert to double for display or interop only. Prefer [cents] for logic.
  double toDouble() => cents / 100.0;

  // ---------------------------------------------------------------------------
  // Tax helpers
  // ---------------------------------------------------------------------------

  /// Add tax on top of the current (net) amount.
  /// [rate] is a percentage, e.g. 8.1 for 8.1% Swiss VAT.
  Money addTax(double rate) {
    final taxCents = (cents * rate / 100).round();
    return Money(cents + taxCents);
  }

  /// Extract the tax portion from a tax-inclusive (gross) price.
  /// [rate] is a percentage, e.g. 8.1 for 8.1% Swiss VAT.
  /// Formula: tax = gross - gross / (1 + rate/100)
  Money extractTax(double rate) {
    final divisor = 1.0 + rate / 100.0;
    final netCents = (cents / divisor).round();
    return Money(cents - netCents);
  }

  /// Net amount from a gross (tax-inclusive) price.
  Money netFromGross(double rate) {
    final tax = extractTax(rate);
    return this - tax;
  }

  // ---------------------------------------------------------------------------
  // Swiss rounding
  // ---------------------------------------------------------------------------

  /// Round to the nearest 5 Rappen (0.05 CHF) for Swiss cash payments.
  /// 1.42 -> 1.40, 1.43 -> 1.45, 1.47 -> 1.45, 1.48 -> 1.50.
  Money roundTo5Rappen() {
    final remainder = cents % 5;
    if (remainder == 0) return this;

    // Standard rounding: >= 3 rounds up, < 3 rounds down.
    final rounded =
        remainder >= 3 ? cents + (5 - remainder) : cents - remainder;
    return Money(rounded);
  }

  // ---------------------------------------------------------------------------
  // Utility
  // ---------------------------------------------------------------------------

  /// Split the amount evenly among [parts], distributing remainder cents
  /// to the first portions.
  List<Money> split(int parts) {
    assert(parts > 0, 'Cannot split into zero or negative parts');
    final base = cents ~/ parts;
    final remainder = cents % parts;
    return List.generate(parts, (i) {
      return Money(i < remainder ? base + 1 : base);
    });
  }

  /// Returns the larger of this and [other].
  Money max(Money other) => cents >= other.cents ? this : other;

  /// Returns the smaller of this and [other].
  Money min(Money other) => cents <= other.cents ? this : other;

  /// Clamp to a range.
  Money clamp(Money lower, Money upper) {
    if (cents < lower.cents) return lower;
    if (cents > upper.cents) return upper;
    return this;
  }

  // ---------------------------------------------------------------------------
  // Equality & hashCode
  // ---------------------------------------------------------------------------

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Money && other.cents == cents);

  @override
  int get hashCode => cents.hashCode;

  @override
  String toString() => 'Money($cents)';
}
