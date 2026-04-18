/// Locks the fixed "Gang 1 / Gang 2 / Gang 3" label policy (2026-04-17).
///
/// Two invariants:
///   1. Seed produces rows named exactly "Gang N".
///   2. Re-running seed on a dev install that still carries the legacy
///      Vorspeise / Hauptgang / Dessert names rewrites them to "Gang N".
library;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/features/gang/data/gang_repository.dart';

const _tenantId = 'tenant-test';

AppDatabase _openInMemory() => AppDatabase(NativeDatabase.memory());

void main() {
  group('GangRepository.seedDefaultGangs — fixed "Gang N" labels', () {
    test('fresh seed creates gangs named exactly "Gang 1..5"', () async {
      final db = _openInMemory();
      addTearDown(db.close);
      final repo = GangRepository(db);

      await repo.seedDefaultGangs(_tenantId);

      // Query raw Drift rows for the `name` column — the domain entity
      // no longer exposes it (labels come from RestaurantSettings).
      final rows = await db.select(db.gangTemplates).get();
      expect(rows.length, 5);
      final byOrder = {for (final g in rows) g.sortOrder: g};
      for (var i = 1; i <= 5; i++) {
        expect(byOrder[i]!.name, 'Gang $i');
      }
      // Entity-level fallback label should mirror sortOrder.
      final entities = await repo.getGangTemplates(_tenantId);
      expect(entities.map((g) => g.fallbackLabel).toSet(),
          {'Gang 1', 'Gang 2', 'Gang 3', 'Gang 4', 'Gang 5'});
    });

    test('re-seed on legacy install rewrites Vorspeise/Hauptgang/Dessert', () async {
      final db = _openInMemory();
      addTearDown(db.close);
      final repo = GangRepository(db);

      // Simulate a pre-2026-04-17 dev install — default rows with the old
      // Swiss-German names.
      final now = DateTime.now();
      for (final entry in const {
        1: ('gang-1', 'Vorspeise'),
        2: ('gang-2', 'Hauptgang'),
        3: ('gang-3', 'Dessert'),
      }.entries) {
        await db.into(db.gangTemplates).insert(GangTemplatesCompanion(
              id: Value(entry.value.$1),
              tenantId: const Value(_tenantId),
              name: Value(entry.value.$2),
              sortOrder: Value(entry.key),
              color: const Value('#90ABFF'),
              isDefault: const Value(true),
              isActive: const Value(true),
              createdAt: Value(now),
              updatedAt: Value(now),
              syncStatus: const Value(0),
              isDeleted: const Value(false),
            ));
      }

      await repo.seedDefaultGangs(_tenantId);

      final rows = await db.select(db.gangTemplates).get();
      final names = rows.map((g) => g.name).toSet();
      expect(names, {'Gang 1', 'Gang 2', 'Gang 3'});
    });

    test('seed preserves a tenant-overridden non-default gang', () async {
      final db = _openInMemory();
      addTearDown(db.close);
      final repo = GangRepository(db);

      // A non-default (isDefault: false) custom gang should NOT be touched —
      // the rewrite path only targets default rows.
      final now = DateTime.now();
      await db.into(db.gangTemplates).insert(GangTemplatesCompanion(
            id: const Value('custom-gang'),
            tenantId: const Value(_tenantId),
            name: const Value('Custom Apéro'),
            sortOrder: const Value(1),
            color: const Value('#FACC15'),
            isDefault: const Value(false),
            isActive: const Value(true),
            createdAt: Value(now),
            updatedAt: Value(now),
            syncStatus: const Value(0),
            isDeleted: const Value(false),
          ));

      await repo.seedDefaultGangs(_tenantId);

      final rows = await db.select(db.gangTemplates).get();
      expect(rows.any((g) => g.name == 'Custom Apéro'), isTrue);
    });
  });
}
