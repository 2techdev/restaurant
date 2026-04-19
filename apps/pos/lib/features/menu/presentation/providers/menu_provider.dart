/// Riverpod providers for the menu feature.
///
/// Provides categories, products, modifier groups, search, filtering, and
/// admin-specific state. The [filteredProductsProvider] combines the selected
/// category and search query into a single derived list for the POS grid.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/features/menu/data/repositories/menu_repository_impl.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/category_entity.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/modifier_entity.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/product_entity.dart';

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

/// Provides a singleton [MenuRepositoryImpl] backed by the app database.
final menuRepositoryProvider = Provider<MenuRepositoryImpl>((ref) {
  final db = ref.watch(databaseProvider);
  return MenuRepositoryImpl(db);
});

// ---------------------------------------------------------------------------
// Categories
// ---------------------------------------------------------------------------

/// All categories (active and inactive) for the current tenant, ordered by
/// [displayOrder]. Used in admin views.
final categoriesProvider = FutureProvider<List<CategoryEntity>>((ref) async {
  final repo = ref.watch(menuRepositoryProvider);
  final tenantId = ref.watch(tenantIdProvider);
  return repo.getAllCategories(tenantId);
});

/// The currently selected category ID. `null` means "All" / no filter.
final selectedCategoryProvider = StateProvider<String?>((ref) => null);

// ---------------------------------------------------------------------------
// Products – POS view (active only)
// ---------------------------------------------------------------------------

/// Products filtered by the currently selected category (active only).
///
/// When [selectedCategoryProvider] is `null`, all active products are returned.
///
/// Implementation note: we fetch the full tenant-scoped list once and filter
/// locally rather than issuing a `categoryId`-only query. The local filter
/// guarantees products always come from the current tenant and collapses two
/// code paths (all vs. filtered) into one — so a stale `selectedCategoryProvider`
/// value can no longer empty the grid.
final productsProvider = FutureProvider<List<ProductEntity>>((ref) async {
  final repo = ref.watch(menuRepositoryProvider);
  final tenantId = ref.watch(tenantIdProvider);
  final categoryId = ref.watch(selectedCategoryProvider);

  final all = await repo.getAllProducts(tenantId);
  if (categoryId == null) return all;
  return all.where((p) => p.categoryId == categoryId).toList();
});

// ---------------------------------------------------------------------------
// Products – Admin view (active + inactive)
// ---------------------------------------------------------------------------

/// All products including inactive ones, filtered by category for admin.
final adminProductsProvider = FutureProvider<List<ProductEntity>>((ref) async {
  final repo = ref.watch(menuRepositoryProvider);
  final tenantId = ref.watch(tenantIdProvider);
  final categoryId = ref.watch(adminSelectedCategoryProvider);

  if (categoryId != null) {
    return repo.getProductsByCategoryAdmin(categoryId);
  }
  return repo.getAllProductsAdmin(tenantId);
});

/// Selected category in the admin product panel. Independent of POS selection.
final adminSelectedCategoryProvider = StateProvider<String?>((ref) => null);

// ---------------------------------------------------------------------------
// Search
// ---------------------------------------------------------------------------

/// Current search query string. Empty string disables search filtering.
final productSearchProvider = StateProvider<String>((ref) => '');

/// Products matching both the category filter **and** the search query.
///
/// Case-insensitive substring match on product name.
/// When the search query is empty the full category-filtered list is returned.
final filteredProductsProvider =
    FutureProvider<List<ProductEntity>>((ref) async {
  final products = await ref.watch(productsProvider.future);
  final search = ref.watch(productSearchProvider).toLowerCase().trim();

  if (search.isEmpty) return products;

  return products
      .where((p) => p.name.toLowerCase().contains(search))
      .toList();
});

/// Admin search query — separate from POS search state.
final adminProductSearchProvider = StateProvider<String>((ref) => '');

/// Admin filtered products combining admin category + admin search.
final filteredAdminProductsProvider =
    FutureProvider<List<ProductEntity>>((ref) async {
  final products = await ref.watch(adminProductsProvider.future);
  final search = ref.watch(adminProductSearchProvider).toLowerCase().trim();

  if (search.isEmpty) return products;

  return products
      .where((p) => p.name.toLowerCase().contains(search))
      .toList();
});

// ---------------------------------------------------------------------------
// Modifier groups
// ---------------------------------------------------------------------------

/// All modifier groups with their modifiers for the current tenant.
final allModifierGroupsProvider =
    FutureProvider<List<ModifierGroupEntity>>((ref) async {
  final repo = ref.watch(menuRepositoryProvider);
  final tenantId = ref.watch(tenantIdProvider);
  return repo.getAllModifierGroups(tenantId);
});

/// Modifier groups linked to a specific product.
final modifierGroupsForProductProvider =
    FutureProvider.family<List<ModifierGroupEntity>, String>(
  (ref, productId) async {
    final repo = ref.watch(menuRepositoryProvider);
    return repo.getModifierGroupsForProduct(productId);
  },
);

// ---------------------------------------------------------------------------
// Menu management UI state
// ---------------------------------------------------------------------------

/// View mode toggle for the admin product panel: `true` = grid, `false` = list.
final menuViewGridProvider = StateProvider<bool>((ref) => false);

/// Active tab index in the MenuManagementScreen: 0=Products, 1=Categories, 2=Modifiers.
final menuAdminTabProvider = StateProvider<int>((ref) => 0);
