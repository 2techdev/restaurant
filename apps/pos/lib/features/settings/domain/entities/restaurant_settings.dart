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

/// Allowed range for [RestaurantSettings.maxGangs].
const int kMinGangsSetting = 1;
const int kMaxGangsSetting = 5;

/// Default labels when the restaurant hasn't overridden them.
///
/// Length is always [kMaxGangsSetting]; [RestaurantSettings.effectiveGangLabels]
/// trims/extends the stored override to match [RestaurantSettings.maxGangs].
const List<String> kDefaultGangLabels = [
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
    this.gangLabels = const [],
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

  /// When `true`, a service charge is added as a separate line on every
  /// order summary (Waiter + POS) and printed receipt.
  final bool serviceChargeEnabled;

  /// Service charge rate as a percentage of the pre-tax subtotal.
  /// Ignored when [serviceChargeEnabled] is `false`.
  final double serviceChargePercent;

  /// Master toggle for the multi-Gang (course) ordering flow.
  ///
  /// When `false`, the waiter course selector is hidden, items are sent to
  /// the kitchen without a gang assignment, and [fireGang] is never called.
  /// Use this for casual/quick-service venues that don't pace courses.
  final bool gangsEnabled;

  /// How many gang slots the restaurant uses. Clamped to
  /// [kMinGangsSetting]..[kMaxGangsSetting] via [clampedMaxGangs].
  final int maxGangs;

  /// Optional per-restaurant labels ("Entrée", "Plat", …). When empty, the
  /// UI falls back to [kDefaultGangLabels]. Length may exceed [maxGangs];
  /// [effectiveGangLabels] trims/extends to the active gang count.
  final List<String> gangLabels;

  /// [maxGangs] forced into the valid [kMinGangsSetting]..[kMaxGangsSetting]
  /// range — the UI should always use this instead of reading [maxGangs]
  /// directly, so a bad stored value never crashes rendering.
  int get clampedMaxGangs =>
      maxGangs < kMinGangsSetting
          ? kMinGangsSetting
          : (maxGangs > kMaxGangsSetting ? kMaxGangsSetting : maxGangs);

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

  factory RestaurantSettings.fromJson(Map<String, dynamic> json) =>
      RestaurantSettings(
        name: (json['name'] as String?) ?? '',
        address: (json['address'] as String?) ?? '',
        phone: (json['phone'] as String?) ?? '',
        mwstNr: (json['mwstNr'] as String?) ?? '',
        logoPath: json['logoPath'] as String?,
        serviceChargeEnabled:
            (json['serviceChargeEnabled'] as bool?) ?? false,
        serviceChargePercent:
            (json['serviceChargePercent'] as num?)?.toDouble() ?? 10.0,
        gangsEnabled: (json['gangsEnabled'] as bool?) ?? true,
        maxGangs: (json['maxGangs'] as num?)?.toInt() ?? 3,
        gangLabels: (json['gangLabels'] as List?)
                ?.whereType<String>()
                .toList(growable: false) ??
            const [],
      );

  String toJsonString() => jsonEncode(toJson());

  factory RestaurantSettings.fromJsonString(String s) =>
      RestaurantSettings.fromJson(jsonDecode(s) as Map<String, dynamic>);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! RestaurantSettings) return false;
    if (name != other.name ||
        address != other.address ||
        phone != other.phone ||
        mwstNr != other.mwstNr ||
        logoPath != other.logoPath ||
        serviceChargeEnabled != other.serviceChargeEnabled ||
        serviceChargePercent != other.serviceChargePercent ||
        gangsEnabled != other.gangsEnabled ||
        maxGangs != other.maxGangs ||
        gangLabels.length != other.gangLabels.length) {
      return false;
    }
    for (var i = 0; i < gangLabels.length; i++) {
      if (gangLabels[i] != other.gangLabels[i]) return false;
    }
    return true;
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
