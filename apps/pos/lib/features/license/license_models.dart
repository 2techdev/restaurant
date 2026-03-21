/// Core domain types for the GastroCore license / feature-flag system.
///
/// These types form the public API consumed by [FlagGate] and
/// [licenseEditionProvider]. They deliberately do NOT import Flutter — the
/// models are pure Dart so they can be used in server-side code and tests
/// without a Flutter environment.
library;

import 'package:flutter/foundation.dart';

// ---------------------------------------------------------------------------
// LicenseEdition
// ---------------------------------------------------------------------------

/// Ordered capability tiers for GastroCore POS.
///
/// Tiers are ordered from least to most capable; [isAtLeast] compares by
/// enum index so `pro.isAtLeast(starter)` is `true`.
///
/// Mapping from the legacy [LicenseTier] enum:
///   free ↔ free  |  starter ↔ starter  |  professional ↔ pro  |  enterprise ↔ enterprise
enum LicenseEdition {
  /// Core POS — no license required.
  free,

  /// Adds receipt printing, advanced reports, and the analytics dashboard.
  starter,

  /// Adds KDS, inventory management, and CRM/loyalty on top of Starter.
  pro,

  /// All features plus cloud sync, multi-device, and API access.
  enterprise;

  // ---------------------------------------------------------------------------
  // Factory
  // ---------------------------------------------------------------------------

  /// Parses the edition string embedded in a license token.
  ///
  /// Accepts both the new edition names and legacy tier names:
  ///   `"pro"` / `"professional"` → [pro]
  ///   `"enterprise"` → [enterprise]
  ///   `"starter"` → [starter]
  ///   anything else → [free]
  static LicenseEdition fromString(String value) =>
      switch (value.toLowerCase()) {
        'starter' => LicenseEdition.starter,
        'pro' || 'professional' => LicenseEdition.pro,
        'enterprise' => LicenseEdition.enterprise,
        _ => LicenseEdition.free,
      };

  // ---------------------------------------------------------------------------
  // Display
  // ---------------------------------------------------------------------------

  String get displayName => switch (this) {
        LicenseEdition.free => 'Free',
        LicenseEdition.starter => 'Starter',
        LicenseEdition.pro => 'Pro',
        LicenseEdition.enterprise => 'Enterprise',
      };

  String get badge => switch (this) {
        LicenseEdition.free => 'FREE',
        LicenseEdition.starter => 'STARTER',
        LicenseEdition.pro => 'PRO',
        LicenseEdition.enterprise => 'ENT',
      };

  // ---------------------------------------------------------------------------
  // Comparison
  // ---------------------------------------------------------------------------

  /// True when this edition's capabilities include those of [other].
  bool isAtLeast(LicenseEdition other) => index >= other.index;
}

// ---------------------------------------------------------------------------
// FeatureFlag
// ---------------------------------------------------------------------------

/// Enumeration of every feature that can be gated by a license edition.
///
/// Each flag declares the minimum [LicenseEdition] required. Code should
/// consult [LicenseToken.hasFlag] or [FlagGate] rather than comparing
/// editions directly.
enum FeatureFlag {
  // ── Starter ────────────────────────────────────────────────────────────────

  /// Analytics dashboard with revenue breakdown and trend charts.
  analytics,

  /// Receipt printing support (thermal / PDF).
  printing,

  /// Detailed shift and sales reports.
  reports,

  // ── Pro ────────────────────────────────────────────────────────────────────

  /// Real-time Kitchen Display System ticket feed.
  kds,

  /// Stock tracking and inventory management module.
  inventory,

  /// CRM loyalty program and customer profiles.
  crm,

  // ── Enterprise ─────────────────────────────────────────────────────────────

  /// Bidirectional cloud sync across devices and locations.
  cloudSync,

  /// Multiple POS registers connected over the network.
  multiDevice,

  /// REST API access for third-party integrations.
  apiAccess;

  // ---------------------------------------------------------------------------
  // Metadata
  // ---------------------------------------------------------------------------

  /// Minimum edition that implicitly enables this flag.
  LicenseEdition get requiredEdition => switch (this) {
        FeatureFlag.analytics => LicenseEdition.starter,
        FeatureFlag.printing => LicenseEdition.starter,
        FeatureFlag.reports => LicenseEdition.starter,
        FeatureFlag.kds => LicenseEdition.pro,
        FeatureFlag.inventory => LicenseEdition.pro,
        FeatureFlag.crm => LicenseEdition.pro,
        FeatureFlag.cloudSync => LicenseEdition.enterprise,
        FeatureFlag.multiDevice => LicenseEdition.enterprise,
        FeatureFlag.apiAccess => LicenseEdition.enterprise,
      };

  String get displayName => switch (this) {
        FeatureFlag.analytics => 'Analytics Dashboard',
        FeatureFlag.printing => 'Receipt Printing',
        FeatureFlag.reports => 'Advanced Reports',
        FeatureFlag.kds => 'Kitchen Display System',
        FeatureFlag.inventory => 'Inventory Management',
        FeatureFlag.crm => 'CRM & Loyalty',
        FeatureFlag.cloudSync => 'Cloud Sync',
        FeatureFlag.multiDevice => 'Multi-Device Sync',
        FeatureFlag.apiAccess => 'API Access',
      };
}

// ---------------------------------------------------------------------------
// LicenseToken
// ---------------------------------------------------------------------------

/// Self-contained license token decoded from an Ed25519-signed JWT.
///
/// Construct via [LicenseService.verifyAndDecode]; do not build manually in
/// production code.
@immutable
class LicenseToken {
  const LicenseToken({
    required this.edition,
    required this.features,
    required this.expiresAt,
    required this.deviceLimit,
    required this.customerName,
    required this.issuedAt,
    this.deviceFingerprint,
  });

  /// The edition granted by this token.
  final LicenseEdition edition;

  /// Explicit feature overrides embedded in the token's `features[]` array.
  ///
  /// Prefer [hasFlag] over accessing this list directly — it combines the
  /// edition-level defaults with these explicit overrides.
  final List<FeatureFlag> features;

  /// UTC timestamp when this token expires.
  final DateTime expiresAt;

  /// Maximum number of devices allowed to activate this license.
  final int deviceLimit;

  /// Human-readable business / customer name from the token payload.
  final String customerName;

  /// UTC timestamp when this token was issued.
  final DateTime issuedAt;

  /// Optional device fingerprint — non-null means the token is device-locked.
  final String? deviceFingerprint;

  // ---------------------------------------------------------------------------
  // Derived state
  // ---------------------------------------------------------------------------

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt);

  /// True when past expiry but within the 7-day grace window.
  bool get isInGracePeriod {
    if (!isExpired) return false;
    final cutoff = expiresAt.add(const Duration(days: 7));
    return DateTime.now().toUtc().isBefore(cutoff);
  }

  /// The edition that is currently enforced, accounting for grace period.
  LicenseEdition get effectiveEdition {
    if (!isExpired || isInGracePeriod) return edition;
    return LicenseEdition.free;
  }

  /// Days remaining until the hard-downgrade (past the grace window). 0 when
  /// already downgraded.
  int get daysUntilDowngrade {
    final cutoff = expiresAt.add(const Duration(days: 7));
    return cutoff.difference(DateTime.now().toUtc()).inDays.clamp(0, 9999);
  }

  /// Days remaining until token expiry. 0 when expired.
  int get daysUntilExpiry {
    if (isExpired) return 0;
    return expiresAt.difference(DateTime.now().toUtc()).inDays.clamp(0, 9999);
  }

  /// Returns `true` when [flag] is active for this token.
  ///
  /// A flag is active when:
  ///   1. The token is not hard-expired (within grace), AND
  ///   2. The [effectiveEdition] is at least [flag.requiredEdition], OR
  ///      [flag] appears in the explicit [features] override list.
  bool hasFlag(FeatureFlag flag) {
    if (isExpired && !isInGracePeriod) return false;
    return effectiveEdition.isAtLeast(flag.requiredEdition) ||
        features.contains(flag);
  }

  // ---------------------------------------------------------------------------
  // Equality
  // ---------------------------------------------------------------------------

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LicenseToken &&
          edition == other.edition &&
          listEquals(features, other.features) &&
          expiresAt == other.expiresAt &&
          deviceLimit == other.deviceLimit &&
          customerName == other.customerName &&
          issuedAt == other.issuedAt &&
          deviceFingerprint == other.deviceFingerprint;

  @override
  int get hashCode => Object.hash(
        edition,
        Object.hashAll(features),
        expiresAt,
        deviceLimit,
        customerName,
        issuedAt,
        deviceFingerprint,
      );

  @override
  String toString() =>
      'LicenseToken(edition: ${edition.name}, customer: $customerName, '
      'expires: $expiresAt, effective: ${effectiveEdition.name})';
}
