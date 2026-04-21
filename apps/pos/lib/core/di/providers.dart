/// Core dependency-injection providers for GastroCore POS.
///
/// Exposes the [AppDatabase] singleton and tenant configuration as
/// Riverpod providers so every feature module can declare its
/// dependencies without importing concrete implementations directly.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';

// ---------------------------------------------------------------------------
// Database
// ---------------------------------------------------------------------------

/// Singleton [AppDatabase] instance shared across the entire application.
///
/// Overridden in `main()` with the real instance created before app start.
///
/// For tests, import `test/helpers/test_provider_overrides.dart` and spread
/// `testProviderOverrides()` into your `ProviderScope.overrides` — that
/// wires an in-memory database and a fixture tenant id in one call.
final databaseProvider = Provider<AppDatabase>((ref) {
  // Not overridden — surface a concrete action item instead of a cryptic
  // UnimplementedError so test failures point at the missing wiring.
  throw StateError(
    'databaseProvider has no value. Either (a) in production, pass '
    '`databaseProvider.overrideWithValue(AppDatabase(...))` via '
    'ProviderScope in main.dart before runApp, or (b) in tests, '
    'spread `testProviderOverrides()` from '
    'test/helpers/test_provider_overrides.dart into your ProviderScope.',
  );
});

// ---------------------------------------------------------------------------
// Tenant
// ---------------------------------------------------------------------------

/// Current tenant identifier.
///
/// Overridden in `main()` with the actual tenant ID loaded from the
/// database after seeding. All feature providers depend on this value
/// to scope queries to the correct tenant.
///
/// For tests, see [databaseProvider] — `testProviderOverrides()`
/// wires both providers together with a fixture tenant id.
final tenantIdProvider = Provider<String>((ref) {
  throw StateError(
    'tenantIdProvider has no value. Either (a) in production, pass '
    '`tenantIdProvider.overrideWithValue(<id>)` via ProviderScope in '
    'main.dart after loading the active tenant, or (b) in tests, '
    'spread `testProviderOverrides()` from '
    'test/helpers/test_provider_overrides.dart into your ProviderScope.',
  );
});

// ---------------------------------------------------------------------------
// Device
// ---------------------------------------------------------------------------

/// Identifier for the current POS terminal / register.
///
/// Defaults to 'DEV-POS-01'. Update via the settings screen to support
/// multiple registers in the same restaurant (e.g. 'DEV-POS-02').
///
/// Using a [StateProvider] so the settings screen can persist a new value
/// without requiring an app restart.
final deviceIdProvider = StateProvider<String>((ref) => 'DEV-POS-01');

// ---------------------------------------------------------------------------
// Tenant info
// ---------------------------------------------------------------------------

/// The [Tenant] record for the current tenant, loaded once on startup.
///
/// Used by the receipt preview, backoffice header, and anywhere that needs
/// the restaurant's name, address, phone, or currency.
final tenantInfoProvider = StreamProvider<Tenant?>((ref) {
  final db = ref.watch(databaseProvider);
  final tenantId = ref.watch(tenantIdProvider);
  return (db.select(db.tenants)
        ..where((t) => t.id.equals(tenantId)))
      .watchSingleOrNull();
});
