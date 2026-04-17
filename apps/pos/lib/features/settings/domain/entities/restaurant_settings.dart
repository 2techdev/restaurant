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

class RestaurantSettings {
  const RestaurantSettings({
    this.name = '',
    this.address = '',
    this.phone = '',
    this.mwstNr = '',
    this.logoPath,
    this.serviceChargeEnabled = false,
    this.serviceChargePercent = 10.0,
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

  RestaurantSettings copyWith({
    String? name,
    String? address,
    String? phone,
    String? mwstNr,
    String? logoPath,
    bool clearLogo = false,
    bool? serviceChargeEnabled,
    double? serviceChargePercent,
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
      );

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
          serviceChargePercent == other.serviceChargePercent;

  @override
  int get hashCode => Object.hash(
        name,
        address,
        phone,
        mwstNr,
        logoPath,
        serviceChargeEnabled,
        serviceChargePercent,
      );
}
