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
///
/// Mirrors the SambaPOS Order Tag Group settings loaded from
/// [ModifierGroupEntity]: the dialog reads minSelections / maxSelections
/// to gate submission, columnCount to lay the grid out, and prefix to
/// label selected options on receipts.
class ModifierGroupData {
  final String id;
  final String name;
  final bool isRequired;
  final bool isMultiSelect;
  final int minSelections;
  final int maxSelections;
  final int columnCount;
  final String prefix;

  /// SambaPOS askQuantity richness — each selected option exposes a
  /// ×N stepper (1..10) and its effective price is `priceDelta × qty`.
  final bool askQuantity;

  /// SambaPOS freeTagging richness — each selected option exposes an
  /// inline note field (≤ 100 chars) surfaced on receipts / KDS.
  final bool freeTagging;

  final List<ModifierOptionData> options;

  const ModifierGroupData({
    this.id = '',
    required this.name,
    this.isRequired = false,
    this.isMultiSelect = false,
    this.minSelections = 0,
    this.maxSelections = 0,
    this.columnCount = 1,
    this.prefix = '',
    this.askQuantity = false,
    this.freeTagging = false,
    required this.options,
  });

  bool get hasUpperBound => maxSelections > 0;

  /// Convert real product modifier groups to dialog data.
  static List<ModifierGroupData> fromProductEntity(ProductEntity product) {
    return product.modifierGroups.map((group) => ModifierGroupData(
      id: group.id,
      name: group.name,
      isRequired: group.isRequired,
      isMultiSelect: group.selectionType == ModifierSelectionType.multiple,
      minSelections: group.minSelections,
      maxSelections: group.maxSelections,
      columnCount: group.effectiveColumnCount,
      prefix: group.prefix,
      askQuantity: group.askQuantity,
      freeTagging: group.freeTagging,
      options: group.modifiers.map((mod) => ModifierOptionData(
        id: mod.id,
        name: mod.name,
        priceDelta: mod.priceDelta,
        isDefault: mod.isDefault,
      )).toList(),
    )).toList();
  }
}

/// A selected option paired with its group-prefixed display name.
///
/// The prefix is applied here (not at callers) so every site that builds
/// `OrderItemModifierEntity` from a dialog result agrees on what lands on
/// the receipt and KDS.
class SelectedModifier {
  final ModifierOptionData option;

  /// `group.prefix + option.name` when the group has a prefix, otherwise
  /// the bare option name.
  final String displayName;

  /// Per-application multiplier from the group's askQuantity stepper.
  /// Callers pass this through to `OrderItemModifierEntity.quantity`.
  final int quantity;

  /// Free-form per-application note from the group's freeTagging field.
  /// Null when the group doesn't opt into freeTagging or the operator
  /// left the field empty.
  final String? note;

  const SelectedModifier({
    required this.option,
    required this.displayName,
    this.quantity = 1,
    this.note,
  });
}

/// Result returned when the user confirms modifier selection.
class ModifierDialogResult {
  /// Raw selections keyed by group name. Retained for callers that
  /// introspect by group; new code should prefer [flattened].
  final Map<String, List<ModifierOptionData>> selectedModifiers;
  final int quantity;
  final String notes;

  /// Per-option quantity multipliers for groups with askQuantity enabled.
  /// Shape: `[groupName][optionId] -> int` (defaults to 1 when absent).
  final Map<String, Map<String, int>> optionQuantities;

  /// Per-option freeTagging notes. Shape: `[groupName][optionId] -> String`
  /// (absent / empty means no note).
  final Map<String, Map<String, String>> optionNotes;

  /// The groups that produced this result. Captured so [flattened] can
  /// apply the group's prefix without the caller having to rejoin by
  /// group name.
  final List<ModifierGroupData> _groups;

  const ModifierDialogResult({
    required this.selectedModifiers,
    required this.quantity,
    required this.notes,
    this.optionQuantities = const {},
    this.optionNotes = const {},
    List<ModifierGroupData> groups = const [],
  }) : _groups = groups;

  /// Flat iteration over selected modifiers in group order, with each
  /// group's [ModifierGroupData.prefix] pre-applied to [displayName].
  /// Construct `OrderItemModifierEntity` from `displayName`, not
  /// `option.name`, so receipts show "+ Extra Cheese" / "- Onions" as
  /// the operator configured.
  ///
  /// When the group opted into askQuantity / freeTagging, the returned
  /// [SelectedModifier] carries the per-application multiplier and note
  /// so callers can forward them into `OrderItemModifierEntity.quantity`
  /// / `.note` without re-threading the raw maps.
  Iterable<SelectedModifier> flattened() sync* {
    for (final group in _groups) {
      final opts = selectedModifiers[group.name] ?? const [];
      final qtyMap = optionQuantities[group.name] ?? const <String, int>{};
      final noteMap = optionNotes[group.name] ?? const <String, String>{};
      for (final opt in opts) {
        final rawNote = noteMap[opt.id];
        yield SelectedModifier(
          option: opt,
          displayName:
              group.prefix.isEmpty ? opt.name : '${group.prefix}${opt.name}',
          quantity: group.askQuantity ? (qtyMap[opt.id] ?? 1) : 1,
          note: group.freeTagging && rawNote != null && rawNote.isNotEmpty
              ? rawNote
              : null,
        );
      }
    }
  }
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

  /// Per-option quantity multipliers for askQuantity groups.
  /// Shape: `[groupName][optionId] -> int` (clamped 1..10).
  final Map<String, Map<String, int>> _optQty = {};

  /// Per-option note controllers for freeTagging groups.
  /// Shape: `[groupName][optionId] -> TextEditingController`.
  final Map<String, Map<String, TextEditingController>> _noteControllers = {};

  /// Max length for inline freeTagging notes — guards the receipt layout
  /// against novel-length entries.
  static const int _kMaxNoteChars = 100;

  /// Hard bounds on the askQuantity stepper.
  static const int _kMinOptQty = 1;
  static const int _kMaxOptQty = 10;

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

      if (group.askQuantity) {
        _optQty[group.name] = {for (final o in group.options) o.id: 1};
      }
      if (group.freeTagging) {
        _noteControllers[group.name] = {
          for (final o in group.options) o.id: TextEditingController(),
        };
      }
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    for (final groupCtrls in _noteControllers.values) {
      for (final c in groupCtrls.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  // -- Price calculation --

  int get _modifierDelta {
    var delta = 0;
    for (final group in widget.modifierGroups) {
      final selected = _selections[group.name] ?? {};
      final qtyMap = _optQty[group.name];
      for (final opt in group.options) {
        if (selected.contains(opt.id)) {
          final qty = group.askQuantity ? (qtyMap?[opt.id] ?? 1) : 1;
          delta += opt.priceDelta * qty;
        }
      }
    }
    return delta;
  }

  void _bumpOptQty(ModifierGroupData group, ModifierOptionData option, int delta) {
    if (!group.askQuantity) return;
    setState(() {
      final map = _optQty[group.name] ??= {};
      final next = (map[option.id] ?? 1) + delta;
      map[option.id] = next.clamp(_kMinOptQty, _kMaxOptQty);
    });
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
          // Block the add if we're already at maxSelections. SambaPOS
          // uses the same hard stop instead of silently dropping a prior
          // pick; the cap is a policy choice the operator has to
          // acknowledge.
          if (group.hasUpperBound && set.length >= group.maxSelections) {
            return;
          }
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

  /// Count of currently-picked options in [group].
  int _selectedCount(ModifierGroupData group) =>
      _selections[group.name]?.length ?? 0;

  /// Whether [group]'s current selection satisfies its minimum.
  /// Optional groups (`isRequired=false` and `minSelections=0`) always
  /// validate — the operator can skip them.
  bool _isGroupValid(ModifierGroupData group) {
    final count = _selectedCount(group);
    final effectiveMin =
        group.isRequired ? (group.minSelections < 1 ? 1 : group.minSelections)
                         : group.minSelections;
    if (count < effectiveMin) return false;
    if (group.hasUpperBound && count > group.maxSelections) return false;
    return true;
  }

  /// Whether every group is within its allowed selection range. Drives
  /// the Confirm button's enabled state.
  bool get _allGroupsValid =>
      widget.modifierGroups.every(_isGroupValid);

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
    final qtys = <String, Map<String, int>>{};
    final notes = <String, Map<String, String>>{};

    for (final group in widget.modifierGroups) {
      final selected = _selections[group.name] ?? {};
      final opts =
          group.options.where((o) => selected.contains(o.id)).toList();
      if (opts.isEmpty) continue;
      result[group.name] = opts;

      if (group.askQuantity) {
        final src = _optQty[group.name] ?? const <String, int>{};
        final picked = <String, int>{
          for (final o in opts) o.id: src[o.id] ?? 1,
        };
        qtys[group.name] = picked;
      }
      if (group.freeTagging) {
        final ctrls =
            _noteControllers[group.name] ?? const <String, TextEditingController>{};
        final picked = <String, String>{};
        for (final o in opts) {
          final txt = ctrls[o.id]?.text.trim() ?? '';
          if (txt.isNotEmpty) picked[o.id] = txt;
        }
        if (picked.isNotEmpty) notes[group.name] = picked;
      }
    }

    Navigator.of(context).pop(ModifierDialogResult(
      selectedModifiers: result,
      quantity: _quantity,
      notes: _notesController.text.trim(),
      optionQuantities: qtys,
      optionNotes: notes,
      groups: widget.modifierGroups,
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
    final count = _selectedCount(group);
    final belowMin = group.isRequired && count < (group.minSelections < 1
        ? 1
        : group.minSelections);
    final counterText = group.hasUpperBound
        ? '$count / ${group.maxSelections}'
        : '$count';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Group label + required badge + live counter
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
            const Spacer(),
            Text(
              counterText,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: belowMin ? AppColors.orange : AppColors.textDim,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Grid of option chips — columnCount drives the layout.
        // columnCount == 1 keeps the previous horizontal scroll; > 1
        // renders a grid the dialog width divides evenly.
        if (group.columnCount <= 1 && !group.askQuantity && !group.freeTagging)
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: group.options.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final opt = group.options[index];
                return _buildChip(
                    group, opt, _isSelected(group.name, opt.id));
              },
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 8.0;
              final cols = group.columnCount < 1 ? 1 : group.columnCount;
              final tileWidth =
                  (constraints.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final opt in group.options)
                    SizedBox(
                      width: tileWidth,
                      child: _buildOptionCell(
                          group, opt, _isSelected(group.name, opt.id)),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }

  /// Chip + optional stepper + optional freeTagging note field for a
  /// single option. Used when the parent group opted into askQuantity
  /// or freeTagging; collapses to just [_buildChip] otherwise.
  Widget _buildOptionCell(
    ModifierGroupData group,
    ModifierOptionData option,
    bool selected,
  ) {
    if (!group.askQuantity && !group.freeTagging) {
      return _buildChip(group, option, selected);
    }

    final qty = _optQty[group.name]?[option.id] ?? 1;
    final noteCtrl = _noteControllers[group.name]?[option.id];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildChip(group, option, selected),
        if (selected && group.askQuantity) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              _buildStepperButton(Icons.remove, qty > _kMinOptQty,
                  () => _bumpOptQty(group, option, -1)),
              const SizedBox(width: 8),
              SizedBox(
                width: 28,
                child: Text(
                  '×$qty',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _buildStepperButton(Icons.add, qty < _kMaxOptQty,
                  () => _bumpOptQty(group, option, 1)),
            ],
          ),
        ],
        if (selected && group.freeTagging && noteCtrl != null) ...[
          const SizedBox(height: 6),
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
            ),
            child: TextField(
              controller: noteCtrl,
              maxLength: _kMaxNoteChars,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textPrimary,
              ),
              decoration: const InputDecoration(
                hintText: 'Not...',
                hintStyle: TextStyle(
                    fontSize: 12, color: AppColors.textDim),
                counterText: '',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStepperButton(IconData icon, bool enabled, VoidCallback onTap) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: enabled
              ? AppColors.surfaceContainerHigh
              : AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          icon,
          size: 14,
          color: enabled ? AppColors.textPrimary : AppColors.textDim,
        ),
      ),
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

          // Confirm — disabled until every group's selection count is
          // within [minSelections, maxSelections].
          GestureDetector(
            onTap: _allGroupsValid ? _onConfirm : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 28),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: _allGroupsValid
                    ? const LinearGradient(
                        colors: [
                          AppColors.primary,
                          AppColors.primaryContainer
                        ],
                        begin: Alignment(-0.7, -0.7),
                        end: Alignment(0.7, 0.7),
                      )
                    : null,
                color: _allGroupsValid ? null : AppColors.surfaceContainerHigh,
              ),
              child: Center(
                child: Text(
                  'Zur Bestellung',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _allGroupsValid
                        ? const Color(0xFF0D1B3A)
                        : AppColors.textDim,
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
