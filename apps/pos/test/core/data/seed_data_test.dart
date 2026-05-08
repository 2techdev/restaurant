/// Unit tests for [SeedData].
///
/// Uses an in-memory Drift database so tests are fast and self-contained.
/// Covers: seedIfEmpty idempotency, seedForce replace, clearAll, staff,
/// categories, products, modifier groups, modifier options, modifier-product
/// links, and tax profiles.
///
/// Updated 2026-05-09: schema v22 — seed reality refresh.
/// - 7 staff (added Hans Koch / kitchen)
/// - Avatars switched to Unsplash CDN URLs
/// - 25 products total (added one beverage)
/// - 7 modifier groups (added Getränke Extras + Schärfe)
/// - "Zusätzliche Zutaten" → "Extras", "Getränkegrösse" → "Grösse"
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/core/data/seed_data.dart';
import 'package:gastrocore_pos/core/database/app_database.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

Future<AppDatabase> _seededDb() async {
  final db = _makeDb();
  await SeedData(db).seedIfEmpty();
  return db;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('seedIfEmpty', () {
    test('creates exactly one tenant', () async {
      final db = await _seededDb();
      final tenants = await db.select(db.tenants).get();
      expect(tenants.length, 1);
      expect(tenants.first.name, 'Demo Restaurant Zürich');
      expect(tenants.first.currencyCode, 'CHF');
      await db.close();
    });

    test('is idempotent — calling twice leaves one tenant', () async {
      final db = _makeDb();
      final seed = SeedData(db);
      await seed.seedIfEmpty();
      await seed.seedIfEmpty();
      final tenants = await db.select(db.tenants).get();
      expect(tenants.length, 1);
      await db.close();
    });
  });

  group('staff', () {
    late AppDatabase db;

    setUp(() async => db = await _seededDb());
    tearDown(() => db.close());

    test('inserts 7 users', () async {
      final users = await db.select(db.users).get();
      expect(users.length, 7);
    });

    test('user names are correct', () async {
      final names = (await db.select(db.users).get()).map((u) => u.name).toSet();
      expect(
        names,
        containsAll([
          'Klaus Wagner',
          'Max Müller',
          'Sarah Weber',
          'Luca Bernasconi',
          'Anna Fischer',
          'Thomas Keller',
          'Hans Koch',
        ]),
      );
    });

    test('roles are one of the expected values', () async {
      final roles = (await db.select(db.users).get()).map((u) => u.role).toSet();
      expect(roles, isSubsetOf({'admin', 'manager', 'waiter', 'cashier', 'kitchen'}));
    });

    test('every user has an avatarPath (Unsplash URL)', () async {
      final users = await db.select(db.users).get();
      for (final u in users) {
        expect(u.avatarPath, isNotNull, reason: '${u.name} should have an avatarPath');
        expect(
          u.avatarPath,
          contains('unsplash.com'),
          reason: '${u.name} should have a CDN avatar URL',
        );
      }
    });

    test('PIN hashes are not plain-text PINs', () async {
      final users = await db.select(db.users).get();
      for (final u in users) {
        expect(u.pinHash, isNot(anyOf('1234', '5678', '9012', '3456', '7890')));
        expect(u.pinHash.length, 64); // SHA-256 hex length
      }
    });

    test('hashPin is deterministic and matches expected hash', () {
      // SHA-256('1234') known value
      const expected =
          '03ac674216f3e15c761ee1a5e255f067953623c8b388b4459e13f978d7c846f4';
      expect(SeedData.hashPin('1234'), expected);
    });
  });

  group('categories', () {
    late AppDatabase db;

    setUp(() async => db = await _seededDb());
    tearDown(() => db.close());

    test('creates 5 categories', () async {
      final cats = await db.select(db.categories).get();
      expect(cats.length, 5);
    });

    test('category names are the expected Swiss-German set', () async {
      final names = (await db.select(db.categories).get())
          .map((c) => c.name)
          .toSet();
      expect(
        names,
        containsAll([
          'Vorspeisen',
          'Hauptspeisen',
          'Pizza & Pasta',
          'Desserts',
          'Getränke',
        ]),
      );
    });

    test('all categories are active and not deleted', () async {
      final cats = await db.select(db.categories).get();
      for (final c in cats) {
        expect(c.isActive, isTrue, reason: '${c.name} should be active');
        expect(c.isDeleted, isFalse, reason: '${c.name} should not be deleted');
      }
    });
  });

  group('products', () {
    late AppDatabase db;

    setUp(() async => db = await _seededDb());
    tearDown(() => db.close());

    test('creates 25 products total', () async {
      final products = await db.select(db.products).get();
      // 4 starters + 6 mains + 4 pizza&pasta + 4 desserts + 7 beverages = 25
      expect(products.length, 25);
    });

    test('all products have a positive price', () async {
      final products = await db.select(db.products).get();
      for (final p in products) {
        expect(p.price, greaterThan(0), reason: '${p.name} has non-positive price');
      }
    });

    test('Swiss product names are present', () async {
      final names = (await db.select(db.products).get())
          .map((p) => p.name)
          .toList();
      expect(names, contains('Zürich Geschnetzeltes'));
      expect(names, contains('Wiener Schnitzel'));
      expect(names, contains('Grilliertes Rindsfilet'));
      expect(names, contains('Lachsfilet'));
    });

    test('beverages use bar printer group', () async {
      final beverages = (await db.select(db.products).get())
          .where((p) => p.taxGroup == 'beverage' || p.taxGroup == 'alcohol')
          .toList();
      for (final b in beverages) {
        expect(b.printerGroup, 'bar', reason: '${b.name} should print to bar');
      }
    });

    test('all products have an imagePath', () async {
      final products = await db.select(db.products).get();
      for (final p in products) {
        expect(
          p.imagePath,
          isNotNull,
          reason: '${p.name} should have an imagePath',
        );
      }
    });

    test('Zürich Geschnetzeltes costs 28.50 CHF (2850 cents)', () async {
      final p = (await db.select(db.products).get())
          .firstWhere((x) => x.name == 'Zürich Geschnetzeltes');
      expect(p.price, 2850);
    });

    test('Burger Classic costs 22.00 CHF (2200 cents)', () async {
      final p = (await db.select(db.products).get())
          .firstWhere((x) => x.name == 'Burger Classic');
      expect(p.price, 2200);
    });
  });

  group('modifier groups', () {
    late AppDatabase db;

    setUp(() async => db = await _seededDb());
    tearDown(() => db.close());

    test('creates 7 modifier groups', () async {
      final groups = await db.select(db.modifierGroups).get();
      expect(groups.length, 7);
    });

    test('group names are correct', () async {
      final names = (await db.select(db.modifierGroups).get())
          .map((g) => g.name)
          .toSet();
      expect(
        names,
        containsAll([
          'Extras',
          'Sauce',
          'Garpunkt',
          'Grösse',
          'Beilage',
          'Getränke Extras',
          'Schärfe',
        ]),
      );
    });

    test('Sauce is required, single, min=1 max=1', () async {
      final g = (await db.select(db.modifierGroups).get())
          .firstWhere((x) => x.name == 'Sauce');
      expect(g.isRequired, isTrue);
      expect(g.selectionType, 'single');
      expect(g.minSelections, 1);
      expect(g.maxSelections, 1);
    });

    test('Extras is optional, multiple, max=5', () async {
      final g = (await db.select(db.modifierGroups).get())
          .firstWhere((x) => x.name == 'Extras');
      expect(g.isRequired, isFalse);
      expect(g.selectionType, 'multiple');
      expect(g.maxSelections, 5);
    });

    test('Grösse is required, single, min=1 max=1', () async {
      final g = (await db.select(db.modifierGroups).get())
          .firstWhere((x) => x.name == 'Grösse');
      expect(g.isRequired, isTrue);
      expect(g.selectionType, 'single');
      expect(g.maxSelections, 1);
    });

    test('Beilage is optional, multiple, max=3', () async {
      final g = (await db.select(db.modifierGroups).get())
          .firstWhere((x) => x.name == 'Beilage');
      expect(g.isRequired, isFalse);
      expect(g.selectionType, 'multiple');
      expect(g.maxSelections, 3);
    });

    test('Garpunkt is required, single', () async {
      final g = (await db.select(db.modifierGroups).get())
          .firstWhere((x) => x.name == 'Garpunkt');
      expect(g.isRequired, isTrue);
      expect(g.selectionType, 'single');
    });
  });

  group('modifier options', () {
    late AppDatabase db;

    setUp(() async => db = await _seededDb());
    tearDown(() => db.close());

    test('Extras has 4 options', () async {
      final group = (await db.select(db.modifierGroups).get())
          .firstWhere((g) => g.name == 'Extras');
      final opts = (await db.select(db.modifiers).get())
          .where((m) => m.groupId == group.id)
          .toList();
      expect(opts.length, 4);
    });

    test('Extras contains Avocado at 350 cents', () async {
      final group = (await db.select(db.modifierGroups).get())
          .firstWhere((g) => g.name == 'Extras');
      final avocado = (await db.select(db.modifiers).get())
          .firstWhere((m) => m.groupId == group.id && m.name == 'Avocado');
      expect(avocado.priceDelta, 350);
    });

    test('Sauce has 4 options with Ketchup as default', () async {
      final group = (await db.select(db.modifierGroups).get())
          .firstWhere((g) => g.name == 'Sauce');
      final opts = (await db.select(db.modifiers).get())
          .where((m) => m.groupId == group.id)
          .toList();
      expect(opts.length, 4);
      final defaultOpt = opts.firstWhere((m) => m.isDefault);
      expect(defaultOpt.name, 'Ketchup');
    });

    test('Garpunkt has 3 options with Medium as default', () async {
      final group = (await db.select(db.modifierGroups).get())
          .firstWhere((g) => g.name == 'Garpunkt');
      final opts = (await db.select(db.modifiers).get())
          .where((m) => m.groupId == group.id)
          .toList();
      expect(opts.length, 3);
      final defaultOpt = opts.firstWhere((m) => m.isDefault);
      expect(defaultOpt.name, 'Medium');
    });

    test('Grösse Normal costs +200 cents', () async {
      final group = (await db.select(db.modifierGroups).get())
          .firstWhere((g) => g.name == 'Grösse');
      final normal = (await db.select(db.modifiers).get())
          .firstWhere((m) => m.groupId == group.id && m.name == 'Normal');
      expect(normal.priceDelta, 200);
    });

    test('Beilage has 4 options', () async {
      final group = (await db.select(db.modifierGroups).get())
          .firstWhere((g) => g.name == 'Beilage');
      final opts = (await db.select(db.modifiers).get())
          .where((m) => m.groupId == group.id)
          .toList();
      expect(opts.length, 4);
    });

    test('Pommes frites costs 450 cents', () async {
      final group = (await db.select(db.modifierGroups).get())
          .firstWhere((g) => g.name == 'Beilage');
      final opt = (await db.select(db.modifiers).get())
          .firstWhere((m) => m.groupId == group.id && m.name == 'Pommes frites');
      expect(opt.priceDelta, 450);
    });
  });

  group('product-modifier links', () {
    late AppDatabase db;

    setUp(() async => db = await _seededDb());
    tearDown(() => db.close());

    test('Burger Classic is linked to Garpunkt', () async {
      final burger = (await db.select(db.products).get())
          .firstWhere((p) => p.name == 'Burger Classic');
      final garpunkt = (await db.select(db.modifierGroups).get())
          .firstWhere((g) => g.name == 'Garpunkt');
      final links = await db.select(db.productModifierGroups).get();
      expect(
        links.any((l) => l.productId == burger.id && l.modifierGroupId == garpunkt.id),
        isTrue,
      );
    });

    test('Burger Classic is linked to Sauce', () async {
      final burger = (await db.select(db.products).get())
          .firstWhere((p) => p.name == 'Burger Classic');
      final sauce = (await db.select(db.modifierGroups).get())
          .firstWhere((g) => g.name == 'Sauce');
      final links = await db.select(db.productModifierGroups).get();
      expect(
        links.any((l) => l.productId == burger.id && l.modifierGroupId == sauce.id),
        isTrue,
      );
    });

    test('Burger Classic is linked to Extras', () async {
      final burger = (await db.select(db.products).get())
          .firstWhere((p) => p.name == 'Burger Classic');
      final extras = (await db.select(db.modifierGroups).get())
          .firstWhere((g) => g.name == 'Extras');
      final links = await db.select(db.productModifierGroups).get();
      expect(
        links.any((l) => l.productId == burger.id && l.modifierGroupId == extras.id),
        isTrue,
      );
    });

    test('all beverages are linked to Grösse', () async {
      final groesse = (await db.select(db.modifierGroups).get())
          .firstWhere((g) => g.name == 'Grösse');
      final beverages = (await db.select(db.products).get())
          .where((p) => p.taxGroup == 'beverage' || p.taxGroup == 'alcohol')
          .toList();
      final links = await db.select(db.productModifierGroups).get();
      for (final bev in beverages) {
        expect(
          links.any((l) =>
              l.productId == bev.id && l.modifierGroupId == groesse.id),
          isTrue,
          reason: '${bev.name} should be linked to Grösse',
        );
      }
    });

    test('all pizzas are linked to Extras', () async {
      final extras = (await db.select(db.modifierGroups).get())
          .firstWhere((g) => g.name == 'Extras');
      final pizzas = (await db.select(db.products).get())
          .where((p) => ['Margherita', 'Quattro Formaggi', 'Prosciutto e Rucola']
              .contains(p.name))
          .toList();
      expect(pizzas.length, 3);
      final links = await db.select(db.productModifierGroups).get();
      for (final pizza in pizzas) {
        expect(
          links.any((l) =>
              l.productId == pizza.id && l.modifierGroupId == extras.id),
          isTrue,
          reason: '${pizza.name} should be linked to Extras',
        );
      }
    });
  });

  group('tax profiles', () {
    late AppDatabase db;

    setUp(() async => db = await _seededDb());
    tearDown(() => db.close());

    test('creates tax profiles for CH', () async {
      final profiles = await db.select(db.taxProfiles).get();
      expect(profiles, isNotEmpty);
      expect(profiles.every((p) => p.countryCode == 'CH'), isTrue);
    });

    test('dine-in food is taxed at 8.1%', () async {
      final profile = (await db.select(db.taxProfiles).get()).firstWhere(
        (p) => p.orderType == 'dine_in' && p.productTaxGroup == 'food',
      );
      expect(profile.taxRate, 8.1);
    });

    test('takeaway food is taxed at 2.6%', () async {
      final profile = (await db.select(db.taxProfiles).get()).firstWhere(
        (p) => p.orderType == 'takeaway' && p.productTaxGroup == 'food',
      );
      expect(profile.taxRate, 2.6);
    });

    test('takeaway alcohol is taxed at 8.1%', () async {
      final profile = (await db.select(db.taxProfiles).get()).firstWhere(
        (p) => p.orderType == 'takeaway' && p.productTaxGroup == 'alcohol',
      );
      expect(profile.taxRate, 8.1);
    });
  });

  group('floors and tables', () {
    late AppDatabase db;

    setUp(() async => db = await _seededDb());
    tearDown(() => db.close());

    test('creates 2 floors', () async {
      final floors = await db.select(db.floors).get();
      expect(floors.length, 2);
    });

    test('floor names are Hauptraum and Terrasse', () async {
      final names = (await db.select(db.floors).get()).map((f) => f.name).toSet();
      expect(names, containsAll(['Hauptraum', 'Terrasse']));
    });

    test('creates 15 tables total (10 main + 5 terrasse)', () async {
      final tables = await db.select(db.restaurantTables).get();
      expect(tables.length, 15);
    });
  });

  group('seedForce', () {
    test('replaces existing data and leaves exactly 1 tenant', () async {
      final db = _makeDb();
      final seed = SeedData(db);
      await seed.seedIfEmpty();
      await seed.seedForce();
      final tenants = await db.select(db.tenants).get();
      expect(tenants.length, 1);
      await db.close();
    });

    test('after seedForce products count is still 25', () async {
      final db = _makeDb();
      final seed = SeedData(db);
      await seed.seedIfEmpty();
      await seed.seedForce();
      final products = await db.select(db.products).get();
      expect(products.length, 25);
      await db.close();
    });
  });

  group('clearAll', () {
    test('leaves database empty after clear', () async {
      final db = _makeDb();
      final seed = SeedData(db);
      await seed.seedIfEmpty();
      await seed.clearAll();
      expect((await db.select(db.tenants).get()), isEmpty);
      expect((await db.select(db.users).get()), isEmpty);
      expect((await db.select(db.categories).get()), isEmpty);
      expect((await db.select(db.products).get()), isEmpty);
      await db.close();
    });

    test('seedIfEmpty works again after clearAll', () async {
      final db = _makeDb();
      final seed = SeedData(db);
      await seed.seedIfEmpty();
      await seed.clearAll();
      await seed.seedIfEmpty();
      expect((await db.select(db.tenants).get()).length, 1);
      await db.close();
    });
  });
}

// ---------------------------------------------------------------------------
// Custom matcher
// ---------------------------------------------------------------------------
Matcher isSubsetOf(Set expected) => _IsSubsetOf(expected);

class _IsSubsetOf extends Matcher {
  const _IsSubsetOf(this._expected);
  final Set _expected;

  @override
  bool matches(dynamic item, Map matchState) {
    if (item is! Set) return false;
    return item.every(_expected.contains);
  }

  @override
  Description describe(Description description) =>
      description.add('is a subset of $_expected');
}
