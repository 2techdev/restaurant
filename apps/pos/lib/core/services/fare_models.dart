/// Data models for the GastroCore Fare Calculation Engine.
///
/// These models mirror OrderPin's comprehensive fare breakdown, supporting
/// Swiss and EU tax regimes, service fees, special discounts, additional
/// costs, coupons, and rounding. All monetary values are in cents (int).
library;

// ---------------------------------------------------------------------------
// Rounding
// ---------------------------------------------------------------------------

/// How to round the final receivable amount.
class RoundingRule {
  /// 'floor', 'round', 'ceil'
  final String rule;

  /// 'percentile' (0.01), 'five_percent' (0.05), 'tenths' (0.10), 'units' (1.00)
  final String unit;

  const RoundingRule({
    this.rule = 'round',
    this.unit = 'percentile',
  });

  /// Returns the rounding unit in cents.
  int get unitInCents {
    switch (unit) {
      case 'five_percent':
        return 5;
      case 'tenths':
        return 10;
      case 'units':
        return 100;
      case 'percentile':
      default:
        return 1;
    }
  }

  /// Apply this rounding rule to [amount] in cents.
  int apply(int amount) {
    final u = unitInCents;
    if (u <= 1) return amount;
    switch (rule) {
      case 'floor':
        return (amount ~/ u) * u;
      case 'ceil':
        return ((amount + u - 1) ~/ u) * u;
      case 'round':
      default:
        final remainder = amount % u;
        if (remainder >= (u / 2).ceil()) {
          return amount + (u - remainder);
        }
        return amount - remainder;
    }
  }

  RoundingRule copyWith({String? rule, String? unit}) {
    return RoundingRule(
      rule: rule ?? this.rule,
      unit: unit ?? this.unit,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoundingRule &&
          runtimeType == other.runtimeType &&
          rule == other.rule &&
          unit == other.unit;

  @override
  int get hashCode => Object.hash(rule, unit);

  @override
  String toString() => 'RoundingRule(rule: $rule, unit: $unit)';
}

// ---------------------------------------------------------------------------
// Tax Rate Config
// ---------------------------------------------------------------------------

/// Configuration for a single tax rate (e.g. "MwSt 8.1%").
class TaxRateConfig {
  final String name;

  /// Percentage, e.g. 8.1 for Swiss standard rate.
  final double rate;

  /// If true, discounts reduce the tax base proportionally.
  final bool isDiscountable;

  /// Override rate for dine-in orders (Swiss dual-rate system).
  final String? dineInRate;

  /// Override rate for takeaway orders.
  final String? takeawayRate;

  const TaxRateConfig({
    required this.name,
    required this.rate,
    this.isDiscountable = true,
    this.dineInRate,
    this.takeawayRate,
  });

  /// Resolve the effective rate for a given order type.
  double effectiveRate(String orderType) {
    if (orderType == 'takeaway' || orderType == 'delivery') {
      if (takeawayRate != null) return double.parse(takeawayRate!);
    }
    if (orderType == 'dine_in') {
      if (dineInRate != null) return double.parse(dineInRate!);
    }
    return rate;
  }

  TaxRateConfig copyWith({
    String? name,
    double? rate,
    bool? isDiscountable,
    String? Function()? dineInRate,
    String? Function()? takeawayRate,
  }) {
    return TaxRateConfig(
      name: name ?? this.name,
      rate: rate ?? this.rate,
      isDiscountable: isDiscountable ?? this.isDiscountable,
      dineInRate: dineInRate != null ? dineInRate() : this.dineInRate,
      takeawayRate: takeawayRate != null ? takeawayRate() : this.takeawayRate,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaxRateConfig &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          rate == other.rate &&
          isDiscountable == other.isDiscountable &&
          dineInRate == other.dineInRate &&
          takeawayRate == other.takeawayRate;

  @override
  int get hashCode => Object.hash(name, rate, isDiscountable, dineInRate, takeawayRate);

  @override
  String toString() => 'TaxRateConfig(name: $name, rate: $rate)';
}

// ---------------------------------------------------------------------------
// Service Fee Config
// ---------------------------------------------------------------------------

/// How service fee is calculated.
class ServiceFeeConfig {
  /// 'fixed_amount' or 'order_amount_ratio'
  final String takenType;

  /// Fixed amount in cents, or ratio * 1000 (e.g. 10% = 100).
  final int value;

  /// Whether the service fee itself is taxable.
  final bool isTaxable;

  /// Tax rate name to use when service fee is taxable.
  final String? taxGroup;

  /// Which order types get service fee applied.
  final List<String> orderTypes;

  const ServiceFeeConfig({
    required this.takenType,
    required this.value,
    this.isTaxable = false,
    this.taxGroup,
    this.orderTypes = const ['dine_in', 'takeaway', 'delivery'],
  });

  /// Calculate the service fee from a base amount (dishes total in cents).
  int calculate(int baseAmount) {
    switch (takenType) {
      case 'fixed_amount':
        return value;
      case 'order_amount_ratio':
        // value is ratio * 1000, e.g. 10% = 100
        return (baseAmount * value / 1000).round();
      default:
        return 0;
    }
  }

  ServiceFeeConfig copyWith({
    String? takenType,
    int? value,
    bool? isTaxable,
    String? Function()? taxGroup,
    List<String>? orderTypes,
  }) {
    return ServiceFeeConfig(
      takenType: takenType ?? this.takenType,
      value: value ?? this.value,
      isTaxable: isTaxable ?? this.isTaxable,
      taxGroup: taxGroup != null ? taxGroup() : this.taxGroup,
      orderTypes: orderTypes ?? this.orderTypes,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ServiceFeeConfig &&
          runtimeType == other.runtimeType &&
          takenType == other.takenType &&
          value == other.value &&
          isTaxable == other.isTaxable &&
          taxGroup == other.taxGroup;

  @override
  int get hashCode => Object.hash(takenType, value, isTaxable, taxGroup);

  @override
  String toString() =>
      'ServiceFeeConfig(takenType: $takenType, value: $value, isTaxable: $isTaxable)';
}

// ---------------------------------------------------------------------------
// Fare Config
// ---------------------------------------------------------------------------

/// Top-level fare configuration for a venue/tenant.
class FareConfig {
  /// Whether prices entered include tax (Swiss standard: true).
  final bool isTaxInclusive;

  /// Currency code (CHF, EUR, USD).
  final String currency;

  /// How to round the final receivable.
  final RoundingRule roundingRule;

  /// Service fee calculation rules.
  final ServiceFeeConfig? serviceFee;

  /// Available tax rates for this venue.
  final List<TaxRateConfig> taxRates;

  const FareConfig({
    this.isTaxInclusive = true,
    this.currency = 'CHF',
    this.roundingRule = const RoundingRule(),
    this.serviceFee,
    this.taxRates = const [],
  });

  /// Find tax rate config by group name. Returns null if not found.
  TaxRateConfig? findTaxRate(String taxGroup) {
    for (final rate in taxRates) {
      if (rate.name == taxGroup) return rate;
    }
    return null;
  }

  FareConfig copyWith({
    bool? isTaxInclusive,
    String? currency,
    RoundingRule? roundingRule,
    ServiceFeeConfig? Function()? serviceFee,
    List<TaxRateConfig>? taxRates,
  }) {
    return FareConfig(
      isTaxInclusive: isTaxInclusive ?? this.isTaxInclusive,
      currency: currency ?? this.currency,
      roundingRule: roundingRule ?? this.roundingRule,
      serviceFee: serviceFee != null ? serviceFee() : this.serviceFee,
      taxRates: taxRates ?? this.taxRates,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FareConfig &&
          runtimeType == other.runtimeType &&
          isTaxInclusive == other.isTaxInclusive &&
          currency == other.currency &&
          roundingRule == other.roundingRule &&
          serviceFee == other.serviceFee;

  @override
  int get hashCode =>
      Object.hash(isTaxInclusive, currency, roundingRule, serviceFee);

  @override
  String toString() =>
      'FareConfig(currency: $currency, taxInclusive: $isTaxInclusive)';
}

// ---------------------------------------------------------------------------
// Fare Line Item (per order item input)
// ---------------------------------------------------------------------------

/// Input model representing one order item for fare calculation.
class FareLineItem {
  final String productId;
  final String productName;
  final int quantity;

  /// Unit price in cents before modifiers.
  final int unitPrice;

  /// Total modifier price in cents (sum of all modifier deltas).
  final int modifierTotal;

  /// Tax group name to look up in [FareConfig.taxRates].
  final String taxGroup;

  /// Whether this item is tax-exempt.
  final bool isTaxFree;

  /// Whether this item's price includes tax.
  final bool isTaxInclusive;

  /// Per-item special discount amount in cents.
  final int specialDiscountAmount;

  /// Weight in grams for weight-based items.
  final int weight;

  /// Whether this is a weight-based item.
  final bool isWeightBased;

  const FareLineItem({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    this.modifierTotal = 0,
    required this.taxGroup,
    this.isTaxFree = false,
    this.isTaxInclusive = true,
    this.specialDiscountAmount = 0,
    this.weight = 0,
    this.isWeightBased = false,
  });

  /// Gross item price in cents before discounts.
  int get grossPrice {
    if (isWeightBased) {
      // unitPrice is per kg, weight is in grams
      return ((unitPrice * weight) / 1000).round() + modifierTotal * quantity;
    }
    return (unitPrice + modifierTotal) * quantity;
  }

  /// Net item price after per-item discount.
  int get netPrice {
    final gross = grossPrice;
    return gross > specialDiscountAmount ? gross - specialDiscountAmount : 0;
  }

  FareLineItem copyWith({
    String? productId,
    String? productName,
    int? quantity,
    int? unitPrice,
    int? modifierTotal,
    String? taxGroup,
    bool? isTaxFree,
    bool? isTaxInclusive,
    int? specialDiscountAmount,
    int? weight,
    bool? isWeightBased,
  }) {
    return FareLineItem(
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      modifierTotal: modifierTotal ?? this.modifierTotal,
      taxGroup: taxGroup ?? this.taxGroup,
      isTaxFree: isTaxFree ?? this.isTaxFree,
      isTaxInclusive: isTaxInclusive ?? this.isTaxInclusive,
      specialDiscountAmount:
          specialDiscountAmount ?? this.specialDiscountAmount,
      weight: weight ?? this.weight,
      isWeightBased: isWeightBased ?? this.isWeightBased,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FareLineItem &&
          runtimeType == other.runtimeType &&
          productId == other.productId &&
          quantity == other.quantity &&
          unitPrice == other.unitPrice &&
          modifierTotal == other.modifierTotal &&
          taxGroup == other.taxGroup &&
          isTaxFree == other.isTaxFree &&
          specialDiscountAmount == other.specialDiscountAmount &&
          weight == other.weight &&
          isWeightBased == other.isWeightBased;

  @override
  int get hashCode => Object.hash(
        productId,
        quantity,
        unitPrice,
        modifierTotal,
        taxGroup,
        isTaxFree,
        specialDiscountAmount,
        weight,
        isWeightBased,
      );

  @override
  String toString() =>
      'FareLineItem(product: $productName, qty: $quantity, unitPrice: $unitPrice)';
}

// ---------------------------------------------------------------------------
// Tax Breakdown
// ---------------------------------------------------------------------------

/// Tax calculation result for a single rate group.
class TaxBreakdown {
  /// Display name, e.g. "MwSt 8.1%".
  final String name;

  /// Rate as string, e.g. "8.1".
  final String rate;

  /// Calculated tax amount in cents (full, before discount adjustments).
  final int amount;

  /// Tax actually payable after discount adjustments.
  final int payableAmount;

  /// Whether discounts affected this tax group's base.
  final bool isDiscounted;

  const TaxBreakdown({
    required this.name,
    required this.rate,
    required this.amount,
    required this.payableAmount,
    this.isDiscounted = false,
  });

  TaxBreakdown copyWith({
    String? name,
    String? rate,
    int? amount,
    int? payableAmount,
    bool? isDiscounted,
  }) {
    return TaxBreakdown(
      name: name ?? this.name,
      rate: rate ?? this.rate,
      amount: amount ?? this.amount,
      payableAmount: payableAmount ?? this.payableAmount,
      isDiscounted: isDiscounted ?? this.isDiscounted,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaxBreakdown &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          rate == other.rate &&
          amount == other.amount &&
          payableAmount == other.payableAmount &&
          isDiscounted == other.isDiscounted;

  @override
  int get hashCode => Object.hash(name, rate, amount, payableAmount, isDiscounted);

  @override
  String toString() =>
      'TaxBreakdown(name: $name, rate: $rate, amount: $amount, payable: $payableAmount)';
}

// ---------------------------------------------------------------------------
// Special Discount
// ---------------------------------------------------------------------------

/// Input model: a named special discount (e.g. "Staff Discount", "Happy Hour").
class SpecialDiscount {
  final String id;
  final String name;

  /// 'fixed' or 'percentage'.
  final String type;

  /// Fixed amount in cents, or percentage * 100 (e.g. 10% = 1000).
  final int value;

  /// Whether this discount reduces the tax base.
  final bool affectsTax;

  const SpecialDiscount({
    required this.id,
    required this.name,
    required this.type,
    required this.value,
    this.affectsTax = true,
  });

  /// Calculate the discount amount for a given base.
  int calculate(int baseAmount) {
    switch (type) {
      case 'percentage':
        return (baseAmount * value / 10000).round();
      case 'fixed':
      default:
        return value > baseAmount ? baseAmount : value;
    }
  }

  SpecialDiscount copyWith({
    String? id,
    String? name,
    String? type,
    int? value,
    bool? affectsTax,
  }) {
    return SpecialDiscount(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      value: value ?? this.value,
      affectsTax: affectsTax ?? this.affectsTax,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpecialDiscount &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          type == other.type &&
          value == other.value &&
          affectsTax == other.affectsTax;

  @override
  int get hashCode => Object.hash(id, name, type, value, affectsTax);

  @override
  String toString() =>
      'SpecialDiscount(id: $id, name: $name, type: $type, value: $value)';
}

/// Output model: a special discount as applied in the fare breakdown.
class SpecialDiscountLine {
  final String id;
  final String name;
  final int amount;
  final int taxAmount;

  const SpecialDiscountLine({
    required this.id,
    required this.name,
    required this.amount,
    this.taxAmount = 0,
  });

  SpecialDiscountLine copyWith({
    String? id,
    String? name,
    int? amount,
    int? taxAmount,
  }) {
    return SpecialDiscountLine(
      id: id ?? this.id,
      name: name ?? this.name,
      amount: amount ?? this.amount,
      taxAmount: taxAmount ?? this.taxAmount,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpecialDiscountLine &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          amount == other.amount &&
          taxAmount == other.taxAmount;

  @override
  int get hashCode => Object.hash(id, name, amount, taxAmount);

  @override
  String toString() =>
      'SpecialDiscountLine(id: $id, name: $name, amount: $amount)';
}

// ---------------------------------------------------------------------------
// Order Discount
// ---------------------------------------------------------------------------

/// A whole-order discount (applied after all items and special discounts).
class OrderDiscount {
  /// 'fixed' or 'percentage'.
  final String type;

  /// Fixed amount in cents, or percentage * 100 (e.g. 15% = 1500).
  final int value;

  /// Label for display.
  final String? label;

  /// Whether this discount reduces the tax base.
  final bool affectsTax;

  const OrderDiscount({
    required this.type,
    required this.value,
    this.label,
    this.affectsTax = true,
  });

  /// Calculate the discount amount for a given base.
  int calculate(int baseAmount) {
    switch (type) {
      case 'percentage':
        return (baseAmount * value / 10000).round();
      case 'fixed':
      default:
        return value > baseAmount ? baseAmount : value;
    }
  }

  OrderDiscount copyWith({
    String? type,
    int? value,
    String? Function()? label,
    bool? affectsTax,
  }) {
    return OrderDiscount(
      type: type ?? this.type,
      value: value ?? this.value,
      label: label != null ? label() : this.label,
      affectsTax: affectsTax ?? this.affectsTax,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrderDiscount &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          value == other.value &&
          label == other.label &&
          affectsTax == other.affectsTax;

  @override
  int get hashCode => Object.hash(type, value, label, affectsTax);

  @override
  String toString() => 'OrderDiscount(type: $type, value: $value)';
}

// ---------------------------------------------------------------------------
// Additional Cost
// ---------------------------------------------------------------------------

/// An additional cost line (e.g. "Cover Charge", "Corkage Fee").
class AdditionalCost {
  final String id;
  final String name;

  /// Amount in cents.
  final int amount;

  /// Tax group name for this cost.
  final String? taxGroup;

  /// Whether this cost is taxable.
  final bool isTaxable;

  const AdditionalCost({
    required this.id,
    required this.name,
    required this.amount,
    this.taxGroup,
    this.isTaxable = false,
  });

  AdditionalCost copyWith({
    String? id,
    String? name,
    int? amount,
    String? Function()? taxGroup,
    bool? isTaxable,
  }) {
    return AdditionalCost(
      id: id ?? this.id,
      name: name ?? this.name,
      amount: amount ?? this.amount,
      taxGroup: taxGroup != null ? taxGroup() : this.taxGroup,
      isTaxable: isTaxable ?? this.isTaxable,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdditionalCost &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          amount == other.amount &&
          taxGroup == other.taxGroup &&
          isTaxable == other.isTaxable;

  @override
  int get hashCode => Object.hash(id, name, amount, taxGroup, isTaxable);

  @override
  String toString() => 'AdditionalCost(id: $id, name: $name, amount: $amount)';
}

/// Output model: an additional cost as it appears in the fare breakdown.
class AdditionalCostLine {
  final String id;
  final String name;
  final int amount;
  final int taxAmount;

  const AdditionalCostLine({
    required this.id,
    required this.name,
    required this.amount,
    this.taxAmount = 0,
  });

  AdditionalCostLine copyWith({
    String? id,
    String? name,
    int? amount,
    int? taxAmount,
  }) {
    return AdditionalCostLine(
      id: id ?? this.id,
      name: name ?? this.name,
      amount: amount ?? this.amount,
      taxAmount: taxAmount ?? this.taxAmount,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdditionalCostLine &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          amount == other.amount &&
          taxAmount == other.taxAmount;

  @override
  int get hashCode => Object.hash(id, name, amount, taxAmount);

  @override
  String toString() =>
      'AdditionalCostLine(id: $id, name: $name, amount: $amount)';
}

// ---------------------------------------------------------------------------
// Fare Breakdown (output)
// ---------------------------------------------------------------------------

/// Complete fare calculation result matching OrderPin's depth.
///
/// All amounts are in cents (int).
class FareBreakdown {
  /// Original total before any discounts.
  final int dishesOriginTotal;

  /// Dishes total before tax.
  final int dishesTotalPreTax;

  /// Total tax on dishes.
  final int dishesTaxTotal;

  /// Dishes total including tax.
  final int dishesTotal;

  /// Tax breakdown by rate group.
  final List<TaxBreakdown> dishesTaxes;

  /// Sum of additional costs.
  final int additionalCostTotal;

  /// Individual additional cost lines.
  final List<AdditionalCostLine> additionalCosts;

  /// Service fee (tax included if applicable).
  final int serviceFeeAmount;

  /// Tax portion of the service fee.
  final int serviceFeeTax;

  /// Packaging fee (takeaway/delivery).
  final int packageFee;

  /// Delivery fee.
  final int deliveryFee;

  /// Charges added at checkout.
  final int temporaryChargeTotal;

  /// Named special discounts total.
  final int specialDiscountTotal;

  /// Tax portion of special discounts.
  final int taxSpecialDiscountTotal;

  /// Individual special discount lines.
  final List<SpecialDiscountLine> specialDiscounts;

  /// Whole-order discount total (including tax portion).
  final int orderDiscountTotal;

  /// Tax portion of order discount.
  final int taxOrderDiscountTotal;

  /// Coupon deduction in cents.
  final int couponTotal;

  /// Rounding adjustment in cents.
  final int roundDownTotal;

  /// What the customer should pay.
  final int receivableTotal;

  /// Remaining unpaid balance.
  final int unpaidTotal;

  /// Actually paid so far.
  final int payTotal;

  /// Change given.
  final int changeTotal;

  /// Total refunded.
  final int refundTotal;

  /// Currency code.
  final String currency;

  const FareBreakdown({
    this.dishesOriginTotal = 0,
    this.dishesTotalPreTax = 0,
    this.dishesTaxTotal = 0,
    this.dishesTotal = 0,
    this.dishesTaxes = const [],
    this.additionalCostTotal = 0,
    this.additionalCosts = const [],
    this.serviceFeeAmount = 0,
    this.serviceFeeTax = 0,
    this.packageFee = 0,
    this.deliveryFee = 0,
    this.temporaryChargeTotal = 0,
    this.specialDiscountTotal = 0,
    this.taxSpecialDiscountTotal = 0,
    this.specialDiscounts = const [],
    this.orderDiscountTotal = 0,
    this.taxOrderDiscountTotal = 0,
    this.couponTotal = 0,
    this.roundDownTotal = 0,
    this.receivableTotal = 0,
    this.unpaidTotal = 0,
    this.payTotal = 0,
    this.changeTotal = 0,
    this.refundTotal = 0,
    this.currency = 'CHF',
  });

  FareBreakdown copyWith({
    int? dishesOriginTotal,
    int? dishesTotalPreTax,
    int? dishesTaxTotal,
    int? dishesTotal,
    List<TaxBreakdown>? dishesTaxes,
    int? additionalCostTotal,
    List<AdditionalCostLine>? additionalCosts,
    int? serviceFeeAmount,
    int? serviceFeeTax,
    int? packageFee,
    int? deliveryFee,
    int? temporaryChargeTotal,
    int? specialDiscountTotal,
    int? taxSpecialDiscountTotal,
    List<SpecialDiscountLine>? specialDiscounts,
    int? orderDiscountTotal,
    int? taxOrderDiscountTotal,
    int? couponTotal,
    int? roundDownTotal,
    int? receivableTotal,
    int? unpaidTotal,
    int? payTotal,
    int? changeTotal,
    int? refundTotal,
    String? currency,
  }) {
    return FareBreakdown(
      dishesOriginTotal: dishesOriginTotal ?? this.dishesOriginTotal,
      dishesTotalPreTax: dishesTotalPreTax ?? this.dishesTotalPreTax,
      dishesTaxTotal: dishesTaxTotal ?? this.dishesTaxTotal,
      dishesTotal: dishesTotal ?? this.dishesTotal,
      dishesTaxes: dishesTaxes ?? this.dishesTaxes,
      additionalCostTotal: additionalCostTotal ?? this.additionalCostTotal,
      additionalCosts: additionalCosts ?? this.additionalCosts,
      serviceFeeAmount: serviceFeeAmount ?? this.serviceFeeAmount,
      serviceFeeTax: serviceFeeTax ?? this.serviceFeeTax,
      packageFee: packageFee ?? this.packageFee,
      deliveryFee: deliveryFee ?? this.deliveryFee,
      temporaryChargeTotal: temporaryChargeTotal ?? this.temporaryChargeTotal,
      specialDiscountTotal: specialDiscountTotal ?? this.specialDiscountTotal,
      taxSpecialDiscountTotal:
          taxSpecialDiscountTotal ?? this.taxSpecialDiscountTotal,
      specialDiscounts: specialDiscounts ?? this.specialDiscounts,
      orderDiscountTotal: orderDiscountTotal ?? this.orderDiscountTotal,
      taxOrderDiscountTotal:
          taxOrderDiscountTotal ?? this.taxOrderDiscountTotal,
      couponTotal: couponTotal ?? this.couponTotal,
      roundDownTotal: roundDownTotal ?? this.roundDownTotal,
      receivableTotal: receivableTotal ?? this.receivableTotal,
      unpaidTotal: unpaidTotal ?? this.unpaidTotal,
      payTotal: payTotal ?? this.payTotal,
      changeTotal: changeTotal ?? this.changeTotal,
      refundTotal: refundTotal ?? this.refundTotal,
      currency: currency ?? this.currency,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FareBreakdown &&
          runtimeType == other.runtimeType &&
          dishesOriginTotal == other.dishesOriginTotal &&
          dishesTotalPreTax == other.dishesTotalPreTax &&
          dishesTaxTotal == other.dishesTaxTotal &&
          dishesTotal == other.dishesTotal &&
          additionalCostTotal == other.additionalCostTotal &&
          serviceFeeAmount == other.serviceFeeAmount &&
          serviceFeeTax == other.serviceFeeTax &&
          packageFee == other.packageFee &&
          deliveryFee == other.deliveryFee &&
          temporaryChargeTotal == other.temporaryChargeTotal &&
          specialDiscountTotal == other.specialDiscountTotal &&
          orderDiscountTotal == other.orderDiscountTotal &&
          couponTotal == other.couponTotal &&
          roundDownTotal == other.roundDownTotal &&
          receivableTotal == other.receivableTotal &&
          unpaidTotal == other.unpaidTotal &&
          payTotal == other.payTotal &&
          changeTotal == other.changeTotal &&
          refundTotal == other.refundTotal &&
          currency == other.currency;

  @override
  int get hashCode => Object.hash(
        dishesOriginTotal,
        dishesTotalPreTax,
        dishesTaxTotal,
        dishesTotal,
        additionalCostTotal,
        serviceFeeAmount,
        packageFee,
        deliveryFee,
        specialDiscountTotal,
        orderDiscountTotal,
        couponTotal,
        roundDownTotal,
        receivableTotal,
        unpaidTotal,
        payTotal,
        changeTotal,
      );

  @override
  String toString() =>
      'FareBreakdown(receivable: $receivableTotal, paid: $payTotal, '
      'dishes: $dishesTotal, tax: $dishesTaxTotal, '
      'discounts: ${specialDiscountTotal + orderDiscountTotal}, '
      'currency: $currency)';
}
