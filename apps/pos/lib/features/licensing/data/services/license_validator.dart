/// Ed25519 license token validator.
///
/// Token format (offline-first, no network required):
///
///   Base64url( UTF-8( JSON ) )
///
/// where the JSON object contains:
/// ```json
/// {
///   "v": 1,
///   "businessId": "UUID",
///   "tier": "free | professional | enterprise",
///   "issuedAt": "ISO-8601 UTC",
///   "expiresAt": "ISO-8601 UTC",
///   "deviceFingerprint": "optional string",
///   "sig": "Base64url Ed25519 signature"
/// }
/// ```
///
/// The signed message is the canonical JSON of all fields *except* "sig",
/// with keys sorted alphabetically, no whitespace, UTF-8 encoded.
///
/// Canonical key order: businessId · deviceFingerprint · expiresAt ·
///   issuedAt · tier · v
///
/// ## Key management
/// The production Ed25519 key pair lives on the GastroCore licence server.
/// Only the 32-byte public key is embedded here. Pass a custom [publicKey]
/// to [LicenseValidator] in unit tests to use a test key pair instead.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import 'package:gastrocore_pos/features/licensing/domain/entities/license_tier.dart';

// ---------------------------------------------------------------------------
// Embedded public key
// ---------------------------------------------------------------------------

/// Production Ed25519 public key for GastroCore license validation.
///
/// Generated 2026-03-23. The matching private seed lives exclusively on
/// the GastroCore license server — never commit it to this repository.
/// To rotate keys: generate a new pair with scripts/generate_license.js,
/// replace these bytes, and re-issue licenses for existing customers.
const List<int> kDevPublicKey = [
  0x6d, 0xd7, 0x0c, 0xf7, 0x21, 0x8b, 0x9d, 0x81,
  0x14, 0xd8, 0x47, 0xd8, 0xeb, 0xd6, 0x20, 0x19,
  0xf2, 0x5f, 0xba, 0x42, 0x91, 0xe4, 0x4b, 0x67,
  0x51, 0xd9, 0x9a, 0xd0, 0x8a, 0x2f, 0xbb, 0x4e,
];

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

/// Outcome of a [LicenseValidator.validate] call.
sealed class LicenseValidationResult {
  const LicenseValidationResult();
}

/// Token is cryptographically valid and all required fields are present.
final class ValidLicense extends LicenseValidationResult {
  const ValidLicense({
    required this.businessId,
    required this.tier,
    required this.issuedAt,
    required this.expiresAt,
    this.deviceFingerprint,
  });

  final String businessId;
  final LicenseTier tier;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final String? deviceFingerprint;
}

/// Token failed validation; [reason] is a developer-facing explanation.
final class InvalidLicense extends LicenseValidationResult {
  const InvalidLicense(this.reason);
  final String reason;
}

// ---------------------------------------------------------------------------
// Pure-Dart Ed25519 verification
// ---------------------------------------------------------------------------
//
// Uses BigInt arithmetic per RFC 8032. SHA-512 is provided by the crypto pkg.

// Field prime: 2^255 - 19
final _p = (BigInt.one << 255) - BigInt.from(19);

// Group order
final _l = (BigInt.one << 252) +
    BigInt.parse('27742317777372353535851937790883648493');

// d = -121665/121666 mod p
final _d = (_modInv(BigInt.from(121666), _p) *
        ((BigInt.from(-121665) % _p + _p) % _p)) %
    _p;

// sqrt(-1) = 2^((p-1)/4) mod p
final _sqrtM1 =
    BigInt.two.modPow((_p - BigInt.one) ~/ BigInt.from(4), _p);

// Base point full (extended coordinates [X, Y, Z, T])
final basePoint = _makeBasePoint();

BigInt _modInv(BigInt a, BigInt m) => a.modInverse(m);

List<BigInt> _makeBasePoint() {
  final y = BigInt.from(4) * _modInv(BigInt.from(5), _p) % _p;
  final x = _recoverX(y);
  return [x, y, BigInt.one, x * y % _p];
}

BigInt _recoverX(BigInt y) {
  // RFC 8032 §5.1.3: recover x from y
  final y2 = y * y % _p;
  final u = (y2 - BigInt.one + _p) % _p;
  final v = (_d * y2 % _p + BigInt.one) % _p;
  // x = (u/v)^((p+3)/8) using x = u * v^3 * (u * v^7)^((p-5)/8)
  final v3 = v * v % _p * v % _p;
  final v7 = v3 * v3 % _p * v % _p;
  final exp = (_p - BigInt.from(5)) ~/ BigInt.from(8);
  var x = u * v3 % _p * (u * v7 % _p).modPow(exp, _p) % _p;
  // check: v * x^2 == u?
  if (v * x % _p * x % _p != u % _p) {
    x = x * _sqrtM1 % _p;
  }
  if (x.isOdd) x = (_p - x) % _p;
  return x;
}

// 2*d constant for extended Edwards point addition
final _d2 = _d * BigInt.two % _p;

List<BigInt> _pointAdd(List<BigInt> P, List<BigInt> Q) {
  // Extended twisted Edwards addition (RFC 8032 §5.1.4)
  final a = (P[1] - P[0] + _p) % _p * ((Q[1] - Q[0] + _p) % _p) % _p;
  final b = (P[1] + P[0]) % _p * ((Q[1] + Q[0]) % _p) % _p;
  final c = P[3] * _d2 % _p * Q[3] % _p;
  final d = P[2] * BigInt.two % _p * Q[2] % _p;
  final e = (b - a + _p) % _p;
  final f = (d - c + _p) % _p;
  final g = (d + c) % _p;
  final h = (b + a) % _p;
  return [e * f % _p, g * h % _p, f * g % _p, e * h % _p];
}

List<BigInt> _scalarMul(List<BigInt> P, BigInt s) {
  var Q = [BigInt.zero, BigInt.one, BigInt.one, BigInt.zero];
  s = s % _l;
  while (s > BigInt.zero) {
    if (s.isOdd) Q = _pointAdd(Q, P);
    P = _pointAdd(P, P);
    s >>= 1;
  }
  return Q;
}

BigInt _decodeLittleEndian(List<int> b) {
  var result = BigInt.zero;
  for (var i = 0; i < b.length; i++) {
    result |= BigInt.from(b[i]) << (8 * i);
  }
  return result;
}

Uint8List _encodeLittleEndian(BigInt n, int length) {
  final b = Uint8List(length);
  var temp = n;
  for (var i = 0; i < length; i++) {
    b[i] = (temp & BigInt.from(0xff)).toInt();
    temp >>= 8;
  }
  return b;
}

List<BigInt> _decodePointFull(List<int> s) {
  final yInt = _decodeLittleEndian(s) & ((BigInt.one << 255) - BigInt.one);
  final sign = s[31] >> 7;
  var x = _recoverX(yInt);
  if (x == BigInt.zero && sign != 0) {
    throw Exception('invalid point: x is zero but sign bit set');
  }
  if (x.isOdd != (sign == 1)) x = (_p - x) % _p;
  return [x, yInt, BigInt.one, x * yInt % _p];
}

Uint8List _encodePoint(List<BigInt> P) {
  final zi = _modInv(P[2], _p);
  final x = P[0] * zi % _p;
  final y = P[1] * zi % _p;
  final b = _encodeLittleEndian(y, 32);
  if (x.isOdd) b[31] |= 0x80;
  return b;
}

Uint8List _sha512(List<int> data) {
  final digest = crypto.sha512.convert(data);
  return Uint8List.fromList(digest.bytes);
}

bool _ed25519Verify(
    Uint8List publicKey, Uint8List message, Uint8List sig) {
  if (sig.length != 64 || publicKey.length != 32) return false;

  try {
    final R = _decodePointFull(sig.sublist(0, 32));
    final A = _decodePointFull(publicKey);

    final S = _decodeLittleEndian(sig.sublist(32, 64));
    if (S >= _l) return false;

    final hInput = <int>[...sig.sublist(0, 32), ...publicKey, ...message];
    final hBytes = _sha512(hInput);
    final h = _decodeLittleEndian(hBytes) % _l;

    // Check: [8][S]B == [8]R + [8][h]A
    final lhs = _encodePoint(_scalarMul(basePoint, BigInt.from(8) * S % _l));
    final rhs = _encodePoint(
      _pointAdd(
        _scalarMul(R, BigInt.from(8)),
        _scalarMul(A, BigInt.from(8) * h % _l),
      ),
    );

    return _constantTimeEqual(lhs, rhs);
  } catch (_) {
    return false;
  }
}

bool _constantTimeEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  var result = 0;
  for (var i = 0; i < a.length; i++) {
    result |= a[i] ^ b[i];
  }
  return result == 0;
}

// ---------------------------------------------------------------------------
// Validator
// ---------------------------------------------------------------------------

class LicenseValidator {
  /// Creates a validator using [publicKey] bytes (32-byte Ed25519 key).
  ///
  /// Defaults to [kDevPublicKey]; pass a custom key in tests.
  LicenseValidator({List<int>? publicKey})
      : _publicKeyBytes =
            Uint8List.fromList(publicKey ?? kDevPublicKey);

  final Uint8List _publicKeyBytes;

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Validates a Base64url-encoded license token.
  LicenseValidationResult validate(String tokenBase64) {
    try {
      // 1. Decode outer Base64url envelope.
      final jsonBytes = _base64UrlDecode(tokenBase64);
      final jsonStr = utf8.decode(jsonBytes);
      final Map<String, dynamic> payload =
          jsonDecode(jsonStr) as Map<String, dynamic>;

      // 2. Extract and remove the signature field.
      final sigBase64 = payload['sig'];
      if (sigBase64 == null || sigBase64 is! String) {
        return const InvalidLicense('Missing or invalid "sig" field');
      }
      final Map<String, dynamic> unsigned = Map<String, dynamic>.from(payload)
        ..remove('sig');

      // 3. Reconstruct the canonical message that was signed.
      final message = _canonicalMessage(unsigned);

      // 4. Verify Ed25519 signature.
      final sigBytes = _base64UrlDecode(sigBase64);
      if (!_verify(message, sigBytes)) {
        return const InvalidLicense('Ed25519 signature verification failed');
      }

      // 5. Parse and validate required fields.
      final businessId = payload['businessId'];
      if (businessId == null || businessId is! String || businessId.isEmpty) {
        return const InvalidLicense('Missing "businessId"');
      }

      // Accept 'edition' (new token format) as an alias for 'tier' (legacy).
      final tierStr = (payload['tier'] ?? payload['edition']) as String?;
      if (tierStr == null || tierStr.isEmpty) {
        return const InvalidLicense('Missing "tier" or "edition" field');
      }
      final tier = LicenseTier.fromString(tierStr);

      final issuedAtStr = payload['issuedAt'];
      final expiresAtStr = payload['expiresAt'];
      if (issuedAtStr == null || expiresAtStr == null) {
        return const InvalidLicense('Missing "issuedAt" or "expiresAt"');
      }

      final issuedAt = DateTime.tryParse(issuedAtStr as String)?.toUtc();
      final expiresAt = DateTime.tryParse(expiresAtStr as String)?.toUtc();
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
    } on FormatException catch (e) {
      return InvalidLicense('Token decode error: ${e.message}');
    } catch (e) {
      return InvalidLicense('Unexpected error: $e');
    }
  }

  // -------------------------------------------------------------------------
  // Private helpers
  // -------------------------------------------------------------------------

  /// Produces the deterministic UTF-8 byte sequence that was signed.
  Uint8List _canonicalMessage(Map<String, dynamic> unsigned) {
    final sorted = Map.fromEntries(
      unsigned.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
    return Uint8List.fromList(utf8.encode(jsonEncode(sorted)));
  }

  /// Runs Ed25519 signature verification.
  bool _verify(Uint8List message, Uint8List sig) {
    return _ed25519Verify(_publicKeyBytes, message, sig);
  }

  /// Decodes a Base64url string with or without padding.
  static Uint8List _base64UrlDecode(String input) {
    final padded = input.padRight(
      input.length + (4 - input.length % 4) % 4,
      '=',
    );
    return base64Url.decode(padded);
  }
}
