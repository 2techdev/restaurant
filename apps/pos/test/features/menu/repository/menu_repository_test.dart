/// Unit tests for MenuRepositoryImpl.
///
/// Uses an in-memory Drift database so tests are fast and self-contained.
/// Covers: categories CRUD, product CRUD, modifier group CRUD, modifier CRUD,
/// product–modifier-group links, bulk price update, toggle active,
/// reorder categories.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/menu/data/repositories/menu_repository_impl.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/category_entity.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/modifier_entity.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/product_entity.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/product_specification_entity.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _tenantId = 'tenant-test';

CategoryEntity makeCategory({
  String? id,
  String name = 'Test Category',
  int displayOrder = 0,
  bool isActive = true,
}) {
  return CategoryEntity(
    id: id ?? IdGenerator.generateId(),
    tenantId: _tenantId,
    name: name,
    displayOrder: displayOrder,
    color: '#FF9F0A',
    icon: '🍔',
    isActive: isActive,
  );
}

ProductEntity makeProduct({
  String? id,
  required String categoryId,
  String name = 'Test Product',
  int price = 1500,
  String taxGroup = 'food',
  bool isActive = true,
  int displayOrder = 0,
}) {
  return ProductEntity(
    id: id ?? IdGenerator.generateId(),
    tenantId: _tenantId,
    categoryId: categoryId,
    name: name,
    price: price,
    costPrice: 0,
    taxGroup: taxGroup,
    isActive: isActive,
    displayOrder: displayOrder,
    printerGroup: 'kitchen',
  );
}

ModifierGroupEntity makeModifierGroup({
  String? id,
  String name = 'Size',
  ModifierSelectionType selectionType = ModifierSelectionType.single,
  bool isRequired = false,
  int displayOrder = 0,
}) {
  return ModifierGroupEntity(
    id: id ?? IdGenerator.generateId(),
    tenantId: _tenantId,
    name: name,
    selectionType: selectionType,
    minSelections: 0,
    maxSelections: 1,
    isRequired: isRequired,
    displayOrder: displayOrder,
  );
}

ModifierEntity makeModifier({
  String? id,
  required String groupId,
  String name = 'Large',
  int priceDelta = 200,
  bool isDefault = false,
  int displayOrder = 0,
}) {
  return ModifierEntity(
    id: id ?? IdGenerator.generateId(),
    tenantId: _tenantId,
    groupId: groupId,
    name: name,
    priceDelta: priceDelta,
    isDefault: isDefault,
    displayOrder: displayOrder,
  );
}

// ---------------------------------------------------------------------------
// Test suite
// ---------------------------------------------------------------------------

void main() {
  late AppDatabase db;
  late MenuRepositoryImpl repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = MenuRepositoryImpl(db);
  });

  tearDown(() async {
    await db.close();
  });

  // =========================================================================
  // Category CRUD
  // =========================================================================

  group('Category CRUD', () {
    test('createCategory and getAllCategories returns inserted category', () async {
      final cat = makeCategory(name: 'Beverages');
      await repo.createCategory(cat);

      final all = await repo.getAllCategories(_tenantId);
      expect(all, hasLength(1));
      expect(all.first.name, 'Beverages');
      expect(all.first.tenantId, _tenantId);
    });

    test('getAllCategories is ordered by displayOrder', () async {
      await repo.createCategory(makeCategory(name: 'C', displayOrder: 2));
      await repo.createCategory(makeCategory(name: 'A', displayOrder: 0));
      await repo.createCategory(makeCategory(name: 'B', displayOrder: 1));

      final all = await repo.getAllCategories(_tenantId);
      expect(all.map((c) => c.name).toList(), ['A', 'B', 'C']);
    });

    test('updateCategory persists changes', () async {
      final cat = makeCategory(name: 'Old Name');
      await repo.createCategory(cat);

      await repo.updateCategory(cat.copyWith(name: 'New Name', isActive: false));

      final updated = await repo.getCategoryById(cat.id);
      expect(updated?.name, 'New Name');
      expect(updated?.isActive, false);
    });

    test('deleteCategory soft-deletes (excluded from getAllCategories)', () async {
      final cat = makeCategory();
      await repo.createCategory(cat);

      await repo.deleteCategory(cat.id);

      final all = await repo.getAllCategories(_tenantId);
      expect(all, isEmpty);

      // getCategoryById also returns null after soft-delete
      final byId = await repo.getCategoryById(cat.id);
      expect(byId, isNull);
    });

    test('categories from different tenants are not returned', () async {
      final cat1 = makeCategory(name: 'Mine');
      await repo.createCategory(cat1);

      // Another tenant's category
      final cat2 = CategoryEntity(
        id: IdGenerator.generateId(),
        tenantId: 'other-tenant',
        name: 'Theirs',
        displayOrder: 0,
        color: '#000000',
        icon: '🍕',
        isActive: true,
      );
      await repo.createCategory(cat2);

      final all = await repo.getAllCategories(_tenantId);
      expect(all, hasLength(1));
      expect(all.first.name, 'Mine');
    });
  });

  // =========================================================================
  // Reorder categories
  // =========================================================================

  group('reorderCategories', () {
    test('reorderCategories updates displayOrder', () async {
      final catA = makeCategory(name: 'A', displayOrder: 0);
      final catB = makeCategory(name: 'B', displayOrder: 1);
      final catC = makeCategory(name: 'C', displayOrder: 2);
      await repo.createCategory(catA);
      await repo.createCategory(catB);
      await repo.createCategory(catC);

      // Reverse order
      await repo.reorderCategories([catC.id, catB.id, catA.id]);

      final all = await repo.getAllCategories(_tenantId);
      expect(all.map((c) => c.name).toList(), ['C', 'B', 'A']);
    });
  });

  // =========================================================================
  // Product CRUD
  // =========================================================================

  group('Product CRUD', () {
    late CategoryEntity cat;

    setUp(() async {
      cat = makeCategory();
      await repo.createCategory(cat);
    });

    test('createProduct and getAllProducts returns product', () async {
      final product = makeProduct(categoryId: cat.id, name: 'Burger');
      await repo.createProduct(product);

      final all = await repo.getAllProducts(_tenantId);
      expect(all, hasLength(1));
      expect(all.first.name, 'Burger');
    });

    test('getProductsByCategory filters correctly', () async {
      final cat2 = makeCategory(name: 'Drinks');
      await repo.createCategory(cat2);

      await repo.createProduct(makeProduct(categoryId: cat.id, name: 'Food'));
      await repo.createProduct(makeProduct(categoryId: cat2.id, name: 'Cola'));

      final foodItems = await repo.getProductsByCategory(cat.id);
      expect(foodItems, hasLength(1));
      expect(foodItems.first.name, 'Food');

      final drinks = await repo.getProductsByCategory(cat2.id);
      expect(drinks, hasLength(1));
      expect(drinks.first.name, 'Cola');
    });

    test('searchProducts finds by name substring', () async {
      await repo.createProduct(makeProduct(categoryId: cat.id, name: 'Adana Kebap'));
      await repo.createProduct(makeProduct(categoryId: cat.id, name: 'Urfa Kebap'));
      await repo.createProduct(makeProduct(categoryId: cat.id, name: 'Salad'));

      final results = await repo.searchProducts(_tenantId, 'kebap');
      expect(results, hasLength(2));
      expect(results.map((p) => p.name),
          containsAll(['Adana Kebap', 'Urfa Kebap']));
    });

    test('searchProducts is case-insensitive', () async {
      await repo.createProduct(makeProduct(categoryId: cat.id, name: 'Pizza'));

      final results = await repo.searchProducts(_tenantId, 'PIZZA');
      expect(results, hasLength(1));
    });

    test('updateProduct persists changes', () async {
      final product = makeProduct(categoryId: cat.id, name: 'Old', price: 1000);
      await repo.createProduct(product);

      await repo.updateProduct(product.copyWith(name: 'New', price: 2000));

      final updated = await repo.getProductById(product.id);
      expect(updated?.name, 'New');
      expect(updated?.price, 2000);
    });

    test('deleteProduct soft-deletes product', () async {
      final product = makeProduct(categoryId: cat.id);
      await repo.createProduct(product);

      await repo.deleteProduct(product.id);

      final all = await repo.getAllProducts(_tenantId);
      expect(all, isEmpty);
    });

    test('getAllProductsAdmin includes inactive products', () async {
      await repo.createProduct(makeProduct(
          categoryId: cat.id, name: 'Active', isActive: true));
      await repo.createProduct(makeProduct(
          categoryId: cat.id, name: 'Inactive', isActive: false));

      final admin = await repo.getAllProductsAdmin(_tenantId);
      expect(admin, hasLength(2));

      final pos = await repo.getAllProducts(_tenantId);
      // getAllProducts returns both since isActive filter is at query time
      // Both are returned since the query checks isDeleted, not isActive
      expect(pos, hasLength(2));
    });
  });

  // =========================================================================
  // Toggle product active
  // =========================================================================

  group('toggleProductActive', () {
    late CategoryEntity cat;

    setUp(() async {
      cat = makeCategory();
      await repo.createCategory(cat);
    });

    test('toggles active to inactive', () async {
      final product = makeProduct(categoryId: cat.id, isActive: true);
      await repo.createProduct(product);

      await repo.toggleProductActive(product.id, isActive: false);

      final updated = await repo.getProductById(product.id);
      expect(updated?.isActive, false);
    });

    test('toggles inactive to active', () async {
      final product = makeProduct(categoryId: cat.id, isActive: false);
      await repo.createProduct(product);

      await repo.toggleProductActive(product.id, isActive: true);

      final updated = await repo.getProductById(product.id);
      expect(updated?.isActive, true);
    });
  });

  // =========================================================================
  // Bulk price update
  // =========================================================================

  group('bulkUpdatePrices', () {
    late CategoryEntity cat;

    setUp(() async {
      cat = makeCategory();
      await repo.createCategory(cat);
    });

    test('increases all product prices by percentage', () async {
      await repo.createProduct(makeProduct(categoryId: cat.id, name: 'A', price: 1000));
      await repo.createProduct(makeProduct(categoryId: cat.id, name: 'B', price: 2000));

      final count = await repo.bulkUpdatePrices(
        tenantId: _tenantId,
        adjustmentPercent: 10.0, // +10%
      );

      expect(count, 2);

      final all = await repo.getAllProducts(_tenantId);
      final prices = all.map((p) => p.price).toList()..sort();
      expect(prices[0], 1100); // 1000 * 1.10 = 1100
      expect(prices[1], 2200); // 2000 * 1.10 = 2200
    });

    test('decreases prices by percentage', () async {
      await repo.createProduct(makeProduct(categoryId: cat.id, price: 1000));

      await repo.bulkUpdatePrices(
        tenantId: _tenantId,
        adjustmentPercent: -10.0, // -10%
      );

      final all = await repo.getAllProducts(_tenantId);
      expect(all.first.price, 900); // 1000 * 0.90 = 900
    });

    test('scopes to categoryId when provided', () async {
      final cat2 = makeCategory(name: 'Other');
      await repo.createCategory(cat2);

      await repo.createProduct(
          makeProduct(categoryId: cat.id, name: 'InScope', price: 1000));
      await repo.createProduct(
          makeProduct(categoryId: cat2.id, name: 'OutOfScope', price: 1000));

      await repo.bulkUpdatePrices(
        tenantId: _tenantId,
        categoryId: cat.id,
        adjustmentPercent: 20.0,
      );

      final all = await repo.getAllProducts(_tenantId);
      final inScope = all.firstWhere((p) => p.name == 'InScope');
      final outScope = all.firstWhere((p) => p.name == 'OutOfScope');

      expect(inScope.price, 1200); // updated
      expect(outScope.price, 1000); // unchanged
    });

    test('returns 0 when no products match', () async {
      final count = await repo.bulkUpdatePrices(
        tenantId: _tenantId,
        adjustmentPercent: 10.0,
      );
      expect(count, 0);
    });
  });

  // =========================================================================
  // Modifier group CRUD
  // =========================================================================

  group('Modifier Group CRUD', () {
    test('createModifierGroup and getAllModifierGroups', () async {
      final group = makeModifierGroup(name: 'Size');
      await repo.createModifierGroup(group);

      final all = await repo.getAllModifierGroups(_tenantId);
      expect(all, hasLength(1));
      expect(all.first.name, 'Size');
      expect(all.first.selectionType, ModifierSelectionType.single);
    });

    test('getAllModifierGroups includes modifiers', () async {
      final group = makeModifierGroup(name: 'Size');
      await repo.createModifierGroup(group);

      await repo.createModifier(makeModifier(groupId: group.id, name: 'Small'));
      await repo.createModifier(makeModifier(groupId: group.id, name: 'Large'));

      final all = await repo.getAllModifierGroups(_tenantId);
      expect(all.first.modifiers, hasLength(2));
    });

    test('updateModifierGroup persists changes', () async {
      final group = makeModifierGroup(name: 'Original');
      await repo.createModifierGroup(group);

      await repo.updateModifierGroup(group.copyWith(
        name: 'Updated',
        selectionType: ModifierSelectionType.multiple,
        isRequired: true,
      ));

      final all = await repo.getAllModifierGroups(_tenantId);
      expect(all.first.name, 'Updated');
      expect(all.first.selectionType, ModifierSelectionType.multiple);
      expect(all.first.isRequired, true);
    });

    test('deleteModifierGroup soft-deletes group and its modifiers', () async {
      final group = makeModifierGroup();
      await repo.createModifierGroup(group);
      await repo.createModifier(makeModifier(groupId: group.id, name: 'Option 1'));
      await repo.createModifier(makeModifier(groupId: group.id, name: 'Option 2'));

      await repo.deleteModifierGroup(group.id);

      final all = await repo.getAllModifierGroups(_tenantId);
      expect(all, isEmpty);

      final modifiers = await repo.getModifiersForGroup(group.id);
      expect(modifiers, isEmpty);
    });
  });

  // =========================================================================
  // Modifier CRUD
  // =========================================================================

  group('Modifier CRUD', () {
    late ModifierGroupEntity group;

    setUp(() async {
      group = makeModifierGroup(name: 'Extras');
      await repo.createModifierGroup(group);
    });

    test('createModifier and getModifiersForGroup', () async {
      final mod = makeModifier(groupId: group.id, name: 'Extra Cheese', priceDelta: 150);
      await repo.createModifier(mod);

      final modifiers = await repo.getModifiersForGroup(group.id);
      expect(modifiers, hasLength(1));
      expect(modifiers.first.name, 'Extra Cheese');
      expect(modifiers.first.priceDelta, 150);
    });

    test('modifiers ordered by displayOrder', () async {
      await repo.createModifier(makeModifier(groupId: group.id, name: 'Z', displayOrder: 2));
      await repo.createModifier(makeModifier(groupId: group.id, name: 'A', displayOrder: 0));
      await repo.createModifier(makeModifier(groupId: group.id, name: 'M', displayOrder: 1));

      final modifiers = await repo.getModifiersForGroup(group.id);
      expect(modifiers.map((m) => m.name).toList(), ['A', 'M', 'Z']);
    });

    test('updateModifier persists changes', () async {
      final mod = makeModifier(groupId: group.id, name: 'Old', priceDelta: 100);
      await repo.createModifier(mod);

      await repo.updateModifier(mod.copyWith(name: 'New', priceDelta: -50, isDefault: true));

      final modifiers = await repo.getModifiersForGroup(group.id);
      expect(modifiers.first.name, 'New');
      expect(modifiers.first.priceDelta, -50);
      expect(modifiers.first.isDefault, true);
    });

    test('deleteModifier soft-deletes modifier', () async {
      final mod = makeModifier(groupId: group.id);
      await repo.createModifier(mod);

      await repo.deleteModifier(mod.id);

      final modifiers = await repo.getModifiersForGroup(group.id);
      expect(modifiers, isEmpty);
    });

    test('negative priceDelta represents a discount', () async {
      final mod = makeModifier(groupId: group.id, name: 'No Extras', priceDelta: -200);
      await repo.createModifier(mod);

      final modifiers = await repo.getModifiersForGroup(group.id);
      expect(modifiers.first.priceDelta, -200);
    });
  });

  // =========================================================================
  // Product ↔ ModifierGroup links
  // =========================================================================

  group('Product–ModifierGroup links', () {
    late CategoryEntity cat;
    late ProductEntity product;
    late ModifierGroupEntity group;

    setUp(() async {
      cat = makeCategory();
      await repo.createCategory(cat);

      product = makeProduct(categoryId: cat.id, name: 'Burger');
      await repo.createProduct(product);

      group = makeModifierGroup(name: 'Size');
      await repo.createModifierGroup(group);
    });

    test('linkModifierGroupToProduct makes group visible on product', () async {
      await repo.linkModifierGroupToProduct(product.id, group.id, 0);

      final linked = await repo.getModifierGroupsForProduct(product.id);
      expect(linked, hasLength(1));
      expect(linked.first.id, group.id);
    });

    test('linking same group twice is idempotent', () async {
      await repo.linkModifierGroupToProduct(product.id, group.id, 0);
      await repo.linkModifierGroupToProduct(product.id, group.id, 1); // update order

      final linked = await repo.getModifierGroupsForProduct(product.id);
      expect(linked, hasLength(1));
    });

    test('unlinkModifierGroupFromProduct removes the link', () async {
      await repo.linkModifierGroupToProduct(product.id, group.id, 0);
      await repo.unlinkModifierGroupFromProduct(product.id, group.id);

      final linked = await repo.getModifierGroupsForProduct(product.id);
      expect(linked, isEmpty);
    });

    test('getModifierGroupsForProduct includes modifiers', () async {
      await repo.createModifier(makeModifier(groupId: group.id, name: 'Small'));
      await repo.createModifier(makeModifier(groupId: group.id, name: 'Large'));
      await repo.linkModifierGroupToProduct(product.id, group.id, 0);

      final linked = await repo.getModifierGroupsForProduct(product.id);
      expect(linked.first.modifiers, hasLength(2));
    });

    test('product with no linked groups returns empty list', () async {
      final linked = await repo.getModifierGroupsForProduct(product.id);
      expect(linked, isEmpty);
    });

    test('multiple groups can be linked to one product', () async {
      final group2 = makeModifierGroup(name: 'Extras');
      await repo.createModifierGroup(group2);

      await repo.linkModifierGroupToProduct(product.id, group.id, 0);
      await repo.linkModifierGroupToProduct(product.id, group2.id, 1);

      final linked = await repo.getModifierGroupsForProduct(product.id);
      expect(linked, hasLength(2));
    });
  });

  // =========================================================================
  // Product Specifications (Variants)
  // =========================================================================

  group('Product Specifications', () {
    late CategoryEntity cat;
    late ProductEntity product;

    setUp(() async {
      cat = makeCategory();
      await repo.createCategory(cat);
      product = makeProduct(categoryId: cat.id, name: 'Burger', price: 1500);
      await repo.createProduct(product);
    });

    test('getProductSpecifications returns empty list when none saved', () async {
      final specs = await repo.getProductSpecifications(product.id);
      expect(specs, isEmpty);
    });

    test('saveProductSpecifications persists single default spec', () async {
      final specs = [
        ProductSpecificationEntity(
          id: IdGenerator.generateId(),
          tenantId: _tenantId,
          productId: product.id,
          name: 'Default',
          price: 1500,
          isDefault: true,
          displayOrder: 0,
        ),
      ];
      await repo.saveProductSpecifications(product.id, _tenantId, specs);

      final loaded = await repo.getProductSpecifications(product.id);
      expect(loaded, hasLength(1));
      expect(loaded.first.name, 'Default');
      expect(loaded.first.price, 1500);
      expect(loaded.first.isDefault, true);
    });

    test('saveProductSpecifications persists size variants', () async {
      final specs = [
        ProductSpecificationEntity(
          id: IdGenerator.generateId(),
          tenantId: _tenantId,
          productId: product.id,
          name: 'Small',
          price: 1000,
          isDefault: true,
          displayOrder: 0,
        ),
        ProductSpecificationEntity(
          id: IdGenerator.generateId(),
          tenantId: _tenantId,
          productId: product.id,
          name: 'Medium',
          price: 1300,
          isDefault: false,
          displayOrder: 1,
        ),
        ProductSpecificationEntity(
          id: IdGenerator.generateId(),
          tenantId: _tenantId,
          productId: product.id,
          name: 'Large',
          price: 1600,
          isDefault: false,
          displayOrder: 2,
        ),
      ];
      await repo.saveProductSpecifications(product.id, _tenantId, specs);

      final loaded = await repo.getProductSpecifications(product.id);
      expect(loaded, hasLength(3));
      expect(loaded.map((s) => s.name).toList(), ['Small', 'Medium', 'Large']);
      expect(loaded.map((s) => s.price).toList(), [1000, 1300, 1600]);
    });

    test('saveProductSpecifications replaces existing specs', () async {
      // Save initial specs
      await repo.saveProductSpecifications(product.id, _tenantId, [
        ProductSpecificationEntity(
          id: IdGenerator.generateId(),
          tenantId: _tenantId,
          productId: product.id,
          name: 'Old',
          price: 999,
          isDefault: true,
          displayOrder: 0,
        ),
      ]);

      // Replace with new specs
      await repo.saveProductSpecifications(product.id, _tenantId, [
        ProductSpecificationEntity(
          id: IdGenerator.generateId(),
          tenantId: _tenantId,
          productId: product.id,
          name: 'New',
          price: 1234,
          isDefault: true,
          displayOrder: 0,
        ),
      ]);

      final loaded = await repo.getProductSpecifications(product.id);
      expect(loaded, hasLength(1));
      expect(loaded.first.name, 'New');
      expect(loaded.first.price, 1234);
    });

    test('saveProductSpecifications assigns display order by list position', () async {
      await repo.saveProductSpecifications(product.id, _tenantId, [
        ProductSpecificationEntity(
          id: IdGenerator.generateId(),
          tenantId: _tenantId,
          productId: product.id,
          name: 'First',
          price: 500,
          isDefault: true,
          displayOrder: 99, // will be overridden by position
        ),
        ProductSpecificationEntity(
          id: IdGenerator.generateId(),
          tenantId: _tenantId,
          productId: product.id,
          name: 'Second',
          price: 700,
          isDefault: false,
          displayOrder: 99,
        ),
      ]);

      final loaded = await repo.getProductSpecifications(product.id);
      expect(loaded[0].displayOrder, 0);
      expect(loaded[1].displayOrder, 1);
    });

    test('specs are scoped to productId (different products have separate specs)', () async {
      final product2 = makeProduct(categoryId: cat.id, name: 'Pizza');
      await repo.createProduct(product2);

      await repo.saveProductSpecifications(product.id, _tenantId, [
        ProductSpecificationEntity(
          id: IdGenerator.generateId(),
          tenantId: _tenantId,
          productId: product.id,
          name: 'Burger Size',
          price: 1500,
          isDefault: true,
          displayOrder: 0,
        ),
      ]);

      // product2 should still have no specs
      final specs2 = await repo.getProductSpecifications(product2.id);
      expect(specs2, isEmpty);

      // product still has its spec
      final specs1 = await repo.getProductSpecifications(product.id);
      expect(specs1, hasLength(1));
    });
  });

  // =========================================================================
  // Swiss MWST tax group values
  // =========================================================================

  group('Swiss MWST tax groups', () {
    late CategoryEntity cat;

    setUp(() async {
      cat = makeCategory();
      await repo.createCategory(cat);
    });

    test('food tax group stores and retrieves correctly', () async {
      final p = makeProduct(categoryId: cat.id, taxGroup: 'food');
      await repo.createProduct(p);

      final all = await repo.getAllProducts(_tenantId);
      expect(all.first.taxGroup, 'food');
    });

    test('alcohol tax group stores correctly', () async {
      final p = makeProduct(categoryId: cat.id, taxGroup: 'alcohol');
      await repo.createProduct(p);

      final all = await repo.getAllProducts(_tenantId);
      expect(all.first.taxGroup, 'alcohol');
    });

    test('beverage tax group stores correctly', () async {
      final p = makeProduct(categoryId: cat.id, taxGroup: 'beverage');
      await repo.createProduct(p);

      final all = await repo.getAllProducts(_tenantId);
      expect(all.first.taxGroup, 'beverage');
    });

    test('accommodation tax group (3.8%) stores correctly', () async {
      final p = makeProduct(categoryId: cat.id, taxGroup: 'accommodation');
      await repo.createProduct(p);

      final all = await repo.getAllProducts(_tenantId);
      expect(all.first.taxGroup, 'accommodation');
    });

    test('all Swiss MWST groups round-trip correctly', () async {
      const groups = ['food', 'beverage', 'alcohol', 'accommodation', 'custom'];
      for (final group in groups) {
        final p = makeProduct(
          id: IdGenerator.generateId(),
          categoryId: cat.id,
          taxGroup: group,
        );
        await repo.createProduct(p);
      }

      final all = await repo.getAllProducts(_tenantId);
      final storedGroups = all.map((p) => p.taxGroup).toSet();
      for (final group in groups) {
        expect(storedGroups, contains(group));
      }
    });
  });
}
