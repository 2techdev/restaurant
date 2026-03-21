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
class TaxRate {
  const TaxRate({
    required this.code,
    required this.label,
    required this.rate,
  });

  /// Internal code used in [ProductEntity.taxGroup] (e.g. 'standard').
  final String code;

  /// Human-readable label shown in the UI (e.g. 'Standard 8.1%').
  final String label;

  /// Rate as a percentage value (e.g. 8.1 for 8.1%).
  final double rate;

  @override
  String toString() => '$label ($rate%)';
}

class TaxSettings {
  /// Swiss standard VAT rate effective 01.01.2024.
  static const double defaultStandardRate = 8.1;

  /// Swiss accommodation (Beherbergung) VAT rate effective 01.01.2024.
  static const double defaultAccommodationRate = 3.8;

  /// Swiss reduced VAT rate for food/books/medicines effective 01.01.2024.
  static const double defaultReducedRate = 2.6;

  const TaxSettings({
    this.standardRate = defaultStandardRate,
    this.accommodationRate = defaultAccommodationRate,
    this.reducedRate = defaultReducedRate,
    this.taxIncludedInPrice = true,
    this.rappenRounding = true,
  });

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

  /// Returns all three Swiss MWST rates as a list.
  List<TaxRate> get rates => [
        TaxRate(
          code: 'standard',
          label: 'Standard (Normalsatz)',
          rate: standardRate,
        ),
        TaxRate(
          code: 'accommodation',
          label: 'Beherbergung (Sondersatz)',
          rate: accommodationRate,
        ),
        TaxRate(
          code: 'reduced',
          label: 'Reduziert (Sondersatz)',
          rate: reducedRate,
        ),
      ];

  /// Finds the rate for a given [code]; falls back to [standardRate].
  double rateForCode(String code) =>
      rates.firstWhere((r) => r.code == code, orElse: () => rates.first).rate;

  TaxSettings copyWith({
    double? standardRate,
    double? accommodationRate,
    double? reducedRate,
    bool? taxIncludedInPrice,
    bool? rappenRounding,
  }) =>
      TaxSettings(
        standardRate: standardRate ?? this.standardRate,
        accommodationRate: accommodationRate ?? this.accommodationRate,
        reducedRate: reducedRate ?? this.reducedRate,
        taxIncludedInPrice: taxIncludedInPrice ?? this.taxIncludedInPrice,
        rappenRounding: rappenRounding ?? this.rappenRounding,
      );

  Map<String, dynamic> toJson() => {
        'standardRate': standardRate,
        'accommodationRate': accommodationRate,
        'reducedRate': reducedRate,
        'taxIncludedInPrice': taxIncludedInPrice,
        'rappenRounding': rappenRounding,
      };

  factory TaxSettings.fromJson(Map<String, dynamic> json) => TaxSettings(
        standardRate:
            (json['standardRate'] as num?)?.toDouble() ?? defaultStandardRate,
        accommodationRate:
            (json['accommodationRate'] as num?)?.toDouble() ??
                defaultAccommodationRate,
        reducedRate:
            (json['reducedRate'] as num?)?.toDouble() ?? defaultReducedRate,
        taxIncludedInPrice: (json['taxIncludedInPrice'] as bool?) ?? true,
        rappenRounding: (json['rappenRounding'] as bool?) ?? true,
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
          rappenRounding == other.rappenRounding;

  @override
  int get hashCode => Object.hash(
        standardRate,
        accommodationRate,
        reducedRate,
        taxIncludedInPrice,
        rappenRounding,
      );
}
