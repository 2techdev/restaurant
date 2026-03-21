/// Immutable domain entity representing an activated license.
///
/// A [LicenseEntity] is constructed by [LicenseRepositoryImpl] after a token
/// has been verified by [LicenseValidator]. It encapsulates both the raw
/// token fields and derived state such as [isExpired] and [effectiveTier].
library;

import 'license_tier.dart';

/// Grace period allowed after expiry before the effective tier is downgraded.
const Duration kLicenseGracePeriod = Duration(days: 7);

class LicenseEntity {
  final String id;

  /// Business identifier embedded in the token.
  final String businessId;

  /// Nominal tier granted by the token.
  final LicenseTier tier;

  /// When the token was issued.
  final DateTime issuedAt;

  /// When the nominal tier expires.
  final DateTime expiresAt;

  /// Optional device fingerprint. Null = not device-locked.
  final String? deviceFingerprint;

  /// Raw Base64url token string (kept for display / re-validation).
  final String tokenRaw;

  const LicenseEntity({
    required this.id,
    required this.businessId,
    required this.tier,
    required this.issuedAt,
    required this.expiresAt,
    this.deviceFingerprint,
    required this.tokenRaw,
  });

  // ---------------------------------------------------------------------------
  // Derived state
  // ---------------------------------------------------------------------------

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt);

  /// True when past expiry but still inside the [kLicenseGracePeriod] window.
  bool get isInGracePeriod {
    if (!isExpired) return false;
    final graceCutoff = expiresAt.add(kLicenseGracePeriod);
    return DateTime.now().toUtc().isBefore(graceCutoff);
  }

  /// The tier that should actually be enforced right now.
  ///
  /// - Active (not expired) → nominal [tier]
  /// - Expired but within grace period → nominal [tier] (grace)
  /// - Expired beyond grace period → [LicenseTier.free]
  LicenseTier get effectiveTier {
    if (!isExpired || isInGracePeriod) return tier;
    return LicenseTier.free;
  }

  /// Number of days remaining before hard downgrade (0 when past grace).
  int get daysUntilDowngrade {
    final graceCutoff = expiresAt.add(kLicenseGracePeriod);
    final diff = graceCutoff.difference(DateTime.now().toUtc()).inDays;
    return diff.clamp(0, 7);
  }

  // ---------------------------------------------------------------------------
  // Equality & copy
  // ---------------------------------------------------------------------------

  LicenseEntity copyWith({
    String? id,
    String? businessId,
    LicenseTier? tier,
    DateTime? issuedAt,
    DateTime? expiresAt,
    String? deviceFingerprint,
    String? tokenRaw,
  }) {
    return LicenseEntity(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      tier: tier ?? this.tier,
      issuedAt: issuedAt ?? this.issuedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      deviceFingerprint: deviceFingerprint ?? this.deviceFingerprint,
      tokenRaw: tokenRaw ?? this.tokenRaw,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LicenseEntity &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          businessId == other.businessId &&
          tier == other.tier &&
          issuedAt == other.issuedAt &&
          expiresAt == other.expiresAt &&
          deviceFingerprint == other.deviceFingerprint;

  @override
  int get hashCode =>
      Object.hash(id, businessId, tier, issuedAt, expiresAt, deviceFingerprint);

  @override
  String toString() =>
      'LicenseEntity(businessId: $businessId, tier: ${tier.name}, '
      'expires: $expiresAt, effective: ${effectiveTier.name})';
}
