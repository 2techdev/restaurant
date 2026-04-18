/// Restaurant profile settings entity.
///
/// Stores the restaurant's public identity: name, address, contact details,
/// Swiss VAT number (MWST-Nummer), and optional logo path.
///
/// Also carries the KDS Gang configuration — see the `gangsEnabled`,
/// `maxGangs`, and `gangLabels` fields below. The 2026-04-17 pivot made
/// Gang grouping a per-restaurant policy rather than a fixed system default.
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

/// Hard bounds for the Gang count. A restaurant that doesn't do course-based
/// service can disable the whole system via [RestaurantSettings.gangsEnabled];
/// a fine-dining restaurant that needs e.g. amuse-bouche + four courses can
/// go up to five.
///
/// "Gang" is a loanword used by German/French/Italian Swiss kitchens, so
/// labels are kept identical across locales by design.
const int kMinGangs = 1;
const int kMaxGangs = 5;

/// Alias for legacy call sites that still import the single-bound constant.
const int kGangsUpperBound = kMaxGangs;

/// Default Gang labels used both by seed data and by the KDS UI when the
/// restaurant has not overridden them. Length matches [kMaxGangs] so
/// [RestaurantSettings.effectiveGangLabels] can fall back safely regardless of
/// the active [RestaurantSettings.maxGangs] value.
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
    this.gangsEnabled = true,
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

  /// Number of Gangs offered for course-based service. Stored as-is; use
  /// [clampedMaxGangs] for UI rendering so a bad stored value never crashes.
  final int maxGangs;

  /// Optional per-restaurant labels ("Entrée", "Plat", …). Indexed by
  /// `sortOrder - 1`. When an entry is missing or blank, the generic
  /// `'Gang N'` label is used. [effectiveGangLabels] resolves this at render
  /// time sized to [clampedMaxGangs].
  final List<String> gangLabels;

  /// [maxGangs] forced into the valid [kMinGangs]..[kMaxGangs] range.
  int get clampedMaxGangs => _clampMaxGangs(maxGangs);

  /// Returns the label list sized to [clampedMaxGangs]. Missing entries fall
  /// back to [kDefaultGangLabels]; entries that are blank after trimming also
  /// fall back, so a half-edited override never renders an empty chip.
  List<String> get effectiveGangLabels {
    final n = clampedMaxGangs;
    return List<String>.generate(n, (i) {
      final override = i < gangLabels.length ? gangLabels[i].trim() : '';
      return override.isNotEmpty ? override : kDefaultGangLabels[i];
    });
  }

  /// Resolve the display label for a given `sortOrder` (1-based). Applies
  /// fallbacks in order: restaurant override → default "Gang N".
  String gangLabelFor(int sortOrder) {
    final idx = sortOrder - 1;
    if (idx >= 0 && idx < gangLabels.length) {
      final label = gangLabels[idx].trim();
      if (label.isNotEmpty) return label;
    }
    if (idx >= 0 && idx < kDefaultGangLabels.length) {
      return kDefaultGangLabels[idx];
    }
    return 'Gang $sortOrder';
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
      serviceChargeEnabled: serviceChargeEnabled ?? this.serviceChargeEnabled,
      serviceChargePercent: serviceChargePercent ?? this.serviceChargePercent,
      gangsEnabled: gangsEnabled ?? this.gangsEnabled,
      maxGangs: _clampMaxGangs(maxGangs ?? this.maxGangs),
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
        ? rawLabels.map((e) => e?.toString() ?? '').toList(growable: false)
        : kDefaultGangLabels;
    return RestaurantSettings(
      name: (json['name'] as String?) ?? '',
      address: (json['address'] as String?) ?? '',
      phone: (json['phone'] as String?) ?? '',
      mwstNr: (json['mwstNr'] as String?) ?? '',
      logoPath: json['logoPath'] as String?,
      serviceChargeEnabled: (json['serviceChargeEnabled'] as bool?) ?? false,
      serviceChargePercent:
          (json['serviceChargePercent'] as num?)?.toDouble() ?? 10.0,
      gangsEnabled: (json['gangsEnabled'] as bool?) ?? true,
      maxGangs: _clampMaxGangs((json['maxGangs'] as num?)?.toInt() ?? 3),
      gangLabels: labels,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory RestaurantSettings.fromJsonString(String s) =>
      RestaurantSettings.fromJson(jsonDecode(s) as Map<String, dynamic>);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RestaurantSettings &&
          name == other.name &&
          address == other.address &&
          phone == other.phone &&
          mwstNr == other.mwstNr &&
          logoPath == other.logoPath &&
          serviceChargeEnabled == other.serviceChargeEnabled &&
          serviceChargePercent == other.serviceChargePercent &&
          gangsEnabled == other.gangsEnabled &&
          maxGangs == other.maxGangs &&
          _listEquals(gangLabels, other.gangLabels);

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

int _clampMaxGangs(int v) {
  if (v < kMinGangs) return kMinGangs;
  if (v > kMaxGangs) return kMaxGangs;
  return v;
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
