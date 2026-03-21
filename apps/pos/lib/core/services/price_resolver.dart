/// Price and tax resolution service for order-type-based pricing.
///
/// Resolves the correct price and tax rate for a product based on the
/// order type (dine-in, takeaway, delivery) and country (CH, DE).
///
/// Resolution order:
/// 1. Check ProductPrices for order-type-specific price override
/// 2. If no override, use product's base price
/// 3. Apply OrderTypeRules (discount/surcharge) if any
/// 4. Look up TaxProfiles for correct VAT rate based on country + order type + tax group
/// 5. Return resolved price + tax rate
library;

import 'package:drift/drift.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';

/// Resolves the correct price and tax rate for a product based on order type.
class PriceResolver {
  final AppDatabase db;

  PriceResolver(this.db);

  /// Resolve price for a product given order type and country.
  ///
  /// [productId] - the product to resolve pricing for.
  /// [basePrice] - the product's base price in cents.
  /// [productTaxGroup] - tax group identifier (e.g. 'food', 'beverage', 'alcohol').
  /// [orderType] - 'dine_in', 'takeaway', or 'delivery'.
  /// [countryCode] - 'CH' or 'DE'.
  /// [tenantId] - tenant identifier for multi-tenant isolation.
  Future<ResolvedPrice> resolvePrice({
    required String productId,
    required int basePrice,
    required String productTaxGroup,
    required String orderType,
    required String countryCode,
    required String tenantId,
  }) async {
    // 1. Check for order-type price override
    int effectivePrice = basePrice;
    final priceOverride = await _findPriceOverride(
      productId: productId,
      orderType: orderType,
      tenantId: tenantId,
    );
    if (priceOverride != null) {
      effectivePrice = priceOverride.price;
    }

    // 2. Apply order-type rules (discount/surcharge)
    int adjustmentAmount = 0;
    String? adjustmentDescription;
    final rules = await _findActiveRules(
      orderType: orderType,
      tenantId: tenantId,
    );
    for (final rule in rules) {
      final result = _applyRule(effectivePrice, rule);
      adjustmentAmount += result.amount;
      adjustmentDescription = rule.description ?? _defaultRuleDescription(rule);
    }

    final grossPrice = effectivePrice + adjustmentAmount;

    // 3. Resolve tax rate from TaxProfiles
    final taxResult = await _resolveTaxProfile(
      countryCode: countryCode,
      orderType: orderType,
      productTaxGroup: productTaxGroup,
      tenantId: tenantId,
    );

    // 4. Calculate tax amount (tax-inclusive: extract from gross)
    // In CH and DE, consumer prices are always tax-inclusive.
    const isTaxInclusive = true;
    int netPrice;
    int taxAmount;

    if (taxResult.rate > 0) {
      // Extract tax from gross: net = gross / (1 + rate/100)
      // In CH and DE, consumer prices are always tax-inclusive.
      final divisor = 1.0 + taxResult.rate / 100.0;
      netPrice = (grossPrice / divisor).round();
      taxAmount = grossPrice - netPrice;
    } else {
      netPrice = grossPrice;
      taxAmount = 0;
    }

    return ResolvedPrice(
      grossPrice: grossPrice,
      netPrice: netPrice,
      taxRate: taxResult.rate,
      taxName: taxResult.name,
      taxAmount: taxAmount,
      originalPrice: basePrice,
      adjustmentAmount: adjustmentAmount,
      adjustmentDescription: adjustmentDescription,
      orderType: orderType,
      isTaxInclusive: isTaxInclusive,
    );
  }

  /// Resolve tax rate for given parameters.
  ///
  /// Returns the tax rate percentage for the given country, order type, and
  /// product tax group. Falls back to wildcard order type '*' if no specific
  /// match is found, then to a default rate of 0.0.
  Future<double> resolveTaxRate({
    required String countryCode,
    required String orderType,
    required String productTaxGroup,
    required String tenantId,
  }) async {
    final result = await _resolveTaxProfile(
      countryCode: countryCode,
      orderType: orderType,
      productTaxGroup: productTaxGroup,
      tenantId: tenantId,
    );
    return result.rate;
  }

  /// Get all active order type rules for a tenant.
  Future<List<OrderTypeRule>> getActiveRules(String tenantId) async {
    final query = db.select(db.orderTypeRules)
      ..where((t) => t.tenantId.equals(tenantId) & t.isActive.equals(true));
    return query.get();
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  /// Find a price override for a product + order type combination.
  Future<ProductPrice?> _findPriceOverride({
    required String productId,
    required String orderType,
    required String tenantId,
  }) async {
    final query = db.select(db.productPrices)
      ..where((t) =>
          t.tenantId.equals(tenantId) &
          t.productId.equals(productId) &
          t.orderType.equals(orderType));
    final results = await query.get();
    return results.isNotEmpty ? results.first : null;
  }

  /// Find active order-type rules for a specific order type.
  Future<List<OrderTypeRule>> _findActiveRules({
    required String orderType,
    required String tenantId,
  }) async {
    final query = db.select(db.orderTypeRules)
      ..where((t) =>
          t.tenantId.equals(tenantId) &
          t.orderType.equals(orderType) &
          t.isActive.equals(true));
    return query.get();
  }

  /// Resolve the tax profile for the given parameters.
  ///
  /// Lookup priority:
  /// 1. Exact match: country + orderType + taxGroup (with valid date range)
  /// 2. Wildcard order type: country + '*' + taxGroup (with valid date range)
  /// 3. Default profile for country (isDefault = true)
  /// 4. Fallback: rate = 0.0, name = 'No Tax'
  Future<_TaxResult> _resolveTaxProfile({
    required String countryCode,
    required String orderType,
    required String productTaxGroup,
    required String tenantId,
  }) async {
    final now = DateTime.now();

    // Try exact match first
    var profile = await _queryTaxProfile(
      countryCode: countryCode,
      orderType: orderType,
      productTaxGroup: productTaxGroup,
      tenantId: tenantId,
      now: now,
    );

    // Fallback to wildcard order type
    profile ??= await _queryTaxProfile(
      countryCode: countryCode,
      orderType: '*',
      productTaxGroup: productTaxGroup,
      tenantId: tenantId,
      now: now,
    );

    // Fallback to default profile for country
    if (profile == null) {
      final defaultQuery = db.select(db.taxProfiles)
        ..where((t) =>
            t.tenantId.equals(tenantId) &
            t.countryCode.equals(countryCode) &
            t.isDefault.equals(true));
      final defaults = await defaultQuery.get();
      if (defaults.isNotEmpty) {
        profile = defaults.first;
      }
    }

    if (profile != null) {
      return _TaxResult(rate: profile.taxRate, name: profile.taxName);
    }

    // Ultimate fallback
    return const _TaxResult(rate: 0.0, name: 'No Tax');
  }

  /// Query for a specific tax profile with date range validation.
  Future<TaxProfile?> _queryTaxProfile({
    required String countryCode,
    required String orderType,
    required String productTaxGroup,
    required String tenantId,
    required DateTime now,
  }) async {
    final query = db.select(db.taxProfiles)
      ..where((t) =>
          t.tenantId.equals(tenantId) &
          t.countryCode.equals(countryCode) &
          t.orderType.equals(orderType) &
          t.productTaxGroup.equals(productTaxGroup));

    final candidates = await query.get();

    // Filter by date range
    for (final candidate in candidates) {
      final validFrom = candidate.validFrom;
      final validUntil = candidate.validUntil;

      final afterStart = validFrom == null || !now.isBefore(validFrom);
      final beforeEnd = validUntil == null || now.isBefore(validUntil);

      if (afterStart && beforeEnd) {
        return candidate;
      }
    }

    // If no date-constrained match, try profiles without date constraints
    for (final candidate in candidates) {
      if (candidate.validFrom == null && candidate.validUntil == null) {
        return candidate;
      }
    }

    return null;
  }

  /// Apply an order-type rule to a price and return the adjustment.
  _AdjustmentResult _applyRule(int currentPrice, OrderTypeRule rule) {
    switch (rule.adjustmentType) {
      case 'percentage_discount':
        // adjustmentValue is percentage * 100, e.g. 1000 = 10%
        final discount = (currentPrice * rule.adjustmentValue / 10000).round();
        return _AdjustmentResult(amount: -discount);
      case 'fixed_discount':
        // adjustmentValue is in cents
        final discount =
            rule.adjustmentValue > currentPrice ? currentPrice : rule.adjustmentValue;
        return _AdjustmentResult(amount: -discount);
      case 'percentage_surcharge':
        final surcharge = (currentPrice * rule.adjustmentValue / 10000).round();
        return _AdjustmentResult(amount: surcharge);
      case 'fixed_surcharge':
        return _AdjustmentResult(amount: rule.adjustmentValue);
      default:
        return const _AdjustmentResult(amount: 0);
    }
  }

  /// Generate a default description for a rule when none is set.
  String _defaultRuleDescription(OrderTypeRule rule) {
    final typeLabel = switch (rule.orderType) {
      'takeaway' => 'Takeaway',
      'delivery' => 'Delivery',
      _ => rule.orderType,
    };
    switch (rule.adjustmentType) {
      case 'percentage_discount':
        final pct = (rule.adjustmentValue / 100).toStringAsFixed(0);
        return '$typeLabel $pct% Rabatt';
      case 'fixed_discount':
        final amount = (rule.adjustmentValue / 100).toStringAsFixed(2);
        return '$typeLabel -$amount';
      case 'percentage_surcharge':
        final pct = (rule.adjustmentValue / 100).toStringAsFixed(0);
        return '$typeLabel +$pct%';
      case 'fixed_surcharge':
        final amount = (rule.adjustmentValue / 100).toStringAsFixed(2);
        return '$typeLabel +$amount';
      default:
        return typeLabel;
    }
  }
}

// ---------------------------------------------------------------------------
// Internal helper classes
// ---------------------------------------------------------------------------

class _TaxResult {
  final double rate;
  final String name;

  const _TaxResult({required this.rate, required this.name});
}

class _AdjustmentResult {
  final int amount;

  const _AdjustmentResult({required this.amount});
}

// ---------------------------------------------------------------------------
// ResolvedPrice - public result class
// ---------------------------------------------------------------------------

/// The fully resolved price for a product given an order type.
///
/// Contains the gross price (what customer pays), net price (before tax),
/// tax details, and any adjustments applied.
class ResolvedPrice {
  /// What the customer pays (cents).
  final int grossPrice;

  /// Price before tax (cents).
  final int netPrice;

  /// Tax rate percentage, e.g. 8.1.
  final double taxRate;

  /// Display name for the tax, e.g. "MwSt 8.1%".
  final String taxName;

  /// Tax portion in cents.
  final int taxAmount;

  /// Base price before adjustments (cents).
  final int originalPrice;

  /// Discount (negative) or surcharge (positive) applied (cents).
  final int adjustmentAmount;

  /// Human-readable description of the adjustment, e.g. "Takeaway 10% Rabatt".
  final String? adjustmentDescription;

  /// The order type this price was resolved for.
  final String orderType;

  /// Whether the gross price includes tax (always true for CH/DE).
  final bool isTaxInclusive;

  const ResolvedPrice({
    required this.grossPrice,
    required this.netPrice,
    required this.taxRate,
    required this.taxName,
    required this.taxAmount,
    required this.originalPrice,
    required this.adjustmentAmount,
    this.adjustmentDescription,
    required this.orderType,
    required this.isTaxInclusive,
  });

  /// Whether the price differs from the original base price.
  bool get hasAdjustment => adjustmentAmount != 0;

  /// Whether there is a price override (original != gross before adjustment).
  bool get hasPriceOverride => originalPrice != (grossPrice - adjustmentAmount);

  /// Format for display, e.g. "CHF 10.00" or "CHF 10.00 (statt 12.00)".
  String formatDisplay(String currency) {
    final grossStr =
        '$currency ${(grossPrice / 100).toStringAsFixed(2)}';
    if (hasAdjustment && originalPrice != grossPrice) {
      final origStr = (originalPrice / 100).toStringAsFixed(2);
      return '$grossStr (statt $currency $origStr)';
    }
    return grossStr;
  }

  ResolvedPrice copyWith({
    int? grossPrice,
    int? netPrice,
    double? taxRate,
    String? taxName,
    int? taxAmount,
    int? originalPrice,
    int? adjustmentAmount,
    String? Function()? adjustmentDescription,
    String? orderType,
    bool? isTaxInclusive,
  }) {
    return ResolvedPrice(
      grossPrice: grossPrice ?? this.grossPrice,
      netPrice: netPrice ?? this.netPrice,
      taxRate: taxRate ?? this.taxRate,
      taxName: taxName ?? this.taxName,
      taxAmount: taxAmount ?? this.taxAmount,
      originalPrice: originalPrice ?? this.originalPrice,
      adjustmentAmount: adjustmentAmount ?? this.adjustmentAmount,
      adjustmentDescription: adjustmentDescription != null
          ? adjustmentDescription()
          : this.adjustmentDescription,
      orderType: orderType ?? this.orderType,
      isTaxInclusive: isTaxInclusive ?? this.isTaxInclusive,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResolvedPrice &&
          runtimeType == other.runtimeType &&
          grossPrice == other.grossPrice &&
          netPrice == other.netPrice &&
          taxRate == other.taxRate &&
          taxName == other.taxName &&
          taxAmount == other.taxAmount &&
          originalPrice == other.originalPrice &&
          adjustmentAmount == other.adjustmentAmount &&
          orderType == other.orderType &&
          isTaxInclusive == other.isTaxInclusive;

  @override
  int get hashCode => Object.hash(
        grossPrice,
        netPrice,
        taxRate,
        taxName,
        taxAmount,
        originalPrice,
        adjustmentAmount,
        orderType,
        isTaxInclusive,
      );

  @override
  String toString() =>
      'ResolvedPrice(gross: $grossPrice, net: $netPrice, tax: $taxRate% '
      '[$taxName], adjustment: $adjustmentAmount, orderType: $orderType)';
}
