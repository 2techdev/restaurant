/// License tier hierarchy for GastroCore POS.
///
/// Tiers are ordered by increasing capability. Code that checks permissions
/// can compare tier indices: `tier.index >= LicenseTier.professional.index`.
library;

enum LicenseTier {
  /// Default tier — no license required.
  /// Limited to core POS operations and a 50-item menu.
  free,

  /// Starter tier — adds receipt printing, analytics, and advanced reports.
  starter,

  /// Professional tier — unlocks KDS, inventory, CRM, unlimited menu,
  /// custom receipts, and backup/restore.
  professional,

  /// Enterprise tier — adds cloud sync, API access, multi-location
  /// support, and custom integrations on top of Professional.
  enterprise;

  /// Human-readable display name shown in upgrade prompts.
  String get displayName => switch (this) {
        LicenseTier.free => 'Free',
        LicenseTier.starter => 'Starter',
        LicenseTier.professional => 'Professional',
        LicenseTier.enterprise => 'Enterprise',
      };

  /// Short badge label used in the status bar / settings.
  String get badge => switch (this) {
        LicenseTier.free => 'FREE',
        LicenseTier.starter => 'STARTER',
        LicenseTier.professional => 'PRO',
        LicenseTier.enterprise => 'ENT',
      };

  /// Parse from the string stored in the license token payload.
  /// Accepts both new edition names ('pro', 'starter') and the legacy
  /// 'professional' name for backward compatibility.
  static LicenseTier fromString(String value) => switch (value.toLowerCase()) {
        'starter' => LicenseTier.starter,
        'pro' || 'professional' => LicenseTier.professional,
        'enterprise' => LicenseTier.enterprise,
        _ => LicenseTier.free,
      };

  /// Whether this tier is at least [other].
  bool isAtLeast(LicenseTier other) => index >= other.index;
}
