/// Drift-backed implementation of [LicenseRepository].
///
/// All license tokens are stored in the [LicenseTokens] table. Only one row
/// per tenant is marked [isActive] = true at any time. Previous tokens are
/// kept for auditing but ignored during tier resolution.
library;

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/features/licensing/data/services/license_validator.dart';
import 'package:gastrocore_pos/features/licensing/domain/entities/app_feature.dart';
import 'package:gastrocore_pos/features/licensing/domain/entities/license_entity.dart';
import 'package:gastrocore_pos/features/licensing/domain/entities/license_tier.dart';
import 'package:gastrocore_pos/features/licensing/domain/repositories/license_repository.dart';

class LicenseRepositoryImpl implements LicenseRepository {
  LicenseRepositoryImpl(this._db, {LicenseValidator? validator})
      : _validator = validator ?? LicenseValidator();

  final AppDatabase _db;
  final LicenseValidator _validator;
  final _uuid = const Uuid();

  // ---------------------------------------------------------------------------
  // LicenseRepository interface
  // ---------------------------------------------------------------------------

  @override
  Future<LicenseEntity> activateLicense(
      String tenantId, String tokenBase64) async {
    // 1. Validate the token cryptographically.
    final result = _validator.validate(tokenBase64);
    if (result is InvalidLicense) {
      throw LicenseException(result.reason);
    }
    final valid = result as ValidLicense;

    // 2. Deactivate any existing active rows for this tenant.
    await (_db.update(_db.licenseTokens)
          ..where((t) => t.tenantId.equals(tenantId) & t.isActive.equals(true)))
        .write(const LicenseTokensCompanion(isActive: Value(false)));

    // 3. Insert the new license row.
    final now = DateTime.now().toUtc();
    final id = _uuid.v4();
    await _db.into(_db.licenseTokens).insert(
          LicenseTokensCompanion.insert(
            id: id,
            tenantId: tenantId,
            tokenRaw: tokenBase64,
            businessId: valid.businessId,
            tier: valid.tier.name,
            issuedAt: valid.issuedAt,
            expiresAt: valid.expiresAt,
            deviceFingerprint: Value(valid.deviceFingerprint),
            isActive: const Value(true),
            activatedAt: now,
          ),
        );

    return LicenseEntity(
      id: id,
      businessId: valid.businessId,
      tier: valid.tier,
      issuedAt: valid.issuedAt,
      expiresAt: valid.expiresAt,
      deviceFingerprint: valid.deviceFingerprint,
      tokenRaw: tokenBase64,
    );
  }

  @override
  Future<LicenseEntity?> getCurrentLicense(String tenantId) async {
    final row = await (_db.select(_db.licenseTokens)
          ..where((t) =>
              t.tenantId.equals(tenantId) & t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm.desc(t.activatedAt)])
          ..limit(1))
        .getSingleOrNull();

    if (row == null) return null;
    return _rowToEntity(row);
  }

  @override
  Future<void> deactivateLicense(String tenantId) async {
    await (_db.update(_db.licenseTokens)
          ..where((t) => t.tenantId.equals(tenantId)))
        .write(const LicenseTokensCompanion(isActive: Value(false)));
  }

  @override
  Future<LicenseTier> getLicenseTier(String tenantId) async {
    final license = await getCurrentLicense(tenantId);
    return license?.effectiveTier ?? LicenseTier.free;
  }

  @override
  Future<bool> isFeatureEnabled(String tenantId, AppFeature feature) async {
    final tier = await getLicenseTier(tenantId);
    return tier.isAtLeast(feature.requiredTier);
  }

  // ---------------------------------------------------------------------------
  // Mapper
  // ---------------------------------------------------------------------------

  LicenseEntity _rowToEntity(LicenseTokenRow row) {
    return LicenseEntity(
      id: row.id,
      businessId: row.businessId,
      tier: LicenseTier.fromString(row.tier),
      issuedAt: row.issuedAt,
      expiresAt: row.expiresAt,
      deviceFingerprint: row.deviceFingerprint,
      tokenRaw: row.tokenRaw,
    );
  }
}
