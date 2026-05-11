/// Waiter menu screen — embedded inside the order flow.
///
/// Phone-optimised menu browser with:
/// - Category chips at the top
/// - Search bar
/// - Product grid with quick-add (tap = instant add, long press = modifiers)
/// - All products filtered by the selected category / search query
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/category_entity.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/product_entity.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/order_item_entity.dart';
import 'package:gastrocore_pos/features/orders/presentation/widgets/modifier_dialog.dart';
import 'package:gastrocore_pos/features/waiter/presentation/providers/waiter_provider.dart';

// ---------------------------------------------------------------------------
// WaiterMenuScreen
// ---------------------------------------------------------------------------

class WaiterMenuScreen extends ConsumerStatefulWidget {
  const WaiterMenuScreen({super.key});

  @override
  ConsumerState<WaiterMenuScreen> createState() => _WaiterMenuScreenState();
}

class _WaiterMenuScreenState extends ConsumerState<WaiterMenuScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(waiterCategoriesProvider);
    final searchQuery = ref.watch(waiterSearchQueryProvider);
    final isSearching = searchQuery.isNotEmpty;

    return Column(
      children: [
        // ── Search bar ────────────────────────────────────────────────────
        _SearchBar(controller: _searchController),
        // ── Category chips ────────────────────────────────────────────────
        if (!isSearching)
          categoriesAsync.when(
            loading: () => const SizedBox(height: 48),
            error: (_, __) => const SizedBox.shrink(),
            data: (cats) => _CategoryChips(categories: cats),
          ),
        // ── Product grid ──────────────────────────────────────────────────
        Expanded(
          child: isSearching
              ? _SearchResultsGrid()
              : _CategoryProductsGrid(),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Search bar
// ---------------------------------------------------------------------------

class _SearchBar extends ConsumerWidget {
  final TextEditingController controller;

  const _SearchBar({required this.controller});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: controller,
        onChanged: (value) =>
            ref.read(waiterSearchQueryProvider.notifier).state = value,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
        decoration: InputDecoration(
          hintText: 'Menüde ara…',
          hintStyle:
              const TextStyle(color: AppColors.textDim, fontSize: 15),
          prefixIcon:
              const Icon(Icons.search, color: AppColors.textDim, size: 20),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear,
                      color: AppColors.textDim, size: 18),
                  onPressed: () {
                    controller.clear();
                    ref.read(waiterSearchQueryProvider.notifier).state = '';
                  },
                )
              : null,
          filled: true,
          fillColor: AppColors.surfaceContainerLow,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Category chips
// ---------------------------------------------------------------------------

class _CategoryChips extends ConsumerWidget {
  final List<CategoryEntity> categories;

  const _CategoryChips({required this.categories});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(waiterSelectedCategoryProvider);

    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final cat = categories[index];
          final isSelected = cat.id == selected?.id;
          return GestureDetector(
            onTap: () {
              ref.read(waiterSelectedCategoryProvider.notifier).state =
                  isSelected ? null : cat;
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(right: 8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.accentDim
                    : AppColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected
                      ? AppColors.primary
                      : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Text(
                cat.name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.textSecondary,
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
// Product grids
// ---------------------------------------------------------------------------

class _CategoryProductsGrid extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(waiterProductsProvider);
    final category = ref.watch(waiterSelectedCategoryProvider);

    if (category == null) {
      return const Center(
        child: Text(
          'Select a category to browse products',
          style: TextStyle(color: AppColors.textDim, fontSize: 14),
        ),
      );
    }

    return productsAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      error: (e, _) =>
          Center(child: Text(e.toString(), style: const TextStyle(color: AppColors.red))),
      data: (products) => _ProductGrid(products: products),
    );
  }
}

class _SearchResultsGrid extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultsAsync = ref.watch(waiterSearchResultsProvider);

    return resultsAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      error: (e, _) =>
          Center(child: Text(e.toString(), style: const TextStyle(color: AppColors.red))),
      data: (products) {
        if (products.isEmpty) {
          return const Center(
            child: Text(
              'No products found',
              style: TextStyle(color: AppColors.textDim, fontSize: 14),
            ),
          );
        }
        return _ProductGrid(products: products);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// _ProductGrid
// ---------------------------------------------------------------------------

class _ProductGrid extends ConsumerWidget {
  final List<ProductEntity> products;

  const _ProductGrid({required this.products});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = products.where((p) => p.isActive).toList();
    if (active.isEmpty) {
      return const Center(
        child: Text('No active products',
            style: TextStyle(color: AppColors.textDim)),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.35,
      ),
      itemCount: active.length,
      itemBuilder: (context, index) {
        return _ProductTile(product: active[index]);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Product tile
// ---------------------------------------------------------------------------

class _ProductTile extends ConsumerWidget {
  final ProductEntity product;

  const _ProductTile({required this.product});

  String _formatPrice(int cents) {
    return 'CHF ${(cents / 100).toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOutOfStock = product.stockStatus == 'out_of_stock' ||
        product.stockStatus == 'out_of_stock_today';

    return GestureDetector(
      // Tap = quick add (quantity 1, no modifier prompt).
      onTap: isOutOfStock
          ? null
          : () {
              HapticFeedback.lightImpact();
              ref.read(waiterActiveTicketProvider.notifier).addProduct(product);
              _showAddedFeedback(context);
            },
      // Long press = modifier dialog (if modifiers exist) or quantity sheet.
      onLongPress: isOutOfStock
          ? null
          : () {
              HapticFeedback.mediumImpact();
              if (product.hasModifiers) {
                _showModifierDialog(context, ref);
              } else {
                _showQuantitySheet(context, ref);
              }
            },
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: isOutOfStock ? 0.45 : 1.0,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Name
              Expanded(
                child: Text(
                  product.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    height: 1.3,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 4),
              // Price row
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _formatPrice(product.price),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  if (isOutOfStock)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.redDim,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '86\'d',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.red),
                      ),
                    )
                  else
                    Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(
                        color: AppColors.accentDim,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.add,
                          color: AppColors.primary, size: 18),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showModifierDialog(BuildContext context, WidgetRef ref) async {
    final modifierGroups = ModifierGroupData.fromProductEntity(product);
    final result = await showModifierDialog(
      context: context,
      productName: product.name,
      productPrice: product.price,
      modifierGroups: modifierGroups,
    );
    if (result != null) {
      final orderModifiers = <OrderItemModifierEntity>[
        for (final sel in result.flattened())
          OrderItemModifierEntity(
            id: IdGenerator.generateId(),
            orderItemId: '',
            modifierId: sel.option.id,
            modifierName: sel.displayName,
            priceDelta: sel.option.priceDelta,
            quantity: sel.quantity,
            note: sel.note,
          ),
      ];
      if (context.mounted) {
        HapticFeedback.lightImpact();
        ref.read(waiterActiveTicketProvider.notifier).addProduct(
              product,
              quantity: result.quantity.toDouble(),
              modifiers: orderModifiers,
              notes: result.notes.isNotEmpty ? result.notes : null,
            );
        _showAddedFeedback(context);
      }
    }
  }

  void _showAddedFeedback(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '+ ${product.name}',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.green,
        duration: const Duration(milliseconds: 800),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showQuantitySheet(BuildContext context, WidgetRef ref) {
    int qty = 1;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _QtyButton(
                        icon: Icons.remove,
                        onTap: qty > 1
                            ? () => setModalState(() => qty--)
                            : null,
                      ),
                      const SizedBox(width: 32),
                      Text(
                        '$qty',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 32),
                      _QtyButton(
                        icon: Icons.add,
                        onTap: () => setModalState(() => qty++),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.surfaceDim,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        HapticFeedback.lightImpact();
                        ref
                            .read(waiterActiveTicketProvider.notifier)
                            .addProduct(product, quantity: qty.toDouble());
                      },
                      child: Text(
                        'Add $qty × ${product.name}',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _QtyButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: onTap == null ? 0.35 : 1.0,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerHigh,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: AppColors.textPrimary, size: 22),
        ),
      ),
    );
  }
}
