/// Swiss MWST (Mehrwertsteuer / TVA / IVA) tax settings entity.
///
/// Switzerland has three VAT tiers since 01.01.2024:
///   • Standard rate  8.1% — most goods & services
///   • Reduced rate   2.6% — food, non-alcoholic drinks, books, medicines
///   • Special rate   3.8% — accommodation (hotel Beherbergungsleistungen)
///
/// Rates are stored as doubles (e.g. 8.1) not decimals.
/// The entity allows overriding the rates in case Swiss law changes.
library;

import 'dart:convert';

/// A named tax rate used in Swiss MWST billing.
///
/// [effectiveFrom] records when this rate became legally effective.
/// Use [TaxSettings.rateForCodeAt] to resolve the rate applicable for a
/// given transaction date when rates change over time.
class TaxRate {
  const TaxRate({
    required this.code,
    required this.label,
    required this.rate,
    required this.effectiveFrom,
  });

  /// Internal code used in [ProductEntity.taxGroup] (e.g. 'standard').
  final String code;

  /// Human-readable label shown in the UI (e.g. 'Standard 8.1%').
  final String label;

  /// Rate as a percentage value (e.g. 8.1 for 8.1%).
  final double rate;

  /// Date from which this rate is legally effective (UTC midnight).
  ///
  /// Defaults to 2024-01-01 when the current Swiss MWST rates came into force.
  final DateTime effectiveFrom;

  /// Returns true if this rate was in effect at [transactionDate].
  bool isEffectiveAt(DateTime transactionDate) =>
      !transactionDate.isBefore(effectiveFrom);

  @override
  String toString() => '$label ($rate%) from ${effectiveFrom.toIso8601String().substring(0, 10)}';
}

class TaxSettings {
  /// Swiss standard VAT rate effective 01.01.2024.
  static const double defaultStandardRate = 8.1;

  /// Swiss accommodation (Beherbergung) VAT rate effective 01.01.2024.
  static const double defaultAccommodationRate = 3.8;

  /// Swiss reduced VAT rate for food/books/medicines effective 01.01.2024.
  static const double defaultReducedRate = 2.6;

  /// Default effective date for current Swiss MWST rates (01.01.2024).
  static final DateTime defaultEffectiveFrom = DateTime.utc(2024, 1, 1);

  TaxSettings({
    this.standardRate = defaultStandardRate,
    this.accommodationRate = defaultAccommodationRate,
    this.reducedRate = defaultReducedRate,
    this.taxIncludedInPrice = true,
    this.rappenRounding = true,
    DateTime? effectiveFrom,
  }) : effectiveFrom = effectiveFrom ?? defaultEffectiveFrom;

  /// Standard rate (Normalsatz) in percent.
  final double standardRate;

  /// Accommodation rate (Sondersatz) in percent.
  final double accommodationRate;

  /// Reduced rate (Sondersatz / Sonderrate) in percent.
  final double reducedRate;

  /// Whether prices in the system are gross (tax-inclusive).
  final bool taxIncludedInPrice;

  /// Round cash totals to nearest 5 Rappen (0.05 CHF).
  /// Required in Switzerland since there are no 1- or 2-Rappen coins.
  final bool rappenRounding;

  /// The date from which the current rate set became legally effective (UTC).
  ///
  /// All three rates share a single effective-from date because Swiss law
  /// changes all rates simultaneously (e.g. 01.01.2024).
  /// When a future rate change occurs, update this date alongside the rates.
  final DateTime effectiveFrom;

  /// Returns all three Swiss MWST rates as a list, each tagged with [effectiveFrom].
  List<TaxRate> get rates => [
        TaxRate(
          code: 'standard',
          label: 'Standard (Normalsatz)',
          rate: standardRate,
          effectiveFrom: effectiveFrom,
        ),
        TaxRate(
          code: 'accommodation',
          label: 'Beherbergung (Sondersatz)',
          rate: accommodationRate,
          effectiveFrom: effectiveFrom,
        ),
        TaxRate(
          code: 'reduced',
          label: 'Reduziert (Sondersatz)',
          rate: reducedRate,
          effectiveFrom: effectiveFrom,
        ),
      ];

  /// Finds the rate for a given [code]; falls back to [standardRate].
  double rateForCode(String code) =>
      rates.firstWhere((r) => r.code == code, orElse: () => rates.first).rate;

  /// Returns the rate for [code] that was in effect at [transactionDate].
  ///
  /// If [transactionDate] is before [effectiveFrom], returns 0.0 (not yet
  /// valid). Call sites that need a historical rate should store the rate
  /// at transaction time rather than re-deriving it here.
  double rateForCodeAt(String code, DateTime transactionDate) {
    final rate =
        rates.firstWhere((r) => r.code == code, orElse: () => rates.first);
    if (rate.isEffectiveAt(transactionDate)) return rate.rate;
    return 0.0;
  }

  TaxSettings copyWith({
    double? standardRate,
    double? accommodationRate,
    double? reducedRate,
    bool? taxIncludedInPrice,
    bool? rappenRounding,
    DateTime? effectiveFrom,
  }) =>
      TaxSettings(
        standardRate: standardRate ?? this.standardRate,
        accommodationRate: accommodationRate ?? this.accommodationRate,
        reducedRate: reducedRate ?? this.reducedRate,
        taxIncludedInPrice: taxIncludedInPrice ?? this.taxIncludedInPrice,
        rappenRounding: rappenRounding ?? this.rappenRounding,
        effectiveFrom: effectiveFrom ?? this.effectiveFrom,
      );

  Map<String, dynamic> toJson() => {
        'standardRate': standardRate,
        'accommodationRate': accommodationRate,
        'reducedRate': reducedRate,
        'taxIncludedInPrice': taxIncludedInPrice,
        'rappenRounding': rappenRounding,
        'effectiveFrom': effectiveFrom.toIso8601String(),
      };

  factory TaxSettings.fromJson(Map<String, dynamic> json) => TaxSettings(
        standardRate:
            (json['standardRate'] as num?)?.toDouble() ?? defaultStandardRate,
        accommodationRate: (json['accommodationRate'] as num?)?.toDouble() ??
            defaultAccommodationRate,
        reducedRate:
            (json['reducedRate'] as num?)?.toDouble() ?? defaultReducedRate,
        taxIncludedInPrice: (json['taxIncludedInPrice'] as bool?) ?? true,
        rappenRounding: (json['rappenRounding'] as bool?) ?? true,
        effectiveFrom: json['effectiveFrom'] != null
            ? DateTime.parse(json['effectiveFrom'] as String).toUtc()
            : null,
      );

  String toJsonString() => jsonEncode(toJson());

  factory TaxSettings.fromJsonString(String s) =>
      TaxSettings.fromJson(jsonDecode(s) as Map<String, dynamic>);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaxSettings &&
          standardRate == other.standardRate &&
          accommodationRate == other.accommodationRate &&
          reducedRate == other.reducedRate &&
          taxIncludedInPrice == other.taxIncludedInPrice &&
          rappenRounding == other.rappenRounding &&
          effectiveFrom == other.effectiveFrom;

  @override
  int get hashCode => Object.hash(
        standardRate,
        accommodationRate,
        reducedRate,
        taxIncludedInPrice,
        rappenRounding,
        effectiveFrom,
      );
}
