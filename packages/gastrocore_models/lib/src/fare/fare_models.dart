/// Data models for the GastroCore Fare Calculation Engine.
///
/// All monetary values are in cents (int).
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
    return RoundingRule(rule: rule ?? this.rule, unit: unit ?? this.unit);
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

class TaxRateConfig {
  final String name;
  final double rate;
  final bool isDiscountable;
  final String? dineInRate;
  final String? takeawayRate;

  const TaxRateConfig({
    required this.name,
    required this.rate,
    this.isDiscountable = true,
    this.dineInRate,
    this.takeawayRate,
  });

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
          rate == other.rate;

  @override
  int get hashCode => Object.hash(name, rate, isDiscountable);

  @override
  String toString() => 'TaxRateConfig(name: $name, rate: $rate)';
}

// ---------------------------------------------------------------------------
// Service Fee Config
// ---------------------------------------------------------------------------

class ServiceFeeConfig {
  final String takenType; // 'fixed_amount' | 'order_amount_ratio'
  final int value;
  final bool isTaxable;
  final String? taxGroup;
  final List<String> orderTypes;

  const ServiceFeeConfig({
    required this.takenType,
    required this.value,
    this.isTaxable = false,
    this.taxGroup,
    this.orderTypes = const ['dine_in', 'takeaway', 'delivery'],
  });

  int calculate(int baseAmount) {
    switch (takenType) {
      case 'fixed_amount':
        return value;
      case 'order_amount_ratio':
        return (baseAmount * value / 1000).round();
      default:
        return 0;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ServiceFeeConfig &&
          runtimeType == other.runtimeType &&
          takenType == other.takenType &&
          value == other.value;

  @override
  int get hashCode => Object.hash(takenType, value, isTaxable, taxGroup);

  @override
  String toString() =>
      'ServiceFeeConfig(takenType: $takenType, value: $value)';
}

// ---------------------------------------------------------------------------
// Fare Config
// ---------------------------------------------------------------------------

class FareConfig {
  final bool isTaxInclusive;
  final String currency;
  final RoundingRule roundingRule;
  final ServiceFeeConfig? serviceFee;
  final List<TaxRateConfig> taxRates;

  const FareConfig({
    this.isTaxInclusive = true,
    this.currency = 'CHF',
    this.roundingRule = const RoundingRule(),
    this.serviceFee,
    this.taxRates = const [],
  });

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
          currency == other.currency;

  @override
  int get hashCode =>
      Object.hash(isTaxInclusive, currency, roundingRule, serviceFee);

  @override
  String toString() =>
      'FareConfig(currency: $currency, taxInclusive: $isTaxInclusive)';
}

// ---------------------------------------------------------------------------
// Fare Line Item
// ---------------------------------------------------------------------------

class FareLineItem {
  final String productId;
  final String productName;
  final int quantity;
  final int unitPrice;
  final int modifierTotal;
  final String taxGroup;
  final bool isTaxFree;
  final bool isTaxInclusive;
  final int specialDiscountAmount;
  final int weight;
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

  int get grossPrice {
    if (isWeightBased) {
      return ((unitPrice * weight) / 1000).round() +
          modifierTotal * quantity;
    }
    return (unitPrice + modifierTotal) * quantity;
  }

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
  String toString() =>
      'FareLineItem(product: $productName, qty: $quantity, unitPrice: $unitPrice)';
}

// ---------------------------------------------------------------------------
// Tax Breakdown
// ---------------------------------------------------------------------------

class TaxBreakdown {
  final String name;
  final String rate;
  final int amount;
  final int payableAmount;
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
          payableAmount == other.payableAmount;

  @override
  int get hashCode =>
      Object.hash(name, rate, amount, payableAmount, isDiscounted);

  @override
  String toString() =>
      'TaxBreakdown(name: $name, rate: $rate, amount: $amount, payable: $payableAmount)';
}

// ---------------------------------------------------------------------------
// Special Discount
// ---------------------------------------------------------------------------

class SpecialDiscount {
  final String id;
  final String name;
  final String type; // 'fixed' | 'percentage'
  final int value;
  final bool affectsTax;

  const SpecialDiscount({
    required this.id,
    required this.name,
    required this.type,
    required this.value,
    this.affectsTax = true,
  });

  int calculate(int baseAmount) {
    switch (type) {
      case 'percentage':
        return (baseAmount * value / 10000).round();
      case 'fixed':
      default:
        return value > baseAmount ? baseAmount : value;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpecialDiscount &&
          id == other.id &&
          name == other.name &&
          type == other.type &&
          value == other.value;

  @override
  int get hashCode => Object.hash(id, name, type, value, affectsTax);

  @override
  String toString() =>
      'SpecialDiscount(id: $id, name: $name, type: $type, value: $value)';
}

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
  String toString() =>
      'SpecialDiscountLine(id: $id, name: $name, amount: $amount)';
}

// ---------------------------------------------------------------------------
// Order Discount
// ---------------------------------------------------------------------------

class OrderDiscount {
  final String type; // 'fixed' | 'percentage'
  final int value;
  final String? label;
  final bool affectsTax;

  const OrderDiscount({
    required this.type,
    required this.value,
    this.label,
    this.affectsTax = true,
  });

  int calculate(int baseAmount) {
    switch (type) {
      case 'percentage':
        return (baseAmount * value / 10000).round();
      case 'fixed':
      default:
        return value > baseAmount ? baseAmount : value;
    }
  }

  @override
  String toString() => 'OrderDiscount(type: $type, value: $value)';
}

// ---------------------------------------------------------------------------
// Additional Cost
// ---------------------------------------------------------------------------

class AdditionalCost {
  final String id;
  final String name;
  final int amount;
  final String? taxGroup;
  final bool isTaxable;

  const AdditionalCost({
    required this.id,
    required this.name,
    required this.amount,
    this.taxGroup,
    this.isTaxable = false,
  });

  @override
  String toString() =>
      'AdditionalCost(id: $id, name: $name, amount: $amount)';
}

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
  String toString() =>
      'AdditionalCostLine(id: $id, name: $name, amount: $amount)';
}

// ---------------------------------------------------------------------------
// Fare Breakdown (output)
// ---------------------------------------------------------------------------

class FareBreakdown {
  final int dishesOriginTotal;
  final int dishesTotalPreTax;
  final int dishesTaxTotal;
  final int dishesTotal;
  final List<TaxBreakdown> dishesTaxes;
  final int additionalCostTotal;
  final List<AdditionalCostLine> additionalCosts;
  final int serviceFeeAmount;
  final int serviceFeeTax;
  final int packageFee;
  final int deliveryFee;
  final int temporaryChargeTotal;
  final int specialDiscountTotal;
  final int taxSpecialDiscountTotal;
  final List<SpecialDiscountLine> specialDiscounts;
  final int orderDiscountTotal;
  final int taxOrderDiscountTotal;
  final int couponTotal;
  final int roundDownTotal;
  final int receivableTotal;
  final int unpaidTotal;
  final int payTotal;
  final int changeTotal;
  final int refundTotal;
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
  String toString() =>
      'FareBreakdown(receivable: $receivableTotal, paid: $payTotal, '
      'dishes: $dishesTotal, tax: $dishesTaxTotal, currency: $currency)';
}
