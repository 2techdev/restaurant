/// Central registry of feature-flag defaults for each license edition.
///
/// Feature access has two sources:
/// 1. **Implicit** — flags whose [FeatureFlag.requiredEdition] is ≤ the
///    active edition (e.g., a Pro license implicitly enables [FeatureFlag.kds]).
/// 2. **Explicit** — overrides embedded in the token's `features[]` array
///    (allows granting individual flags independently of the edition tier).
///
/// Use [FeatureFlags.effectiveFlags] to merge both sources.
library;

import 'package:gastrocore_pos/features/license/license_models.dart';

abstract final class FeatureFlags {
  // ---------------------------------------------------------------------------
  // Core API
  // ---------------------------------------------------------------------------

  /// All [FeatureFlag]s implicitly enabled by [edition] alone.
  static Set<FeatureFlag> implicitFlags(LicenseEdition edition) => {
        for (final f in FeatureFlag.values)
          if (edition.isAtLeast(f.requiredEdition)) f,
      };

  /// Merges [implicitFlags] with any explicit [overrides] from the token.
  static Set<FeatureFlag> effectiveFlags(
    LicenseEdition edition,
    List<FeatureFlag> overrides,
  ) =>
      {...implicitFlags(edition), ...overrides};

  // ---------------------------------------------------------------------------
  // Reference table — default flag set per edition (no explicit overrides).
  // ---------------------------------------------------------------------------

  static const Map<LicenseEdition, List<FeatureFlag>> defaultsByEdition = {
    LicenseEdition.free: [],
    LicenseEdition.starter: [
      FeatureFlag.analytics,
      FeatureFlag.printing,
      FeatureFlag.reports,
    ],
    LicenseEdition.pro: [
      FeatureFlag.analytics,
      FeatureFlag.printing,
      FeatureFlag.reports,
      FeatureFlag.kds,
      FeatureFlag.inventory,
      FeatureFlag.crm,
    ],
    LicenseEdition.enterprise: [
      FeatureFlag.analytics,
      FeatureFlag.printing,
      FeatureFlag.reports,
      FeatureFlag.kds,
      FeatureFlag.inventory,
      FeatureFlag.crm,
      FeatureFlag.cloudSync,
      FeatureFlag.multiDevice,
      FeatureFlag.apiAccess,
    ],
  };
}
