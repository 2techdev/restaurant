/// Ed25519 JWT license service for GastroCore POS.
///
/// [LicenseService] wraps the existing [LicenseValidator] for signature
/// verification and adds parsing of the extended token payload fields
/// introduced in the `edition`-based token format:
/// `edition`, `features[]`, `maxDevices`, `customerName`.
///
/// It is also backward-compatible with the legacy `tier`-based token format
/// (tokens that use `"tier"` instead of `"edition"`).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:gastrocore_pos/features/license/license_models.dart';
import 'package:gastrocore_pos/features/licensing/data/services/license_validator.dart';

/// Service that decodes and verifies GastroCore license tokens.
///
/// All verification is done offline using the embedded Ed25519 public key —
/// no network call is required (Swiss offline-first requirement).
///
/// Inject a custom [publicKey] in unit tests to use a test key pair.
class LicenseService {
  const LicenseService({List<int>? publicKey}) : _publicKey = publicKey;

  final List<int>? _publicKey;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Verifies the Ed25519 signature of [tokenBase64] and decodes all claims.
  ///
  /// Returns `null` when the signature is invalid, the token is structurally
  /// malformed, or required fields are missing.
  ///
  /// Does NOT check expiry — callers should inspect [LicenseToken.isExpired].
  LicenseToken? verifyAndDecode(String tokenBase64) {
    // 1. Verify the Ed25519 signature via the existing validator.
    //    The validator accepts both 'edition' and 'tier' field names.
    final validator = LicenseValidator(publicKey: _publicKey);
    final result = validator.validate(tokenBase64);
    if (result is InvalidLicense) return null;
    final valid = result as ValidLicense;

    // 2. Decode the raw JSON to extract extended fields not parsed by the
    //    base validator.
    try {
      final jsonBytes = _base64UrlDecode(tokenBase64);
      final jsonStr = utf8.decode(jsonBytes);
      final payload = jsonDecode(jsonStr) as Map<String, dynamic>;

      // Edition: prefer 'edition' field; fall back to 'tier' for legacy tokens.
      final editionStr =
          (payload['edition'] as String?) ?? (payload['tier'] as String?) ?? '';
      final edition = LicenseEdition.fromString(editionStr);

      // Explicit feature overrides embedded in the token.
      final featuresRaw = payload['features'] as List<dynamic>? ?? const [];
      final features = featuresRaw
          .whereType<String>()
          .map(_parseFlag)
          .whereType<FeatureFlag>()
          .toList();

      final customerName = (payload['customerName'] as String?) ?? '';
      final maxDevices = (payload['maxDevices'] as num?)?.toInt() ?? 1;

      return LicenseToken(
        edition: edition,
        features: features,
        expiresAt: valid.expiresAt,
        deviceLimit: maxDevices,
        customerName: customerName,
        issuedAt: valid.issuedAt,
        deviceFingerprint: valid.deviceFingerprint,
      );
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  static FeatureFlag? _parseFlag(String name) {
    for (final f in FeatureFlag.values) {
      if (f.name == name) return f;
    }
    return null;
  }

  static Uint8List _base64UrlDecode(String input) {
    final padded = input.padRight(
      input.length + (4 - input.length % 4) % 4,
      '=',
    );
    return base64Url.decode(padded);
  }
}
