/// Unit tests for the GastroCore FareEngine.
///
/// Covers basic price calculation, tax-inclusive and tax-exclusive handling,
/// Swiss dual-rate VAT, German VAT rates, discount application, service fees,
/// 5-Rappen rounding, multi-tax-rate orders, special discounts with tax
/// effects, and combo pricing via line items.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/core/services/fare_engine.dart';
import 'package:gastrocore_pos/core/services/fare_models.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Swiss restaurant config: tax-inclusive, CHF, 5-Rappen rounding,
/// dual-rate VAT (food: 8.1% dine-in / 2.6% takeaway).
FareConfig swissConfig({
  ServiceFeeConfig? serviceFee,
}) {
  return FareConfig(
    isTaxInclusive: true,
    currency: 'CHF',
    roundingRule: const RoundingRule(rule: 'round', unit: 'five_percent'),
    serviceFee: serviceFee,
    taxRates: const [
      TaxRateConfig(
        name: 'food',
        rate: 8.1,
        dineInRate: '8.1',
        takeawayRate: '2.6',
      ),
      TaxRateConfig(
        name: 'beverage',
        rate: 8.1,
        dineInRate: '8.1',
        takeawayRate: '8.1',
      ),
    ],
  );
}

/// German restaurant config: tax-exclusive, EUR, standard rounding.
FareConfig germanConfig() {
  return const FareConfig(
    isTaxInclusive: false,
    currency: 'EUR',
    roundingRule: RoundingRule(rule: 'round', unit: 'percentile'),
    taxRates: [
      TaxRateConfig(name: 'food', rate: 7.0),
      TaxRateConfig(name: 'beverage', rate: 19.0),
    ],
  );
}

FareLineItem foodItem({
  String name = 'Food',
  int unitPrice = 2500,
  int quantity = 1,
  bool isTaxInclusive = true,
}) {
  return FareLineItem(
    productId: 'p-food',
    productName: name,
    quantity: quantity,
    unitPrice: unitPrice,
    taxGroup: 'food',
    isTaxInclusive: isTaxInclusive,
  );
}

FareLineItem beverageItem({
  String name = 'Drink',
  int unitPrice = 800,
  int quantity = 1,
  bool isTaxInclusive = true,
}) {
  return FareLineItem(
    productId: 'p-drink',
    productName: name,
    quantity: quantity,
    unitPrice: unitPrice,
    taxGroup: 'beverage',
    isTaxInclusive: isTaxInclusive,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('FareEngine', () {
    // =======================================================================
    // Basic price calculation
    // =======================================================================

    group('basic price calculation', () {
      test('single item, no tax config -> dishesTotal equals item price', () {
        final result = FareEngine.calculateFare(
          items: [
            const FareLineItem(
              productId: 'p1',
              productName: 'Burger',
              quantity: 1,
              unitPrice: 1500,
              taxGroup: 'none', // no matching config
            ),
          ],
          config: const FareConfig(taxRates: []),
        );

        expect(result.dishesOriginTotal, 1500);
        expect(result.dishesTotal, 1500);
        expect(result.dishesTaxTotal, 0);
        expect(result.receivableTotal, 1500);
      });

      test('multiple items sum correctly', () {
        final result = FareEngine.calculateFare(
          items: [
            foodItem(unitPrice: 2000, quantity: 2),
            beverageItem(unitPrice: 500, quantity: 3),
          ],
          config: const FareConfig(taxRates: []),
        );

        // 2000*2 + 500*3 = 5500
        expect(result.dishesOriginTotal, 5500);
        expect(result.receivableTotal, 5500);
      });

      test('item with modifiers includes modifier total in gross price', () {
        final result = FareEngine.calculateFare(
          items: [
            const FareLineItem(
              productId: 'p1',
              productName: 'Burger',
              quantity: 1,
              unitPrice: 1500,
              modifierTotal: 200, // extra cheese
              taxGroup: 'none',
            ),
          ],
          config: const FareConfig(taxRates: []),
        );

        // (1500 + 200) * 1 = 1700
        expect(result.dishesOriginTotal, 1700);
        expect(result.receivableTotal, 1700);
      });

      test('quantity multiplies unit price and modifiers', () {
        final result = FareEngine.calculateFare(
          items: [
            const FareLineItem(
              productId: 'p1',
              productName: 'Burger',
              quantity: 3,
              unitPrice: 1000,
              modifierTotal: 200,
              taxGroup: 'none',
            ),
          ],
          config: const FareConfig(taxRates: []),
        );

        // (1000 + 200) * 3 = 3600
        expect(result.dishesOriginTotal, 3600);
      });
    });

    // =======================================================================
    // Tax calculation (inclusive and exclusive)
    // =======================================================================

    group('tax calculation', () {
      test('tax-inclusive: extracts tax from gross price', () {
        // CHF 25.00 inclusive at 8.1%
        final result = FareEngine.calculateFare(
          items: [foodItem(unitPrice: 2500, isTaxInclusive: true)],
          config: swissConfig(),
          orderType: 'dine_in',
        );

        // Tax = 2500 - round(2500 / 1.081) = 2500 - 2313 = 187
        expect(result.dishesTaxTotal, 187);
        expect(result.dishesTotalPreTax, 2313);
        expect(result.dishesTotal, 2500);
        expect(result.dishesTaxes.length, 1);
        expect(result.dishesTaxes.first.name, 'food');
      });

      test('tax-exclusive: adds tax on top of net price', () {
        // EUR 20.00 net at 7%
        final result = FareEngine.calculateFare(
          items: [foodItem(unitPrice: 2000, isTaxInclusive: false)],
          config: germanConfig(),
          orderType: 'dine_in',
        );

        // Tax = round(2000 * 7 / 100) = 140
        expect(result.dishesTaxTotal, 140);
        expect(result.dishesTotalPreTax, 2000);
        expect(result.dishesTotal, 2140);
      });

      test('tax-free item has no tax regardless of config', () {
        final result = FareEngine.calculateFare(
          items: [
            const FareLineItem(
              productId: 'p-free',
              productName: 'Water',
              quantity: 1,
              unitPrice: 300,
              taxGroup: 'food',
              isTaxFree: true,
            ),
          ],
          config: swissConfig(),
          orderType: 'dine_in',
        );

        expect(result.dishesTaxTotal, 0);
        expect(result.dishesTotalPreTax, 300);
        expect(result.dishesTotal, 300);
      });
    });

    // =======================================================================
    // Swiss VAT: dine-in 8.1% vs takeaway 2.6%
    // =======================================================================

    group('Swiss dual-rate VAT', () {
      test('food dine-in uses 8.1%', () {
        final result = FareEngine.calculateFare(
          items: [foodItem(unitPrice: 2500)],
          config: swissConfig(),
          orderType: 'dine_in',
        );

        final taxLine = result.dishesTaxes.first;
        expect(taxLine.rate, '8.1');
      });

      test('food takeaway uses 2.6%', () {
        final result = FareEngine.calculateFare(
          items: [foodItem(unitPrice: 2500)],
          config: swissConfig(),
          orderType: 'takeaway',
        );

        final taxLine = result.dishesTaxes.first;
        expect(taxLine.rate, '2.6');

        // Tax at 2.6% from 2500 inclusive:
        // preTax = round(2500 / 1.026) = 2437
        // tax = 2500 - 2437 = 63
        expect(result.dishesTaxTotal, 63);
      });

      test('beverage keeps 8.1% for both dine-in and takeaway', () {
        final dineIn = FareEngine.calculateFare(
          items: [beverageItem(unitPrice: 800)],
          config: swissConfig(),
          orderType: 'dine_in',
        );

        final takeaway = FareEngine.calculateFare(
          items: [beverageItem(unitPrice: 800)],
          config: swissConfig(),
          orderType: 'takeaway',
        );

        expect(dineIn.dishesTaxes.first.rate, '8.1');
        expect(takeaway.dishesTaxes.first.rate, '8.1');
        expect(dineIn.dishesTaxTotal, takeaway.dishesTaxTotal);
      });
    });

    // =======================================================================
    // German VAT: food 7%, beverages 19%
    // =======================================================================

    group('German VAT rates', () {
      test('food at 7% exclusive', () {
        final result = FareEngine.calculateFare(
          items: [foodItem(unitPrice: 1000, isTaxInclusive: false)],
          config: germanConfig(),
          orderType: 'dine_in',
        );

        // Tax = round(1000 * 7 / 100) = 70
        expect(result.dishesTaxTotal, 70);
        expect(result.dishesTotal, 1070);
      });

      test('beverage at 19% exclusive', () {
        final result = FareEngine.calculateFare(
          items: [beverageItem(unitPrice: 500, isTaxInclusive: false)],
          config: germanConfig(),
          orderType: 'dine_in',
        );

        // Tax = round(500 * 19 / 100) = 95
        expect(result.dishesTaxTotal, 95);
        expect(result.dishesTotal, 595);
      });

      test('mixed food + beverage with separate tax rates', () {
        final result = FareEngine.calculateFare(
          items: [
            foodItem(unitPrice: 2000, isTaxInclusive: false),
            beverageItem(unitPrice: 600, isTaxInclusive: false),
          ],
          config: germanConfig(),
          orderType: 'dine_in',
        );

        // Food tax = 140, Beverage tax = 114
        expect(result.dishesTaxes.length, 2);

        final foodTax =
            result.dishesTaxes.firstWhere((t) => t.name == 'food');
        final bevTax =
            result.dishesTaxes.firstWhere((t) => t.name == 'beverage');

        expect(foodTax.amount, 140);
        expect(bevTax.amount, 114);
        expect(result.dishesTaxTotal, 254);
      });
    });

    // =======================================================================
    // Discount application
    // =======================================================================

    group('discount application', () {
      test('percentage special discount reduces total', () {
        // 10% off on CHF 25.00
        final result = FareEngine.calculateFare(
          items: [foodItem(unitPrice: 2500)],
          config: swissConfig(),
          orderType: 'dine_in',
          specialDiscounts: [
            const SpecialDiscount(
              id: 'd1',
              name: 'Happy Hour',
              type: 'percentage',
              value: 1000, // 10%
            ),
          ],
        );

        // 10% of 2500 = 250
        expect(result.specialDiscountTotal, 250);
        // Receivable = 2500 - 250 = 2250, rounded to 5 Rappen = 2250
        expect(result.receivableTotal, 2250);
      });

      test('fixed special discount reduces total', () {
        final result = FareEngine.calculateFare(
          items: [foodItem(unitPrice: 2500)],
          config: swissConfig(),
          orderType: 'dine_in',
          specialDiscounts: [
            const SpecialDiscount(
              id: 'd1',
              name: 'Staff Meal',
              type: 'fixed',
              value: 500, // CHF 5.00
            ),
          ],
        );

        expect(result.specialDiscountTotal, 500);
        expect(result.receivableTotal, 2000);
      });

      test('order discount (percentage) applied after special discounts', () {
        final result = FareEngine.calculateFare(
          items: [foodItem(unitPrice: 5000)],
          config: swissConfig(),
          orderType: 'dine_in',
          specialDiscounts: [
            const SpecialDiscount(
              id: 'd1',
              name: 'Coupon',
              type: 'fixed',
              value: 1000, // CHF 10.00
            ),
          ],
          orderDiscount: const OrderDiscount(
            type: 'percentage',
            value: 1000, // 10%
          ),
        );

        // Special: 1000
        expect(result.specialDiscountTotal, 1000);
        // Base for order discount = 5000 - 1000 = 4000
        // Order discount = 10% of 4000 = 400
        expect(result.orderDiscountTotal, 400);
        // Receivable before rounding = 5000 - 1000 - 400 = 3600
        expect(result.receivableTotal, 3600);
      });

      test('fixed discount cannot exceed total', () {
        final result = FareEngine.calculateFare(
          items: [foodItem(unitPrice: 300)],
          config: const FareConfig(taxRates: []),
          specialDiscounts: [
            const SpecialDiscount(
              id: 'd1',
              name: 'Big Discount',
              type: 'fixed',
              value: 500, // more than item total
            ),
          ],
        );

        // Discount capped at item total (300).
        expect(result.specialDiscountTotal, 300);
        expect(result.receivableTotal, 0);
      });
    });

    // =======================================================================
    // Service fee calculation
    // =======================================================================

    group('service fee', () {
      test('fixed service fee added to total', () {
        final result = FareEngine.calculateFare(
          items: [foodItem(unitPrice: 2500)],
          config: swissConfig(
            serviceFee: const ServiceFeeConfig(
              takenType: 'fixed_amount',
              value: 500,
              orderTypes: ['dine_in'],
            ),
          ),
          orderType: 'dine_in',
        );

        expect(result.serviceFeeAmount, 500);
        // Receivable = 2500 + 500 = 3000
        expect(result.receivableTotal, 3000);
      });

      test('percentage service fee (10%) calculated from dishes total', () {
        final result = FareEngine.calculateFare(
          items: [foodItem(unitPrice: 5000)],
          config: swissConfig(
            serviceFee: const ServiceFeeConfig(
              takenType: 'order_amount_ratio',
              value: 100, // 10% (value/1000)
              orderTypes: ['dine_in'],
            ),
          ),
          orderType: 'dine_in',
        );

        // 10% of 5000 = 500
        expect(result.serviceFeeAmount, 500);
        expect(result.receivableTotal, 5500);
      });

      test('service fee not applied for non-matching order type', () {
        final result = FareEngine.calculateFare(
          items: [foodItem(unitPrice: 2500)],
          config: swissConfig(
            serviceFee: const ServiceFeeConfig(
              takenType: 'fixed_amount',
              value: 500,
              orderTypes: ['dine_in'], // only dine-in
            ),
          ),
          orderType: 'takeaway', // not in allowed list
        );

        expect(result.serviceFeeAmount, 0);
      });

      test('service fee override takes precedence', () {
        final result = FareEngine.calculateFare(
          items: [foodItem(unitPrice: 2500)],
          config: swissConfig(
            serviceFee: const ServiceFeeConfig(
              takenType: 'fixed_amount',
              value: 500,
              orderTypes: ['dine_in'],
            ),
          ),
          orderType: 'dine_in',
          serviceFeeOverride: 300,
        );

        expect(result.serviceFeeAmount, 300);
      });
    });

    // =======================================================================
    // 5-Rappen rounding
    // =======================================================================

    group('5-Rappen rounding', () {
      test('amount already divisible by 5 stays unchanged', () {
        final result = FareEngine.calculateFare(
          items: [foodItem(unitPrice: 2500)],
          config: swissConfig(),
          orderType: 'dine_in',
        );

        // 2500 % 5 == 0, no rounding adjustment.
        expect(result.roundDownTotal, 0);
        expect(result.receivableTotal, 2500);
      });

      test('amount rounds down (1 or 2 Rappen remainder)', () {
        // 2501 should round down to 2500.
        final result = FareEngine.calculateFare(
          items: [
            const FareLineItem(
              productId: 'p1',
              productName: 'Item',
              quantity: 1,
              unitPrice: 2501,
              taxGroup: 'none',
            ),
          ],
          config: const FareConfig(
            roundingRule: RoundingRule(rule: 'round', unit: 'five_percent'),
          ),
        );

        expect(result.receivableTotal, 2500);
        expect(result.roundDownTotal, 1);
      });

      test('amount rounds up (3 or 4 Rappen remainder)', () {
        // 2503 should round up to 2505.
        final result = FareEngine.calculateFare(
          items: [
            const FareLineItem(
              productId: 'p1',
              productName: 'Item',
              quantity: 1,
              unitPrice: 2503,
              taxGroup: 'none',
            ),
          ],
          config: const FareConfig(
            roundingRule: RoundingRule(rule: 'round', unit: 'five_percent'),
          ),
        );

        expect(result.receivableTotal, 2505);
        expect(result.roundDownTotal, -2); // negative = rounded up
      });

      test('floor rounding always rounds down', () {
        final result = FareEngine.calculateFare(
          items: [
            const FareLineItem(
              productId: 'p1',
              productName: 'Item',
              quantity: 1,
              unitPrice: 2504,
              taxGroup: 'none',
            ),
          ],
          config: const FareConfig(
            roundingRule: RoundingRule(rule: 'floor', unit: 'five_percent'),
          ),
        );

        expect(result.receivableTotal, 2500);
        expect(result.roundDownTotal, 4);
      });

      test('ceil rounding always rounds up', () {
        final result = FareEngine.calculateFare(
          items: [
            const FareLineItem(
              productId: 'p1',
              productName: 'Item',
              quantity: 1,
              unitPrice: 2501,
              taxGroup: 'none',
            ),
          ],
          config: const FareConfig(
            roundingRule: RoundingRule(rule: 'ceil', unit: 'five_percent'),
          ),
        );

        expect(result.receivableTotal, 2505);
        expect(result.roundDownTotal, -4);
      });
    });

    // =======================================================================
    // Multiple tax rates in a single order
    // =======================================================================

    group('multiple tax rates in single order', () {
      test('Swiss order with food + beverage tracks each rate', () {
        final result = FareEngine.calculateFare(
          items: [
            foodItem(unitPrice: 2500), // food 8.1% inclusive
            beverageItem(unitPrice: 800), // beverage 8.1% inclusive
          ],
          config: swissConfig(),
          orderType: 'dine_in',
        );

        expect(result.dishesTaxes.length, 2);

        final foodTax =
            result.dishesTaxes.firstWhere((t) => t.name == 'food');
        final bevTax =
            result.dishesTaxes.firstWhere((t) => t.name == 'beverage');

        // Both at 8.1% for dine-in.
        expect(foodTax.rate, '8.1');
        expect(bevTax.rate, '8.1');

        // Food tax: 2500 - round(2500/1.081) = 2500 - 2313 = 187
        expect(foodTax.amount, 187);
        // Bev tax: 800 - round(800/1.081) = 800 - 740 = 60
        expect(bevTax.amount, 60);
      });

      test('Swiss takeaway: food rate changes, beverage stays', () {
        final result = FareEngine.calculateFare(
          items: [
            foodItem(unitPrice: 2500),
            beverageItem(unitPrice: 800),
          ],
          config: swissConfig(),
          orderType: 'takeaway',
        );

        final foodTax =
            result.dishesTaxes.firstWhere((t) => t.name == 'food');
        final bevTax =
            result.dishesTaxes.firstWhere((t) => t.name == 'beverage');

        expect(foodTax.rate, '2.6');
        expect(bevTax.rate, '8.1');

        // Food at 2.6%: preTax = round(2500/1.026) = 2437, tax = 63
        expect(foodTax.amount, 63);
      });
    });

    // =======================================================================
    // Special discounts with tax effect
    // =======================================================================

    group('special discounts with tax effect', () {
      test('discount affecting tax reduces tax proportionally', () {
        final result = FareEngine.calculateFare(
          items: [foodItem(unitPrice: 5000)],
          config: swissConfig(),
          orderType: 'dine_in',
          specialDiscounts: [
            const SpecialDiscount(
              id: 'd1',
              name: 'Staff',
              type: 'percentage',
              value: 2000, // 20%
              affectsTax: true,
            ),
          ],
        );

        // Discount = 20% of 5000 = 1000
        expect(result.specialDiscountTotal, 1000);
        // Tax portion of discount (proportional):
        // dishesTaxTotal = 5000 - round(5000/1.081) = 5000 - 4625 = 375
        // taxDiscount = round(1000 * 375 / 5000) = 75
        expect(result.taxSpecialDiscountTotal, 75);
      });

      test('discount NOT affecting tax leaves tax unchanged', () {
        final result = FareEngine.calculateFare(
          items: [foodItem(unitPrice: 5000)],
          config: swissConfig(),
          orderType: 'dine_in',
          specialDiscounts: [
            const SpecialDiscount(
              id: 'd1',
              name: 'Loyalty',
              type: 'percentage',
              value: 2000,
              affectsTax: false,
            ),
          ],
        );

        expect(result.specialDiscountTotal, 1000);
        expect(result.taxSpecialDiscountTotal, 0);
      });
    });

    // =======================================================================
    // Combo pricing via line items
    // =======================================================================

    group('combo pricing', () {
      test('combo items with individual prices sum correctly', () {
        // Simulate a combo: main + side + drink with pre-set combo prices.
        final result = FareEngine.calculateFare(
          items: [
            const FareLineItem(
              productId: 'combo-main',
              productName: 'Combo Main',
              quantity: 1,
              unitPrice: 1200,
              taxGroup: 'food',
              isTaxInclusive: true,
            ),
            const FareLineItem(
              productId: 'combo-side',
              productName: 'Combo Side',
              quantity: 1,
              unitPrice: 400,
              taxGroup: 'food',
              isTaxInclusive: true,
            ),
            const FareLineItem(
              productId: 'combo-drink',
              productName: 'Combo Drink',
              quantity: 1,
              unitPrice: 400,
              taxGroup: 'beverage',
              isTaxInclusive: true,
            ),
          ],
          config: swissConfig(),
          orderType: 'dine_in',
        );

        // Total = 1200 + 400 + 400 = 2000
        expect(result.dishesOriginTotal, 2000);
        expect(result.receivableTotal, 2000);
      });

      test('combo with special discount', () {
        // Combo price is discounted from individual items.
        final result = FareEngine.calculateFare(
          items: [
            foodItem(unitPrice: 1500), // main: 15.00
            foodItem(
                unitPrice: 600, name: 'Side'), // side: 6.00
            beverageItem(unitPrice: 500), // drink: 5.00
          ],
          config: swissConfig(),
          orderType: 'dine_in',
          specialDiscounts: [
            const SpecialDiscount(
              id: 'combo1',
              name: 'Menu Combo Discount',
              type: 'fixed',
              value: 600, // save CHF 6.00
            ),
          ],
        );

        // Items total = 1500 + 600 + 500 = 2600
        expect(result.dishesOriginTotal, 2600);
        expect(result.specialDiscountTotal, 600);
        expect(result.receivableTotal, 2000);
      });
    });

    // =======================================================================
    // Payment tracking
    // =======================================================================

    group('payment tracking', () {
      test('unpaid = receivable when no payment', () {
        final result = FareEngine.calculateFare(
          items: [foodItem(unitPrice: 2500)],
          config: swissConfig(),
          orderType: 'dine_in',
        );

        expect(result.unpaidTotal, result.receivableTotal);
      });

      test('partial payment reduces unpaid', () {
        final result = FareEngine.calculateFare(
          items: [foodItem(unitPrice: 2500)],
          config: swissConfig(),
          orderType: 'dine_in',
          payTotal: 1500,
        );

        expect(result.unpaidTotal, 1000);
      });

      test('overpayment sets unpaid to 0', () {
        final result = FareEngine.calculateFare(
          items: [foodItem(unitPrice: 2500)],
          config: swissConfig(),
          orderType: 'dine_in',
          payTotal: 3000,
        );

        expect(result.unpaidTotal, 0);
      });

      test('updatePayment recalculates unpaid correctly', () {
        final initial = FareEngine.calculateFare(
          items: [foodItem(unitPrice: 2500)],
          config: swissConfig(),
          orderType: 'dine_in',
        );

        final updated = FareEngine.updatePayment(
          initial,
          payTotal: 3000,
          changeTotal: 500,
        );

        // unpaid = 2500 - 3000 + 500 = 0 (clamped)
        expect(updated.unpaidTotal, 0);
        expect(updated.payTotal, 3000);
        expect(updated.changeTotal, 500);
      });
    });

    // =======================================================================
    // Additional costs
    // =======================================================================

    group('additional costs', () {
      test('cover charge added to receivable', () {
        final result = FareEngine.calculateFare(
          items: [foodItem(unitPrice: 2500)],
          config: swissConfig(),
          orderType: 'dine_in',
          additionalCosts: [
            const AdditionalCost(
              id: 'ac1',
              name: 'Cover',
              amount: 300,
            ),
          ],
        );

        expect(result.additionalCostTotal, 300);
        expect(result.receivableTotal, 2800);
      });

      test('delivery and package fees added to receivable', () {
        final result = FareEngine.calculateFare(
          items: [foodItem(unitPrice: 2500)],
          config: swissConfig(),
          orderType: 'delivery',
          deliveryFee: 500,
          packageFee: 200,
        );

        // 2500 + 500 + 200 = 3200
        expect(result.receivableTotal, 3200);
        expect(result.deliveryFee, 500);
        expect(result.packageFee, 200);
      });
    });

    // =======================================================================
    // Coupon deduction
    // =======================================================================

    group('coupon', () {
      test('coupon reduces receivable', () {
        final result = FareEngine.calculateFare(
          items: [foodItem(unitPrice: 3000)],
          config: swissConfig(),
          orderType: 'dine_in',
          couponAmount: 500,
        );

        expect(result.couponTotal, 500);
        expect(result.receivableTotal, 2500);
      });
    });

    // =======================================================================
    // Edge cases
    // =======================================================================

    group('edge cases', () {
      test('empty items list produces zero totals', () {
        final result = FareEngine.calculateFare(
          items: [],
          config: swissConfig(),
        );

        expect(result.dishesOriginTotal, 0);
        expect(result.dishesTotal, 0);
        expect(result.receivableTotal, 0);
        expect(result.unpaidTotal, 0);
      });

      test('receivable cannot go negative', () {
        final result = FareEngine.calculateFare(
          items: [foodItem(unitPrice: 200)],
          config: swissConfig(),
          orderType: 'dine_in',
          couponAmount: 500,
        );

        expect(result.receivableTotal, 0);
      });

      test('weight-based item calculates price from unit price and weight', () {
        final result = FareEngine.calculateFare(
          items: [
            const FareLineItem(
              productId: 'p-meat',
              productName: 'Steak (per kg)',
              quantity: 1,
              unitPrice: 8000, // CHF 80.00 / kg
              taxGroup: 'food',
              isTaxInclusive: true,
              isWeightBased: true,
              weight: 350, // 350g
            ),
          ],
          config: swissConfig(),
          orderType: 'dine_in',
        );

        // (8000 * 350) / 1000 = 2800
        expect(result.dishesOriginTotal, 2800);
      });
    });
  });

  // =========================================================================
  // RoundingRule standalone tests
  // =========================================================================

  group('RoundingRule', () {
    test('percentile keeps every cent', () {
      const rule = RoundingRule(rule: 'round', unit: 'percentile');
      expect(rule.apply(2501), 2501);
      expect(rule.apply(2503), 2503);
    });

    test('five_percent rounds to nearest 5', () {
      const rule = RoundingRule(rule: 'round', unit: 'five_percent');
      expect(rule.apply(2501), 2500);
      expect(rule.apply(2503), 2505);
      expect(rule.apply(2505), 2505);
      expect(rule.apply(2502), 2500);
      expect(rule.apply(2507), 2505);
      expect(rule.apply(2508), 2510);
    });

    test('tenths rounds to nearest 10', () {
      const rule = RoundingRule(rule: 'round', unit: 'tenths');
      expect(rule.apply(2504), 2500);
      expect(rule.apply(2505), 2510);
      expect(rule.apply(2509), 2510);
    });

    test('units rounds to nearest 100 (whole currency unit)', () {
      const rule = RoundingRule(rule: 'round', unit: 'units');
      expect(rule.apply(2549), 2500);
      expect(rule.apply(2550), 2600);
      expect(rule.apply(2599), 2600);
    });
  });
}
