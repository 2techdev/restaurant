// TODO(v2): Move to RestaurantSettings.favorites (JSON column) + backoffice Settings UI
//   - Drag-drop reorder
//   - Add/remove buttons
//   - Assign action type + target from a product / category / action picker
//   - Per-tenant colour override
//
/// Favorites quick bar — a horizontal strip above the product grid with
/// "function-assignable" shortcut buttons.
///
/// Pilot v3 ships two action types hard-coded:
///   * [FavoriteAction.addProduct] — tap adds the matched product to the cart
///   * [FavoriteAction.openCategory] — tap switches the product grid to the
///     matched category (writes [selectedCategoryProvider]).
///
/// Targets are matched by **name** for the pilot demo (seed UUIDs are
/// generated per-install so we can't hard-code them yet). The [FavoriteButton]
/// model carries a single `target` string; v2 will repurpose it as the real
/// UUID once the backoffice picker lands.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/core/theme/app_tokens.dart';
import 'package:gastrocore_pos/core/theme/kinetic_theme.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/category_entity.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/product_entity.dart';
import 'package:gastrocore_pos/features/menu/presentation/providers/menu_provider.dart';

// ---------------------------------------------------------------------------
// FavoriteButton data model — action + target + label (+ optional colour)
// ---------------------------------------------------------------------------

enum FavoriteAction { addProduct, openCategory }

class FavoriteButton {
  const FavoriteButton({
    required this.action,
    required this.target,
    required this.label,
    this.color,
  });

  /// What tapping the button does.
  final FavoriteAction action;

  /// Pilot v3: matched by name (case-insensitive contains).
  /// v2: real UUID from RestaurantSettings.favorites.
  final String target;

  /// Button label as rendered. Caller uppercases at render time.
  final String label;

  /// Optional colour override. `null` uses the semantic default
  /// (green for product, orange for category).
  final Color? color;
}

/// Hard-coded demo list shown in the pilot. Keep it short (4 buttons) so the
/// bar stays under the product grid header — longer lists move to scroll in v2.
const List<FavoriteButton> kDemoFavorites = <FavoriteButton>[
  FavoriteButton(
    action: FavoriteAction.addProduct,
    target: 'Coca-Cola Zero',
    label: 'Cola Zero',
  ),
  FavoriteButton(
    action: FavoriteAction.addProduct,
    target: 'Mineralwasser',
    label: 'Su',
  ),
  FavoriteButton(
    action: FavoriteAction.openCategory,
    target: 'Getränke',
    label: 'İçecekler',
  ),
  FavoriteButton(
    action: FavoriteAction.openCategory,
    target: 'Desserts',
    label: 'Tatlılar',
  ),
];

// ---------------------------------------------------------------------------
// Providers — all-active products (category-independent) for favorites lookup
// ---------------------------------------------------------------------------

/// Returns *all* active products for the current tenant, unfiltered by
/// [selectedCategoryProvider]. The POS [productsProvider] applies the
/// category filter; the favorites bar needs the raw list so it can resolve
/// targets regardless of what's currently on screen.
final allActiveProductsProvider =
    FutureProvider<List<ProductEntity>>((ref) async {
  final repo = ref.watch(menuRepositoryProvider);
  final tenantId = ref.watch(tenantIdProvider);
  return repo.getAllProducts(tenantId);
});

// ---------------------------------------------------------------------------
// FavoritesBar widget
// ---------------------------------------------------------------------------

class FavoritesBar extends ConsumerWidget {
  const FavoritesBar({
    super.key,
    required this.favorites,
    required this.onAddProduct,
  });

  /// Buttons to render. Defaults to [kDemoFavorites] via the factory below.
  final List<FavoriteButton> favorites;

  /// Called when a [FavoriteAction.addProduct] button is tapped and the
  /// matching product is found. Wired to the same ticket-add flow as
  /// [ProductGrid].
  final void Function(ProductEntity product) onAddProduct;

  /// Convenience factory that wires up the demo list.
  factory FavoritesBar.demo({
    Key? key,
    required void Function(ProductEntity product) onAddProduct,
  }) {
    return FavoritesBar(
      key: key,
      favorites: kDemoFavorites,
      onAddProduct: onAddProduct,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(allActiveProductsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);

    final products = productsAsync.valueOrNull ?? const <ProductEntity>[];
    final categories =
        categoriesAsync.valueOrNull ?? const <CategoryEntity>[];

    return Container(
      color: GcColors.surfaceContainerLowest,
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.space16,
        vertical: AppTokens.space8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(
            width: 64,
            child: Center(
              child: Text(
                'HIZLI',
                style: TextStyle(
                  fontFamily: 'WorkSans',
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: GcColors.onSurfaceVariant,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppTokens.space12),
          for (var i = 0; i < favorites.length; i++) ...[
            if (i > 0) const SizedBox(width: AppTokens.space8),
            Expanded(
              child: _FavoriteTile(
                button: favorites[i],
                onTap: () => _dispatch(
                  ref: ref,
                  button: favorites[i],
                  products: products,
                  categories: categories,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _dispatch({
    required WidgetRef ref,
    required FavoriteButton button,
    required List<ProductEntity> products,
    required List<CategoryEntity> categories,
  }) {
    switch (button.action) {
      case FavoriteAction.addProduct:
        final match = _matchProductByName(products, button.target);
        if (match == null) return; // silently skip if seed missing
        onAddProduct(match);
      case FavoriteAction.openCategory:
        final match = _matchCategoryByName(categories, button.target);
        if (match == null) return;
        ref.read(selectedCategoryProvider.notifier).state = match;
    }
  }

  ProductEntity? _matchProductByName(
    List<ProductEntity> products,
    String target,
  ) {
    final needle = target.toLowerCase().trim();
    for (final p in products) {
      if (p.name.toLowerCase() == needle) return p;
    }
    for (final p in products) {
      if (p.name.toLowerCase().contains(needle)) return p;
    }
    return null;
  }

  String? _matchCategoryByName(
    List<CategoryEntity> categories,
    String target,
  ) {
    final needle = target.toLowerCase().trim();
    for (final c in categories) {
      if (c.name.toLowerCase() == needle) return c.id;
    }
    for (final c in categories) {
      if (c.name.toLowerCase().contains(needle)) return c.id;
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// _FavoriteTile — one button. Green for products, orange for categories.
// ---------------------------------------------------------------------------

class _FavoriteTile extends StatelessWidget {
  const _FavoriteTile({required this.button, required this.onTap});

  final FavoriteButton button;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = button.color ??
        (button.action == FavoriteAction.addProduct
            ? GcColors.catGreen
            : GcColors.catOrange);

    return Material(
      color: bg,
      child: InkWell(
        onTap: onTap,
        splashColor: button.action == FavoriteAction.addProduct
            ? GcColors.catDarkGreen
            : GcColors.catYellow,
        highlightColor: button.action == FavoriteAction.addProduct
            ? GcColors.catDarkGreen
            : GcColors.catYellow,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: kInsetHighlight, width: 2),
            ),
          ),
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: AppTokens.space12),
            alignment: Alignment.center,
            child: Text(
              button.label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'WorkSans',
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
