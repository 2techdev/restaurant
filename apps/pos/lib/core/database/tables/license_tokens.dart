import 'package:drift/drift.dart';

/// Stores activated Ed25519-signed license tokens for the current installation.
///
/// Only one token per tenant should be active at a time. When a new token is
/// activated the old rows are deactivated (isActive = false) rather than
/// deleted so the audit trail is preserved.
@DataClassName('LicenseTokenRow')
class LicenseTokens extends Table {
  /// Primary key — UUID generated at activation time.
  TextColumn get id => text()();

  /// Scopes the license to a tenant (matches Tenants.id).
  TextColumn get tenantId => text()();

  /// Original Base64url-encoded token string as provided by the user.
  TextColumn get tokenRaw => text()();

  /// Extracted businessId field from the verified token payload.
  TextColumn get businessId => text()();

  /// Tier string: 'free' | 'professional' | 'enterprise'.
  TextColumn get tier => text()();

  /// Token issuedAt timestamp (UTC).
  DateTimeColumn get issuedAt => dateTime()();

  /// Token expiry timestamp (UTC).
  DateTimeColumn get expiresAt => dateTime()();

  /// Optional device fingerprint embedded in the token (e.g. 'DEV-POS-01').
  /// Null means the token is not locked to a specific device.
  TextColumn get deviceFingerprint => text().nullable()();

  /// Whether this is the currently active license for the tenant.
  BoolColumn get isActive =>
      boolean().withDefault(const Constant(true))();

  /// When the token was first activated on this device.
  DateTimeColumn get activatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
