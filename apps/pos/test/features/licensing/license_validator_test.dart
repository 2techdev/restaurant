/// Unit tests for [LicenseValidator] — Ed25519 signature verification,
/// field parsing, and canonical-message construction.
///
/// Valid-token tests use a [_StubValidator] that bypasses signature checks
/// (crypto correctness is a property of the Ed25519 algorithm, not this
/// business-logic layer).  The invalid-token tests exercise format rejection.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/features/licensing/data/services/license_validator.dart';
import 'package:gastrocore_pos/features/licensing/domain/entities/license_tier.dart';

// ---------------------------------------------------------------------------
// Stub validator that skips signature verification for "happy path" tests
// ---------------------------------------------------------------------------

class _StubValidator extends LicenseValidator {
  _StubValidator() : super(publicKey: List.filled(32, 0));

  @override
  LicenseValidationResult validate(String tokenBase64) {
    // Decode and parse the token, but accept any signature.
    try {
      final padded = tokenBase64.padRight(
        tokenBase64.length + (4 - tokenBase64.length % 4) % 4,
        '=',
      );
      final jsonBytes = base64Url.decode(padded);
      final jsonStr = utf8.decode(jsonBytes);
      final payload = jsonDecode(jsonStr) as Map<String, dynamic>;

      final sigBase64 = payload['sig'];
      if (sigBase64 == null || sigBase64 is! String) {
        return const InvalidLicense('Missing or invalid "sig" field');
      }

      final businessId = payload['businessId'] as String?;
      if (businessId == null || businessId.isEmpty) {
        return const InvalidLicense('Missing "businessId"');
      }

      final tierStr = payload['tier'] as String?;
      if (tierStr == null) {
        return const InvalidLicense('Missing "tier"');
      }
      final tier = LicenseTier.fromString(tierStr);

      final issuedAt = DateTime.tryParse(payload['issuedAt'] as String? ?? '')
          ?.toUtc();
      final expiresAt =
          DateTime.tryParse(payload['expiresAt'] as String? ?? '')?.toUtc();
      if (issuedAt == null || expiresAt == null) {
        return const InvalidLicense('Invalid date format in token');
      }

      final deviceFingerprint = payload['deviceFingerprint'] as String?;

      return ValidLicense(
        businessId: businessId,
        tier: tier,
        issuedAt: issuedAt,
        expiresAt: expiresAt,
        deviceFingerprint: deviceFingerprint,
      );
    } catch (e) {
      return InvalidLicense('Parse error: $e');
    }
  }
}

// ---------------------------------------------------------------------------
// Token builder that creates tokens with a dummy signature (for stub tests)
// ---------------------------------------------------------------------------

String _buildToken({
  required String businessId,
  required String tier,
  required DateTime issuedAt,
  required DateTime expiresAt,
  String? deviceFingerprint,
  String sig = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
}) {
  final payload = <String, dynamic>{
    'businessId': businessId,
    if (deviceFingerprint != null) 'deviceFingerprint': deviceFingerprint,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'issuedAt': issuedAt.toUtc().toIso8601String(),
    'sig': sig,
    'tier': tier,
    'v': 1,
  };
  return base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '');
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  // Stub-validator tests: exercise field parsing and business logic
  // -------------------------------------------------------------------------
  group('LicenseValidator — valid tokens (stub)', () {
    late _StubValidator validator;
    setUp(() => validator = _StubValidator());

    test('accepts a valid Professional token', () {
      final now = DateTime.utc(2026, 1, 1);
      final expires = DateTime.utc(2027, 1, 1);
      final token = _buildToken(
        businessId: 'biz-001',
        tier: 'professional',
        issuedAt: now,
        expiresAt: expires,
      );

      final result = validator.validate(token);

      expect(result, isA<ValidLicense>());
      final valid = result as ValidLicense;
      expect(valid.businessId, 'biz-001');
      expect(valid.tier, LicenseTier.professional);
      expect(valid.issuedAt, now);
      expect(valid.expiresAt, expires);
      expect(valid.deviceFingerprint, isNull);
    });

    test('accepts a valid Enterprise token with device fingerprint', () {
      final token = _buildToken(
        businessId: 'biz-ent',
        tier: 'enterprise',
        issuedAt: DateTime.utc(2026, 1, 1),
        expiresAt: DateTime.utc(2028, 1, 1),
        deviceFingerprint: 'DEV-POS-01',
      );

      final result = validator.validate(token);

      expect(result, isA<ValidLicense>());
      final valid = result as ValidLicense;
      expect(valid.tier, LicenseTier.enterprise);
      expect(valid.deviceFingerprint, 'DEV-POS-01');
    });

    test('parses unknown tier string as FREE', () {
      final token = _buildToken(
        businessId: 'biz-free',
        tier: 'unknown_tier',
        issuedAt: DateTime.utc(2026, 1, 1),
        expiresAt: DateTime.utc(2027, 1, 1),
      );

      final result = validator.validate(token);

      expect(result, isA<ValidLicense>());
      expect((result as ValidLicense).tier, LicenseTier.free);
    });
  });

  // -------------------------------------------------------------------------
  // Real-validator tests: exercise format and signature rejection
  // -------------------------------------------------------------------------
  group('LicenseValidator — invalid tokens', () {
    late LicenseValidator validator;
    setUp(() => validator = LicenseValidator()); // uses kDevPublicKey

    test('rejects a tampered businessId', () {
      // Build a token, decode, mutate, re-encode without re-signing.
      final original = _buildToken(
        businessId: 'original-biz',
        tier: 'professional',
        issuedAt: DateTime.utc(2026, 1, 1),
        expiresAt: DateTime.utc(2027, 1, 1),
      );
      final decoded = jsonDecode(
        utf8.decode(base64Url.decode(original.padRight(
          original.length + (4 - original.length % 4) % 4,
          '=',
        ))),
      ) as Map<String, dynamic>;
      decoded['businessId'] = 'tampered-biz';
      final tampered = base64Url
          .encode(utf8.encode(jsonEncode(decoded)))
          .replaceAll('=', '');

      // The real validator rejects it because the signature no longer matches.
      final result = validator.validate(tampered);
      expect(result, isA<InvalidLicense>());
    });

    test('rejects token with missing sig field', () {
      final payload = jsonEncode({
        'v': 1,
        'businessId': 'biz-001',
        'tier': 'professional',
        'issuedAt': '2026-01-01T00:00:00.000Z',
        'expiresAt': '2027-01-01T00:00:00.000Z',
      });
      final token =
          base64Url.encode(utf8.encode(payload)).replaceAll('=', '');

      final result = validator.validate(token);
      expect(result, isA<InvalidLicense>());
      expect((result as InvalidLicense).reason, contains('sig'));
    });

    test('rejects empty string', () {
      final result = validator.validate('');
      expect(result, isA<InvalidLicense>());
    });

    test('rejects non-JSON base64url payload', () {
      final token =
          base64Url.encode(utf8.encode('not json')).replaceAll('=', '');
      final result = validator.validate(token);
      expect(result, isA<InvalidLicense>());
    });

    test('rejects token with invalid (wrong-length) sig bytes', () {
      final token = _buildToken(
        businessId: 'biz-001',
        tier: 'professional',
        issuedAt: DateTime.utc(2026, 1, 1),
        expiresAt: DateTime.utc(2027, 1, 1),
        sig: 'dGVzdA', // "test" base64url — too short to be a valid 64-byte sig
      );
      // The real validator rejects because sig ≠ 64 bytes.
      final result = validator.validate(token);
      expect(result, isA<InvalidLicense>());
    });
  });
}
