/// Category management panel — Categories tab of MenuManagementScreen.
///
/// Features:
/// - Drag-to-reorder category list (persists displayOrder to DB)
/// - Add / edit category (name, emoji icon, color)
/// - Toggle active/inactive
/// - Delete category (with confirmation)
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/category_entity.dart';
import 'package:gastrocore_pos/features/menu/presentation/providers/menu_provider.dart';
import 'package:gastrocore_pos/shared/widgets/pos_button.dart';
import 'package:gastrocore_pos/shared/widgets/pos_text_field.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const _foodEmojis = [
  '🍔', '🍕', '🌮', '🌯', '🥙', '🥗', '🍝', '🍜',
  '🍣', '🍤', '🥩', '🥓', '🍗', '🍖', '🥪', '🥐',
  '🍞', '🎂', '🍰', '🍦', '☕', '🍵', '🍺', '🍷',
  '🍹', '🍸', '🧃', '🥛', '🍫', '🍪', '🍱', '🥘',
];

const _presetColors = [
  '#FF9F0A', '#FF3B30', '#FF6B6B', '#BF5AF2', '#AF52DE',
  '#528DFF', '#4F8CFF', '#05B046', '#34C759', '#FFD60A',
  '#FF9500', '#5AC8FA', '#64D2FF', '#8E8E93', '#AEAEB2',
];

// ---------------------------------------------------------------------------
// Panel
// ---------------------------------------------------------------------------

class CategoryManagementPanel extends ConsumerStatefulWidget {
  const CategoryManagementPanel({super.key});

  @override
  ConsumerState<CategoryManagementPanel> createState() =>
      _CategoryManagementPanelState();
}

class _CategoryManagementPanelState
    extends ConsumerState<CategoryManagementPanel> {
  // Local copy of category order for optimistic drag-reorder UI
  List<CategoryEntity>? _localOrder;

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // List panel
          Expanded(
            flex: 5,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  Expanded(
                    child: categoriesAsync.when(
                      data: (cats) {
                        // Sync local order when data arrives (unless user is dragging)
                        if (_localOrder == null) {
                          WidgetsBinding.instance
                              .addPostFrameCallback((_) {
                            if (mounted) {
                              setState(() => _localOrder = List.from(cats));
                            }
                          });
                        }
                        return _buildCategoryList(_localOrder ?? cats);
                      },
                      loading: () => const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primary, strokeWidth: 2),
                      ),
                      error: (e, _) => Center(
                        child: Text('Error: $e',
                            style: const TextStyle(
                                color: AppColors.red, fontSize: 13)),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: PosGradientButton(
                      label: 'Add Category',
                      icon: Icons.add_rounded,
                      height: 44,
                      onPressed: _showCategoryDialog,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 16),

          // Info / hint panel
          SizedBox(
            width: 260,
            child: _buildInfoPanel(),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Header
  // -------------------------------------------------------------------------

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Row(
        children: [
          const Text(
            'Categories',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.drag_indicator_rounded,
                    size: 14, color: AppColors.textDim),
                SizedBox(width: 4),
                Text(
                  'Drag to reorder',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textDim,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Category list with drag reorder
  // -------------------------------------------------------------------------

  Widget _buildCategoryList(List<CategoryEntity> categories) {
    if (categories.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.category_outlined, size: 40, color: AppColors.textDim),
            SizedBox(height: 12),
            Text(
              'No categories yet',
              style: TextStyle(color: AppColors.textDim, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: categories.length,
      onReorder: (oldIndex, newIndex) => _onReorder(categories, oldIndex, newIndex),
      proxyDecorator: (child, index, animation) => Material(
        color: AppColors.surfaceBright,
        borderRadius: BorderRadius.circular(12),
        elevation: 4,
        child: child,
      ),
      itemBuilder: (ctx, i) {
        final cat = categories[i];
        return _CategoryRow(
          key: ValueKey(cat.id),
          category: cat,
          onEdit: () => _showCategoryDialog(existing: cat),
          onToggleActive: () => _toggleActive(cat),
          onDelete: () => _confirmDelete(cat),
        );
      },
    );
  }

  void _onReorder(
    List<CategoryEntity> categories,
    int oldIndex,
    int newIndex,
  ) {
    if (newIndex > oldIndex) newIndex--;

    final updated = List<CategoryEntity>.from(categories);
    final item = updated.removeAt(oldIndex);
    updated.insert(newIndex, item);

    setState(() => _localOrder = updated);

    // Persist new order to DB
    final repo = ref.read(menuRepositoryProvider);
    repo
        .reorderCategories(updated.map((c) => c.id).toList())
        .then((_) => ref.invalidate(categoriesProvider));
  }

  // -------------------------------------------------------------------------
  // Info panel
  // -------------------------------------------------------------------------

  Widget _buildInfoPanel() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Category Tips',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 16),
          _TipItem(
            icon: Icons.drag_indicator_rounded,
            text: 'Drag rows to change the order shown on the POS screen.',
          ),
          SizedBox(height: 12),
          _TipItem(
            icon: Icons.toggle_off_rounded,
            text: 'Toggle a category inactive to hide it from the POS without deleting products.',
          ),
          SizedBox(height: 12),
          _TipItem(
            icon: Icons.color_lens_outlined,
            text: 'Pick a colour and emoji so staff can quickly identify categories.',
          ),
          SizedBox(height: 12),
          _TipItem(
            icon: Icons.delete_outline_rounded,
            text: 'Deleting a category soft-deletes it. Products are not deleted.',
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Actions
  // -------------------------------------------------------------------------

  Future<void> _toggleActive(CategoryEntity cat) async {
    final repo = ref.read(menuRepositoryProvider);
    await repo.updateCategory(cat.copyWith(isActive: !cat.isActive));
    _localOrder = null;
    ref.invalidate(categoriesProvider);
  }

  Future<void> _confirmDelete(CategoryEntity cat) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: AppColors.bgOverlay,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.surfaceContainerHighest,
        elevation: 0,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Delete Category',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Delete "${cat.name}"? Products in this category will NOT be deleted, but will no longer appear in POS.',
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
                      child: PosSolidButton(
                        label: 'Delete',
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
      _localOrder = null;
      ref.invalidate(categoriesProvider);
    }
  }

  // -------------------------------------------------------------------------
  // Category dialog
  // -------------------------------------------------------------------------

  Future<void> _showCategoryDialog({CategoryEntity? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    String selectedEmoji = existing?.icon ?? _foodEmojis.first;
    String selectedColor = existing?.color ?? _presetColors.first;

    final saved = await showDialog<bool>(
      context: context,
      barrierColor: AppColors.bgOverlay,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => Dialog(
          backgroundColor: AppColors.surfaceContainerHighest,
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      existing != null ? 'Edit Category' : 'Add Category',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Name
                    PosTextField(
                      label: 'Category Name',
                      hint: 'e.g. Beverages',
                      controller: nameCtrl,
                      autofocus: true,
                    ),
                    const SizedBox(height: 20),

                    // Emoji picker
                    const _FieldLabel('Icon'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _foodEmojis.map((emoji) {
                        final isSel = selectedEmoji == emoji;
                        return GestureDetector(
                          onTap: () =>
                              setDialog(() => selectedEmoji = emoji),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: isSel
                                  ? AppColors.accentDim
                                  : AppColors.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text(emoji,
                                  style: const TextStyle(fontSize: 20)),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),

                    // Color picker
                    const _FieldLabel('Color'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _presetColors.map((hex) {
                        final isSel = selectedColor == hex;
                        final color = _hexToColor(hex);
                        return GestureDetector(
                          onTap: () =>
                              setDialog(() => selectedColor = hex),
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(8),
                              border: isSel
                                  ? Border.all(
                                      color: AppColors.textPrimary,
                                      width: 2,
                                    )
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
                            label: 'Cancel',
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: PosGradientButton(
                            label: 'Save',
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

    if (saved == true && nameCtrl.text.trim().isNotEmpty) {
      final repo = ref.read(menuRepositoryProvider);
      final tenantId = ref.read(tenantIdProvider);

      if (existing != null) {
        await repo.updateCategory(existing.copyWith(
          name: nameCtrl.text.trim(),
          icon: selectedEmoji,
          color: selectedColor,
        ));
      } else {
        final cats = await ref.read(categoriesProvider.future);
        await repo.createCategory(CategoryEntity(
          id: IdGenerator.generateId(),
          tenantId: tenantId,
          name: nameCtrl.text.trim(),
          displayOrder: cats.length,
          color: selectedColor,
          icon: selectedEmoji,
          isActive: true,
        ));
      }
      _localOrder = null;
      ref.invalidate(categoriesProvider);
    }

    nameCtrl.dispose();
  }

  static Color _hexToColor(String hex) {
    final buffer = StringBuffer();
    if (hex.length == 6 || hex.length == 7) buffer.write('FF');
    buffer.write(hex.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }
}

// ---------------------------------------------------------------------------
// Category row widget
// ---------------------------------------------------------------------------

class _CategoryRow extends StatelessWidget {
  final CategoryEntity category;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;
  final VoidCallback onDelete;

  const _CategoryRow({
    required super.key,
    required this.category,
    required this.onEdit,
    required this.onToggleActive,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cat = category;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: cat.isActive
              ? AppColors.surfaceContainerLow
              : AppColors.surfaceContainerLow.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // Drag handle
            const SizedBox(width: 4),
            const Icon(Icons.drag_indicator_rounded,
                size: 20, color: AppColors.textDim),
            const SizedBox(width: 8),

            // Colour swatch
            Container(
              width: 4,
              height: 32,
              decoration: BoxDecoration(
                color: _hexToColor(cat.color),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),

            // Emoji
            Text(
              cat.icon.length <= 4 ? cat.icon : '📋',
              style: const TextStyle(fontSize: 20),
            ),
            const SizedBox(width: 10),

            // Name
            Expanded(
              child: Text(
                cat.name,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: cat.isActive
                      ? AppColors.textPrimary
                      : AppColors.textDim,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Order badge
            Container(
              width: 28,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${cat.displayOrder + 1}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDim,
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Active toggle
            GestureDetector(
              onTap: onToggleActive,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: cat.isActive ? AppColors.greenDim : AppColors.redDim,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  cat.isActive ? 'Active' : 'Off',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: cat.isActive ? AppColors.green : AppColors.red,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Edit
            _SmallBtn(Icons.edit_rounded, onTap: onEdit),
            // Delete
            _SmallBtn(Icons.delete_outline_rounded,
                color: AppColors.red, onTap: onDelete),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  static Color _hexToColor(String hex) {
    final buffer = StringBuffer();
    if (hex.length == 6 || hex.length == 7) buffer.write('FF');
    buffer.write(hex.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }
}

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

class _SmallBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _SmallBtn(this.icon, {this.color = AppColors.textDim, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
      ),
    );
  }
}

class _TipItem extends StatelessWidget {
  final IconData icon;
  final String text;
  const _TipItem({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: AppColors.textDim),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textDim,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}
