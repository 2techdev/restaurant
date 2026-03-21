/// Test app bootstrap for GastroCore POS integration tests.
///
/// Provides [launchTestApp] which:
///   - Creates an in-memory Drift database
///   - Runs AppInitializer to seed demo data
///   - Pumps [GastroCoreApp] with provider overrides so the real router,
///     theme, and localization are exercised end-to-end.
///
/// Also exposes [testDb] and [testTenantId] accessors for tests that need
/// to manipulate data directly (e.g. pre-create orders).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/app.dart';
import 'package:gastrocore_pos/core/data/app_initializer.dart';
import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/di/providers.dart';

// ---------------------------------------------------------------------------
// Shared state exposed to test files
// ---------------------------------------------------------------------------

late AppDatabase testDb;
late String testTenantId;

// ---------------------------------------------------------------------------
// Bootstrap
// ---------------------------------------------------------------------------

/// Boot the app inside an in-memory database with seeded demo data.
///
/// After this call the widget tree is live and [testDb] / [testTenantId] are
/// populated.  The calling test must [pumpUntilFound] for the screen it expects.
Future<void> launchTestApp(WidgetTester tester) async {
  testDb = AppDatabase.createInMemory();
  await AppInitializer.initialize(testDb);

  final tenants = await testDb.select(testDb.tenants).get();
  testTenantId = tenants.first.id;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(testDb),
        tenantIdProvider.overrideWithValue(testTenantId),
      ],
      child: const GastroCoreApp(),
    ),
  );
}

// ---------------------------------------------------------------------------
// Polling helper (shared)
// ---------------------------------------------------------------------------

/// Pump frames until [finder] matches at least one widget, or [timeout] elapses.
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 200));
  }
  await tester.pumpAndSettle();
}
