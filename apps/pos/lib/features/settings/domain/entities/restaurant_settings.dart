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
const int kMinGangs = 1;
const int kMaxGangs = 5;

/// Default Gang labels used both by seed data and by the KDS UI when the
/// restaurant has not overridden them.
const List<String> kDefaultGangLabels = <String>['Gang 1', 'Gang 2', 'Gang 3'];

class RestaurantSettings {
  const RestaurantSettings({
    this.name = '',
    this.address = '',
    this.phone = '',
    this.mwstNr = '',
    this.logoPath,
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

  /// When `false`, the KDS renders a single flat stream of tickets ordered by
  /// arrival time — no Gang headers, no per-Gang fire button. Casual
  /// restaurants (bar, fast-casual, takeaway) typically turn this off.
  final bool gangsEnabled;

  /// Number of Gangs offered for course-based service. Clamped to
  /// [kMinGangs]..[kMaxGangs] on construction.
  final int maxGangs;

  /// Display labels for each Gang ordinal. Indexed by `sortOrder - 1`.
  /// If the list is shorter than [maxGangs], missing entries fall back to the
  /// generic `'Gang N'` label at render time.
  final List<String> gangLabels;

  /// Resolve the display label for a given `sortOrder` (1-based). Falls back
  /// to `'Gang N'` when the restaurant hasn't provided a custom entry or the
  /// ordinal is out of range.
  String gangLabelFor(int sortOrder) {
    final idx = sortOrder - 1;
    if (idx >= 0 && idx < gangLabels.length) {
      final label = gangLabels[idx].trim();
      if (label.isNotEmpty) return label;
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
