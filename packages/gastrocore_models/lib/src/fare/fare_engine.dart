/// GastroCore Fare Calculation Engine.
///
/// Pure Dart — no Flutter or database dependencies.
/// All amounts are in cents (integer arithmetic only).
library;

import 'fare_models.dart';

class FareEngine {
  const FareEngine._();

  /// Calculate complete fare breakdown for a ticket.
  static FareBreakdown calculateFare({
    required List<FareLineItem> items,
    required FareConfig config,
    List<SpecialDiscount>? specialDiscounts,
    OrderDiscount? orderDiscount,
    List<AdditionalCost>? additionalCosts,
    int serviceFeeOverride = 0,
    int packageFee = 0,
    int deliveryFee = 0,
    int temporaryCharge = 0,
    String orderType = 'dine_in',
    int couponAmount = 0,
    int payTotal = 0,
    int changeTotal = 0,
    int refundTotal = 0,
  }) {
    // Step 1: Per-item calculations
    int dishesOriginTotal = 0;
    int dishesTotalPreTax = 0;
    int dishesTaxTotal = 0;

    final taxAccumulator = <String, _TaxAccumEntry>{};

    for (final item in items) {
      final grossPrice = item.grossPrice;
      dishesOriginTotal += grossPrice;

      final netPrice = item.netPrice;

      if (item.isTaxFree) {
        dishesTotalPreTax += netPrice;
        continue;
      }

      final taxConfig = config.findTaxRate(item.taxGroup);
      if (taxConfig == null) {
        dishesTotalPreTax += netPrice;
        continue;
      }

      final effectiveRate = taxConfig.effectiveRate(orderType);
      final useTaxInclusive = item.isTaxInclusive;

      int itemPreTax;
      int itemTax;

      if (useTaxInclusive) {
        itemPreTax = _extractPreTax(netPrice, effectiveRate);
        itemTax = netPrice - itemPreTax;
      } else {
        itemPreTax = netPrice;
        itemTax = _calculateTax(netPrice, effectiveRate);
      }

      dishesTotalPreTax += itemPreTax;
      dishesTaxTotal += itemTax;

      final key = item.taxGroup;
      final existing = taxAccumulator[key];
      if (existing != null) {
        taxAccumulator[key] = _TaxAccumEntry(
          netBase: existing.netBase + itemPreTax,
          taxAmount: existing.taxAmount + itemTax,
          config: taxConfig,
          effectiveRate: effectiveRate,
        );
      } else {
        taxAccumulator[key] = _TaxAccumEntry(
          netBase: itemPreTax,
          taxAmount: itemTax,
          config: taxConfig,
          effectiveRate: effectiveRate,
        );
      }
    }

    final dishesTotal = dishesTotalPreTax + dishesTaxTotal;

    // Step 2: Special discounts
    int specialDiscountTotalAmount = 0;
    int taxSpecialDiscountTotal = 0;
    final specialDiscountLines = <SpecialDiscountLine>[];

    if (specialDiscounts != null) {
      for (final discount in specialDiscounts) {
        final discAmount = discount.calculate(dishesTotal);
        int discTax = 0;

        if (discount.affectsTax && dishesTaxTotal > 0 && dishesTotal > 0) {
          discTax =
              (discAmount * dishesTaxTotal / dishesTotal).round();
        }

        specialDiscountTotalAmount += discAmount;
        taxSpecialDiscountTotal += discTax;

        specialDiscountLines.add(SpecialDiscountLine(
          id: discount.id,
          name: discount.name,
          amount: discAmount,
          taxAmount: discTax,
        ));
      }
    }

    // Step 3: Additional costs
    int additionalCostTotalAmount = 0;
    final additionalCostLines = <AdditionalCostLine>[];

    if (additionalCosts != null) {
      for (final cost in additionalCosts) {
        int costTax = 0;
        if (cost.isTaxable && cost.taxGroup != null) {
          final costTaxConfig = config.findTaxRate(cost.taxGroup!);
          if (costTaxConfig != null) {
            final costRate = costTaxConfig.effectiveRate(orderType);
            if (config.isTaxInclusive) {
              final preTax = _extractPreTax(cost.amount, costRate);
              costTax = cost.amount - preTax;
            } else {
              costTax = _calculateTax(cost.amount, costRate);
            }
          }
        }

        additionalCostTotalAmount += cost.amount;
        additionalCostLines.add(AdditionalCostLine(
          id: cost.id,
          name: cost.name,
          amount: cost.amount,
          taxAmount: costTax,
        ));
      }
    }

    // Step 4: Service fee
    int serviceFeeAmount = 0;
    int serviceFeeTax = 0;

    if (serviceFeeOverride > 0) {
      serviceFeeAmount = serviceFeeOverride;
    } else if (config.serviceFee != null) {
      final sfConfig = config.serviceFee!;
      if (sfConfig.orderTypes.contains(orderType)) {
        serviceFeeAmount = sfConfig.calculate(dishesTotal);
      }
    }

    if (serviceFeeAmount > 0 && config.serviceFee != null) {
      final sfConfig = config.serviceFee!;
      if (sfConfig.isTaxable && sfConfig.taxGroup != null) {
        final sfTaxConfig = config.findTaxRate(sfConfig.taxGroup!);
        if (sfTaxConfig != null) {
          final sfRate = sfTaxConfig.effectiveRate(orderType);
          if (config.isTaxInclusive) {
            final preTax = _extractPreTax(serviceFeeAmount, sfRate);
            serviceFeeTax = serviceFeeAmount - preTax;
          } else {
            serviceFeeTax = _calculateTax(serviceFeeAmount, sfRate);
          }
        }
      }
    }

    // Step 5: Order discount
    int orderDiscountTotalAmount = 0;
    int taxOrderDiscountTotal = 0;

    if (orderDiscount != null) {
      final baseForOrderDiscount = dishesTotal -
          specialDiscountTotalAmount +
          additionalCostTotalAmount +
          serviceFeeAmount;
      orderDiscountTotalAmount = orderDiscount.calculate(
          baseForOrderDiscount > 0 ? baseForOrderDiscount : 0);

      if (orderDiscount.affectsTax &&
          dishesTaxTotal > 0 &&
          baseForOrderDiscount > 0) {
        final totalTaxInScope =
            dishesTaxTotal - taxSpecialDiscountTotal + serviceFeeTax;
        taxOrderDiscountTotal = (orderDiscountTotalAmount *
                totalTaxInScope /
                baseForOrderDiscount)
            .round();
      }
    }

    // Step 6: Build tax breakdown
    final dishesTaxes = <TaxBreakdown>[];
    for (final entry in taxAccumulator.entries) {
      final accum = entry.value;
      int payableAmount = accum.taxAmount;
      bool isDiscounted = false;

      if (accum.config.isDiscountable) {
        final totalDiscountOnTax =
            taxSpecialDiscountTotal + taxOrderDiscountTotal;
        if (totalDiscountOnTax > 0 && dishesTaxTotal > 0) {
          final groupShare =
              (totalDiscountOnTax * accum.taxAmount / dishesTaxTotal)
                  .round();
          payableAmount = accum.taxAmount - groupShare;
          if (payableAmount < 0) payableAmount = 0;
          isDiscounted = true;
        }
      }

      dishesTaxes.add(TaxBreakdown(
        name: accum.config.name,
        rate: accum.effectiveRate.toString(),
        amount: accum.taxAmount,
        payableAmount: payableAmount,
        isDiscounted: isDiscounted,
      ));
    }

    // Step 7: Receivable
    int receivableBeforeRounding = dishesTotal +
        additionalCostTotalAmount +
        serviceFeeAmount +
        packageFee +
        deliveryFee +
        temporaryCharge -
        specialDiscountTotalAmount -
        orderDiscountTotalAmount -
        couponAmount;

    if (receivableBeforeRounding < 0) receivableBeforeRounding = 0;

    // Step 8: Rounding
    final receivableTotal =
        config.roundingRule.apply(receivableBeforeRounding);
    final roundDownTotal = receivableBeforeRounding - receivableTotal;

    // Step 9: Unpaid
    int unpaidTotal =
        receivableTotal - payTotal + changeTotal + refundTotal;
    if (unpaidTotal < 0) unpaidTotal = 0;

    return FareBreakdown(
      dishesOriginTotal: dishesOriginTotal,
      dishesTotalPreTax: dishesTotalPreTax,
      dishesTaxTotal: dishesTaxTotal,
      dishesTotal: dishesTotal,
      dishesTaxes: dishesTaxes,
      additionalCostTotal: additionalCostTotalAmount,
      additionalCosts: additionalCostLines,
      serviceFeeAmount: serviceFeeAmount,
      serviceFeeTax: serviceFeeTax,
      packageFee: packageFee,
      deliveryFee: deliveryFee,
      temporaryChargeTotal: temporaryCharge,
      specialDiscountTotal: specialDiscountTotalAmount,
      taxSpecialDiscountTotal: taxSpecialDiscountTotal,
      specialDiscounts: specialDiscountLines,
      orderDiscountTotal: orderDiscountTotalAmount,
      taxOrderDiscountTotal: taxOrderDiscountTotal,
      couponTotal: couponAmount,
      roundDownTotal: roundDownTotal,
      receivableTotal: receivableTotal,
      unpaidTotal: unpaidTotal,
      payTotal: payTotal,
      changeTotal: changeTotal,
      refundTotal: refundTotal,
      currency: config.currency,
    );
  }

  /// Update payment totals on an existing breakdown without recalculating
  /// the full fare.
  static FareBreakdown updatePayment(
    FareBreakdown breakdown, {
    required int payTotal,
    int changeTotal = 0,
    int refundTotal = 0,
  }) {
    int unpaidTotal =
        breakdown.receivableTotal - payTotal + changeTotal + refundTotal;
    if (unpaidTotal < 0) unpaidTotal = 0;

    return breakdown.copyWith(
      payTotal: payTotal,
      changeTotal: changeTotal,
      refundTotal: refundTotal,
      unpaidTotal: unpaidTotal,
    );
  }

  // Internal helpers

  static int _extractPreTax(int inclusivePrice, double ratePercent) {
    if (ratePercent <= 0) return inclusivePrice;
    final divisor = 1.0 + ratePercent / 100.0;
    return (inclusivePrice / divisor).round();
  }

  static int _calculateTax(int exclusivePrice, double ratePercent) {
    if (ratePercent <= 0) return 0;
    return (exclusivePrice * ratePercent / 100.0).round();
  }
}

class _TaxAccumEntry {
  final int netBase;
  final int taxAmount;
  final TaxRateConfig config;
  final double effectiveRate;

  const _TaxAccumEntry({
    required this.netBase,
    required this.taxAmount,
    required this.config,
    required this.effectiveRate,
  });
}
