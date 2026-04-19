/// Restaurant profile settings entity.
///
/// Stores the restaurant's public identity: name, address, contact details,
/// Swiss VAT number (MWST-Nummer), and optional logo path.
library;

import 'dart:convert';

/// Validates a Swiss MWST-Nummer (UID-based VAT number).
///
/// Accepted formats:
///   CHE-123.456.789
///   CHE-123.456.789 MWST
///   CHE-123.456.789 TVA
///   CHE-123.456.789 IVA
///
/// Returns `null` if the number is valid (or empty — empty is allowed for
/// restaurants that are not VAT-registered). Returns an error string otherwise.
String? validateMwstNr(String value) {
  if (value.trim().isEmpty) return null; // Optional field.
  final pattern = RegExp(
    r'^CHE-\d{3}\.\d{3}\.\d{3}( MWST| TVA| IVA)?$',
    caseSensitive: false,
  );
  if (!pattern.hasMatch(value.trim())) {
    return 'Format: CHE-XXX.XXX.XXX (e.g. CHE-123.456.789 MWST)';
  }
  return null;
}

/// Hard ceiling on configurable course count, regardless of settings.
/// Anything above this won't fit the order panel at common resolutions.
const int kGangsUpperBound = 5;

/// Default labels shown when the restaurant hasn't customized them.
/// Kept identical across locales by design — "Gang" is a loanword the
/// industry uses in German/French/Italian Swiss kitchens.
const List<String> kDefaultGangLabels = <String>[
  'Gang 1',
  'Gang 2',
  'Gang 3',
  'Gang 4',
  'Gang 5',
];

class RestaurantSettings {
  const RestaurantSettings({
    this.name = '',
    this.address = '',
    this.phone = '',
    this.mwstNr = '',
    this.logoPath,
    this.serviceChargeEnabled = false,
    this.serviceChargePercent = 10.0,
    this.gangsEnabled = false,
    this.maxGangs = 3,
    this.gangLabels = kDefaultGangLabels,
  });

  /// Restaurant display name shown on receipts and the POS header.
  final String name;

  /// Full street address (e.g. "Bahnhofstrasse 12, 8001 Zürich").
  final String address;

  /// Contact phone number.
  final String phone;

  /// Swiss VAT registration number (e.g. "CHE-123.456.789 MWST").
  final String mwstNr;

  /// Absolute path to the logo image file on device storage.
  final String? logoPath;

  /// Whether a service charge line should be added to every dine-in ticket.
  ///
  /// Switzerland does not legally require a service charge (unlike, e.g.,
  /// France), but fine-dining restaurants commonly add one. When off the
  /// ticket is unaffected; when on, a separate line at
  /// [serviceChargePercent]% of the subtotal is applied and printed
  /// separately on the receipt as required by FiscalDE/MwSt transparency.
  final bool serviceChargeEnabled;

  /// Service charge rate applied when [serviceChargeEnabled] is true.
  final double serviceChargePercent;

  /// Whether the restaurant runs a coursed service (fine-dining "Gang"
  /// workflow). Fast-food and bistro concepts turn this off and treat
  /// the order as a single flow — the order panel hides the Gang
  /// selector and Hold/Fire controls, and kitchen tickets omit the
  /// "Gang N" section header.
  final bool gangsEnabled;

  /// Number of course slots shown when [gangsEnabled] is true.
  /// Clamped to `[1, kGangsUpperBound]` at read sites.
  final int maxGangs;

  /// Per-slot labels. Indexed 0..[maxGangs]-1; reads beyond the list
  /// length fall back to [kDefaultGangLabels].
  final List<String> gangLabels;

  /// Convenience: resolve the display label for a 1-based course index,
  /// applying fallbacks in order: restaurant override → default "Gang N".
  String gangLabelFor(int oneBasedIndex) {
    final idx = oneBasedIndex - 1;
    if (idx >= 0 && idx < gangLabels.length) {
      final label = gangLabels[idx].trim();
      if (label.isNotEmpty) return label;
    }
    if (idx >= 0 && idx < kDefaultGangLabels.length) {
      return kDefaultGangLabels[idx];
    }
    return 'Gang $oneBasedIndex';
  }

  RestaurantSettings copyWith({
    String? name,
    String? address,
    String? phone,
    String? mwstNr,
    String? logoPath,
    bool clearLogo = false,
    bool? serviceChargeEnabled,
    double? serviceChargePercent,
    bool? gangsEnabled,
    int? maxGangs,
    List<String>? gangLabels,
  }) {
    return RestaurantSettings(
      name: name ?? this.name,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      mwstNr: mwstNr ?? this.mwstNr,
      logoPath: clearLogo ? null : (logoPath ?? this.logoPath),
      serviceChargeEnabled:
          serviceChargeEnabled ?? this.serviceChargeEnabled,
      serviceChargePercent:
          serviceChargePercent ?? this.serviceChargePercent,
      gangsEnabled: gangsEnabled ?? this.gangsEnabled,
      maxGangs: maxGangs ?? this.maxGangs,
      gangLabels: gangLabels ?? this.gangLabels,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'address': address,
        'phone': phone,
        'mwstNr': mwstNr,
        'logoPath': logoPath,
        'serviceChargeEnabled': serviceChargeEnabled,
        'serviceChargePercent': serviceChargePercent,
        'gangsEnabled': gangsEnabled,
        'maxGangs': maxGangs,
        'gangLabels': gangLabels,
      };

  factory RestaurantSettings.fromJson(Map<String, dynamic> json) {
    final rawLabels = json['gangLabels'];
    final labels = rawLabels is List
        ? rawLabels
            .map((e) => e?.toString() ?? '')
            .toList(growable: false)
        : kDefaultGangLabels;
    final rawMax = (json['maxGangs'] as num?)?.toInt() ?? 3;
    return RestaurantSettings(
      name: (json['name'] as String?) ?? '',
      address: (json['address'] as String?) ?? '',
      phone: (json['phone'] as String?) ?? '',
      mwstNr: (json['mwstNr'] as String?) ?? '',
      logoPath: json['logoPath'] as String?,
      serviceChargeEnabled:
          (json['serviceChargeEnabled'] as bool?) ?? false,
      serviceChargePercent:
          (json['serviceChargePercent'] as num?)?.toDouble() ?? 10.0,
      gangsEnabled: (json['gangsEnabled'] as bool?) ?? false,
      maxGangs: rawMax.clamp(1, kGangsUpperBound),
      gangLabels: labels,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory RestaurantSettings.fromJsonString(String s) =>
      RestaurantSettings.fromJson(jsonDecode(s) as Map<String, dynamic>);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! RestaurantSettings) return false;
    if (gangLabels.length != other.gangLabels.length) return false;
    for (var i = 0; i < gangLabels.length; i++) {
      if (gangLabels[i] != other.gangLabels[i]) return false;
    }
    return name == other.name &&
        address == other.address &&
        phone == other.phone &&
        mwstNr == other.mwstNr &&
        logoPath == other.logoPath &&
        serviceChargeEnabled == other.serviceChargeEnabled &&
        serviceChargePercent == other.serviceChargePercent &&
        gangsEnabled == other.gangsEnabled &&
        maxGangs == other.maxGangs;
  }

  @override
  int get hashCode => Object.hash(
        name,
        address,
        phone,
        mwstNr,
        logoPath,
        serviceChargeEnabled,
        serviceChargePercent,
        gangsEnabled,
        maxGangs,
        Object.hashAll(gangLabels),
      );
}
