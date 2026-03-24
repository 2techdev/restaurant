/// Modifier Selection Dialog for GastroCore POS.
///
/// Modal bottom sheet / dialog for selecting product modifiers, quantity,
/// and special notes before adding to the order.
/// Follows Stitch S04 design reference.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/modifier_entity.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/product_entity.dart';

// ---------------------------------------------------------------------------
// Data models for modifier groups / options
// ---------------------------------------------------------------------------

/// A single modifier option within a group.
class ModifierOptionData {
  final String id;
  final String name;
  final int priceDelta; // cents (positive = surcharge, 0 = included)
  final bool isDefault;

  const ModifierOptionData({
    required this.id,
    required this.name,
    this.priceDelta = 0,
    this.isDefault = false,
  });
}

/// A group of related modifier options (e.g. "Size", "Extras", "Sauce").
class ModifierGroupData {
  final String id;
  final String name;
  final bool isRequired;
  final bool isMultiSelect;
  final int maxSelections;
  final List<ModifierOptionData> options;

  const ModifierGroupData({
    this.id = '',
    required this.name,
    this.isRequired = false,
    this.isMultiSelect = false,
    this.maxSelections = 0,
    required this.options,
  });

  /// Convert real product modifier groups to dialog data.
  static List<ModifierGroupData> fromProductEntity(ProductEntity product) {
    return product.modifierGroups.map((group) => ModifierGroupData(
      id: group.id,
      name: group.name,
      isRequired: group.isRequired,
      isMultiSelect: group.selectionType == ModifierSelectionType.multiple,
      maxSelections: group.maxSelections,
      options: group.modifiers.map((mod) => ModifierOptionData(
        id: mod.id,
        name: mod.name,
        priceDelta: mod.priceDelta,
        isDefault: mod.isDefault,
      )).toList(),
    )).toList();
  }
}

/// Result returned when the user confirms modifier selection.
class ModifierDialogResult {
  final Map<String, List<ModifierOptionData>> selectedModifiers;
  final int quantity;
  final String notes;

  const ModifierDialogResult({
    required this.selectedModifiers,
    required this.quantity,
    required this.notes,
  });
}

// ---------------------------------------------------------------------------
// Public helper to show the dialog
// ---------------------------------------------------------------------------

/// Shows the modifier selection dialog as a modal bottom sheet.
///
/// Returns [ModifierDialogResult] if the user confirms, or `null` if cancelled.
Future<ModifierDialogResult?> showModifierDialog({
  required BuildContext context,
  required String productName,
  required int productPrice,
  required List<ModifierGroupData> modifierGroups,
}) {
  return showModalBottomSheet<ModifierDialogResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.bgOverlay,
    builder: (ctx) => _ModifierDialogContent(
      productName: productName,
      productPrice: productPrice,
      modifierGroups: modifierGroups,
    ),
  );
}

// ---------------------------------------------------------------------------
// Dialog content (stateful)
// ---------------------------------------------------------------------------

class _ModifierDialogContent extends ConsumerStatefulWidget {
  final String productName;
  final int productPrice;
  final List<ModifierGroupData> modifierGroups;

  const _ModifierDialogContent({
    required this.productName,
    required this.productPrice,
    required this.modifierGroups,
  });

  @override
  ConsumerState<_ModifierDialogContent> createState() =>
      _ModifierDialogContentState();
}

class _ModifierDialogContentState
    extends ConsumerState<_ModifierDialogContent> {
  /// For single-select groups: groupName -> selected option id
  /// For multi-select groups: groupName -> set of selected option ids
  late final Map<String, Set<String>> _selections;
  int _quantity = 1;
  final TextEditingController _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selections = {};
    for (final group in widget.modifierGroups) {
      final defaults = <String>{};
      for (final opt in group.options) {
        if (opt.isDefault) defaults.add(opt.id);
      }
      _selections[group.name] = defaults;
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  // -- Price calculation --

  int get _modifierDelta {
    var delta = 0;
    for (final group in widget.modifierGroups) {
      final selected = _selections[group.name] ?? {};
      for (final opt in group.options) {
        if (selected.contains(opt.id)) {
          delta += opt.priceDelta;
        }
      }
    }
    return delta;
  }

  int get _unitTotal => widget.productPrice + _modifierDelta;
  int get _grandTotal => _unitTotal * _quantity;

  String _formatCents(int cents) {
    final isNeg = cents < 0;
    final abs = cents.abs();
    final whole = abs ~/ 100;
    final frac = (abs % 100).toString().padLeft(2, '0');
    return '${isNeg ? '-' : ''}$whole.$frac';
  }

  // -- Selection logic --

  void _toggleOption(ModifierGroupData group, ModifierOptionData option) {
    setState(() {
      final set = _selections[group.name] ??= {};
      if (group.isMultiSelect) {
        if (set.contains(option.id)) {
          set.remove(option.id);
        } else {
          set.add(option.id);
        }
      } else {
        // single select: replace
        set.clear();
        set.add(option.id);
      }
    });
  }

  bool _isSelected(String groupName, String optionId) {
    return _selections[groupName]?.contains(optionId) ?? false;
  }

  // -- Quantity --

  void _increment() {
    if (_quantity < 99) setState(() => _quantity++);
  }

  void _decrement() {
    if (_quantity > 1) setState(() => _quantity--);
  }

  // -- Submit --

  void _onConfirm() {
    final result = <String, List<ModifierOptionData>>{};
    for (final group in widget.modifierGroups) {
      final selected = _selections[group.name] ?? {};
      final opts =
          group.options.where((o) => selected.contains(o.id)).toList();
      if (opts.isNotEmpty) {
        result[group.name] = opts;
      }
    }
    Navigator.of(context).pop(ModifierDialogResult(
      selectedModifiers: result,
      quantity: _quantity,
      notes: _notesController.text.trim(),
    ));
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      constraints: BoxConstraints(maxHeight: screenHeight * 0.85),
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainerHighest,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(),
          Flexible(child: _buildBody()),
          _buildBottomBar(),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Header
  // -------------------------------------------------------------------------

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.productName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'CHF ${_formatCents(widget.productPrice)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.green,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.surfaceBright,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.close_rounded,
                size: 20,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Scrollable body
  // -------------------------------------------------------------------------

  Widget _buildBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Modifier groups
          for (final group in widget.modifierGroups) ...[
            _buildGroupSection(group),
            const SizedBox(height: 20),
          ],

          // Quantity selector
          _buildQuantitySection(),
          const SizedBox(height: 20),

          // Notes field
          _buildNotesField(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildGroupSection(ModifierGroupData group) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Group label + required badge
        Row(
          children: [
            Text(
              group.name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            if (group.isRequired) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.orangeDim,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'PFLICHT',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: AppColors.orange,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),

        // Horizontal scrollable chips
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: group.options.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final opt = group.options[index];
              final selected = _isSelected(group.name, opt.id);
              return _buildChip(group, opt, selected);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildChip(
    ModifierGroupData group,
    ModifierOptionData option,
    bool selected,
  ) {
    return GestureDetector(
      onTap: () => _toggleOption(group, option),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentDim : AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.accent : Colors.transparent,
            width: selected ? 1.5 : 0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              option.name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color:
                    selected ? AppColors.accent : AppColors.textSecondary,
              ),
            ),
            if (option.priceDelta != 0) ...[
              const SizedBox(width: 6),
              Text(
                '+CHF ${_formatCents(option.priceDelta)}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: selected
                      ? AppColors.accent.withValues(alpha: 0.7)
                      : AppColors.textDim,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Quantity selector
  // -------------------------------------------------------------------------

  Widget _buildQuantitySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Anzahl',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _buildQtyButton(Icons.remove, _decrement, _quantity > 1),
            const SizedBox(width: 16),
            SizedBox(
              width: 48,
              child: Text(
                '$_quantity',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 16),
            _buildQtyButton(Icons.add, _increment, _quantity < 99),
          ],
        ),
      ],
    );
  }

  Widget _buildQtyButton(IconData icon, VoidCallback onTap, bool enabled) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: enabled
              ? AppColors.surfaceContainerHigh
              : AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          size: 22,
          color: enabled ? AppColors.textPrimary : AppColors.textDim,
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Notes field
  // -------------------------------------------------------------------------

  Widget _buildNotesField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Bemerkung',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(10),
          ),
          child: TextField(
            controller: _notesController,
            maxLines: 2,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textPrimary,
            ),
            decoration: const InputDecoration(
              hintText: 'Besondere Wünsche...',
              hintStyle: TextStyle(
                fontSize: 14,
                color: AppColors.textDim,
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Bottom bar
  // -------------------------------------------------------------------------

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(0),
          topRight: Radius.circular(0),
        ),
      ),
      child: Row(
        children: [
          // Total preview
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'TOTAL',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDim,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'CHF ${_formatCents(_grandTotal)}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),

          // Cancel
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Text(
                  'Abbrechen',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Confirm
          GestureDetector(
            onTap: _onConfirm,
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 28),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryContainer],
                  begin: Alignment(-0.7, -0.7), // ~135 degrees
                  end: Alignment(0.7, 0.7),
                ),
              ),
              child: const Center(
                child: Text(
                  'Zur Bestellung',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0D1B3A),
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
