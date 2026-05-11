/// Product → modifier-group assignment panel.
///
/// Fills the operator-facing gap that the existing [ModifierManagementPanel]
/// left open: groups + options can already be CRUD'd, but until now the
/// only place a product could be linked to a modifier group was the
/// backoffice form dialog. This panel lets a cashier with menu admin
/// permission attach / detach groups directly from the POS — useful when
/// a new combo or sauce gets added on shift and the tablet is the only
/// device in front of the operator.
///
/// Layout:
///   • Left:  product list (admin scope = active + inactive), filtered by
///            category + name search. Mirrors the picker used in
///            [ProductAdminPanel] so muscle memory carries over.
///   • Right: when a product is selected, two stacked sections —
///            "Atanmış modifier grupları" (assigned, with remove chip) and
///            "Ekle" (unassigned dropdown + Ekle button).
///
/// Writes go through [MenuRepositoryImpl.linkModifierGroupToProduct] /
/// [unlinkModifierGroupFromProduct], which already mark the junction row
/// for the standard sync_queue pipeline, so the cloud Postgres mirror
/// catches up on the next sync cycle. Local Drift is the source of truth
/// until the push succeeds — operators can keep editing while offline.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/modifier_entity.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/product_entity.dart';
import 'package:gastrocore_pos/features/menu/presentation/providers/menu_provider.dart';
import 'package:gastrocore_pos/shared/widgets/pos_button.dart';
import 'package:gastrocore_pos/shared/widgets/pos_text_field.dart';

class ProductModifierAssignmentPanel extends ConsumerStatefulWidget {
  const ProductModifierAssignmentPanel({super.key});

  @override
  ConsumerState<ProductModifierAssignmentPanel> createState() =>
      _ProductModifierAssignmentPanelState();
}

class _ProductModifierAssignmentPanelState
    extends ConsumerState<ProductModifierAssignmentPanel> {
  String? _selectedProductId;
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 4, child: _buildProductPanel()),
          const SizedBox(width: 16),
          Expanded(flex: 6, child: _buildAssignmentPanel()),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Left: product list
  // -------------------------------------------------------------------------

  Widget _buildProductPanel() {
    final productsAsync = ref.watch(adminProductsProvider);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ürünler',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                PosTextField(
                  hint: 'Ürün ara…',
                  onChanged: (v) => setState(() => _searchQuery = v.trim()),
                ),
              ],
            ),
          ),
          Expanded(
            child: productsAsync.when(
              data: _buildProductList,
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
        ],
      ),
    );
  }

  Widget _buildProductList(List<ProductEntity> products) {
    final q = _searchQuery.toLowerCase();
    final filtered = q.isEmpty
        ? products
        : products.where((p) => p.name.toLowerCase().contains(q)).toList();

    if (filtered.isEmpty) {
      return const Center(
        child: Text(
          'Ürün bulunamadı',
          style: TextStyle(color: AppColors.textDim, fontSize: 13),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: filtered.length,
      itemBuilder: (_, i) {
        final p = filtered[i];
        final isSelected = p.id == _selectedProductId;
        return _ProductRow(
          product: p,
          isSelected: isSelected,
          onTap: () => setState(() => _selectedProductId = p.id),
        );
      },
    );
  }

  // -------------------------------------------------------------------------
  // Right: assignment panel
  // -------------------------------------------------------------------------

  Widget _buildAssignmentPanel() {
    if (_selectedProductId == null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(48),
            child: Text(
              'Modifier grubu atamak için soldan bir ürün seçin.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textDim, fontSize: 13),
            ),
          ),
        ),
      );
    }

    final productId = _selectedProductId!;
    final assignedAsync =
        ref.watch(modifierGroupsForProductProvider(productId));
    final allGroupsAsync = ref.watch(allModifierGroupsProvider);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: assignedAsync.maybeWhen(
              data: (groups) => Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Atanmış modifier grupları',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    '${groups.length}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textDim,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              orElse: () => const Text(
                'Atanmış modifier grupları',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          Expanded(
            child: assignedAsync.when(
              data: (assigned) => _buildAssignedList(productId, assigned),
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
          const Divider(height: 1, color: AppColors.surfaceContainerHigh),
          Padding(
            padding: const EdgeInsets.all(16),
            child: allGroupsAsync.maybeWhen(
              data: (all) => _buildAddSection(
                productId,
                all,
                assignedAsync.valueOrNull ?? const [],
              ),
              orElse: () => const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssignedList(
    String productId,
    List<ModifierGroupEntity> assigned,
  ) {
    if (assigned.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'Bu ürüne henüz modifier grubu atanmamış.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textDim, fontSize: 13),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      itemCount: assigned.length,
      itemBuilder: (_, i) => _AssignedGroupRow(
        group: assigned[i],
        order: i + 1,
        onRemove: () => _unlinkGroup(productId, assigned[i]),
      ),
    );
  }

  Widget _buildAddSection(
    String productId,
    List<ModifierGroupEntity> allGroups,
    List<ModifierGroupEntity> assigned,
  ) {
    final assignedIds = assigned.map((g) => g.id).toSet();
    final available =
        allGroups.where((g) => !assignedIds.contains(g.id)).toList();

    if (available.isEmpty && allGroups.isNotEmpty) {
      return const Text(
        'Tüm modifier grupları bu ürüne atanmış.',
        style: TextStyle(color: AppColors.textDim, fontSize: 12),
      );
    }
    if (allGroups.isEmpty) {
      return const Text(
        'Önce "Modifiers" sekmesinden bir grup oluşturun.',
        style: TextStyle(color: AppColors.textDim, fontSize: 12),
      );
    }

    return _AddGroupRow(
      candidates: available,
      onPick: (group) => _linkGroup(productId, group, assigned.length),
    );
  }

  // -------------------------------------------------------------------------
  // Mutations
  // -------------------------------------------------------------------------

  Future<void> _linkGroup(
    String productId,
    ModifierGroupEntity group,
    int displayOrder,
  ) async {
    final repo = ref.read(menuRepositoryProvider);
    await repo.linkModifierGroupToProduct(productId, group.id, displayOrder);
    ref.invalidate(modifierGroupsForProductProvider(productId));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${group.name}" atandı')),
      );
    }
  }

  Future<void> _unlinkGroup(
    String productId,
    ModifierGroupEntity group,
  ) async {
    final repo = ref.read(menuRepositoryProvider);
    await repo.unlinkModifierGroupFromProduct(productId, group.id);
    ref.invalidate(modifierGroupsForProductProvider(productId));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${group.name}" kaldırıldı')),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Product row
// ---------------------------------------------------------------------------

class _ProductRow extends StatelessWidget {
  final ProductEntity product;
  final bool isSelected;
  final VoidCallback onTap;

  const _ProductRow({
    required this.product,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: isSelected ? AppColors.accentDim : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: AppColors.primary.withValues(alpha: 0.08),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    product.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: product.isActive
                          ? (isSelected
                              ? AppColors.primary
                              : AppColors.textPrimary)
                          : AppColors.textDim,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  'CHF ${(product.price / 100).toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textDim,
                  ),
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
// Assigned group row
// ---------------------------------------------------------------------------

class _AssignedGroupRow extends StatelessWidget {
  final ModifierGroupEntity group;
  final int order;
  final VoidCallback onRemove;

  const _AssignedGroupRow({
    required this.group,
    required this.order,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
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
              '$order',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textDim,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Name + meta
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${group.modifiers.length} seçenek · '
                  '${group.selectionType == ModifierSelectionType.single ? 'Tek' : 'Çoklu'}'
                  '${group.isRequired ? ' · Zorunlu' : ''}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textDim,
                  ),
                ),
              ],
            ),
          ),
          // Remove
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            color: AppColors.red,
            tooltip: 'Bu üründen kaldır',
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add group row (dropdown + button)
// ---------------------------------------------------------------------------

class _AddGroupRow extends StatefulWidget {
  final List<ModifierGroupEntity> candidates;
  final ValueChanged<ModifierGroupEntity> onPick;

  const _AddGroupRow({required this.candidates, required this.onPick});

  @override
  State<_AddGroupRow> createState() => _AddGroupRowState();
}

class _AddGroupRowState extends State<_AddGroupRow> {
  ModifierGroupEntity? _picked;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<ModifierGroupEntity>(
            initialValue: _picked,
            decoration: const InputDecoration(
              labelText: 'Modifier grubu seç',
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            items: widget.candidates
                .map(
                  (g) => DropdownMenuItem(
                    value: g,
                    child: Text(
                      g.name,
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (g) => setState(() => _picked = g),
          ),
        ),
        const SizedBox(width: 12),
        PosGradientButton(
          label: 'Ekle',
          icon: Icons.add_rounded,
          height: 44,
          expand: false,
          onPressed: _picked == null
              ? null
              : () {
                  final g = _picked!;
                  widget.onPick(g);
                  setState(() => _picked = null);
                },
        ),
      ],
    );
  }
}
