/// Menu Management tab for the Back Office screen.
///
/// Two-column layout: category list on the left, product grid on the right.
/// Supports full CRUD for categories and products via real providers.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/menu/presentation/providers/menu_provider.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/category_entity.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/product_entity.dart';
import 'package:gastrocore_pos/shared/widgets/pos_text_field.dart';
import 'package:gastrocore_pos/shared/widgets/pos_button.dart';
import 'package:gastrocore_pos/features/backoffice/presentation/widgets/product_form_dialog.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const _foodEmojis = [
  '\u{1F354}', '\u{1F355}', '\u{1F32E}', '\u{1F32F}', '\u{1F959}',
  '\u{1F957}', '\u{1F35D}', '\u{1F35C}', '\u{1F363}', '\u{1F364}',
  '\u{1F969}', '\u{1F953}', '\u{1F357}', '\u{1F356}', '\u{1F96A}',
  '\u{1F950}', '\u{1F35E}', '\u{1F382}', '\u{1F370}', '\u{1F366}',
  '\u{2615}', '\u{1F375}', '\u{1F37A}', '\u{1F377}', '\u{1F379}',
  '\u{1F378}', '\u{1F9C3}', '\u{1F95B}', '\u{1F36B}', '\u{1F36A}',
];

const _presetColors = [
  '#FF9F0A', '#FF3B30', '#FF6B6B', '#BF5AF2', '#AF52DE',
  '#528DFF', '#4F8CFF', '#05B046', '#34C759', '#FFD60A',
  '#FF9500', '#5AC8FA', '#64D2FF', '#8E8E93', '#AEAEB2',
];

// ---------------------------------------------------------------------------
// MenuManagementTab
// ---------------------------------------------------------------------------

class MenuManagementTab extends ConsumerStatefulWidget {
  const MenuManagementTab({super.key});

  @override
  ConsumerState<MenuManagementTab> createState() => _MenuManagementTabState();
}

class _MenuManagementTabState extends ConsumerState<MenuManagementTab> {
  String? _selectedCategoryId;
  String _productSearch = '';

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // -- LEFT: Category list (~40%) --
          Expanded(
            flex: 4,
            child: _buildCategoryPanel(categoriesAsync),
          ),
          const SizedBox(width: 24),

          // -- RIGHT: Product list (~60%) --
          Expanded(
            flex: 6,
            child: _buildProductPanel(),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // Category panel
  // =========================================================================

  Widget _buildCategoryPanel(AsyncValue<List<CategoryEntity>> categoriesAsync) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Text(
              'Kategoriler',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),

          // Category list
          Expanded(
            child: categoriesAsync.when(
              data: (categories) => _buildCategoryList(categories),
              loading: () => const Center(
                child: CircularProgressIndicator(
                  color: AppColors.primary,
                  strokeWidth: 2,
                ),
              ),
              error: (e, _) => Center(
                child: Text(
                  'Hata: $e',
                  style: const TextStyle(color: AppColors.red, fontSize: 13),
                ),
              ),
            ),
          ),

          // Add category button
          Padding(
            padding: const EdgeInsets.all(16),
            child: PosGradientButton(
              label: 'Kategori Ekle',
              icon: Icons.add_rounded,
              height: 44,
              onPressed: () => _showCategoryDialog(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryList(List<CategoryEntity> categories) {
    if (categories.isEmpty) {
      return const Center(
        child: Text(
          'Henuz kategori yok',
          style: TextStyle(color: AppColors.textDim, fontSize: 13),
        ),
      );
    }

    // Auto-select first category if none selected
    if (_selectedCategoryId == null && categories.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _selectedCategoryId = categories.first.id);
        }
      });
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final cat = categories[index];
        return _buildCategoryRow(cat);
      },
    );
  }

  Widget _buildCategoryRow(CategoryEntity cat) {
    final isSelected = _selectedCategoryId == cat.id;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: isSelected ? AppColors.surfaceBright : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            setState(() => _selectedCategoryId = cat.id);
          },
          onLongPress: () => _showCategoryActions(cat),
          splashColor: AppColors.textPrimary.withValues(alpha: 0.04),
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                // Emoji / icon
                Text(
                  cat.icon.length <= 4 ? cat.icon : '\u{1F4CB}',
                  style: const TextStyle(fontSize: 20),
                ),
                const SizedBox(width: 12),

                // Name
                Expanded(
                  child: Text(
                    cat.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                // Edit icon
                GestureDetector(
                  onTap: () => _showCategoryDialog(existing: cat),
                  child: const SizedBox(
                    width: 36,
                    height: 36,
                    child: Icon(
                      Icons.edit_rounded,
                      size: 16,
                      color: AppColors.textDim,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCategoryActions(CategoryEntity cat) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainerHighest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_rounded,
                  color: AppColors.textPrimary),
              title: const Text(
                'Duzenle',
                style: TextStyle(color: AppColors.textPrimary),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _showCategoryDialog(existing: cat);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_rounded, color: AppColors.red),
              title: const Text(
                'Sil',
                style: TextStyle(color: AppColors.red),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _deleteCategory(cat);
              },
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // Product panel
  // =========================================================================

  Widget _buildProductPanel() {
    final allProductsAsync = ref.watch(productsProvider);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header + search
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Row(
              children: [
                const Text(
                  'Urunler',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: 240,
                  child: PosTextField(
                    hint: 'Urun ara...',
                    prefixIcon: Icons.search_rounded,
                    onChanged: (v) => setState(() => _productSearch = v),
                  ),
                ),
              ],
            ),
          ),

          // Product list
          Expanded(
            child: allProductsAsync.when(
              data: (products) {
                var filtered = _selectedCategoryId != null
                    ? products
                        .where((p) => p.categoryId == _selectedCategoryId)
                        .toList()
                    : products;

                if (_productSearch.isNotEmpty) {
                  final q = _productSearch.toLowerCase();
                  filtered = filtered
                      .where((p) => p.name.toLowerCase().contains(q))
                      .toList();
                }

                return _buildProductList(filtered);
              },
              loading: () => const Center(
                child: CircularProgressIndicator(
                  color: AppColors.primary,
                  strokeWidth: 2,
                ),
              ),
              error: (e, _) => Center(
                child: Text(
                  'Hata: $e',
                  style: const TextStyle(color: AppColors.red, fontSize: 13),
                ),
              ),
            ),
          ),

          // Add product button
          Padding(
            padding: const EdgeInsets.all(16),
            child: PosGradientButton(
              label: 'Urun Ekle',
              icon: Icons.add_rounded,
              height: 44,
              onPressed: _selectedCategoryId != null
                  ? () => _showProductDialog()
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductList(List<ProductEntity> products) {
    if (products.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 40, color: AppColors.textDim),
            SizedBox(height: 12),
            Text(
              'Bu kategoride urun yok',
              style: TextStyle(color: AppColors.textDim, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: products.length,
      itemBuilder: (context, index) => _buildProductCard(products[index]),
    );
  }

  Widget _buildProductCard(ProductEntity product) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Product info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      'CHF ${(product.price / 100).toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (product.hasModifiers)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.purpleDim,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${product.modifierGroups.length} modifier',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.purple,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // Status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: product.isActive ? AppColors.greenDim : AppColors.redDim,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              product.isActive ? 'Aktif' : 'Pasif',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: product.isActive ? AppColors.green : AppColors.red,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Edit
          _iconButton(
            Icons.edit_rounded,
            onTap: () => _showProductDialog(existing: product),
          ),
          const SizedBox(width: 4),

          // Delete
          _iconButton(
            Icons.delete_outline_rounded,
            color: AppColors.red,
            onTap: () => _deleteProduct(product),
          ),
        ],
      ),
    );
  }

  Widget _iconButton(
    IconData icon, {
    Color color = AppColors.textDim,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }

  // =========================================================================
  // Category dialog
  // =========================================================================

  Future<void> _showCategoryDialog({CategoryEntity? existing}) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    String selectedEmoji = existing?.icon ?? _foodEmojis.first;
    String selectedColor = existing?.color ?? _presetColors.first;

    final result = await showDialog<bool>(
      context: context,
      barrierColor: AppColors.bgOverlay,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: AppColors.surfaceContainerHighest,
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      existing != null ? 'Kategori Duzenle' : 'Kategori Ekle',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Name field
                    PosTextField(
                      label: 'Kategori Adi',
                      hint: 'ornegin: Icecekler',
                      controller: nameController,
                      autofocus: true,
                    ),
                    const SizedBox(height: 20),

                    // Emoji picker
                    const Text(
                      'Ikon',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _foodEmojis.map((emoji) {
                        final isSelected = selectedEmoji == emoji;
                        return GestureDetector(
                          onTap: () =>
                              setDialogState(() => selectedEmoji = emoji),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.accentDim
                                  : AppColors.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child:
                                  Text(emoji, style: const TextStyle(fontSize: 20)),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),

                    // Color picker
                    const Text(
                      'Renk',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _presetColors.map((hex) {
                        final isSelected = selectedColor == hex;
                        final color = _hexToColor(hex);
                        return GestureDetector(
                          onTap: () =>
                              setDialogState(() => selectedColor = hex),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(8),
                              border: isSelected
                                  ? Border.all(
                                      color: AppColors.textPrimary, width: 2)
                                  : null,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),

                    // Actions
                    Row(
                      children: [
                        Expanded(
                          child: PosGhostButton(
                            label: 'Iptal',
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: PosGradientButton(
                            label: 'Kaydet',
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
        ),
      ),
    );

    if (result == true && nameController.text.trim().isNotEmpty) {
      final repo = ref.read(menuRepositoryProvider);
      final tenantId = ref.read(tenantIdProvider);

      if (existing != null) {
        await repo.updateCategory(existing.copyWith(
          name: nameController.text.trim(),
          icon: selectedEmoji,
          color: selectedColor,
        ));
      } else {
        final categoriesList = await ref.read(categoriesProvider.future);
        final newCategory = CategoryEntity(
          id: IdGenerator.generateId(),
          tenantId: tenantId,
          name: nameController.text.trim(),
          displayOrder: categoriesList.length,
          color: selectedColor,
          icon: selectedEmoji,
          isActive: true,
        );
        await repo.createCategory(newCategory);
      }

      ref.invalidate(categoriesProvider);
      ref.invalidate(productsProvider);
    }

    nameController.dispose();
  }

  Future<void> _deleteCategory(CategoryEntity cat) async {
    final confirmed = await showDialog<bool>(
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
                const Text(
                  'Kategori Sil',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '"${cat.name}" kategorisini silmek istediginize emin misiniz?',
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
                        label: 'Iptal',
                        onPressed: () => Navigator.pop(ctx, false),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: PosSolidButton(
                        label: 'Sil',
                        color: AppColors.red,
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

    if (confirmed == true) {
      final repo = ref.read(menuRepositoryProvider);
      await repo.deleteCategory(cat.id);
      if (_selectedCategoryId == cat.id) {
        _selectedCategoryId = null;
      }
      ref.invalidate(categoriesProvider);
      ref.invalidate(productsProvider);
    }
  }

  // =========================================================================
  // Product dialog
  // =========================================================================

  Future<void> _showProductDialog({ProductEntity? existing}) async {
    final result = await showProductFormDialog(
      context,
      existing: existing,
      initialCategoryId: _selectedCategoryId ?? '',
    );

    if (result == true) {
      ref.invalidate(productsProvider);
    }
  }

  Future<void> _deleteProduct(ProductEntity product) async {
    final confirmed = await showDialog<bool>(
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
                const Text(
                  'Urun Sil',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '"${product.name}" urununu silmek istediginize emin misiniz?',
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
                        label: 'Iptal',
                        onPressed: () => Navigator.pop(ctx, false),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: PosSolidButton(
                        label: 'Sil',
                        color: AppColors.red,
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

    if (confirmed == true) {
      final repo = ref.read(menuRepositoryProvider);
      await repo.deleteProduct(product.id);
      ref.invalidate(productsProvider);
    }
  }

  // =========================================================================
  // Helpers
  // =========================================================================

  static Color _hexToColor(String hex) {
    final buffer = StringBuffer();
    if (hex.length == 6 || hex.length == 7) buffer.write('FF');
    buffer.write(hex.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }
}
