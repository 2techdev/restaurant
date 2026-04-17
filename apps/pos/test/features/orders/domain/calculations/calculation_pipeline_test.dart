/// Tests for [runCalculationPipeline].
///
/// Covers the SambaPOS-parity ordering (Discount → ServiceCharge →
/// Tax → Rounding) and the Swiss-specific behaviours:
///
///   * MWST is extracted tax-inclusively from each bucket's
///     *post-adjustment* gross.
///   * 5-Rappen cash rounding is applied to the final grand total.
///   * Discount and service are apportioned proportionally across
///     buckets with the last bucket absorbing the rounding remainder.
///
/// Edge cases explicitly requested by the user:
///   - free item (zero gross)
///   - discount larger than subtotal
///   - tax-exempt modifier (rate = 0)
///   - split-check (apportion must reconcile across split buckets)
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/features/orders/domain/calculations/calculation_pipeline.dart';
import 'package:gastrocore_pos/features/orders/domain/calculations/calculation_step.dart';

void main() {
  group('runCalculationPipeline — ordering', () {
    test('emits steps sorted by default sortOrder (100/200/300/400)', () {
      // Pick inputs so the final gross needs 5-Rappen rounding (10000
      // − 503 + 952 = 10449 → 10450), exercising every stage.
      final result = runCalculationPipeline(
        const PipelineInput(
          subtotalByMwst: {'A': 10000},
          discountAmount: 503,
          discountLabel: 'Rabatt 5%',
          serviceAmount: 952,
          serviceLabel: 'Service 10%',
        ),
      );

      final kinds = result.steps.map((s) => s.kind).toList();
      expect(kinds.first, CalculationKind.discount);
      expect(kinds[1], CalculationKind.serviceCharge);
      expect(kinds[2], CalculationKind.tax);
      expect(kinds.last, CalculationKind.rounding);
    });

    test('omits missing steps (no discount, no service, no rounding)', () {
      final result = runCalculationPipeline(
        const PipelineInput(
          subtotalByMwst: {'A': 10000},
          applyRounding: false,
        ),
      );

      final kinds = result.steps.map((s) => s.kind).toSet();
      expect(kinds, {CalculationKind.tax});
    });
  });

  group('runCalculationPipeline — Swiss MWST extraction', () {
    test('extracts 8.1% from Normalsatz bucket (dine-in)', () {
      final result = runCalculationPipeline(
        const PipelineInput(
          subtotalByMwst: {'A': 10810}, // CHF 108.10 gross
          applyRounding: false,
        ),
      );

      // 10810 × 8.1 / 108.1 = 810 cents exactly.
      expect(result.taxByCode['A'], 810);
      expect(result.taxableBaseByCode['A'], 10810);
      expect(result.grandTotal, 10810);
    });

    test('extracts 2.6% from Reduzierter bucket (takeaway)', () {
      final result = runCalculationPipeline(
        const PipelineInput(
          subtotalByMwst: {'B': 10260}, // CHF 102.60 gross
          applyRounding: false,
        ),
      );

      // 10260 × 2.6 / 102.6 = 260 cents exactly.
      expect(result.taxByCode['B'], 260);
      expect(result.grandTotal, 10260);
    });

    test('extracts per-bucket when multiple MwSt codes coexist', () {
      final result = runCalculationPipeline(
        const PipelineInput(
          subtotalByMwst: {
            'A': 5405, // Normalsatz
            'B': 5130, // Reduzierter
          },
          applyRounding: false,
        ),
      );

      expect(result.taxByCode['A'], 405); // 5405 × 8.1 / 108.1
      expect(result.taxByCode['B'], 130); // 5130 × 2.6 / 102.6
      // Tax never changes grand total for tax-inclusive prices.
      expect(result.grandTotal, 10535);
    });
  });

  group('runCalculationPipeline — 5-Rappen rounding', () {
    test('rounds 123.47 → 123.45 (remainder 2 → down)', () {
      final result = runCalculationPipeline(
        const PipelineInput(subtotalByMwst: {'A': 12347}),
      );

      expect(result.grandTotal, 12345);
      final rounding = result.steps.firstWhere(
        (s) => s.kind == CalculationKind.rounding,
      );
      expect(rounding.amount, -2);
    });

    test('rounds 123.48 → 123.50 (remainder 3 → up)', () {
      final result = runCalculationPipeline(
        const PipelineInput(subtotalByMwst: {'A': 12348}),
      );

      expect(result.grandTotal, 12350);
    });

    test('does not emit rounding step when already a multiple of 5', () {
      final result = runCalculationPipeline(
        const PipelineInput(subtotalByMwst: {'A': 12345}),
      );

      final hasRounding =
          result.steps.any((s) => s.kind == CalculationKind.rounding);
      expect(hasRounding, false);
      expect(result.grandTotal, 12345);
    });

    test('applyRounding=false leaves the raw gross untouched', () {
      final result = runCalculationPipeline(
        const PipelineInput(
          subtotalByMwst: {'A': 12347},
          applyRounding: false,
        ),
      );

      expect(result.grandTotal, 12347);
    });
  });

  group('runCalculationPipeline — discount apportionment', () {
    test('distributes discount proportionally across buckets', () {
      final result = runCalculationPipeline(
        const PipelineInput(
          subtotalByMwst: {
            'A': 6000, // 60% of gross
            'B': 4000, // 40% of gross
          },
          discountAmount: 1000, // CHF 10 off CHF 100
          applyRounding: false,
        ),
      );

      // 60% of 1000 = 600 off A, 40% = 400 off B. Last bucket absorbs
      // any remainder; here the split is exact.
      expect(result.taxableBaseByCode['A'], 5400);
      expect(result.taxableBaseByCode['B'], 3600);
      expect(result.grandTotal, 9000);
    });

    test('last bucket absorbs the apportionment remainder', () {
      // 1 cent discount on a 2-bucket split cannot divide evenly — the
      // last bucket must absorb the remainder so the total reconciles.
      final result = runCalculationPipeline(
        const PipelineInput(
          subtotalByMwst: {'A': 5000, 'B': 5000},
          discountAmount: 1,
          applyRounding: false,
        ),
      );

      final sum = result.taxableBaseByCode.values
          .fold<int>(0, (s, v) => s + v);
      expect(sum, 9999, reason: 'sum of buckets must equal 10000 − 1');
    });
  });

  group('runCalculationPipeline — service charge (VAT-inclusive)', () {
    test('adds service to each bucket proportionally, re-extracts MWST', () {
      final result = runCalculationPipeline(
        const PipelineInput(
          subtotalByMwst: {
            'A': 8000,
            'B': 2000,
          },
          serviceAmount: 1000, // 10% service on CHF 100
          applyRounding: false,
        ),
      );

      // Service apportioned 80/20: A gets +800, B gets +200.
      expect(result.taxableBaseByCode['A'], 8800);
      expect(result.taxableBaseByCode['B'], 2200);
      expect(result.grandTotal, 11000);
    });
  });

  group('runCalculationPipeline — edge cases', () {
    test('free item (zero gross) short-circuits the pipeline', () {
      final result = runCalculationPipeline(
        const PipelineInput(subtotalByMwst: {'A': 0}),
      );

      expect(result.grandTotal, 0);
      expect(result.taxByCode['A'] ?? 0, 0);
      // No discount / service / rounding steps with zero gross.
      final kinds = result.steps.map((s) => s.kind).toSet();
      expect(kinds.contains(CalculationKind.discount), false);
      expect(kinds.contains(CalculationKind.serviceCharge), false);
    });

    test('empty buckets produce an empty result', () {
      final result = runCalculationPipeline(
        const PipelineInput(subtotalByMwst: {}),
      );

      expect(result.steps, isEmpty);
      expect(result.grandTotal, 0);
      expect(result.taxableBaseByCode, isEmpty);
    });

    test('discount larger than subtotal drives total to zero or negative', () {
      final result = runCalculationPipeline(
        const PipelineInput(
          subtotalByMwst: {'A': 1000},
          discountAmount: 1500,
          applyRounding: false,
        ),
      );

      // The pipeline is a pure calculator — clamping is a policy
      // decision for the caller. What we *guarantee* is that the math
      // reconciles (1000 − 1500 = −500) and that the tax step is
      // skipped for a non-positive bucket (no negative MWST line on
      // the receipt).
      expect(result.grandTotal, -500);
      final taxSteps = result.steps
          .where((s) => s.kind == CalculationKind.tax)
          .toList();
      expect(taxSteps, isEmpty);
    });

    test('tax-exempt bucket (rate=0) emits no tax step, keeps gross', () {
      final result = runCalculationPipeline(
        const PipelineInput(
          subtotalByMwst: {'A': 5000, 'X': 2000},
          mwstRateByCode: {'A': 8.1, 'X': 0.0},
          applyRounding: false,
        ),
      );

      expect(result.taxByCode['X'], 0);
      expect(result.taxableBaseByCode['X'], 2000);
      // Only the taxable bucket emits a tax line.
      final taxSteps = result.steps
          .where((s) => s.kind == CalculationKind.tax)
          .toList();
      expect(taxSteps, hasLength(1));
      expect(taxSteps.first.mwstCode, 'A');
    });

    test('split-check apportion reconciles exactly across two buckets', () {
      // A CHF 33.33 discount on an uneven 3-bucket split. Floor-rounding
      // each share would leave cents unassigned; the pipeline's last-
      // bucket-absorbs-remainder rule must reconcile exactly.
      final result = runCalculationPipeline(
        const PipelineInput(
          subtotalByMwst: {'A': 3333, 'B': 3333, 'C': 3334},
          discountAmount: 3333,
          applyRounding: false,
        ),
      );

      final sum = result.taxableBaseByCode.values
          .fold<int>(0, (s, v) => s + v);
      expect(sum, 3333 + 3333 + 3334 - 3333);
      expect(result.grandTotal, 6667);
    });
  });

  group('runCalculationPipeline — step metadata', () {
    test('discount step carries negative amount and label', () {
      final result = runCalculationPipeline(
        const PipelineInput(
          subtotalByMwst: {'A': 10000},
          discountAmount: 1000,
          discountLabel: 'Rabatt 10%',
          discountPercent: 10,
          applyRounding: false,
        ),
      );

      final discount = result.steps
          .firstWhere((s) => s.kind == CalculationKind.discount);
      expect(discount.amount, -1000);
      expect(discount.label, 'Rabatt 10%');
      expect(discount.percent, 10);
    });

    test('tax step carries mwstCode and rate', () {
      final result = runCalculationPipeline(
        const PipelineInput(
          subtotalByMwst: {'A': 10810},
          applyRounding: false,
        ),
      );

      final tax = result.steps
          .firstWhere((s) => s.kind == CalculationKind.tax);
      expect(tax.mwstCode, 'A');
      expect(tax.percent, 8.1);
      expect(tax.label, 'MwSt A 8.1%');
    });
  });
}
