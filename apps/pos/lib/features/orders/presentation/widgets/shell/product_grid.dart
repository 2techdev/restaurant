/// Product grid for the Kinetic sales shell.
///
/// Renders `filteredProductsProvider` in a responsive GridView whose column
/// count is user-toggleable (1 ↔ 2). The grid stays on zero-radius tiles
/// with a ghost border — depth is expressed via surface nesting, not
/// shadows. Products with an [ProductEntity.imagePath] set get a thumbnail
/// pushed against the leading edge; text-only tiles stay Kinetic-clean.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_tokens.dart';
import 'package:gastrocore_pos/core/theme/kinetic_theme.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/product_entity.dart';
import 'package:gastrocore_pos/features/menu/presentation/providers/menu_provider.dart';

/// Column-count preference for the product grid (1 or 2).
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
// ProductGrid
// ---------------------------------------------------------------------------

class ProductGrid extends ConsumerWidget {
  const ProductGrid({
    super.key,
    required this.columns,
    required this.onProductTap,
    this.cartQuantities = const <String, int>{},
  });

  final int columns;
  final Map<String, int> cartQuantities;
  final void Function(ProductEntity) onProductTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(filteredProductsProvider);
    final crossAxisCount = clampProductGridColumns(columns);

    return ColoredBox(
      color: GcColors.surface,
      child: productsAsync.when(
        data: (products) {
          if (products.isEmpty) return const _EmptyState();
          return GridView.builder(
            key: ValueKey('product_grid_cols_$crossAxisCount'),
            padding: AppInsets.all12,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: AppTokens.space8,
              crossAxisSpacing: AppTokens.space8,
              childAspectRatio: crossAxisCount == 1 ? 3.2 : 1.25,
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
// ProductCard
// ---------------------------------------------------------------------------

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
    final hasThumb = (product.imagePath ?? '').isNotEmpty;
    return Material(
      color: GcColors.surfaceContainerLowest,
      shape: const Border.fromBorderSide(
        BorderSide(color: GcColors.ghostBorder),
      ),
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            hasThumb
                ? _thumbLayout(context)
                : Padding(
                    padding: AppInsets.all12,
                    child: _textOnlyLayout(),
                  ),
            if (quantity > 0)
              Positioned(
                top: AppTokens.space4,
                right: AppTokens.space4,
                child: _QuantityBadge(quantity: quantity),
              ),
          ],
        ),
      ),
    );
  }

  Widget _textOnlyLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                product.name,
                style: GcText.body.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              Align(
                alignment: Alignment.bottomRight,
                child: Text(
                  _formatCHF(product.price),
                  style: GcText.price.copyWith(
                    fontSize: 13,
                    color: GcColors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _thumbLayout(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 80,
          child: Image.network(
            product.imagePath!,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const ColoredBox(
              color: GcColors.surfaceContainerHigh,
              child: Icon(Icons.restaurant_rounded,
                  size: 28, color: GcColors.outlineVariant),
            ),
            loadingBuilder: (c, child, prog) => prog == null
                ? child
                : const ColoredBox(color: GcColors.surfaceContainer),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.space12,
              vertical: AppTokens.space8,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  product.name,
                  style: GcText.body.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _formatCHF(product.price),
                  style: GcText.price.copyWith(
                    fontSize: 13,
                    color: GcColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      color: GcColors.primary,
      child: Text(
        '×$quantity',
        style: GcText.button.copyWith(
          fontSize: 11,
          color: GcColors.onPrimary,
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
