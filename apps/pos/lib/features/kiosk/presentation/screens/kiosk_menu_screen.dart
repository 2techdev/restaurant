/// Kiosk menu browsing screen.
///
/// Two-panel layout for large tablets:
///   Left  — category rail (large icon buttons)
///   Right — scrollable product grid with Add-to-Cart buttons
///
/// A running-total sidebar / cart badge shows the current cart value.
/// Products with modifiers navigate to [KioskProductDetailScreen];
/// simple products are added directly.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/utils/money.dart';
import 'package:gastrocore_pos/features/kiosk/presentation/providers/kiosk_provider.dart';
import 'package:gastrocore_pos/features/kiosk/router/kiosk_router.dart';
import 'package:gastrocore_pos/features/kiosk/theme/kiosk_theme.dart';
import 'package:gastrocore_pos/features/kiosk/presentation/screens/kiosk_welcome_screen.dart';
import 'package:gastrocore_pos/features/kiosk/presentation/screens/kiosk_language_screen.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/product_entity.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/category_entity.dart';

class KioskMenuScreen extends ConsumerWidget {
  const KioskMenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(kioskCategoriesProvider);
    final selectedCategory = ref.watch(kioskSelectedCategoryProvider);
    final cartItemCount = ref.watch(kioskSessionProvider).itemCount;
    final cartTotal = ref.watch(kioskCartTotalProvider);

    return Scaffold(
      backgroundColor: KioskColors.bgPage,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ────────────────────────────────────────────────────
            _TopBar(
              cartItemCount: cartItemCount,
              cartTotal: cartTotal,
              onCartTap: () => context.go(KioskRoutes.cart),
              onBack: () => context.go(KioskRoutes.language),
            ),

            // ── Body: category rail + product grid ─────────────────────────
            Expanded(
              child: Row(
                children: [
                  // Category rail
                  SizedBox(
                    width: 200,
                    child: categoriesAsync.when(
                      data: (cats) => _CategoryRail(
                        categories: cats,
                        selectedCategory: selectedCategory,
                        onSelect: (cat) {
                          ref
                              .read(kioskSelectedCategoryProvider.notifier)
                              .state = cat;
                        },
                      ),
                      loading: () => const Center(
                        child: CircularProgressIndicator(),
                      ),
                      error: (e, _) => Center(
                        child: Text('Error: $e'),
                      ),
                    ),
                  ),

                  // Vertical divider
                  Container(
                    width: 1,
                    color: KioskColors.border,
                  ),

                  // Product grid
                  Expanded(
                    child: selectedCategory == null
                        ? _NoCategorySelected(
                            onSelectFirst: () {
                              categoriesAsync.whenData((cats) {
                                if (cats.isNotEmpty) {
                                  ref
                                      .read(kioskSelectedCategoryProvider
                                          .notifier)
                                      .state = cats.first;
                                }
                              });
                            },
                          )
                        : _ProductGrid(category: selectedCategory),
                  ),
                ],
              ),
            ),

            // ── Step indicator ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: const KioskStepIndicator(currentStep: 1),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top bar
// ---------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  final int cartItemCount;
  final int cartTotal;
  final VoidCallback onCartTap;
  final VoidCallback onBack;

  const _TopBar({
    required this.cartItemCount,
    required this.cartTotal,
    required this.onCartTap,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: KioskColors.bgCard,
        border: Border(bottom: BorderSide(color: KioskColors.border)),
      ),
      child: Row(
        children: [
          KioskBackButton(onTap: onBack),
          const SizedBox(width: 20),
          Text(
            'Menu',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const Spacer(),
          if (cartItemCount > 0)
            GestureDetector(
              onTap: onCartTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: KioskColors.primary,
                  borderRadius: BorderRadius.circular(kKioskRadiusMedium),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.shopping_cart_rounded,
                        color: Colors.white, size: 22),
                    const SizedBox(width: 10),
                    Text(
                      '$cartItemCount item${cartItemCount == 1 ? '' : 's'}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      Money(cartTotal).format('CHF'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Category rail
// ---------------------------------------------------------------------------

class _CategoryRail extends StatelessWidget {
  final List<CategoryEntity> categories;
  final CategoryEntity? selectedCategory;
  final ValueChanged<CategoryEntity> onSelect;

  const _CategoryRail({
    required this.categories,
    required this.selectedCategory,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: KioskColors.bgCard,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final cat = categories[i];
          final isSelected = selectedCategory?.id == cat.id;
          return GestureDetector(
            onTap: () => onSelect(cat),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              decoration: BoxDecoration(
                color: isSelected
                    ? KioskColors.primaryContainer
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(kKioskRadiusMedium),
                border: isSelected
                    ? Border.all(color: KioskColors.primary, width: 2)
                    : null,
              ),
              child: Text(
                cat.name,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight:
                      isSelected ? FontWeight.w700 : FontWeight.w400,
                  color: isSelected
                      ? KioskColors.primary
                      : KioskColors.textPrimary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Product grid
// ---------------------------------------------------------------------------

class _ProductGrid extends ConsumerWidget {
  final CategoryEntity category;
  const _ProductGrid({required this.category});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(kioskProductsProvider);

    return productsAsync.when(
      data: (products) {
        if (products.isEmpty) {
          return Center(
            child: Text(
              'No products in this category.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: KioskColors.textSecondary,
                  ),
            ),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(20),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 260,
            childAspectRatio: 0.72,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
          ),
          itemCount: products.length,
          itemBuilder: (context, i) => _ProductCard(product: products[i]),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}

// ---------------------------------------------------------------------------
// Product card
// ---------------------------------------------------------------------------

class _ProductCard extends ConsumerWidget {
  final ProductEntity product;
  const _ProductCard({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOutOfStock = product.stockStatus == 'out_of_stock' ||
        product.stockStatus == 'out_of_stock_today';

    return GestureDetector(
      onTap: isOutOfStock
          ? null
          : () {
              if (product.hasModifiers) {
                context.go(KioskRoutes.productFor(product.id));
              } else {
                ref.read(kioskSessionProvider.notifier).addItem(product);
                _showAddedFeedback(context, product.name);
              }
            },
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: isOutOfStock ? 0.45 : 1.0,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: KioskColors.bgCard,
            borderRadius: BorderRadius.circular(kKioskRadiusLarge),
            border: Border.all(color: KioskColors.border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product image placeholder
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(kKioskRadiusLarge),
                  ),
                  child: product.imagePath != null
                      ? Image.asset(
                          product.imagePath!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          errorBuilder: (_, __, ___) =>
                              _ProductImagePlaceholder(name: product.name),
                        )
                      : _ProductImagePlaceholder(name: product.name),
                ),
              ),

              // Info
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: KioskColors.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          Money(product.price).format('CHF'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: KioskColors.primary,
                          ),
                        ),
                        if (isOutOfStock)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: KioskColors.errorContainer,
                              borderRadius:
                                  BorderRadius.circular(kKioskRadiusSmall),
                            ),
                            child: const Text(
                              'Sold out',
                              style: TextStyle(
                                fontSize: 11,
                                color: KioskColors.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                        else
                          _AddButton(
                            onTap: () {
                              if (product.hasModifiers) {
                                context.go(
                                  KioskRoutes.productFor(product.id),
                                );
                              } else {
                                ref
                                    .read(kioskSessionProvider.notifier)
                                    .addItem(product);
                                _showAddedFeedback(context, product.name);
                              }
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddedFeedback(BuildContext context, String name) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$name added to cart'),
        duration: const Duration(milliseconds: 1200),
        behavior: SnackBarBehavior.floating,
        width: 300,
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: KioskColors.primary,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.add, color: Colors.white, size: 20),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Image placeholder
// ---------------------------------------------------------------------------

class _ProductImagePlaceholder extends StatelessWidget {
  final String name;
  const _ProductImagePlaceholder({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: KioskColors.bgCardAlt,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.restaurant_menu_rounded,
            size: 40,
            color: KioskColors.textDim,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              name,
              style: const TextStyle(
                fontSize: 12,
                color: KioskColors.textSecondary,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// No category selected placeholder
// ---------------------------------------------------------------------------

class _NoCategorySelected extends StatelessWidget {
  final VoidCallback onSelectFirst;
  const _NoCategorySelected({required this.onSelectFirst});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.menu_book_rounded,
            size: 80,
            color: KioskColors.textDim,
          ),
          const SizedBox(height: 16),
          Text(
            'Select a category to browse products',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: KioskColors.textSecondary,
                ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: onSelectFirst,
            child: const Text('Browse Menu'),
          ),
        ],
      ),
    );
  }
}
