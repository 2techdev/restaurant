/// Riverpod providers for the licensing feature.
///
/// Exposes the [LicenseRepositoryImpl] singleton, the current [LicenseEntity],
/// the resolved [LicenseTier], and the [FeatureFlagService] that feature
/// modules consult before showing gated UI.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/features/licensing/data/repositories/license_repository_impl.dart';
import 'package:gastrocore_pos/features/licensing/domain/entities/app_feature.dart';
import 'package:gastrocore_pos/features/licensing/domain/entities/license_entity.dart';
import 'package:gastrocore_pos/features/licensing/domain/entities/license_tier.dart';
import 'package:gastrocore_pos/features/licensing/domain/repositories/license_repository.dart';

// ---------------------------------------------------------------------------
// Repository singleton
// ---------------------------------------------------------------------------

final licenseRepositoryProvider = Provider<LicenseRepositoryImpl>((ref) {
  final db = ref.watch(databaseProvider);
  return LicenseRepositoryImpl(db);
});

// ---------------------------------------------------------------------------
// Current license
// ---------------------------------------------------------------------------

/// Async provider for the active license row. Returns `null` when no license
/// has been activated (FREE tier applies).
final currentLicenseProvider = FutureProvider<LicenseEntity?>((ref) async {
  final repo = ref.watch(licenseRepositoryProvider);
  final tenantId = ref.watch(tenantIdProvider);
  return repo.getCurrentLicense(tenantId);
});

// ---------------------------------------------------------------------------
// License tier (synchronous, defaults to FREE)
// ---------------------------------------------------------------------------

/// The effective [LicenseTier] derived from the current license.
///
/// Synchronous — features can watch this without async boilerplate.
/// Falls back to [LicenseTier.free] while the async license is loading
/// or when no license is present.
final licenseTierProvider = Provider<LicenseTier>((ref) {
  final asyncLicense = ref.watch(currentLicenseProvider);
  return asyncLicense.maybeWhen(
    data: (license) => license?.effectiveTier ?? LicenseTier.free,
    orElse: () => LicenseTier.free,
  );
});

// ---------------------------------------------------------------------------
// FeatureFlagService
// ---------------------------------------------------------------------------

/// Stateless service that evaluates feature access against the current tier.
class FeatureFlagService {
  const FeatureFlagService(this.tier);

  final LicenseTier tier;

  /// Returns `true` when the current tier enables [feature].
  bool isEnabled(AppFeature feature) => tier.isAtLeast(feature.requiredTier);

  /// Convenience: returns all features enabled for the current tier.
  List<AppFeature> get enabledFeatures =>
      AppFeature.values.where(isEnabled).toList();
}

final featureFlagServiceProvider = Provider<FeatureFlagService>((ref) {
  final tier = ref.watch(licenseTierProvider);
  return FeatureFlagService(tier);
});

// ---------------------------------------------------------------------------
// License notifier (activate / deactivate)
// ---------------------------------------------------------------------------

/// Notifier that handles user-triggered license activation and deactivation.
///
/// UI calls [activate] with the token string pasted by the user; the notifier
/// validates via Ed25519, persists to SQLite, and invalidates
/// [currentLicenseProvider] so all downstream providers refresh.
class LicenseNotifier extends StateNotifier<AsyncValue<LicenseEntity?>> {
  LicenseNotifier(this._ref) : super(const AsyncValue.loading()) {
    _load();
  }

  final Ref _ref;

  Future<void> _load() async {
    state = const AsyncValue.loading();
    try {
      final repo = _ref.read(licenseRepositoryProvider);
      final tenantId = _ref.read(tenantIdProvider);
      final license = await repo.getCurrentLicense(tenantId);
      state = AsyncValue.data(license);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Activate a new license token. Returns the entity on success.
  /// Throws [LicenseException] on validation failure.
  Future<LicenseEntity> activate(String tokenBase64) async {
    final repo = _ref.read(licenseRepositoryProvider);
    final tenantId = _ref.read(tenantIdProvider);
    final entity = await repo.activateLicense(tenantId, tokenBase64);
    state = AsyncValue.data(entity);
    // Invalidate all downstream providers.
    _ref.invalidate(currentLicenseProvider);
    return entity;
  }

  /// Remove the current license and revert to FREE.
  Future<void> deactivate() async {
    final repo = _ref.read(licenseRepositoryProvider);
    final tenantId = _ref.read(tenantIdProvider);
    await repo.deactivateLicense(tenantId);
    state = const AsyncValue.data(null);
    _ref.invalidate(currentLicenseProvider);
  }
}

final licenseNotifierProvider =
    StateNotifierProvider<LicenseNotifier, AsyncValue<LicenseEntity?>>((ref) {
  return LicenseNotifier(ref);
});
