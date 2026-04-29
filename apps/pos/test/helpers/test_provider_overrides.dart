/// Shared Riverpod overrides for tests.
///
/// Drop-in replacement for the `databaseProvider` / `tenantIdProvider`
/// hard-error fallback so test harnesses can bring up the POS stack
/// without wiring the overrides themselves:
///
/// ```dart
/// ProviderScope(
///   overrides: [
///     ...testProviderOverrides(),
///     // feature-specific overrides on top
///   ],
///   child: MaterialApp(...),
/// )
/// ```
///
/// Each call creates a fresh [AppDatabase.createInMemory] — callers that
/// want to assert on DB state should pass their own instance via
/// [database] so they keep a reference to it.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/di/providers.dart';

/// Canonical fixture tenant id used across tests.
const String kTestTenantId = 'test-tenant';

/// Returns overrides suitable for a ProviderScope in any widget / unit
/// test that touches the DI graph.
///
/// [database] — optional pre-constructed instance (e.g. when the test
/// needs to seed rows before the scope is built). Defaults to a fresh
/// in-memory database.
///
/// [tenantId] — override the fixture tenant id if the test needs a
/// different scope (e.g. cross-tenant isolation tests).
List<Override> testProviderOverrides({
  AppDatabase? database,
  String tenantId = kTestTenantId,
}) {
  final db = database ?? AppDatabase.createInMemory();
  return <Override>[
    databaseProvider.overrideWithValue(db),
    tenantIdProvider.overrideWithValue(tenantId),
  ];
}
