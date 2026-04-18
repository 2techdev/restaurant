/// Unit tests for [StationRepository] — covers default seeding and lookup
/// by code, plus soft-delete + reactivation.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/features/stations/data/station_repository.dart';

void main() {
  const tenantId = 'tenant-test';
  late AppDatabase db;
  late StationRepository repo;

  setUp(() {
    db = AppDatabase.createInMemory();
    repo = StationRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('seedDefaults', () {
    test('creates the five Swiss default stations on first run', () async {
      await repo.seedDefaults(tenantId);
      final stations = await repo.getActiveStations(tenantId);

      expect(stations.length, 5);
      expect(
        stations.map((s) => s.code),
        ['kitchen', 'grill', 'cold', 'dessert', 'bar'],
      );
      expect(stations.every((s) => s.isDefault), isTrue);
    });

    test('is idempotent — second run does not duplicate', () async {
      await repo.seedDefaults(tenantId);
      await repo.seedDefaults(tenantId);
      final stations = await repo.getActiveStations(tenantId);
      expect(stations.length, 5);
    });
  });

  group('getByCode', () {
    test('resolves a seeded station code to its entity', () async {
      await repo.seedDefaults(tenantId);
      final grill = await repo.getByCode(tenantId, 'grill');
      expect(grill, isNotNull);
      expect(grill!.name, 'Grill');
    });

    test('returns null for an unknown code', () async {
      await repo.seedDefaults(tenantId);
      final unknown = await repo.getByCode(tenantId, 'pastry');
      expect(unknown, isNull);
    });
  });

  group('setActive + softDelete', () {
    test('deactivating a station excludes it from active list', () async {
      await repo.seedDefaults(tenantId);
      await repo.setActive('station-bar', false);
      final active = await repo.getActiveStations(tenantId);
      expect(active.any((s) => s.code == 'bar'), isFalse);
    });

    test('softDelete hides the station from active queries', () async {
      await repo.seedDefaults(tenantId);
      await repo.softDelete('station-cold');
      final active = await repo.getActiveStations(tenantId);
      expect(active.any((s) => s.code == 'cold'), isFalse);
    });
  });
}
