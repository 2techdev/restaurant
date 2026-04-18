/// Sorted calculation-pipeline primitive.
///
/// Each step represents one stage of the SambaPOS-3 adjustment pipeline
/// applied between a ticket's raw subtotal and its printable grand
/// total. Steps are ordered by [sortOrder] and then evaluated left to
/// right, so the printed receipt always shows:
///
///   Subtotal
///   - Discount   (sortOrder 100)
///   + Service    (sortOrder 200)
///   = Taxable base (Swiss: extracted from gross, shown as MwSt table)
///   = Rounding   (sortOrder 400)
///   = TOTAL
///
/// Rounding is intentionally last so the final amount is a cashier-
/// friendly value (Swiss 5-Rappen round).
library;

/// What role a step plays in the pipeline. Determines default sort and
/// how the receipt renderer formats the line.
enum CalculationKind {
  /// Subtractive adjustment applied first. `amount` is negative.
  discount,

  /// Additive adjustment applied after discount. `amount` is positive.
  /// In Switzerland the service charge is VAT-inclusive — the VAT
  /// extraction step later re-apportions MwSt across buckets to
  /// include the service gross.
  serviceCharge,

  /// Informational tax extraction. Does NOT change the total when
  /// prices are tax-inclusive (Swiss MWST model). Multiple tax
  /// steps may coexist, one per MwSt rate bracket.
  tax,

  /// Cashier rounding — in Switzerland this rounds the grand total to
  /// the nearest 5 Rappen (0.05 CHF). Signed: can be + or −.
  rounding,
}

/// Default sort order for each [CalculationKind]. Callers may override
/// per step when emitting e.g. multiple discounts in a specific order.
const Map<CalculationKind, int> kDefaultSortOrder = <CalculationKind, int>{
  CalculationKind.discount: 100,
  CalculationKind.serviceCharge: 200,
  CalculationKind.tax: 300,
  CalculationKind.rounding: 400,
};

/// Immutable pipeline step.
class CalculationStep implements Comparable<CalculationStep> {
  const CalculationStep({
    required this.kind,
    required this.label,
    required this.amount,
    int? sortOrder,
    this.percent,
    this.mwstCode,
  }) : sortOrder = sortOrder ?? -1;

  /// What this step represents.
  final CalculationKind kind;

  /// Human-facing label shown on the receipt (e.g. "Rabatt 10%",
  /// "Service 10%", "MwSt A 8.1%"). The UI is responsible for any
  /// l10n — steps just carry the final string.
  final String label;

  /// Amount in cents. Signed:
  ///   discount       → negative (reduces receivable)
  ///   serviceCharge  → positive
  ///   tax            → positive (informational only for inclusive VAT)
  ///   rounding       → signed (usually small, −4..+4 Rappen)
  final int amount;

  /// Explicit position. Smaller runs first. `-1` means "use default
  /// for `kind`" — resolved at construction via [effectiveSortOrder].
  final int sortOrder;

  /// Optional display percent (e.g. 10.0 for a 10% service charge).
  /// Purely informational — the authoritative value is [amount].
  final double? percent;

  /// For [CalculationKind.tax] steps, which MwSt bucket this line
  /// represents. Null for non-tax steps.
  final String? mwstCode;

  /// Resolve the real sort order, falling back to the kind default.
  int get effectiveSortOrder => sortOrder >= 0
      ? sortOrder
      : (kDefaultSortOrder[kind] ?? 0);

  @override
  int compareTo(CalculationStep other) =>
      effectiveSortOrder.compareTo(other.effectiveSortOrder);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CalculationStep &&
          kind == other.kind &&
          label == other.label &&
          amount == other.amount &&
          effectiveSortOrder == other.effectiveSortOrder &&
          percent == other.percent &&
          mwstCode == other.mwstCode;

  @override
  int get hashCode => Object.hash(
        kind,
        label,
        amount,
        effectiveSortOrder,
        percent,
        mwstCode,
      );

  @override
  String toString() =>
      'CalculationStep($kind, "$label", amount=$amount, '
      'sort=$effectiveSortOrder)';
}
