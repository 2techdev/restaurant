/// Stock movement recording screen.
///
/// Allows staff to record stock in, stock out, waste, restock,
/// or an adjustment for a specific inventory item.
/// Also shows recent movement history for the item.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/inventory/domain/inventory_item.dart';
import 'package:gastrocore_pos/features/inventory/domain/stock_movement.dart';
import 'package:gastrocore_pos/features/inventory/presentation/providers/inventory_providers.dart';

class StockMovementScreen extends ConsumerStatefulWidget {
  final InventoryItem item;

  const StockMovementScreen({super.key, required this.item});

  @override
  ConsumerState<StockMovementScreen> createState() =>
      _StockMovementScreenState();
}

class _StockMovementScreenState extends ConsumerState<StockMovementScreen> {
  MovementType _selectedType = MovementType.stockIn;
  final _qtyCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Save movement
  // ---------------------------------------------------------------------------

  Future<void> _save() async {
    final qtyText = _qtyCtrl.text.trim();
    final qty = double.tryParse(qtyText);
    if (qty == null || qty <= 0) {
      setState(() => _error = 'Enter a valid quantity greater than zero');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await ref.read(inventoryNotifierProvider.notifier).recordMovement(
            itemId: widget.item.id,
            movementType: _selectedType,
            qty: qty,
            notes: _notesCtrl.text.trim().isEmpty
                ? null
                : _notesCtrl.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final movementsState = ref.watch(itemMovementsProvider(widget.item.id));

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      appBar: AppBar(
        title: Text(widget.item.name),
        backgroundColor: AppColors.surface,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: const Divider(height: 1),
        ),
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Movement form ───────────────────────────────────────────────
          SizedBox(
            width: 380,
            child: _MovementForm(
              item: widget.item,
              selectedType: _selectedType,
              qtyCtrl: _qtyCtrl,
              notesCtrl: _notesCtrl,
              isLoading: _isLoading,
              error: _error,
              onTypeChanged: (t) => setState(() => _selectedType = t),
              onSave: _save,
            ),
          ),

          const VerticalDivider(width: 1),

          // ── Movement history ────────────────────────────────────────────
          Expanded(
            child: _MovementHistory(
              state: movementsState,
              unit: widget.item.unit,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Movement form panel
// ---------------------------------------------------------------------------

class _MovementForm extends StatelessWidget {
  final InventoryItem item;
  final MovementType selectedType;
  final TextEditingController qtyCtrl;
  final TextEditingController notesCtrl;
  final bool isLoading;
  final String? error;
  final void Function(MovementType) onTypeChanged;
  final VoidCallback onSave;

  const _MovementForm({
    required this.item,
    required this.selectedType,
    required this.qtyCtrl,
    required this.notesCtrl,
    required this.isLoading,
    required this.error,
    required this.onTypeChanged,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Current stock summary
          _StockSummaryCard(item: item),
          const SizedBox(height: 24),

          // Movement type selector
          Text('Movement Type',
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          _MovementTypeGrid(
            selected: selectedType,
            onChanged: onTypeChanged,
          ),
          const SizedBox(height: 20),

          // Quantity
          Text('Quantity (${item.unit})',
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          TextField(
            controller: qtyCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            decoration: InputDecoration(
              hintText: selectedType == MovementType.adjustment
                  ? 'Positive = add, negative = remove'
                  : 'Enter quantity',
              border: const OutlineInputBorder(),
              filled: true,
              fillColor: AppColors.surface,
              suffix: Text(item.unit,
                  style:
                      const TextStyle(color: AppColors.textSecondary)),
            ),
          ),
          const SizedBox(height: 16),

          // Notes
          Text('Notes (optional)',
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          TextField(
            controller: notesCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              hintText: 'Supplier delivery, breakage, count correction…',
              border: OutlineInputBorder(),
              filled: true,
              fillColor: AppColors.surface,
            ),
          ),
          const SizedBox(height: 8),

          // Error
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(error!,
                  style: const TextStyle(color: AppColors.red)),
            ),

          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: isLoading ? null : onSave,
            icon: isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(isLoading ? 'Saving…' : 'Record Movement'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stock summary card
// ---------------------------------------------------------------------------

class _StockSummaryCard extends StatelessWidget {
  final InventoryItem item;
  const _StockSummaryCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final isLow = item.isLow;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isLow
            ? AppColors.red.withValues(alpha: 0.06)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLow ? AppColors.red.withValues(alpha: 0.3) : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            color: isLow ? AppColors.red : AppColors.primary,
            size: 28,
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Current Stock',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  )),
              Text(
                '${_fmt(item.currentQty)} ${item.unit}',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: isLow ? AppColors.red : AppColors.textPrimary,
                ),
              ),
            ],
          ),
          if (isLow) ...[
            const Spacer(),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('LOW STOCK',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.red,
                    letterSpacing: 0.8,
                  )),
            ),
          ],
        ],
      ),
    );
  }

  String _fmt(double v) {
    if (v == v.truncateToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2);
  }
}

// ---------------------------------------------------------------------------
// Movement type grid
// ---------------------------------------------------------------------------

class _MovementTypeGrid extends StatelessWidget {
  final MovementType selected;
  final void Function(MovementType) onChanged;

  const _MovementTypeGrid({
    required this.selected,
    required this.onChanged,
  });

  static const _types = [
    (MovementType.stockIn, Icons.arrow_downward_rounded, AppColors.green),
    (MovementType.restock, Icons.inventory_2_rounded, AppColors.green),
    (MovementType.stockOut, Icons.arrow_upward_rounded, AppColors.primary),
    (MovementType.waste, Icons.delete_sweep_rounded, AppColors.red),
    (MovementType.adjustment, Icons.tune_rounded, AppColors.textSecondary),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _types.map((entry) {
        final (type, icon, color) = entry;
        final isSelected = selected == type;
        return GestureDetector(
          onTap: () => onChanged(type),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? color.withValues(alpha: 0.12) : AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? color : AppColors.border,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 16,
                    color: isSelected ? color : AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(
                  type.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected ? color : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Movement history
// ---------------------------------------------------------------------------

class _MovementHistory extends StatelessWidget {
  final AsyncValue<List<StockMovement>> state;
  final String unit;

  const _MovementHistory({required this.state, required this.unit});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          color: AppColors.surface,
          child: const Text(
            'Movement History',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: state.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Text('Could not load history',
                  style: const TextStyle(color: AppColors.textDim)),
            ),
            data: (movements) {
              if (movements.isEmpty) {
                return const Center(
                  child: Text('No movements yet',
                      style: TextStyle(color: AppColors.textDim)),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: movements.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, i) =>
                    _MovementRow(movement: movements[i], unit: unit),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Movement row
// ---------------------------------------------------------------------------

class _MovementRow extends StatelessWidget {
  final StockMovement movement;
  final String unit;

  const _MovementRow({required this.movement, required this.unit});

  @override
  Widget build(BuildContext context) {
    final type = movement.movementType;
    final color = type.isDeduction ? AppColors.red : AppColors.green;
    final prefix = type.isDeduction ? '−' : '+';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              type.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$prefix${_fmt(movement.qty)} $unit → ${_fmt(movement.qtyAfter)} $unit',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (movement.notes != null)
                  Text(movement.notes!,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textDim)),
              ],
            ),
          ),
          Text(
            _formatDate(movement.createdAt),
            style: const TextStyle(fontSize: 11, color: AppColors.textDim),
          ),
        ],
      ),
    );
  }

  String _fmt(double v) {
    if (v == v.truncateToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2);
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    return '${local.day.toString().padLeft(2, '0')}.'
        '${local.month.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}
