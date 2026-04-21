/// Verifies [testProviderOverrides] actually satisfies the DI graph that
/// would otherwise hard-throw from `core/di/providers.dart`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/di/providers.dart';

import 'test_provider_overrides.dart';

void main() {
  test('providers throw a StateError with actionable guidance by default',
      () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      () => container.read(databaseProvider),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('testProviderOverrides'),
        ),
      ),
    );
    expect(
      () => container.read(tenantIdProvider),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('testProviderOverrides'),
        ),
      ),
    );
  });

  test('testProviderOverrides wires both providers with sensible defaults',
      () {
    final container = ProviderContainer(
      overrides: testProviderOverrides(),
    );
    addTearDown(container.dispose);

    final db = container.read(databaseProvider);
    expect(db, isA<AppDatabase>());
    expect(container.read(tenantIdProvider), kTestTenantId);

    addTearDown(db.close);
  });

  test('caller can inject their own database instance to seed fixtures',
      () async {
    final db = AppDatabase.createInMemory();
    addTearDown(db.close);

    final container = ProviderContainer(
      overrides: testProviderOverrides(database: db, tenantId: 'acme'),
    );
    addTearDown(container.dispose);

    expect(identical(container.read(databaseProvider), db), isTrue);
    expect(container.read(tenantIdProvider), 'acme');
  });
}
