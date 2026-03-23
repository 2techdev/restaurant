/// Inventory management tab for the Back Office screen.
///
/// Shows all products grouped by category with their current stock status.
/// Managers can quickly toggle between: In Stock / Low Stock / Out of Stock.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/category_entity.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/product_entity.dart';
import 'package:gastrocore_pos/features/menu/presentation/providers/menu_provider.dart';

// ---------------------------------------------------------------------------
// Stock status constants
// ---------------------------------------------------------------------------

const _kInStock = 'in_stock';
const _kLowStock = 'low_stock';
const _kOutOfStock = 'out_of_stock';

// ---------------------------------------------------------------------------
// InventoryManagementTab
// ---------------------------------------------------------------------------

class InventoryManagementTab extends ConsumerStatefulWidget {
  const InventoryManagementTab({super.key});

  @override
  ConsumerState<InventoryManagementTab> createState() =>
      _InventoryManagementTabState();
}

class _InventoryManagementTabState
    extends ConsumerState<InventoryManagementTab> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String? _filterStatus; // null = all, or one of the _k* constants

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final productsAsync = ref.watch(adminProductsProvider);

    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: categoriesAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            error: (e, _) => Center(
              child: Text('Error: $e',
                  style:
                      const TextStyle(color: AppColors.red, fontSize: 13)),
            ),
            data: (cats) => productsAsync.when(
              loading: () => const Center(
                  child: CircularProgressIndicator(strokeWidth: 2)),
              error: (e, _) => Center(
                child: Text('Error: $e',
                    style:
                        const TextStyle(color: AppColors.red, fontSize: 13)),
              ),
              data: (products) =>
                  _buildList(cats, products),
            ),
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Header: search + filter chips
  // -------------------------------------------------------------------------

  Widget _buildHeader() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Stok Yonetimi',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          // Search
          Container(
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.bgInput,
              borderRadius: BorderRadius.circular(10),
            ),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(
                  fontSize: 14, color: AppColors.textPrimary),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded,
                    size: 18, color: AppColors.textDim),
                hintText: 'Urun ara...',
                hintStyle:
                    TextStyle(fontSize: 14, color: AppColors.textDim),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
              onChanged: (v) => setState(() => _searchQuery = v.trim()),
            ),
          ),
          const SizedBox(height: 10),
          // Filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip(label: 'Tumu', value: null),
                const SizedBox(width: 8),
                _filterChip(
                  label: 'Stokta',
                  value: _kInStock,
                  color: AppColors.green,
                ),
                const SizedBox(width: 8),
                _filterChip(
                  label: 'Dusuk Stok',
                  value: _kLowStock,
                  color: AppColors.orange,
                ),
                const SizedBox(width: 8),
                _filterChip(
                  label: 'Tukendi',
                  value: _kOutOfStock,
                  color: AppColors.red,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required String? value,
    Color? color,
  }) {
    final isSelected = _filterStatus == value;
    return GestureDetector(
      onTap: () => setState(() => _filterStatus = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? (color ?? AppColors.primary).withValues(alpha: 0.15)
              : AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? (color ?? AppColors.primary)
                : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight:
                isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected
                ? (color ?? AppColors.primary)
                : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Main list
  // -------------------------------------------------------------------------

  Widget _buildList(
      List<CategoryEntity> cats, List<ProductEntity> products) {
    // Build category map
    final catMap = {for (final c in cats) c.id: c};

    // Filter products
    final filtered = products.where((p) {
      if (_filterStatus != null && p.stockStatus != _filterStatus) {
        return false;
      }
      if (_searchQuery.isNotEmpty &&
          !p.name.toLowerCase().contains(_searchQuery.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();

    if (filtered.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_rounded,
                size: 48, color: AppColors.textDim),
            SizedBox(height: 12),
            Text(
              'Urun bulunamadi',
              style: TextStyle(
                  fontSize: 15, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    // Group by category
    final grouped = <String, List<ProductEntity>>{};
    for (final p in filtered) {
      (grouped[p.categoryId] ??= []).add(p);
    }

    // Sort categories by display order
    final sortedCatIds = grouped.keys.toList()
      ..sort((a, b) {
        final aOrder = catMap[a]?.displayOrder ?? 999;
        final bOrder = catMap[b]?.displayOrder ?? 999;
        return aOrder.compareTo(bOrder);
      });

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: sortedCatIds.length,
      itemBuilder: (ctx, i) {
        final catId = sortedCatIds[i];
        final catName =
            catMap[catId]?.name ?? 'Unknown Category';
        final catProducts = grouped[catId]!;
        return _buildCategorySection(catName, catProducts);
      },
    );
  }

  Widget _buildCategorySection(
      String catName, List<ProductEntity> products) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text(
            catName.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textDim,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              for (int i = 0; i < products.length; i++) ...[
                _buildProductRow(products[i]),
                if (i < products.length - 1)
                  const Divider(
                      height: 1, color: AppColors.surfaceContainerHigh),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProductRow(ProductEntity product) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Product name + price
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'CHF ${(product.price / 100).toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textDim,
                  ),
                ),
              ],
            ),
          ),
          // Stock status toggle
          _StockStatusToggle(
            product: product,
            onChanged: (newStatus) => _updateStock(product, newStatus),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Actions
  // -------------------------------------------------------------------------

  Future<void> _updateStock(
      ProductEntity product, String newStatus) async {
    final repo = ref.read(menuRepositoryProvider);
    await repo.updateProduct(
        product.copyWith(stockStatus: newStatus));
    ref.invalidate(adminProductsProvider);
  }
}

// ---------------------------------------------------------------------------
// Stock status toggle widget
// ---------------------------------------------------------------------------

class _StockStatusToggle extends StatelessWidget {
  const _StockStatusToggle({
    required this.product,
    required this.onChanged,
  });

  final ProductEntity product;
  final void Function(String newStatus) onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _statusBtn(
          label: 'Stokta',
          value: _kInStock,
          activeColor: AppColors.green,
        ),
        const SizedBox(width: 6),
        _statusBtn(
          label: 'Dusuk',
          value: _kLowStock,
          activeColor: AppColors.orange,
        ),
        const SizedBox(width: 6),
        _statusBtn(
          label: 'Tukendi',
          value: _kOutOfStock,
          activeColor: AppColors.red,
        ),
      ],
    );
  }

  Widget _statusBtn({
    required String label,
    required String value,
    required Color activeColor,
  }) {
    final isActive = product.stockStatus == value;
    return GestureDetector(
      onTap: isActive ? null : () => onChanged(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? activeColor.withValues(alpha: 0.15)
              : AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? activeColor : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            color: isActive ? activeColor : AppColors.textDim,
          ),
        ),
      ),
    );
  }
}
