/// Product grid for the fine-dining shell.
///
/// Renders `filteredProductsProvider` in a responsive GridView whose column
/// count is user-toggleable (1 ↔ 2). Product decision 2026-04-17: operators
/// on crowded nights with long menus prefer a dense 1-col list; slower nights
/// with a short "house favourites" menu prefer 2-col big-button mode.
///
/// The toggle state lives in [productGridColumnsProvider] so settings, the
/// category strip header, and the grid itself all stay in sync.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/core/theme/app_tokens.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/product_entity.dart';
import 'package:gastrocore_pos/features/menu/presentation/providers/menu_provider.dart';

/// Column-count preference for the fine-dining product grid.
///
/// Values: 1 (list/wide), 2 (two-per-row). Default 2 matches SambaPOS.
/// Clamped by [clampProductGridColumns] on write so callers can't push
/// invalid counts from a slider or shortcut.
final productGridColumnsProvider = StateProvider<int>((ref) => 2);

/// Minimum column count — a single wide card per row.
const int kProductGridMinColumns = 1;

/// Maximum column count — current pilot cap. Raising means recomputing card
/// aspect ratios; don't just bump this integer without checking [ProductCard].
const int kProductGridMaxColumns = 2;

/// Clamp [n] to the legal [kProductGridMinColumns]..[kProductGridMaxColumns]
/// range. Exposed so tests and menu shortcuts share the same rule.
int clampProductGridColumns(int n) =>
    n.clamp(kProductGridMinColumns, kProductGridMaxColumns);

/// Toggle the [productGridColumnsProvider] between 1 and 2. Idempotent and
/// side-effect-free beyond the state update — safe to call from a toolbar.
void toggleProductGridColumns(WidgetRef ref) {
  final current = ref.read(productGridColumnsProvider);
  ref.read(productGridColumnsProvider.notifier).state =
      current == 1 ? 2 : 1;
}

// ---------------------------------------------------------------------------
// ProductGrid widget
// ---------------------------------------------------------------------------

/// Renders the product grid. Accepts an explicit [columns] so tests can drive
/// the widget without provider plumbing. In production callers pass the
/// [productGridColumnsProvider] value.
class ProductGrid extends ConsumerWidget {
  const ProductGrid({
    super.key,
    required this.columns,
    required this.onProductTap,
    this.cartQuantities = const <String, int>{},
  });

  final int columns;

  /// Map of productId → pending (not-yet-sent) quantity, for the badge.
  final Map<String, int> cartQuantities;

  final void Function(ProductEntity) onProductTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(filteredProductsProvider);
    final crossAxisCount = clampProductGridColumns(columns);

    return productsAsync.when(
      data: (products) {
        if (products.isEmpty) {
          return const _EmptyState();
        }
        return GridView.builder(
          key: ValueKey('product_grid_cols_$crossAxisCount'),
          padding: AppInsets.all12,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: AppTokens.space12,
            crossAxisSpacing: AppTokens.space12,
            // 1-col: wide banner cards (aspect 3:1). 2-col: square-ish (1.15:1).
            childAspectRatio: crossAxisCount == 1 ? 3.2 : AppTokens.productCardAspect,
          ),
          itemCount: products.length,
          itemBuilder: (context, index) {
            final p = products[index];
            return ProductCard(
              key: ValueKey('product_card_${p.id}'),
              product: p,
              quantity: cartQuantities[p.id] ?? 0,
              columns: crossAxisCount,
              onTap: () => onProductTap(p),
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
            style: const TextStyle(color: AppColors.red),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ProductCard
// ---------------------------------------------------------------------------

/// A single product tile. Layout adapts to [columns] to stay readable at
/// both aspect ratios.
class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
    required this.columns,
    this.quantity = 0,
  });

  final ProductEntity product;
  final VoidCallback onTap;
  final int columns;
  final int quantity;

  @override
  Widget build(BuildContext context) {
    final isRow = columns == 1;
    return Material(
      color: AppColors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        child: Stack(
          children: [
            Padding(
              padding: AppInsets.all12,
              child: isRow
                  ? _rowLayout(context)
                  : _squareLayout(context),
            ),
            if (quantity > 0)
              Positioned(
                top: AppTokens.space8,
                right: AppTokens.space8,
                child: _QuantityBadge(quantity: quantity),
              ),
          ],
        ),
      ),
    );
  }

  Widget _rowLayout(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                product.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (product.description != null &&
                  product.description!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  product.description!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: AppTokens.space12),
        Text(
          _formatCHF(product.price),
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
      ],
    );
  }

  Widget _squareLayout(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Center(
            child: Text(
              product.name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(height: AppTokens.space8),
        Text(
          _formatCHF(product.price),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
      ],
    );
  }

  static String _formatCHF(int cents) {
    final whole = cents ~/ 100;
    final frac = (cents % 100).toString().padLeft(2, '0');
    return 'CHF $whole.$frac';
  }
}

class _QuantityBadge extends StatelessWidget {
  const _QuantityBadge({required this.quantity});
  final int quantity;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '×$quantity',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: Colors.white,
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
              size: 48, color: AppColors.textDim),
          SizedBox(height: AppTokens.space8),
          Text(
            'Bu kategoride ürün yok',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
