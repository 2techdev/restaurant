/// Drift-backed implementation of the menu repository.
///
/// Handles CRUD for categories, products, modifier groups, and modifiers.
/// Products can be loaded with their full modifier tree via joins against
/// the [ProductModifierGroups], [ModifierGroups], and [Modifiers] tables.
library;

import 'package:drift/drift.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/category_entity.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/combo_item_entity.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/modifier_entity.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/product_entity.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/product_specification_entity.dart';

class MenuRepositoryImpl {
  final AppDatabase _db;

  MenuRepositoryImpl(this._db);

  // =========================================================================
  // Categories
  // =========================================================================

  /// Return all active categories for [tenantId], ordered by [displayOrder].
  Future<List<CategoryEntity>> getAllCategories(String tenantId) async {
    final query = _db.select(_db.categories)
      ..where(
        (c) => c.tenantId.equals(tenantId) & c.isDeleted.equals(false),
      )
      ..orderBy([(c) => OrderingTerm.asc(c.displayOrder)]);
    final rows = await query.get();
    return rows.map(_categoryToEntity).toList();
  }

  /// Fetch a single category by [id], or `null` if not found / deleted.
  Future<CategoryEntity?> getCategoryById(String id) async {
    final query = _db.select(_db.categories)
      ..where((c) => c.id.equals(id) & c.isDeleted.equals(false));
    final row = await query.getSingleOrNull();
    return row == null ? null : _categoryToEntity(row);
  }

  /// Insert a new category.
  Future<void> createCategory(CategoryEntity entity) async {
    await _db.into(_db.categories).insert(_categoryToCompanion(entity));
  }

  /// Update an existing category.
  Future<void> updateCategory(CategoryEntity entity) async {
    final companion = CategoriesCompanion(
      name: Value(entity.name),
      displayOrder: Value(entity.displayOrder),
      color: Value(entity.color),
      icon: Value(entity.icon),
      parentId: Value(entity.parentId),
      isActive: Value(entity.isActive),
      updatedAt: Value(DateTime.now()),
    );
    await (_db.update(_db.categories)..where((c) => c.id.equals(entity.id)))
        .write(companion);
  }

  /// Soft-delete a category.
  Future<void> deleteCategory(String id) async {
    await (_db.update(_db.categories)..where((c) => c.id.equals(id))).write(
      CategoriesCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Update [displayOrder] for a list of category IDs.
  ///
  /// The position in [orderedIds] determines the new displayOrder value.
  Future<void> reorderCategories(List<String> orderedIds) async {
    for (var i = 0; i < orderedIds.length; i++) {
      await (_db.update(_db.categories)
            ..where((c) => c.id.equals(orderedIds[i])))
          .write(
        CategoriesCompanion(
          displayOrder: Value(i),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
  }

  // =========================================================================
  // Products
  // =========================================================================

  /// Return all active products for [tenantId], ordered by [displayOrder].
  Future<List<ProductEntity>> getAllProducts(String tenantId) async {
    final query = _db.select(_db.products)
      ..where(
        (p) => p.tenantId.equals(tenantId) & p.isDeleted.equals(false),
      )
      ..orderBy([(p) => OrderingTerm.asc(p.displayOrder)]);
    final rows = await query.get();
    return rows.map(_productToEntity).toList();
  }

  /// Return all products (active and inactive) for admin views.
  Future<List<ProductEntity>> getAllProductsAdmin(String tenantId) async {
    final query = _db.select(_db.products)
      ..where(
        (p) => p.tenantId.equals(tenantId) & p.isDeleted.equals(false),
      )
      ..orderBy([
        (p) => OrderingTerm.asc(p.categoryId),
        (p) => OrderingTerm.asc(p.displayOrder),
      ]);
    final rows = await query.get();
    return rows.map(_productToEntity).toList();
  }

  /// Return all active products belonging to [categoryId].
  Future<List<ProductEntity>> getProductsByCategory(String categoryId) async {
    final query = _db.select(_db.products)
      ..where(
        (p) =>
            p.categoryId.equals(categoryId) & p.isDeleted.equals(false),
      )
      ..orderBy([(p) => OrderingTerm.asc(p.displayOrder)]);
    final rows = await query.get();
    return rows.map(_productToEntity).toList();
  }

  /// Return products (including inactive) belonging to [categoryId] for admin.
  Future<List<ProductEntity>> getProductsByCategoryAdmin(
      String categoryId) async {
    final query = _db.select(_db.products)
      ..where(
        (p) =>
            p.categoryId.equals(categoryId) & p.isDeleted.equals(false),
      )
      ..orderBy([(p) => OrderingTerm.asc(p.displayOrder)]);
    final rows = await query.get();
    return rows.map(_productToEntity).toList();
  }

  /// Fetch a product by [id] with its full modifier tree loaded.
  Future<ProductEntity?> getProductById(String id) async {
    final query = _db.select(_db.products)
      ..where((p) => p.id.equals(id) & p.isDeleted.equals(false));
    final row = await query.getSingleOrNull();
    if (row == null) return null;

    final modifierGroups = await getModifierGroupsForProduct(row.id);
    return _productToEntity(row, modifierGroups: modifierGroups);
  }

  /// Full-text search on product name for the given [tenantId].
  Future<List<ProductEntity>> searchProducts(
    String tenantId,
    String queryText,
  ) async {
    final pattern = '%${queryText.toLowerCase()}%';
    final query = _db.select(_db.products)
      ..where(
        (p) =>
            p.tenantId.equals(tenantId) &
            p.isDeleted.equals(false) &
            p.name.lower().like(pattern),
      )
      ..orderBy([(p) => OrderingTerm.asc(p.displayOrder)]);
    final rows = await query.get();
    return rows.map(_productToEntity).toList();
  }

  /// Insert a new product.
  Future<void> createProduct(ProductEntity entity) async {
    await _db.into(_db.products).insert(_productToCompanion(entity));
  }

  /// Update an existing product.
  Future<void> updateProduct(ProductEntity entity) async {
    final companion = ProductsCompanion(
      categoryId: Value(entity.categoryId),
      name: Value(entity.name),
      description: Value(entity.description),
      price: Value(entity.price),
      costPrice: Value(entity.costPrice),
      taxGroup: Value(entity.taxGroup),
      imagePath: Value(entity.imagePath),
      barcode: Value(entity.barcode),
      isActive: Value(entity.isActive),
      isAvailable: Value(entity.isAvailable),
      displayOrder: Value(entity.displayOrder),
      prepTimeMinutes: Value(entity.prepTimeMinutes),
      printerGroup: Value(entity.printerGroup),
      updatedAt: Value(DateTime.now()),
    );
    await (_db.update(_db.products)..where((p) => p.id.equals(entity.id)))
        .write(companion);
  }

  /// Soft-delete a product.
  Future<void> deleteProduct(String id) async {
    await (_db.update(_db.products)..where((p) => p.id.equals(id))).write(
      ProductsCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Toggle product active status.
  Future<void> toggleProductActive(
    String productId, {
    required bool isActive,
  }) async {
    await (_db.update(_db.products)
          ..where((p) => p.id.equals(productId)))
        .write(
      ProductsCompanion(
        isActive: Value(isActive),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Flip the "sold out / 86'd" flag on a product. Lightweight companion
  /// to [toggleProductActive]: only touches [isAvailable], does not
  /// re-stamp any other field, and is cheap enough to wire to a long-
  /// press gesture on the POS product tile.
  Future<void> setProductAvailable(
    String productId, {
    required bool isAvailable,
  }) async {
    await (_db.update(_db.products)
          ..where((p) => p.id.equals(productId)))
        .write(
      ProductsCompanion(
        isAvailable: Value(isAvailable),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Apply a percentage adjustment to product prices.
  ///
  /// [adjustmentPercent] of 10.0 = +10%, -5.0 = -5%.
  /// When [categoryId] is provided, only affects products in that category.
  /// Returns the number of products updated.
  Future<int> bulkUpdatePrices({
    required String tenantId,
    String? categoryId,
    required double adjustmentPercent,
  }) async {
    final query = _db.select(_db.products)
      ..where((p) {
        var cond = p.tenantId.equals(tenantId) & p.isDeleted.equals(false);
        if (categoryId != null) {
          cond = cond & p.categoryId.equals(categoryId);
        }
        return cond;
      });
    final rows = await query.get();

    final factor = 1.0 + adjustmentPercent / 100.0;
    for (final row in rows) {
      final newPrice = (row.price * factor).round().clamp(0, 9999999);
      await (_db.update(_db.products)..where((p) => p.id.equals(row.id)))
          .write(
        ProductsCompanion(
          price: Value(newPrice),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
    return rows.length;
  }

  // =========================================================================
  // Modifier groups
  // =========================================================================

  /// Return all modifier groups for [tenantId], including their modifiers.
  Future<List<ModifierGroupEntity>> getAllModifierGroups(
      String tenantId) async {
    final query = _db.select(_db.modifierGroups)
      ..where(
        (g) => g.tenantId.equals(tenantId) & g.isDeleted.equals(false),
      )
      ..orderBy([(g) => OrderingTerm.asc(g.displayOrder)]);
    final groupRows = await query.get();

    if (groupRows.isEmpty) return const [];

    final groupIds = groupRows.map((r) => r.id).toList();
    final modQuery = _db.select(_db.modifiers)
      ..where(
        (m) => m.groupId.isIn(groupIds) & m.isDeleted.equals(false),
      )
      ..orderBy([(m) => OrderingTerm.asc(m.displayOrder)]);
    final modRows = await modQuery.get();

    final modsByGroup = <String, List<ModifierEntity>>{};
    for (final m in modRows) {
      modsByGroup.putIfAbsent(m.groupId, () => []).add(_modifierToEntity(m));
    }

    return groupRows
        .map((r) => _modifierGroupToEntity(r, modsByGroup[r.id] ?? const []))
        .toList();
  }

  /// Insert a new modifier group.
  Future<void> createModifierGroup(ModifierGroupEntity entity) async {
    await _db
        .into(_db.modifierGroups)
        .insert(_modifierGroupToCompanion(entity));
  }

  /// Update an existing modifier group.
  Future<void> updateModifierGroup(ModifierGroupEntity entity) async {
    final companion = ModifierGroupsCompanion(
      name: Value(entity.name),
      selectionType: Value(
        entity.selectionType == ModifierSelectionType.multiple
            ? 'multiple'
            : 'single',
      ),
      minSelections: Value(entity.minSelections),
      maxSelections: Value(entity.maxSelections),
      isRequired: Value(entity.isRequired),
      askQuantity: Value(entity.askQuantity),
      freeTagging: Value(entity.freeTagging),
      columnCount: Value(entity.columnCount),
      prefix: Value(entity.prefix),
      displayOrder: Value(entity.displayOrder),
      updatedAt: Value(DateTime.now()),
    );
    await (_db.update(_db.modifierGroups)
          ..where((g) => g.id.equals(entity.id)))
        .write(companion);
  }

  /// Soft-delete a modifier group and all its modifiers.
  Future<void> deleteModifierGroup(String id) async {
    await (_db.update(_db.modifiers)..where((m) => m.groupId.equals(id)))
        .write(
      ModifiersCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await (_db.update(_db.modifierGroups)..where((g) => g.id.equals(id)))
        .write(
      ModifierGroupsCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  // =========================================================================
  // Modifiers
  // =========================================================================

  /// Return all active modifiers for a group, ordered by displayOrder.
  Future<List<ModifierEntity>> getModifiersForGroup(String groupId) async {
    final query = _db.select(_db.modifiers)
      ..where(
        (m) => m.groupId.equals(groupId) & m.isDeleted.equals(false),
      )
      ..orderBy([(m) => OrderingTerm.asc(m.displayOrder)]);
    final rows = await query.get();
    return rows.map(_modifierToEntity).toList();
  }

  /// Insert a new modifier.
  Future<void> createModifier(ModifierEntity entity) async {
    await _db.into(_db.modifiers).insert(_modifierToCompanion(entity));
  }

  /// Update an existing modifier.
  Future<void> updateModifier(ModifierEntity entity) async {
    final companion = ModifiersCompanion(
      name: Value(entity.name),
      priceDelta: Value(entity.priceDelta),
      isDefault: Value(entity.isDefault),
      displayOrder: Value(entity.displayOrder),
      updatedAt: Value(DateTime.now()),
    );
    await (_db.update(_db.modifiers)..where((m) => m.id.equals(entity.id)))
        .write(companion);
  }

  /// Soft-delete a modifier.
  Future<void> deleteModifier(String id) async {
    await (_db.update(_db.modifiers)..where((m) => m.id.equals(id))).write(
      ModifiersCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  // =========================================================================
  // Product Specifications (Variants)
  // =========================================================================

  /// Return all specs for [productId], ordered by [displayOrder].
  Future<List<ProductSpecificationEntity>> getProductSpecifications(
    String productId,
  ) async {
    final query = _db.select(_db.productSpecifications)
      ..where((s) => s.productId.equals(productId))
      ..orderBy([(s) => OrderingTerm.asc(s.displayOrder)]);
    final rows = await query.get();
    return rows.map(_specToEntity).toList();
  }

  /// Replace all specs for [productId] with [specs] in a single transaction.
  ///
  /// The position in [specs] determines the stored [displayOrder].
  /// At least one spec with [isDefault] = true should be present.
  Future<void> saveProductSpecifications(
    String productId,
    String tenantId,
    List<ProductSpecificationEntity> specs,
  ) async {
    await _db.transaction(() async {
      await (_db.delete(_db.productSpecifications)
            ..where((s) => s.productId.equals(productId)))
          .go();

      for (var i = 0; i < specs.length; i++) {
        final spec = specs[i];
        await _db.into(_db.productSpecifications).insert(
              ProductSpecificationsCompanion(
                id: Value(spec.id),
                tenantId: Value(tenantId),
                productId: Value(productId),
                name: Value(spec.name),
                price: Value(spec.price),
                isDefault: Value(spec.isDefault),
                displayOrder: Value(i),
                createdAt: Value(DateTime.now()),
                updatedAt: Value(DateTime.now()),
              ),
            );
      }
    });
  }

  // =========================================================================
  // Product ↔ ModifierGroup links
  // =========================================================================

  /// Load all modifier groups (with their modifiers) linked to [productId]
  /// via the [ProductModifierGroups] junction table.
  Future<List<ModifierGroupEntity>> getModifierGroupsForProduct(
    String productId,
  ) async {
    final junctionQuery = _db.select(_db.productModifierGroups)
      ..where((j) => j.productId.equals(productId))
      ..orderBy([(j) => OrderingTerm.asc(j.displayOrder)]);
    final junctions = await junctionQuery.get();

    if (junctions.isEmpty) return const [];

    final groupIds = junctions.map((j) => j.modifierGroupId).toList();

    final groupQuery = _db.select(_db.modifierGroups)
      ..where(
        (g) => g.id.isIn(groupIds) & g.isDeleted.equals(false),
      );
    final groupRows = await groupQuery.get();

    final modQuery = _db.select(_db.modifiers)
      ..where(
        (m) => m.groupId.isIn(groupIds) & m.isDeleted.equals(false),
      )
      ..orderBy([(m) => OrderingTerm.asc(m.displayOrder)]);
    final modRows = await modQuery.get();

    final modsByGroup = <String, List<ModifierEntity>>{};
    for (final m in modRows) {
      modsByGroup.putIfAbsent(m.groupId, () => []).add(_modifierToEntity(m));
    }

    final result = <ModifierGroupEntity>[];
    for (final junction in junctions) {
      final groupRow =
          groupRows.where((g) => g.id == junction.modifierGroupId);
      if (groupRow.isEmpty) continue;
      final g = groupRow.first;
      result.add(_modifierGroupToEntity(g, modsByGroup[g.id] ?? const []));
    }

    return result;
  }

  /// Link a modifier group to a product via the junction table.
  ///
  /// If the link already exists, updates the [displayOrder].
  Future<void> linkModifierGroupToProduct(
    String productId,
    String groupId,
    int displayOrder,
  ) async {
    final existing = await (_db.select(_db.productModifierGroups)
          ..where(
            (j) =>
                j.productId.equals(productId) &
                j.modifierGroupId.equals(groupId),
          ))
        .getSingleOrNull();

    if (existing != null) {
      await (_db.update(_db.productModifierGroups)
            ..where((j) => j.id.equals(existing.id)))
          .write(
        ProductModifierGroupsCompanion(
          displayOrder: Value(displayOrder),
        ),
      );
    } else {
      await _db.into(_db.productModifierGroups).insert(
            ProductModifierGroupsCompanion(
              id: Value(IdGenerator.generateId()),
              productId: Value(productId),
              modifierGroupId: Value(groupId),
              displayOrder: Value(displayOrder),
            ),
          );
    }
  }

  /// Remove the link between a product and a modifier group.
  Future<void> unlinkModifierGroupFromProduct(
    String productId,
    String groupId,
  ) async {
    await (_db.delete(_db.productModifierGroups)
          ..where(
            (j) =>
                j.productId.equals(productId) &
                j.modifierGroupId.equals(groupId),
          ))
        .go();
  }

  // =========================================================================
  // Mappers – Category
  // =========================================================================

  CategoryEntity _categoryToEntity(Category row) {
    return CategoryEntity(
      id: row.id,
      tenantId: row.tenantId,
      name: row.name,
      displayOrder: row.displayOrder,
      color: row.color ?? '#FF9F0A',
      icon: row.icon ?? 'restaurant',
      parentId: row.parentId,
      isActive: row.isActive,
      defaultGangId: row.defaultGangId,
    );
  }

  CategoriesCompanion _categoryToCompanion(CategoryEntity entity) {
    return CategoriesCompanion(
      id: Value(entity.id),
      tenantId: Value(entity.tenantId),
      name: Value(entity.name),
      displayOrder: Value(entity.displayOrder),
      color: Value(entity.color),
      icon: Value(entity.icon),
      parentId: Value(entity.parentId),
      defaultGangId: Value(entity.defaultGangId),
      isActive: Value(entity.isActive),
      createdAt: Value(DateTime.now()),
      updatedAt: Value(DateTime.now()),
      isDeleted: const Value(false),
      syncStatus: const Value(0),
    );
  }

  // =========================================================================
  // Mappers – Product
  // =========================================================================

  ProductEntity _productToEntity(
    Product row, {
    List<ModifierGroupEntity> modifierGroups = const [],
  }) {
    return ProductEntity(
      id: row.id,
      tenantId: row.tenantId,
      categoryId: row.categoryId,
      name: row.name,
      description: row.description,
      price: row.price,
      costPrice: row.costPrice,
      taxGroup: row.taxGroup,
      imagePath: row.imagePath,
      barcode: row.barcode,
      isActive: row.isActive,
      isAvailable: row.isAvailable,
      displayOrder: row.displayOrder,
      prepTimeMinutes: row.prepTimeMinutes,
      printerGroup: row.printerGroup,
      modifierGroups: modifierGroups,
      defaultGangId: row.defaultGangId,
      isCombo: row.isCombo,
      comboDiscountCents: row.comboDiscountCents,
    );
  }

  ProductsCompanion _productToCompanion(ProductEntity entity) {
    return ProductsCompanion(
      id: Value(entity.id),
      tenantId: Value(entity.tenantId),
      categoryId: Value(entity.categoryId),
      name: Value(entity.name),
      description: Value(entity.description),
      price: Value(entity.price),
      costPrice: Value(entity.costPrice),
      taxGroup: Value(entity.taxGroup),
      imagePath: Value(entity.imagePath),
      barcode: Value(entity.barcode),
      isActive: Value(entity.isActive),
      isAvailable: Value(entity.isAvailable),
      displayOrder: Value(entity.displayOrder),
      prepTimeMinutes: Value(entity.prepTimeMinutes),
      printerGroup: Value(entity.printerGroup),
      defaultGangId: Value(entity.defaultGangId),
      isCombo: Value(entity.isCombo),
      comboDiscountCents: Value(entity.comboDiscountCents),
      createdAt: Value(DateTime.now()),
      updatedAt: Value(DateTime.now()),
      isDeleted: const Value(false),
      syncStatus: const Value(0),
    );
  }

  // =========================================================================
  // Mappers – Modifier group / modifier
  // =========================================================================

  ModifierGroupEntity _modifierGroupToEntity(
    ModifierGroup row,
    List<ModifierEntity> modifiers,
  ) {
    return ModifierGroupEntity(
      id: row.id,
      tenantId: row.tenantId,
      name: row.name,
      selectionType: row.selectionType == 'multiple'
          ? ModifierSelectionType.multiple
          : ModifierSelectionType.single,
      minSelections: row.minSelections,
      maxSelections: row.maxSelections,
      isRequired: row.isRequired,
      askQuantity: row.askQuantity,
      freeTagging: row.freeTagging,
      columnCount: row.columnCount,
      prefix: row.prefix,
      displayOrder: row.displayOrder,
      modifiers: modifiers,
    );
  }

  ModifierGroupsCompanion _modifierGroupToCompanion(
      ModifierGroupEntity entity) {
    return ModifierGroupsCompanion(
      id: Value(entity.id),
      tenantId: Value(entity.tenantId),
      name: Value(entity.name),
      selectionType: Value(
        entity.selectionType == ModifierSelectionType.multiple
            ? 'multiple'
            : 'single',
      ),
      minSelections: Value(entity.minSelections),
      maxSelections: Value(entity.maxSelections),
      isRequired: Value(entity.isRequired),
      askQuantity: Value(entity.askQuantity),
      freeTagging: Value(entity.freeTagging),
      columnCount: Value(entity.columnCount),
      prefix: Value(entity.prefix),
      displayOrder: Value(entity.displayOrder),
      createdAt: Value(DateTime.now()),
      updatedAt: Value(DateTime.now()),
      isDeleted: const Value(false),
      syncStatus: const Value(0),
    );
  }

  ModifierEntity _modifierToEntity(Modifier row) {
    return ModifierEntity(
      id: row.id,
      tenantId: row.tenantId,
      groupId: row.groupId,
      name: row.name,
      priceDelta: row.priceDelta,
      isDefault: row.isDefault,
      displayOrder: row.displayOrder,
    );
  }

  ModifiersCompanion _modifierToCompanion(ModifierEntity entity) {
    return ModifiersCompanion(
      id: Value(entity.id),
      tenantId: Value(entity.tenantId),
      groupId: Value(entity.groupId),
      name: Value(entity.name),
      priceDelta: Value(entity.priceDelta),
      isDefault: Value(entity.isDefault),
      displayOrder: Value(entity.displayOrder),
      createdAt: Value(DateTime.now()),
      updatedAt: Value(DateTime.now()),
      isDeleted: const Value(false),
      syncStatus: const Value(0),
    );
  }

  // =========================================================================
  // Mappers – Product Specification
  // =========================================================================

  ProductSpecificationEntity _specToEntity(ProductSpecification row) {
    return ProductSpecificationEntity(
      id: row.id,
      tenantId: row.tenantId,
      productId: row.productId,
      name: row.name,
      price: row.price,
      isDefault: row.isDefault,
      displayOrder: row.displayOrder,
    );
  }

  // =========================================================================
  // Combos — component lookup for set-menu pickers
  // =========================================================================

  /// Load every component row attached to [comboProductId] in
  /// `display_order` order. Empty list when the product isn't a combo or
  /// has no rows yet (e.g. seed forgot to add components).
  Future<List<ComboItemEntity>> getComboItems(String comboProductId) async {
    final query = _db.select(_db.comboItems)
      ..where((c) => c.comboProductId.equals(comboProductId))
      ..orderBy([
        (c) => OrderingTerm(expression: c.displayOrder),
      ]);
    final rows = await query.get();
    return rows
        .map((r) => ComboItemEntity(
              id: r.id,
              tenantId: r.tenantId,
              comboProductId: r.comboProductId,
              itemProductId: r.itemProductId,
              quantity: r.quantity,
              groupName: r.groupName,
              isRequired: r.isRequired,
              canSubstitute: r.canSubstitute,
              displayOrder: r.displayOrder,
            ))
        .toList();
  }
}
