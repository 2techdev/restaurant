/// Admin product panel — Products tab of MenuManagementScreen.
///
/// Features:
/// - Category filter sidebar
/// - Grid / list view toggle
/// - Search by name
/// - Active / inactive badge with one-tap toggle
/// - Bulk price update button (per category or all)
/// - Add / edit product (delegates to ProductFormDialog)
/// - Delete product
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/category_entity.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/product_entity.dart';
import 'package:gastrocore_pos/features/menu/presentation/providers/menu_provider.dart';
import 'package:gastrocore_pos/features/menu/presentation/widgets/bulk_price_dialog.dart';
import 'package:gastrocore_pos/features/menu/presentation/widgets/linked_items_overlay_tab.dart';
import 'package:gastrocore_pos/features/backoffice/presentation/widgets/product_form_dialog.dart';
import 'package:gastrocore_pos/shared/widgets/pos_button.dart';
import 'package:gastrocore_pos/shared/widgets/pos_text_field.dart';

// Swiss MWST rate display
const _taxLabels = <String, String>{
  'food': 'Food 2.6/8.1%',
  'beverage': 'Bev. 2.6/8.1%',
  'alcohol': 'Alcohol 8.1%',
  'custom': 'Custom',
  'default': 'Default',
};

class ProductAdminPanel extends ConsumerStatefulWidget {
  const ProductAdminPanel({super.key});

  @override
  ConsumerState<ProductAdminPanel> createState() => _ProductAdminPanelState();
}

class _ProductAdminPanelState extends ConsumerState<ProductAdminPanel> {
  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final isGrid = ref.watch(menuViewGridProvider);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: category filter
          SizedBox(
            width: 220,
            child: _CategorySidebar(categoriesAsync: categoriesAsync),
          ),
          const SizedBox(width: 16),

          // Right: product list/grid
          Expanded(
            child: Column(
              children: [
                _buildToolbar(isGrid),
                const SizedBox(height: 12),
                Expanded(
                  child: isGrid
                      ? _buildGridView()
                      : _buildListView(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(bool isGrid) {
    final selectedCategoryId = ref.watch(adminSelectedCategoryProvider);

    return Row(
      children: [
        // Search
        Expanded(
          child: PosTextField(
            hint: 'Search products...',
            prefixIcon: Icons.search_rounded,
            onChanged: (v) =>
                ref.read(adminProductSearchProvider.notifier).state = v,
          ),
        ),
        const SizedBox(width: 12),

        // Bulk price
        _ToolbarButton(
          icon: Icons.price_change_outlined,
          label: 'Bulk Price',
          onTap: () => _showBulkPriceDialog(selectedCategoryId),
        ),
        const SizedBox(width: 8),

        // View toggle
        _ToggleViewButton(
          isGrid: isGrid,
          onToggle: () =>
              ref.read(menuViewGridProvider.notifier).state = !isGrid,
        ),
        const SizedBox(width: 8),

        // Add product
        PosGradientButton(
          label: 'Add Product',
          icon: Icons.add_rounded,
          height: 44,
          expand: false,
          onPressed: selectedCategoryId != null
              ? () => _showProductForm(categoryId: selectedCategoryId)
              : null,
        ),
      ],
    );
  }

  Widget _buildListView() {
    final productsAsync = ref.watch(filteredAdminProductsProvider);

    return productsAsync.when(
      data: (products) {
        if (products.isEmpty) {
          return _EmptyProductsState(
            onAdd: () {
              final catId = ref.read(adminSelectedCategoryProvider);
              if (catId != null) _showProductForm(categoryId: catId);
            },
          );
        }
        return ListView.builder(
          itemCount: products.length,
          itemBuilder: (ctx, i) => _ProductListTile(
            product: products[i],
            onEdit: () => _showProductForm(existing: products[i]),
            onDelete: () => _confirmDeleteProduct(products[i]),
            onToggleActive: () => _toggleActive(products[i]),
          ),
        );
      },
      loading: () =>
          const Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2)),
      error: (e, _) => Center(
        child: Text('Error: $e',
            style: const TextStyle(color: AppColors.red, fontSize: 13)),
      ),
    );
  }

  Widget _buildGridView() {
    final productsAsync = ref.watch(filteredAdminProductsProvider);

    return productsAsync.when(
      data: (products) {
        if (products.isEmpty) {
          return _EmptyProductsState(
            onAdd: () {
              final catId = ref.read(adminSelectedCategoryProvider);
              if (catId != null) _showProductForm(categoryId: catId);
            },
          );
        }
        return GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            childAspectRatio: 0.85,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: products.length,
          itemBuilder: (ctx, i) => _ProductGridCard(
            product: products[i],
            onEdit: () => _showProductForm(existing: products[i]),
            onDelete: () => _confirmDeleteProduct(products[i]),
            onToggleActive: () => _toggleActive(products[i]),
          ),
        );
      },
      loading: () =>
          const Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2)),
      error: (e, _) => Center(
        child: Text('Error: $e',
            style: const TextStyle(color: AppColors.red, fontSize: 13)),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Actions
  // -------------------------------------------------------------------------

  Future<void> _showProductForm({
    ProductEntity? existing,
    String? categoryId,
  }) async {
    final catId =
        categoryId ?? existing?.categoryId ?? ref.read(adminSelectedCategoryProvider) ?? '';
    final result =
        await showProductFormDialog(context, existing: existing, initialCategoryId: catId);
    if (result == true) {
      ref.invalidate(adminProductsProvider);
      ref.invalidate(productsProvider);
    }
  }

  Future<void> _toggleActive(ProductEntity product) async {
    final repo = ref.read(menuRepositoryProvider);
    await repo.toggleProductActive(product.id, isActive: !product.isActive);
    ref.invalidate(adminProductsProvider);
    ref.invalidate(productsProvider);
  }

  Future<void> _confirmDeleteProduct(ProductEntity product) async {
    final confirmed = await _showConfirmDialog(
      title: 'Delete Product',
      message: 'Delete "${product.name}"? This cannot be undone.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (confirmed == true) {
      final repo = ref.read(menuRepositoryProvider);
      await repo.deleteProduct(product.id);
      ref.invalidate(adminProductsProvider);
      ref.invalidate(productsProvider);
    }
  }

  Future<void> _showBulkPriceDialog(String? categoryId) async {
    final tenantId = ref.read(tenantIdProvider);
    await showBulkPriceDialog(
      context,
      tenantId: tenantId,
      categoryId: categoryId,
      categoryName: categoryId != null
          ? _getCategoryName(categoryId)
          : null,
    );
    ref.invalidate(adminProductsProvider);
    ref.invalidate(productsProvider);
  }

  String? _getCategoryName(String categoryId) {
    final cats = ref.read(categoriesProvider).valueOrNull;
    return cats?.firstWhere((c) => c.id == categoryId,
            orElse: () => CategoryEntity(
                id: '', tenantId: '', name: 'Unknown',
                displayOrder: 0, color: '', icon: '', isActive: true))
        .name;
  }

  Future<bool?> _showConfirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
    bool isDestructive = false,
  }) {
    return showDialog<bool>(
      context: context,
      barrierColor: AppColors.bgOverlay,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.surfaceContainerHighest,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: PosGhostButton(
                        label: 'Cancel',
                        onPressed: () => Navigator.pop(ctx, false),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: isDestructive
                          ? PosSolidButton(
                              label: confirmLabel,
                              color: AppColors.red,
                              height: 44,
                              onPressed: () => Navigator.pop(ctx, true),
                            )
                          : PosGradientButton(
                              label: confirmLabel,
                              height: 44,
                              onPressed: () => Navigator.pop(ctx, true),
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Category sidebar
// ---------------------------------------------------------------------------

class _CategorySidebar extends ConsumerWidget {
  final AsyncValue<List<CategoryEntity>> categoriesAsync;

  const _CategorySidebar({required this.categoriesAsync});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(adminSelectedCategoryProvider);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Categories',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
          ),

          // "All" option
          _SidebarItem(
            label: 'All Products',
            icon: '🍽️',
            isSelected: selected == null,
            onTap: () =>
                ref.read(adminSelectedCategoryProvider.notifier).state = null,
          ),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Divider(color: AppColors.border, height: 1),
          ),

          Expanded(
            child: categoriesAsync.when(
              data: (cats) => ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: cats.length,
                itemBuilder: (_, i) {
                  final cat = cats[i];
                  return _SidebarItem(
                    label: cat.name,
                    icon: cat.icon.length <= 4 ? cat.icon : '📋',
                    isSelected: selected == cat.id,
                    isInactive: !cat.isActive,
                    onTap: () => ref
                        .read(adminSelectedCategoryProvider.notifier)
                        .state = cat.id,
                  );
                },
              ),
              loading: () => const Center(
                child: CircularProgressIndicator(
                    color: AppColors.primary, strokeWidth: 2),
              ),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final String label;
  final String icon;
  final bool isSelected;
  final bool isInactive;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.label,
    required this.icon,
    required this.isSelected,
    this.isInactive = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? AppColors.accentDim : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: AppColors.primary.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isInactive
                        ? AppColors.textDim
                        : (isSelected
                            ? AppColors.primary
                            : AppColors.textSecondary),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isInactive)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.redDim,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'OFF',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: AppColors.red,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Product list tile
// ---------------------------------------------------------------------------

class _ProductListTile extends StatelessWidget {
  final ProductEntity product;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleActive;

  const _ProductListTile({
    required this.product,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleActive,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: product.isActive
            ? null
            : Border.all(color: AppColors.red.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          // Active indicator bar
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 3,
            height: 40,
            decoration: BoxDecoration(
              color: product.isActive ? AppColors.green : AppColors.textDim,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 14),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: product.isActive
                        ? AppColors.textPrimary
                        : AppColors.textDim,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(
                      'CHF ${(product.price / 100).toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    _TaxBadge(taxGroup: product.taxGroup),
                    if (product.hasModifiers) ...[
                      const SizedBox(width: 6),
                      _ModifierBadge(count: product.modifierGroups.length),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Active toggle
          GestureDetector(
            onTap: onToggleActive,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: product.isActive ? AppColors.greenDim : AppColors.redDim,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                product.isActive ? 'Active' : 'Inactive',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: product.isActive ? AppColors.green : AppColors.red,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Edit
          _IconBtn(Icons.edit_rounded, onTap: onEdit),
          const SizedBox(width: 4),

          // Delete
          _IconBtn(Icons.delete_outline_rounded,
              color: AppColors.red, onTap: onDelete),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Product grid card
// ---------------------------------------------------------------------------

class _ProductGridCard extends StatelessWidget {
  final ProductEntity product;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleActive;

  const _ProductGridCard({
    required this.product,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleActive,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: product.isActive
            ? null
            : Border.all(color: AppColors.red.withValues(alpha: 0.2)),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name
                Expanded(
                  child: Text(
                    product.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: product.isActive
                          ? AppColors.textPrimary
                          : AppColors.textDim,
                      height: 1.3,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                // Price
                Text(
                  'CHF ${(product.price / 100).toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 6),

                // Tax + action row
                Row(
                  children: [
                    _TaxBadge(taxGroup: product.taxGroup),
                    const Spacer(),
                    Tooltip(
                      message: "Online ek bilgiler — gastro.2hub.ch'te yönetilir",
                      child: _IconBtn(
                        Icons.cloud_outlined,
                        size: 16,
                        onTap: () => showLinkedItemsOverlaySheet(context, product),
                      ),
                    ),
                    const SizedBox(width: 2),
                    _IconBtn(Icons.edit_rounded, size: 16, onTap: onEdit),
                    const SizedBox(width: 2),
                    _IconBtn(Icons.delete_outline_rounded,
                        size: 16, color: AppColors.red, onTap: onDelete),
                  ],
                ),
              ],
            ),
          ),

          // Active toggle in corner
          Positioned(
            top: 10,
            right: 10,
            child: GestureDetector(
              onTap: onToggleActive,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: product.isActive ? AppColors.green : AppColors.red,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small reusable widgets
// ---------------------------------------------------------------------------

class _TaxBadge extends StatelessWidget {
  final String taxGroup;
  const _TaxBadge({required this.taxGroup});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        _taxLabels[taxGroup] ?? taxGroup,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _ModifierBadge extends StatelessWidget {
  final int count;
  const _ModifierBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.purpleDim,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        '$count mod',
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: AppColors.purple,
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final double size;

  const _IconBtn(
    this.icon, {
    this.color = AppColors.textDim,
    required this.onTap,
    this.size = 17,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(icon, size: size, color: color),
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: AppColors.textPrimary.withValues(alpha: 0.06),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToggleViewButton extends StatelessWidget {
  final bool isGrid;
  final VoidCallback onToggle;

  const _ToggleViewButton({required this.isGrid, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onToggle,
        splashColor: AppColors.textPrimary.withValues(alpha: 0.06),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            isGrid ? Icons.view_list_rounded : Icons.grid_view_rounded,
            size: 18,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _EmptyProductsState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyProductsState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inventory_2_outlined,
              size: 48, color: AppColors.textDim),
          const SizedBox(height: 12),
          const Text(
            'No products in this category',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textDim,
            ),
          ),
          const SizedBox(height: 20),
          PosGradientButton(
            label: 'Add First Product',
            icon: Icons.add_rounded,
            height: 44,
            expand: false,
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}
