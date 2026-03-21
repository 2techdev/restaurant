/// Abstract interface for license storage and retrieval.
///
/// All feature-level code depends on this interface rather than the concrete
/// [LicenseRepositoryImpl], keeping the domain layer free of Drift/SQLite
/// details and easy to mock in tests.
library;

import 'package:gastrocore_pos/features/licensing/domain/entities/app_feature.dart';
import 'package:gastrocore_pos/features/licensing/domain/entities/license_entity.dart';
import 'package:gastrocore_pos/features/licensing/domain/entities/license_tier.dart';

abstract class LicenseRepository {
  /// Validate [tokenBase64] using Ed25519, persist it, and return the entity.
  ///
  /// Throws [LicenseException] if the token is malformed, the signature is
  /// invalid, or the token has already expired (beyond the grace window).
  Future<LicenseEntity> activateLicense(String tenantId, String tokenBase64);

  /// Returns the current active license for [tenantId], or `null` if none.
  Future<LicenseEntity?> getCurrentLicense(String tenantId);

  /// Deactivates all license rows for [tenantId] (reverts to FREE).
  Future<void> deactivateLicense(String tenantId);

  /// Returns the effective tier for the current license, defaulting to FREE.
  Future<LicenseTier> getLicenseTier(String tenantId);

  /// Returns `true` when the current effective tier enables [feature].
  Future<bool> isFeatureEnabled(String tenantId, AppFeature feature);
}

// ---------------------------------------------------------------------------
// Exception
// ---------------------------------------------------------------------------

class LicenseException implements Exception {
  const LicenseException(this.message);
  final String message;

  @override
  String toString() => 'LicenseException: $message';
}
