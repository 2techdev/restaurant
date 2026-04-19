/// Product grid for the Kinetic sales shell.
///
/// Renders [filteredProductsProvider] as a dense tile grid matching the
/// SambaPOS reference (019da150) the user approved: each tile is a
/// zero-radius [catGreen] card with white body text (top-left) and a
/// white price chip (bottom-right).
///
/// Column count is responsive — driven by the rendering width rather than
/// a user toggle, because the middle "category column" already owns the
/// 1↔2 toggle via [productGridColumnsProvider]. A tablet at 1280dp hits the
/// 4-column breakpoint; the 7" pilot (~800dp product area) lands on 3.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_tokens.dart';
import 'package:gastrocore_pos/core/theme/kinetic_theme.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/category_entity.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/product_entity.dart';
import 'package:gastrocore_pos/features/menu/presentation/providers/menu_provider.dart';

/// Column-count preference shared by the middle category column and — when
/// set to 1 — by a fallback single-column product list. The product grid
/// itself is responsive, so in the default (2-column category) mode this
/// value doesn't actually constrain the product grid.
final productGridColumnsProvider = StateProvider<int>((ref) => 2);

const int kProductGridMinColumns = 1;
const int kProductGridMaxColumns = 2;

int clampProductGridColumns(int n) =>
    n.clamp(kProductGridMinColumns, kProductGridMaxColumns);

void toggleProductGridColumns(WidgetRef ref) {
  final current = ref.read(productGridColumnsProvider);
  ref.read(productGridColumnsProvider.notifier).state =
      current == 1 ? 2 : 1;
}

// ---------------------------------------------------------------------------
// Tile sizing — picks a column count based on the grid's usable width.
// ---------------------------------------------------------------------------

const double _tileHeight = 112;
const double _tileMinWidth = 140;

int _columnsForWidth(double width) {
  if (width >= 880) return 5;
  if (width >= 720) return 4;
  if (width >= 520) return 3;
  return 2;
}

// ---------------------------------------------------------------------------
// ProductGrid
// ---------------------------------------------------------------------------

class ProductGrid extends ConsumerWidget {
  const ProductGrid({
    super.key,
    required this.onProductTap,
    this.cartQuantities = const <String, int>{},
  });

  final Map<String, int> cartQuantities;
  final void Function(ProductEntity) onProductTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(filteredProductsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);

    // Per-category hex colour lookup — drives POS-v2 category tinting on the
    // product tiles. When the DB is still loading, resolveCategoryColor falls
    // back to the warm orange default.
    final colorByCatId = <String, String?>{};
    final cats = categoriesAsync.asData?.value ?? const <CategoryEntity>[];
    for (final c in cats) {
      colorByCatId[c.id] = c.color;
    }

    return ColoredBox(
      color: GcColors.surface,
      child: productsAsync.when(
        data: (products) {
          if (products.isEmpty) return const _EmptyState();
          return LayoutBuilder(
            builder: (context, bc) {
              final cols = _columnsForWidth(bc.maxWidth);
              final tileWidth = (bc.maxWidth -
                      AppTokens.space16 - // outer padding
                      AppTokens.space8 * (cols - 1)) /
                  cols;
              final aspect = tileWidth / _tileHeight;

              return GridView.builder(
                key: ValueKey('product_grid_cols_$cols'),
                padding: const EdgeInsets.all(AppTokens.space8),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisSpacing: AppTokens.space8,
                  crossAxisSpacing: AppTokens.space8,
                  childAspectRatio: tileWidth < _tileMinWidth ? 1 : aspect,
                ),
                itemCount: products.length,
                itemBuilder: (context, index) {
                  final p = products[index];
                  return ProductCard(
                    key: ValueKey('product_card_${p.id}'),
                    product: p,
                    quantity: cartQuantities[p.id] ?? 0,
                    categoryColorHex: colorByCatId[p.categoryId],
                    onTap: () => onProductTap(p),
                  );
                },
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: AppInsets.all16,
            child: Text(
              'Menü yüklenemedi: $err',
              style: GcText.bodySmall.copyWith(color: GcColors.error),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ProductCard — zero-radius tile, name top-left, price bottom-right.
// ---------------------------------------------------------------------------

class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
    this.quantity = 0,
    this.categoryColorHex,
  });

  final ProductEntity product;
  final VoidCallback onTap;
  final int quantity;

  /// Hex string from the product's [CategoryEntity.color]. When null or
  /// malformed the card falls back to the warm default.
  final String? categoryColorHex;

  @override
  Widget build(BuildContext context) {
    final style = resolveCategoryColor(categoryColorHex);
    final bg = style.bg;
    final fg = style.fg;
    return Material(
      color: bg,
      child: InkWell(
        onTap: onTap,
        splashColor: darken(bg, 0.18),
        highlightColor: darken(bg, 0.12),
        child: Stack(
          children: [
            DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: kInsetHighlight, width: 2),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppTokens.space8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Text(
                        product.name,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: fg,
                          height: 1.15,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomRight,
                      child: Text(
                        _formatCHF(product.price),
                        style: TextStyle(
                          fontFamily: 'WorkSans',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: fg,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (quantity > 0)
              Positioned(
                top: AppTokens.space4,
                right: AppTokens.space4,
                child: _QuantityBadge(quantity: quantity, tileColor: bg),
              ),
          ],
        ),
      ),
    );
  }

  static String _formatCHF(int cents) {
    final whole = cents ~/ 100;
    final frac = (cents % 100).toString().padLeft(2, '0');
    return 'CHF $whole.$frac';
  }
}

class _QuantityBadge extends StatelessWidget {
  const _QuantityBadge({required this.quantity, required this.tileColor});
  final int quantity;
  final Color tileColor;

  @override
  Widget build(BuildContext context) {
    // POS v2: in-cart badge is a white circle with the category colour as
    // text — it reads as a numeric chip over the tile, not a coloured pill.
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: Text(
        quantity > 9 ? '9+' : '$quantity',
        style: GcText.button.copyWith(
          fontSize: 11,
          color: tileColor,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.restaurant_menu_rounded,
              size: 48, color: GcColors.outlineVariant),
          SizedBox(height: AppTokens.space8),
          Text(
            'Bu kategoride ürün yok',
            style: GcText.bodySmall,
          ),
        ],
      ),
    );
  }
}
