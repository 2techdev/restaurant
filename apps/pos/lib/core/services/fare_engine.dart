/// GastroCore Fare Calculation Engine.
///
/// Inspired by OrderPin's comprehensive fare model with 15+ line items.
/// Supports tax-inclusive and tax-exclusive pricing, Swiss dual-rate VAT,
/// special discounts, order discounts, additional costs, service fees,
/// coupons, and configurable rounding. All amounts in cents (integer).
library;

import 'package:gastrocore_pos/core/services/fare_models.dart';
import 'package:gastrocore_pos/core/services/price_resolver.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/order_item_entity.dart';

class FareEngine {
  const FareEngine._();

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Calculate complete fare breakdown for a ticket.
  ///
  /// [items] -- order line items with prices and tax groups.
  /// [config] -- venue-level fare configuration.
  /// [specialDiscounts] -- named discounts applied to the whole order.
  /// [orderDiscount] -- single order-level discount.
  /// [additionalCosts] -- extra charges (cover, corkage, etc.).
  /// [serviceFeeOverride] -- manual override for service fee in cents (0 = use config).
  /// [packageFee] -- packaging fee in cents.
  /// [deliveryFee] -- delivery fee in cents.
  /// [temporaryCharge] -- ad-hoc charges added at checkout.
  /// [orderType] -- 'dine_in', 'takeaway', 'delivery'.
  /// [couponAmount] -- coupon deduction in cents.
  /// [payTotal] -- amount already paid in cents.
  /// [changeTotal] -- change already given in cents.
  /// [refundTotal] -- total refunded in cents.
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
    // ------------------------------------------------------------------
    // Step 1: Per-item calculations
    // ------------------------------------------------------------------
    int dishesOriginTotal = 0;
    int dishesTotalPreTax = 0;
    int dishesTaxTotal = 0;

    // Accumulate tax by rate group: taxGroup -> (netBase, taxAmount, taxConfig)
    final taxAccumulator = <String, _TaxAccumEntry>{};

    for (final item in items) {
      final grossPrice = item.grossPrice;
      dishesOriginTotal += grossPrice;

      final netPrice = item.netPrice;

      if (item.isTaxFree) {
        // No tax for this item
        dishesTotalPreTax += netPrice;
        continue;
      }

      final taxConfig = config.findTaxRate(item.taxGroup);
      if (taxConfig == null) {
        // No matching tax config -- treat as tax-free
        dishesTotalPreTax += netPrice;
        continue;
      }

      final effectiveRate = taxConfig.effectiveRate(orderType);
      final useTaxInclusive = item.isTaxInclusive;

      int itemPreTax;
      int itemTax;

      if (useTaxInclusive) {
        // Price includes tax -- extract tax
        itemPreTax = _extractPreTax(netPrice, effectiveRate);
        itemTax = netPrice - itemPreTax;
      } else {
        // Price excludes tax -- add tax
        itemPreTax = netPrice;
        itemTax = _calculateTax(netPrice, effectiveRate);
      }

      dishesTotalPreTax += itemPreTax;
      dishesTaxTotal += itemTax;

      // Accumulate for tax breakdown
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

    // ------------------------------------------------------------------
    // Step 2: Special discounts (order-level named discounts)
    // ------------------------------------------------------------------
    int specialDiscountTotalAmount = 0;
    int taxSpecialDiscountTotal = 0;
    final specialDiscountLines = <SpecialDiscountLine>[];

    if (specialDiscounts != null) {
      for (final discount in specialDiscounts) {
        final discAmount = discount.calculate(dishesTotal);
        int discTax = 0;

        if (discount.affectsTax && dishesTaxTotal > 0 && dishesTotal > 0) {
          // Proportionally reduce tax
          discTax = (discAmount * dishesTaxTotal / dishesTotal).round();
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

    // ------------------------------------------------------------------
    // Step 3: Additional costs
    // ------------------------------------------------------------------
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

    // ------------------------------------------------------------------
    // Step 4: Service fee
    // ------------------------------------------------------------------
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

    // ------------------------------------------------------------------
    // Step 5: Order discount
    // ------------------------------------------------------------------
    // Applied to: dishesTotal - specialDiscounts + additionalCosts + serviceFee
    int orderDiscountTotalAmount = 0;
    int taxOrderDiscountTotal = 0;

    if (orderDiscount != null) {
      final baseForOrderDiscount = dishesTotal - specialDiscountTotalAmount +
          additionalCostTotalAmount + serviceFeeAmount;
      orderDiscountTotalAmount = orderDiscount.calculate(
          baseForOrderDiscount > 0 ? baseForOrderDiscount : 0);

      if (orderDiscount.affectsTax &&
          dishesTaxTotal > 0 &&
          baseForOrderDiscount > 0) {
        // Proportional tax reduction
        final totalTaxInScope =
            dishesTaxTotal - taxSpecialDiscountTotal + serviceFeeTax;
        taxOrderDiscountTotal =
            (orderDiscountTotalAmount * totalTaxInScope / baseForOrderDiscount)
                .round();
      }
    }

    // ------------------------------------------------------------------
    // Step 6: Build tax breakdown with discount adjustments
    // ------------------------------------------------------------------
    final dishesTaxes = <TaxBreakdown>[];
    for (final entry in taxAccumulator.entries) {
      final accum = entry.value;
      int payableAmount = accum.taxAmount;
      bool isDiscounted = false;

      if (accum.config.isDiscountable) {
        // Proportionally reduce tax for discounts affecting this group
        final totalDiscountOnTax =
            taxSpecialDiscountTotal + taxOrderDiscountTotal;
        if (totalDiscountOnTax > 0 && dishesTaxTotal > 0) {
          final groupShare =
              (totalDiscountOnTax * accum.taxAmount / dishesTaxTotal).round();
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

    // ------------------------------------------------------------------
    // Step 7: Calculate receivable (before rounding)
    // ------------------------------------------------------------------
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

    // ------------------------------------------------------------------
    // Step 8: Rounding
    // ------------------------------------------------------------------
    final receivableTotal =
        config.roundingRule.apply(receivableBeforeRounding);
    final roundDownTotal = receivableBeforeRounding - receivableTotal;

    // ------------------------------------------------------------------
    // Step 9: Unpaid balance
    // ------------------------------------------------------------------
    int unpaidTotal = receivableTotal - payTotal + changeTotal + refundTotal;
    if (unpaidTotal < 0) unpaidTotal = 0;

    // ------------------------------------------------------------------
    // Build result
    // ------------------------------------------------------------------
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

  // -------------------------------------------------------------------------
  // Convenience: recalculate from a breakdown with updated payment info
  // -------------------------------------------------------------------------

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

  // -------------------------------------------------------------------------
  // Convenience: create FareLineItems with resolved prices
  // -------------------------------------------------------------------------

  /// Create [FareLineItem]s from order items with prices and tax rates
  /// resolved via [PriceResolver] based on order type and country.
  ///
  /// This bridges the order-item domain entities with the fare calculation
  /// engine, applying order-type-specific pricing (overrides, discounts,
  /// surcharges) and country-specific tax rates before building line items.
  ///
  /// [items] -- order line items from the ticket.
  /// [resolver] -- PriceResolver instance for DB lookups.
  /// [orderType] -- 'dine_in', 'takeaway', or 'delivery'.
  /// [countryCode] -- 'CH' or 'DE'.
  /// [tenantId] -- tenant identifier.
  static Future<List<FareLineItem>> resolveLineItems({
    required List<OrderItemEntity> items,
    required PriceResolver resolver,
    required String orderType,
    required String countryCode,
    required String tenantId,
  }) async {
    final lineItems = <FareLineItem>[];

    for (final item in items) {
      // Determine the product tax group from item context.
      // The taxGroup is stored on the product; for order items we default
      // to 'food' if not available. Callers can set taxGroup on the
      // FareLineItem after resolution if needed.
      const defaultTaxGroup = 'food';

      // Resolve the modifier total for this item
      final modifierTotal =
          item.modifiers.fold<int>(0, (sum, m) => sum + m.priceDelta);

      // Resolve price for the base product (without modifiers)
      final resolved = await resolver.resolvePrice(
        productId: item.productId,
        basePrice: item.unitPrice,
        productTaxGroup: defaultTaxGroup,
        orderType: orderType,
        countryCode: countryCode,
        tenantId: tenantId,
      );

      lineItems.add(FareLineItem(
        productId: item.productId,
        productName: item.productName,
        quantity: item.quantity.ceil(),
        unitPrice: resolved.grossPrice,
        modifierTotal: modifierTotal,
        taxGroup: resolved.taxName,
        isTaxFree: item.isTaxFree,
        isTaxInclusive: resolved.isTaxInclusive,
        specialDiscountAmount: item.specialDiscountAmount,
        weight: item.weight != null ? (item.weight! * 1000).round() : 0,
        isWeightBased: item.isWeightBased,
      ));
    }

    return lineItems;
  }

  // -------------------------------------------------------------------------
  // Internal helpers
  // -------------------------------------------------------------------------

  /// Extract pre-tax amount from a tax-inclusive price.
  /// Formula: preTax = price / (1 + rate/100)
  static int _extractPreTax(int inclusivePrice, double ratePercent) {
    if (ratePercent <= 0) return inclusivePrice;
    final divisor = 1.0 + ratePercent / 100.0;
    return (inclusivePrice / divisor).round();
  }

  /// Calculate tax from a tax-exclusive price.
  /// Formula: tax = price * rate / 100
  static int _calculateTax(int exclusivePrice, double ratePercent) {
    if (ratePercent <= 0) return 0;
    return (exclusivePrice * ratePercent / 100.0).round();
  }
}

// ---------------------------------------------------------------------------
// Internal accumulator for grouping tax by rate
// ---------------------------------------------------------------------------

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
