/// Country-specific fiscal and tax configuration for GastroCore POS.
///
/// GastroCore supports multi-country operation. Each country has its own:
///   • Tax rates (MWST for CH, MwSt for DE)
///   • Fiscal requirements (TSE mandatory in Germany, not in Switzerland)
///   • Receipt requirements (QR-Bill in Switzerland)
///   • Currency and rounding rules
library;

import 'package:gastrocore_pos/features/settings/domain/entities/tax_settings.dart';

/// Supported country codes (ISO 3166-1 alpha-2).
enum CountryCode { ch, de }

/// Country-specific configuration for fiscal compliance and tax rates.
///
/// Use [CountryConfig.forCode] to look up by ISO string, or access the
/// pre-defined constants [CountryConfig.ch] and [CountryConfig.de].
class CountryConfig {
  const CountryConfig({
    required this.code,
    required this.name,
    required this.currency,
    required this.taxSettings,
    required this.requiresTse,
    required this.requiresQrBill,
    required this.taxLabel,
    required this.standardRateCode,
    required this.reducedRateCode,
  });

  /// ISO 3166-1 alpha-2 country code enum.
  final CountryCode code;

  /// Human-readable country name (in local language).
  final String name;

  /// ISO 4217 currency code (e.g. 'CHF', 'EUR').
  final String currency;

  /// Tax rate configuration for this country.
  final TaxSettings taxSettings;

  /// Whether German KassenSichV TSE signing is required.
  /// True for Germany, false for Switzerland.
  final bool requiresTse;

  /// Whether Swiss QR-Bill format is required on invoices.
  final bool requiresQrBill;

  /// Local abbreviation for value-added tax (e.g. 'MWST', 'MwSt').
  final String taxLabel;

  /// Internal code for the standard (full) VAT rate in [taxSettings].
  final String standardRateCode;

  /// Internal code for the reduced VAT rate in [taxSettings].
  final String reducedRateCode;

  // ---------------------------------------------------------------------------
  // Pre-defined country configurations
  // ---------------------------------------------------------------------------

  /// Switzerland: MWST 8.1% / 2.6% / 3.8%, QR-Bill, Rappen rounding, no TSE.
  static const ch = CountryConfig(
    code: CountryCode.ch,
    name: 'Schweiz / Suisse / Svizzera',
    currency: 'CHF',
    taxSettings: TaxSettings(
      standardRate: 8.1,
      accommodationRate: 3.8,
      reducedRate: 2.6,
      taxIncludedInPrice: true,
      rappenRounding: true,
    ),
    requiresTse: false,
    requiresQrBill: true,
    taxLabel: 'MWST',
    standardRateCode: 'standard',
    reducedRateCode: 'reduced',
  );

  /// Germany: MwSt 19% / 7%, Fiskaly TSE required, DSFinV-K export, EUR.
  static const de = CountryConfig(
    code: CountryCode.de,
    name: 'Deutschland',
    currency: 'EUR',
    taxSettings: TaxSettings(
      standardRate: 19.0,
      // accommodationRate holds the German reduced food/book rate (7%)
      accommodationRate: 7.0,
      reducedRate: 7.0,
      taxIncludedInPrice: true,
      rappenRounding: false,
    ),
    requiresTse: true,
    requiresQrBill: false,
    taxLabel: 'MwSt',
    standardRateCode: 'standard',
    reducedRateCode: 'reduced',
  );

  // ---------------------------------------------------------------------------
  // Lookup
  // ---------------------------------------------------------------------------

  /// Returns the [CountryConfig] for a given ISO 3166-1 alpha-2 string.
  /// Defaults to [ch] for unrecognised codes.
  static CountryConfig forCode(String code) =>
      switch (code.toUpperCase()) {
        'CH' => ch,
        'DE' => de,
        _ => ch,
      };

  /// ISO 3166-1 alpha-2 string for this country.
  String get isoCode => switch (code) {
        CountryCode.ch => 'CH',
        CountryCode.de => 'DE',
      };

  /// Standard VAT rate percentage for this country.
  double get standardRate => taxSettings.standardRate;

  /// Reduced VAT rate percentage for this country.
  double get reducedRate => taxSettings.reducedRate;

  @override
  String toString() => 'CountryConfig($isoCode, $currency)';
}
