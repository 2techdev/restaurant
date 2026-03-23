/// Modifier management panel — Modifiers tab of MenuManagementScreen.
///
/// Left panel: list of modifier groups (master list).
/// Right panel: modifier options for the selected group (detail list).
///
/// Features:
/// - Create / edit / delete modifier groups
/// - Set selection type (single / multiple), required flag, min/max selections
/// - Create / edit / delete individual modifiers (name, price delta, default)
/// - Swiss CHF price delta display (e.g. +CHF 1.50 / -CHF 0.50)
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/modifier_entity.dart';
import 'package:gastrocore_pos/features/menu/presentation/providers/menu_provider.dart';
import 'package:gastrocore_pos/shared/widgets/pos_button.dart';
import 'package:gastrocore_pos/shared/widgets/pos_text_field.dart';

// ---------------------------------------------------------------------------
// Panel
// ---------------------------------------------------------------------------

class ModifierManagementPanel extends ConsumerStatefulWidget {
  const ModifierManagementPanel({super.key});

  @override
  ConsumerState<ModifierManagementPanel> createState() =>
      _ModifierManagementPanelState();
}

class _ModifierManagementPanelState
    extends ConsumerState<ModifierManagementPanel> {
  String? _selectedGroupId;

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(allModifierGroupsProvider);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: group list
          Expanded(
            flex: 4,
            child: _buildGroupPanel(groupsAsync),
          ),
          const SizedBox(width: 16),

          // Right: modifier options detail
          Expanded(
            flex: 6,
            child: _buildModifierPanel(groupsAsync),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Group panel
  // -------------------------------------------------------------------------

  Widget _buildGroupPanel(
      AsyncValue<List<ModifierGroupEntity>> groupsAsync) {
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
            child: Row(
              children: [
                const Text(
                  'Modifier Groups',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                groupsAsync.whenData(
                      (groups) => Text(
                        '${groups.length}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textDim,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ).valueOrNull ??
                    const SizedBox.shrink(),
              ],
            ),
          ),
          Expanded(
            child: groupsAsync.when(
              data: _buildGroupList,
              loading: () => const Center(
                child: CircularProgressIndicator(
                    color: AppColors.primary, strokeWidth: 2),
              ),
              error: (e, _) => Center(
                child: Text('Error: $e',
                    style:
                        const TextStyle(color: AppColors.red, fontSize: 13)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: PosGradientButton(
              label: 'Add Modifier Group',
              icon: Icons.add_rounded,
              height: 44,
              onPressed: _showGroupDialog,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupList(List<ModifierGroupEntity> groups) {
    if (groups.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tune_rounded, size: 40, color: AppColors.textDim),
            SizedBox(height: 12),
            Text(
              'No modifier groups yet',
              style: TextStyle(color: AppColors.textDim, fontSize: 13),
            ),
          ],
        ),
      );
    }

    // Auto-select first group
    if (_selectedGroupId == null && groups.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedGroupId = groups.first.id);
      });
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: groups.length,
      itemBuilder: (_, i) => _GroupRow(
        group: groups[i],
        isSelected: _selectedGroupId == groups[i].id,
        onSelect: () => setState(() => _selectedGroupId = groups[i].id),
        onEdit: () => _showGroupDialog(existing: groups[i]),
        onDelete: () => _confirmDeleteGroup(groups[i]),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Modifier options panel
  // -------------------------------------------------------------------------

  Widget _buildModifierPanel(
      AsyncValue<List<ModifierGroupEntity>> groupsAsync) {
    final groups = groupsAsync.valueOrNull;
    final selectedGroup = groups?.where((g) => g.id == _selectedGroupId).firstOrNull;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selectedGroup?.name ?? 'Select a Group',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (selectedGroup != null) ...[
                        const SizedBox(height: 4),
                        _GroupMetaBadges(group: selectedGroup),
                      ],
                    ],
                  ),
                ),
                if (selectedGroup != null)
                  PosGradientButton(
                    label: 'Add Option',
                    icon: Icons.add_rounded,
                    height: 40,
                    expand: false,
                    onPressed: () =>
                        _showModifierDialog(groupId: selectedGroup.id),
                  ),
              ],
            ),
          ),

          Expanded(
            child: selectedGroup == null
                ? const Center(
                    child: Text(
                      'Select a modifier group to manage its options.',
                      style: TextStyle(
                          color: AppColors.textDim, fontSize: 13),
                    ),
                  )
                : _buildModifierList(selectedGroup.modifiers, selectedGroup.id),
          ),
        ],
      ),
    );
  }

  Widget _buildModifierList(
      List<ModifierEntity> modifiers, String groupId) {
    if (modifiers.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.list_alt_rounded,
                size: 40, color: AppColors.textDim),
            const SizedBox(height: 12),
            const Text(
              'No options yet',
              style: TextStyle(color: AppColors.textDim, fontSize: 13),
            ),
            const SizedBox(height: 20),
            PosGradientButton(
              label: 'Add First Option',
              icon: Icons.add_rounded,
              height: 44,
              expand: false,
              onPressed: () => _showModifierDialog(groupId: groupId),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      itemCount: modifiers.length,
      itemBuilder: (_, i) => _ModifierOptionRow(
        modifier: modifiers[i],
        onEdit: () => _showModifierDialog(
            groupId: groupId, existing: modifiers[i]),
        onDelete: () => _confirmDeleteModifier(modifiers[i]),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Group dialog
  // -------------------------------------------------------------------------

  Future<void> _showGroupDialog({ModifierGroupEntity? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    var selectionType = existing?.selectionType ?? ModifierSelectionType.single;
    var isRequired = existing?.isRequired ?? false;
    var minSel = existing?.minSelections ?? 0;
    var maxSel = existing?.maxSelections ?? 1;

    final saved = await showDialog<bool>(
      context: context,
      barrierColor: AppColors.bgOverlay,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => Dialog(
          backgroundColor: AppColors.surfaceContainerHighest,
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
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
                      existing != null
                          ? 'Edit Modifier Group'
                          : 'Add Modifier Group',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Name
                    PosTextField(
                      label: 'Group Name',
                      hint: 'e.g. Size, Extras, Sauce',
                      controller: nameCtrl,
                      autofocus: true,
                    ),
                    const SizedBox(height: 20),

                    // Selection type
                    const _FieldLabel('Selection Type'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _SelectionTypeButton(
                            label: 'Single Choice',
                            subtitle: 'Radio — exactly one',
                            isSelected: selectionType ==
                                ModifierSelectionType.single,
                            onTap: () => setDialog(() =>
                                selectionType = ModifierSelectionType.single),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _SelectionTypeButton(
                            label: 'Multiple Choice',
                            subtitle: 'Checkbox — many',
                            isSelected: selectionType ==
                                ModifierSelectionType.multiple,
                            onTap: () => setDialog(() => selectionType =
                                ModifierSelectionType.multiple),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Required toggle
                    _ToggleRow(
                      label: 'Required',
                      subtitle: 'Staff must make a selection before adding to order',
                      value: isRequired,
                      onChanged: (v) => setDialog(() => isRequired = v),
                    ),
                    const SizedBox(height: 16),

                    // Min / max selections (only for multiple)
                    if (selectionType == ModifierSelectionType.multiple) ...[
                      Row(
                        children: [
                          Expanded(
                            child: _NumericStepField(
                              label: 'Min Selections',
                              value: minSel,
                              min: 0,
                              max: maxSel,
                              onChanged: (v) =>
                                  setDialog(() => minSel = v),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _NumericStepField(
                              label: 'Max Selections',
                              value: maxSel,
                              min: minSel > 0 ? minSel : 1,
                              max: 20,
                              onChanged: (v) =>
                                  setDialog(() => maxSel = v),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],

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
        await repo.updateModifierGroup(existing.copyWith(
          name: nameCtrl.text.trim(),
          selectionType: selectionType,
          isRequired: isRequired,
          minSelections: selectionType == ModifierSelectionType.multiple
              ? minSel
              : 0,
          maxSelections: selectionType == ModifierSelectionType.multiple
              ? maxSel
              : 1,
        ));
      } else {
        final groups = ref.read(allModifierGroupsProvider).valueOrNull ?? [];
        final newGroup = ModifierGroupEntity(
          id: IdGenerator.generateId(),
          tenantId: tenantId,
          name: nameCtrl.text.trim(),
          selectionType: selectionType,
          isRequired: isRequired,
          minSelections:
              selectionType == ModifierSelectionType.multiple ? minSel : 0,
          maxSelections:
              selectionType == ModifierSelectionType.multiple ? maxSel : 1,
          displayOrder: groups.length,
        );
        await repo.createModifierGroup(newGroup);
        setState(() => _selectedGroupId = newGroup.id);
      }
      ref.invalidate(allModifierGroupsProvider);
    }

    nameCtrl.dispose();
  }

  // -------------------------------------------------------------------------
  // Modifier option dialog
  // -------------------------------------------------------------------------

  Future<void> _showModifierDialog({
    required String groupId,
    ModifierEntity? existing,
  }) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final priceCtrl = TextEditingController(
      text: existing != null
          ? (existing.priceDelta / 100).toStringAsFixed(2)
          : '0.00',
    );
    var isDefault = existing?.isDefault ?? false;

    final saved = await showDialog<bool>(
      context: context,
      barrierColor: AppColors.bgOverlay,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => Dialog(
          backgroundColor: AppColors.surfaceContainerHighest,
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    existing != null ? 'Edit Option' : 'Add Option',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Name
                  PosTextField(
                    label: 'Option Name',
                    hint: 'e.g. Large, Extra Cheese, No Onion',
                    controller: nameCtrl,
                    autofocus: true,
                  ),
                  const SizedBox(height: 16),

                  // Price delta
                  PosTextField(
                    label: 'Price Delta (CHF)',
                    hint: '0.00  (use negative for discount)',
                    controller: priceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        signed: true, decimal: true),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Positive = surcharge  ·  Negative = discount  ·  0 = free',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textDim),
                  ),
                  const SizedBox(height: 16),

                  // Default toggle
                  _ToggleRow(
                    label: 'Pre-selected by default',
                    subtitle: 'This option will be selected when the dialog opens',
                    value: isDefault,
                    onChanged: (v) => setDialog(() => isDefault = v),
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
    );

    if (saved == true && nameCtrl.text.trim().isNotEmpty) {
      final repo = ref.read(menuRepositoryProvider);
      final tenantId = ref.read(tenantIdProvider);
      final priceDeltaCents =
          (double.tryParse(priceCtrl.text.replaceAll(',', '.')) ?? 0.0) * 100;

      if (existing != null) {
        await repo.updateModifier(existing.copyWith(
          name: nameCtrl.text.trim(),
          priceDelta: priceDeltaCents.round(),
          isDefault: isDefault,
        ));
      } else {
        final existingMods = ref
                .read(allModifierGroupsProvider)
                .valueOrNull
                ?.firstWhere((g) => g.id == groupId,
                    orElse: () => ModifierGroupEntity(
                          id: '',
                          tenantId: '',
                          name: '',
                          selectionType: ModifierSelectionType.single,
                          minSelections: 0,
                          maxSelections: 1,
                          isRequired: false,
                          displayOrder: 0,
                        ))
                .modifiers ??
            [];
        await repo.createModifier(ModifierEntity(
          id: IdGenerator.generateId(),
          tenantId: tenantId,
          groupId: groupId,
          name: nameCtrl.text.trim(),
          priceDelta: priceDeltaCents.round(),
          isDefault: isDefault,
          displayOrder: existingMods.length,
        ));
      }
      ref.invalidate(allModifierGroupsProvider);
    }

    nameCtrl.dispose();
    priceCtrl.dispose();
  }

  // -------------------------------------------------------------------------
  // Delete actions
  // -------------------------------------------------------------------------

  Future<void> _confirmDeleteGroup(ModifierGroupEntity group) async {
    final confirmed = await _deleteDialog(
      'Delete Modifier Group',
      'Delete "${group.name}" and all its options? Products linked to this group will no longer show these options.',
    );
    if (confirmed == true) {
      if (_selectedGroupId == group.id) {
        setState(() => _selectedGroupId = null);
      }
      await ref.read(menuRepositoryProvider).deleteModifierGroup(group.id);
      ref.invalidate(allModifierGroupsProvider);
    }
  }

  Future<void> _confirmDeleteModifier(ModifierEntity modifier) async {
    final confirmed = await _deleteDialog(
      'Delete Option',
      'Delete "${modifier.name}"?',
    );
    if (confirmed == true) {
      await ref.read(menuRepositoryProvider).deleteModifier(modifier.id);
      ref.invalidate(allModifierGroupsProvider);
    }
  }

  Future<bool?> _deleteDialog(String title, String message) {
    return showDialog<bool>(
      context: context,
      barrierColor: AppColors.bgOverlay,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.surfaceContainerHighest,
        elevation: 0,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
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
  }
}

// ---------------------------------------------------------------------------
// Group row
// ---------------------------------------------------------------------------

class _GroupRow extends StatelessWidget {
  final ModifierGroupEntity group;
  final bool isSelected;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _GroupRow({
    required this.group,
    required this.isSelected,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
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
          onTap: onSelect,
          splashColor: AppColors.primary.withValues(alpha: 0.08),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                // Required badge
                if (group.isRequired)
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: const BoxDecoration(
                      color: AppColors.orange,
                      shape: BoxShape.circle,
                    ),
                  )
                else
                  const SizedBox(width: 14),

                // Name + meta
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${group.modifiers.length} option${group.modifiers.length == 1 ? '' : 's'}'
                        ' · ${group.selectionType == ModifierSelectionType.single ? 'Single' : 'Multiple'}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textDim,
                        ),
                      ),
                    ],
                  ),
                ),

                // Edit / delete
                _SmallBtn(Icons.edit_rounded, onTap: onEdit),
                _SmallBtn(Icons.delete_outline_rounded,
                    color: AppColors.red, onTap: onDelete),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Modifier option row
// ---------------------------------------------------------------------------

class _ModifierOptionRow extends StatelessWidget {
  final ModifierEntity modifier;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ModifierOptionRow({
    required this.modifier,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final delta = modifier.priceDelta;
    final deltaStr = delta == 0
        ? 'Free'
        : delta > 0
            ? '+CHF ${(delta / 100).toStringAsFixed(2)}'
            : '-CHF ${(delta.abs() / 100).toStringAsFixed(2)}';
    final deltaColor = delta > 0
        ? AppColors.orange
        : delta < 0
            ? AppColors.green
            : AppColors.textDim;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Default indicator
          if (modifier.isDefault)
            const Icon(Icons.star_rounded,
                size: 14, color: AppColors.yellow)
          else
            const Icon(Icons.radio_button_unchecked_rounded,
                size: 14, color: AppColors.textDim),
          const SizedBox(width: 12),

          // Name
          Expanded(
            child: Text(
              modifier.name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),

          // Price delta
          Text(
            deltaStr,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: deltaColor,
            ),
          ),
          const SizedBox(width: 12),

          // Order badge
          Container(
            width: 26,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              '${modifier.displayOrder + 1}',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppColors.textDim,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Edit / delete
          _SmallBtn(Icons.edit_rounded, onTap: onEdit),
          _SmallBtn(Icons.delete_outline_rounded,
              color: AppColors.red, onTap: onDelete),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Group meta badges
// ---------------------------------------------------------------------------

class _GroupMetaBadges extends StatelessWidget {
  final ModifierGroupEntity group;
  const _GroupMetaBadges({required this.group});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      children: [
        _Badge(
          label: group.selectionType == ModifierSelectionType.single
              ? 'Single'
              : 'Multiple',
          color: AppColors.primary,
        ),
        if (group.isRequired) const _Badge(label: 'Required', color: AppColors.orange),
        if (group.selectionType == ModifierSelectionType.multiple)
          _Badge(
            label:
                'min ${group.minSelections} · max ${group.maxSelections}',
            color: AppColors.textDim,
          ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable small widgets
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
          width: 32,
          height: 32,
          child: Icon(icon, size: 15, color: color),
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

class _SelectionTypeButton extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  const _SelectionTypeButton({
    required this.label,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.accentDim
              : AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
          border: isSelected
              ? Border.all(color: AppColors.primary.withValues(alpha: 0.4))
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? AppColors.primary
                    : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textDim,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: AppColors.primary,
          inactiveThumbColor: AppColors.textDim,
          inactiveTrackColor: AppColors.surfaceContainerHigh,
        ),
      ],
    );
  }
}

class _NumericStepField extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _NumericStepField({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label),
        const SizedBox(height: 6),
        Container(
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.bgInput,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              // Decrement
              _StepBtn(
                icon: Icons.remove_rounded,
                enabled: value > min,
                onTap: () {
                  if (value > min) onChanged(value - 1);
                },
              ),
              Expanded(
                child: Text(
                  '$value',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              // Increment
              _StepBtn(
                icon: Icons.add_rounded,
                enabled: value < max,
                onTap: () {
                  if (value < max) onChanged(value + 1);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _StepBtn({required this.icon, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            icon,
            size: 18,
            color: enabled ? AppColors.textPrimary : AppColors.textDim,
          ),
        ),
      ),
    );
  }
}
