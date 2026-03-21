/// Integration tests for [LicenseRepositoryImpl] using an in-memory Drift DB.
///
/// A stub [LicenseValidator] is injected so tests are not coupled to
/// Ed25519 key material — cryptographic correctness is covered separately
/// in license_validator_test.dart.
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/features/licensing/data/repositories/license_repository_impl.dart';
import 'package:gastrocore_pos/features/licensing/data/services/license_validator.dart';
import 'package:gastrocore_pos/features/licensing/domain/entities/app_feature.dart';
import 'package:gastrocore_pos/features/licensing/domain/entities/license_tier.dart';
import 'package:gastrocore_pos/features/licensing/domain/repositories/license_repository.dart';

// ---------------------------------------------------------------------------
// Stub validator
// ---------------------------------------------------------------------------

/// A [LicenseValidator] subclass that returns a predetermined result.
class _StubValidator extends LicenseValidator {
  _StubValidator(this._result);
  final LicenseValidationResult _result;

  @override
  LicenseValidationResult validate(String tokenBase64) => _result;
}

LicenseValidator _validatorFor(LicenseTier tier) {
  return _StubValidator(
    ValidLicense(
      businessId: 'biz-test',
      tier: tier,
      issuedAt: DateTime.utc(2026, 1, 1),
      expiresAt: DateTime.utc(2027, 1, 1),
    ),
  );
}

LicenseValidator _expiredValidatorFor(LicenseTier tier) {
  return _StubValidator(
    ValidLicense(
      businessId: 'biz-test',
      tier: tier,
      issuedAt: DateTime.utc(2024, 1, 1),
      // Expired well beyond grace period.
      expiresAt: DateTime.utc(2024, 6, 1),
    ),
  );
}

LicenseValidator _invalidValidator() {
  return _StubValidator(const InvalidLicense('Bad signature'));
}

// ---------------------------------------------------------------------------
// Setup helpers
// ---------------------------------------------------------------------------

const _tenantId = 'tenant-001';

AppDatabase _createDb() => AppDatabase(NativeDatabase.memory());

/// Seed the minimum required tenant row.
Future<void> _seedTenant(AppDatabase db) async {
  final now = DateTime.now().toUtc();
  await db.into(db.tenants).insert(
        TenantsCompanion.insert(
          id: _tenantId,
          name: 'Test Restaurant',
          createdAt: now,
          updatedAt: now,
        ),
      );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late AppDatabase db;

  setUp(() async {
    db = _createDb();
    await _seedTenant(db);
  });

  tearDown(() async {
    await db.close();
  });

  // -------------------------------------------------------------------------
  group('getCurrentLicense', () {
    test('returns null when no license has been activated', () async {
      final repo = LicenseRepositoryImpl(db);
      final license = await repo.getCurrentLicense(_tenantId);
      expect(license, isNull);
    });
  });

  // -------------------------------------------------------------------------
  group('activateLicense', () {
    test('persists a valid Professional license', () async {
      final repo = LicenseRepositoryImpl(
          db, validator: _validatorFor(LicenseTier.professional));

      final entity = await repo.activateLicense(_tenantId, 'fake-token');

      expect(entity.tier, LicenseTier.professional);
      expect(entity.businessId, 'biz-test');

      final fetched = await repo.getCurrentLicense(_tenantId);
      expect(fetched, isNotNull);
      expect(fetched!.tier, LicenseTier.professional);
    });

    test('replaces previous active license on re-activation', () async {
      final proRepo = LicenseRepositoryImpl(
          db, validator: _validatorFor(LicenseTier.professional));
      await proRepo.activateLicense(_tenantId, 'token-pro');

      final entRepo = LicenseRepositoryImpl(
          db, validator: _validatorFor(LicenseTier.enterprise));
      await entRepo.activateLicense(_tenantId, 'token-ent');

      final current = await entRepo.getCurrentLicense(_tenantId);
      expect(current!.tier, LicenseTier.enterprise);

      // Only one active row should exist.
      final activeRows = await (db.select(db.licenseTokens)
            ..where((t) =>
                t.tenantId.equals(_tenantId) & t.isActive.equals(true)))
          .get();
      expect(activeRows.length, 1);
    });

    test('throws LicenseException for invalid token', () async {
      final repo =
          LicenseRepositoryImpl(db, validator: _invalidValidator());

      expect(
        () => repo.activateLicense(_tenantId, 'bad-token'),
        throwsA(isA<LicenseException>()),
      );
    });
  });

  // -------------------------------------------------------------------------
  group('getLicenseTier', () {
    test('returns FREE when no license activated', () async {
      final repo = LicenseRepositoryImpl(db);
      final tier = await repo.getLicenseTier(_tenantId);
      expect(tier, LicenseTier.free);
    });

    test('returns nominal tier for active non-expired license', () async {
      final repo = LicenseRepositoryImpl(
          db, validator: _validatorFor(LicenseTier.enterprise));
      await repo.activateLicense(_tenantId, 'token');

      final tier = await repo.getLicenseTier(_tenantId);
      expect(tier, LicenseTier.enterprise);
    });

    test('returns FREE for expired license past grace period', () async {
      final repo = LicenseRepositoryImpl(
          db, validator: _expiredValidatorFor(LicenseTier.professional));
      await repo.activateLicense(_tenantId, 'expired-token');

      // effectiveTier is computed from the entity.
      final tier = await repo.getLicenseTier(_tenantId);
      expect(tier, LicenseTier.free);
    });
  });

  // -------------------------------------------------------------------------
  group('isFeatureEnabled', () {
    test('KDS disabled on FREE tier', () async {
      final repo = LicenseRepositoryImpl(db);
      final enabled =
          await repo.isFeatureEnabled(_tenantId, AppFeature.kds);
      expect(enabled, isFalse);
    });

    test('KDS enabled on PROFESSIONAL tier', () async {
      final repo = LicenseRepositoryImpl(
          db, validator: _validatorFor(LicenseTier.professional));
      await repo.activateLicense(_tenantId, 'token');

      final enabled =
          await repo.isFeatureEnabled(_tenantId, AppFeature.kds);
      expect(enabled, isTrue);
    });

    test('cloudSync disabled on PROFESSIONAL tier', () async {
      final repo = LicenseRepositoryImpl(
          db, validator: _validatorFor(LicenseTier.professional));
      await repo.activateLicense(_tenantId, 'token');

      final enabled =
          await repo.isFeatureEnabled(_tenantId, AppFeature.cloudSync);
      expect(enabled, isFalse);
    });

    test('all features enabled on ENTERPRISE tier', () async {
      final repo = LicenseRepositoryImpl(
          db, validator: _validatorFor(LicenseTier.enterprise));
      await repo.activateLicense(_tenantId, 'token');

      for (final feature in AppFeature.values) {
        final enabled =
            await repo.isFeatureEnabled(_tenantId, feature);
        expect(enabled, isTrue,
            reason: '${feature.name} should be enabled for enterprise');
      }
    });
  });

  // -------------------------------------------------------------------------
  group('deactivateLicense', () {
    test('reverts to FREE after deactivation', () async {
      final repo = LicenseRepositoryImpl(
          db, validator: _validatorFor(LicenseTier.professional));
      await repo.activateLicense(_tenantId, 'token');
      await repo.deactivateLicense(_tenantId);

      final license = await repo.getCurrentLicense(_tenantId);
      expect(license, isNull);

      final tier = await repo.getLicenseTier(_tenantId);
      expect(tier, LicenseTier.free);
    });
  });
}
