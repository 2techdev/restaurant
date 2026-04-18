/// Sorted calculation pipeline — applies Discount → Service → Tax →
/// Rounding in SambaPOS-3 order and emits the steps a receipt should
/// print.
///
/// Swiss context the pipeline embeds:
///   * Prices are VAT-inclusive (Bruttopreise). Tax steps extract MwSt
///     from the final gross per bucket; they never change the total.
///   * 5-Rappen rounding on the grand total is standard — controlled
///     by [PipelineInput.applyRounding] (default true).
///   * Service charge, when enabled, is itself VAT-inclusive, so the
///     apportion step distributes it across existing MwSt buckets
///     before tax extraction runs.
///
/// The pipeline is deterministic and pure — no provider or tenant
/// access. Feed it the ticket-level aggregates and receive a
/// structured [PipelineResult]. Callers decide how to render it.
library;

import 'package:gastrocore_pos/features/orders/domain/calculations/calculation_step.dart';

/// Pre-computed per-MwSt-bucket gross totals coming in from the line
/// items. Keys are MwSt code letters ('A', 'B', 'C'); values are
/// VAT-inclusive cents.
typedef MwStBuckets = Map<String, int>;

/// Input contract for [runCalculationPipeline].
class PipelineInput {
  const PipelineInput({
    required this.subtotalByMwst,
    this.discountAmount = 0,
    this.discountLabel,
    this.discountPercent,
    this.serviceAmount = 0,
    this.serviceLabel,
    this.servicePercent,
    this.applyRounding = true,
    this.mwstRateByCode = _defaultRates,
  });

  /// Gross (VAT-inclusive) amount per MwSt code before any
  /// pipeline adjustments. The order of codes is irrelevant — the
  /// pipeline sorts deterministically on output.
  final MwStBuckets subtotalByMwst;

  /// Already-computed discount amount in cents. Non-negative — the
  /// pipeline emits it with a negative sign.
  final int discountAmount;

  /// Display label for the discount line, e.g. "Rabatt 10%".
  final String? discountLabel;

  /// Optional display percent for the discount.
  final double? discountPercent;

  /// Service-charge amount in cents. Zero disables the step.
  final int serviceAmount;

  /// Display label for the service line.
  final String? serviceLabel;

  /// Optional display percent for the service charge.
  final double? servicePercent;

  /// When true (default), a rounding step nudges the grand total to
  /// the nearest 5 Rappen (Swiss convention).
  final bool applyRounding;

  /// MwSt code → rate percent. Used to extract the tax amount from
  /// each bucket's post-apportion gross. Defaults to the Swiss
  /// standard rates effective 01.01.2024.
  final Map<String, double> mwstRateByCode;

  /// Sum of all input buckets — convenience for callers.
  int get grossItemsTotal =>
      subtotalByMwst.values.fold<int>(0, (s, v) => s + v);
}

const Map<String, double> _defaultRates = <String, double>{
  'A': 8.1, // Normalsatz: restaurant / bar
  'B': 2.6, // Reduzierter: takeaway food
  'C': 3.8, // Sondersatz: accommodation
};

/// Output contract: ordered steps + reconciled grand total + MwSt
/// breakdown for the tax table on the receipt.
class PipelineResult {
  const PipelineResult({
    required this.steps,
    required this.grandTotal,
    required this.taxableBaseByCode,
    required this.taxByCode,
  });

  /// All emitted steps, already sorted by `sortOrder`. May be empty
  /// when no adjustments apply.
  final List<CalculationStep> steps;

  /// The receivable amount after every step — i.e. subtotal
  /// − discount + service + rounding. Tax extraction is informational
  /// and never alters this number.
  final int grandTotal;

  /// Per-MwSt-code gross taxable base after discount + service
  /// apportionment. Keys match the input codes.
  final MwStBuckets taxableBaseByCode;

  /// Per-MwSt-code extracted tax (informational).
  final MwStBuckets taxByCode;
}

/// Run the pipeline.
///
/// The returned steps are sorted; the caller iterates them in order
/// and prints a line per step. The tax breakdown is also returned
/// separately so an ESC/POS MwSt table can be rendered.
PipelineResult runCalculationPipeline(PipelineInput input) {
  // Working buckets — mutate as we apportion.
  final buckets = Map<String, int>.from(input.subtotalByMwst);
  final codes = buckets.keys.toList()..sort();

  final steps = <CalculationStep>[];

  // --- Step 1: Discount -----------------------------------------------
  if (input.discountAmount > 0) {
    _apportion(
      buckets: buckets,
      codes: codes,
      delta: -input.discountAmount,
    );
    steps.add(
      CalculationStep(
        kind: CalculationKind.discount,
        label: input.discountLabel ?? 'Rabatt',
        amount: -input.discountAmount,
        percent: input.discountPercent,
      ),
    );
  }

  // --- Step 2: Service charge (VAT-inclusive in CH) ------------------
  if (input.serviceAmount > 0) {
    _apportion(
      buckets: buckets,
      codes: codes,
      delta: input.serviceAmount,
    );
    steps.add(
      CalculationStep(
        kind: CalculationKind.serviceCharge,
        label: input.serviceLabel ?? 'Service',
        amount: input.serviceAmount,
        percent: input.servicePercent,
      ),
    );
  }

  // Running gross total after discount + service, pre-rounding.
  int gross = buckets.values.fold<int>(0, (s, v) => s + v);

  // --- Step 3: Tax extraction (informational, does not change total) -
  final taxableBase = <String, int>{};
  final taxByCode = <String, int>{};
  for (final code in codes) {
    final bucketGross = buckets[code] ?? 0;
    if (bucketGross <= 0) continue;
    final rate = input.mwstRateByCode[code];
    if (rate == null || rate <= 0) {
      taxableBase[code] = bucketGross;
      taxByCode[code] = 0;
      continue;
    }
    // Tax-inclusive extraction: tax = gross × rate / (100 + rate).
    final tax = (bucketGross * rate / (100 + rate)).round();
    taxableBase[code] = bucketGross;
    taxByCode[code] = tax;
    steps.add(
      CalculationStep(
        kind: CalculationKind.tax,
        label: 'MwSt $code ${rate.toStringAsFixed(1)}%',
        amount: tax,
        percent: rate,
        mwstCode: code,
      ),
    );
  }

  // --- Step 4: 5-Rappen rounding on the grand total ------------------
  if (input.applyRounding) {
    final rounded = _roundTo5Rappen(gross);
    final delta = rounded - gross;
    if (delta != 0) {
      steps.add(
        CalculationStep(
          kind: CalculationKind.rounding,
          label: 'Rundung',
          amount: delta,
        ),
      );
      gross = rounded;
    }
  }

  steps.sort();

  return PipelineResult(
    steps: List.unmodifiable(steps),
    grandTotal: gross,
    taxableBaseByCode: Map.unmodifiable(taxableBase),
    taxByCode: Map.unmodifiable(taxByCode),
  );
}

/// Pro-rata distribute `delta` (signed cents) across the buckets, in
/// code order, floor-rounding each share and letting the last bucket
/// absorb the accumulated remainder so the total reconciles exactly.
void _apportion({
  required Map<String, int> buckets,
  required List<String> codes,
  required int delta,
}) {
  if (delta == 0 || codes.isEmpty) return;
  final total = buckets.values.fold<int>(0, (s, v) => s + v);
  if (total <= 0) return;

  var assigned = 0;
  for (var i = 0; i < codes.length; i++) {
    final code = codes[i];
    final share = buckets[code] ?? 0;
    int addend;
    if (i == codes.length - 1) {
      addend = delta - assigned; // absorb remainder
    } else {
      // Proportional share, rounded toward zero to keep |Σ| ≤ |delta|.
      addend = (share * delta / total).truncate();
      assigned += addend;
    }
    buckets[code] = share + addend;
  }
}

/// Swiss 5-Rappen rounding on a cents value.
///
/// Rounds to the nearest multiple of 5. Half-up at 2.5 Rappen so
/// 123.475 → 123.50 rather than 123.45.
int _roundTo5Rappen(int cents) {
  final remainder = cents % 5;
  if (remainder == 0) return cents;
  if (remainder >= 3) return cents + (5 - remainder);
  return cents - remainder;
}
