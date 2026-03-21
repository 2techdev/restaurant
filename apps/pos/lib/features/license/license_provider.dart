/// Riverpod providers for the new edition-based license / feature-flag system.
///
/// These providers form the public API consumed by [FlagGate] and any code
/// that needs to check feature access programmatically.
///
/// They deliberately wrap — rather than replace — the underlying
/// [currentLicenseProvider] from the legacy `licensing` module, so both
/// the old [FeatureGate] and the new [FlagGate] widgets work simultaneously
/// during the migration period.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/features/license/license_models.dart';
import 'package:gastrocore_pos/features/license/license_service.dart';
import 'package:gastrocore_pos/features/licensing/presentation/providers/license_provider.dart'
    as legacy;

// ---------------------------------------------------------------------------
// LicenseService singleton
// ---------------------------------------------------------------------------

final licenseServiceProvider = Provider<LicenseService>((ref) {
  return const LicenseService();
});

// ---------------------------------------------------------------------------
// Decoded LicenseToken
// ---------------------------------------------------------------------------

/// The [LicenseToken] decoded from the raw JWT stored in the database.
///
/// Returns `null` when no license has been activated (FREE tier applies).
///
/// The token is re-verified from the raw `tokenRaw` column so that the
/// `edition` field (e.g. `"starter"`) is correctly reflected even when the
/// legacy `tier` column stored a different value.
///
/// Ed25519 verification happens once per license change, not on every build.
final licenseTokenProvider = Provider<LicenseToken?>((ref) {
  final asyncLicense = ref.watch(legacy.currentLicenseProvider);
  final service = ref.watch(licenseServiceProvider);
  return asyncLicense.maybeWhen(
    data: (entity) {
      if (entity == null) return null;
      return service.verifyAndDecode(entity.tokenRaw);
    },
    orElse: () => null,
  );
});

// ---------------------------------------------------------------------------
// Current edition
// ---------------------------------------------------------------------------

/// The [LicenseEdition] currently in effect.
///
/// Falls back to [LicenseEdition.free] while the async license is loading
/// or when no license is installed.
final licenseEditionProvider = Provider<LicenseEdition>((ref) {
  final token = ref.watch(licenseTokenProvider);
  return token?.effectiveEdition ?? LicenseEdition.free;
});

// ---------------------------------------------------------------------------
// Feature flags
// ---------------------------------------------------------------------------

/// The complete set of [FeatureFlag]s currently enabled.
///
/// Combines implicit edition-level flags with any explicit overrides from
/// the token's `features[]` array.
final enabledFlagsProvider = Provider<Set<FeatureFlag>>((ref) {
  final token = ref.watch(licenseTokenProvider);
  if (token == null) return {};
  return {
    for (final flag in FeatureFlag.values)
      if (token.hasFlag(flag)) flag,
  };
});

/// Whether a specific [FeatureFlag] is enabled for the current license.
///
/// Usage:
/// ```dart
/// final canUseKds = ref.watch(isFlagEnabledProvider(FeatureFlag.kds));
/// ```
final isFlagEnabledProvider =
    Provider.family<bool, FeatureFlag>((ref, flag) {
  final token = ref.watch(licenseTokenProvider);
  if (token == null) return false;
  return token.hasFlag(flag);
});
