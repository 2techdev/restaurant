/// Inventory list screen for the Back Office.
///
/// Shows all stock items with their current quantities.
/// Items below min_qty are highlighted in red.
/// Supports creating new items and recording stock movements.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/inventory/domain/inventory_item.dart';
import 'package:gastrocore_pos/features/inventory/domain/stock_movement.dart';
import 'package:gastrocore_pos/features/inventory/presentation/providers/inventory_providers.dart';
import 'package:gastrocore_pos/features/inventory/presentation/screens/stock_movement_screen.dart';

class InventoryListScreen extends ConsumerStatefulWidget {
  const InventoryListScreen({super.key});

  @override
  ConsumerState<InventoryListScreen> createState() => _InventoryListScreenState();
}

class _InventoryListScreenState extends ConsumerState<InventoryListScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(inventoryNotifierProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Toolbar ──────────────────────────────────────────────────────────
        _buildToolbar(),

        // ── Content ──────────────────────────────────────────────────────────
        Expanded(
          child: state.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _ErrorView(
              message: e.toString(),
              onRetry: () =>
                  ref.read(inventoryNotifierProvider.notifier).refresh(),
            ),
            data: (items) {
              final filtered = _filterItems(items);
              if (filtered.isEmpty) {
                return _EmptyView(
                  hasSearch: _search.isNotEmpty,
                  onAdd: () => _showAddItemDialog(context),
                );
              }
              return _ItemList(
                items: filtered,
                onMovement: (item) => _openMovementScreen(context, item),
                onDelete: (item) => _confirmDelete(context, item),
              );
            },
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Toolbar
  // ---------------------------------------------------------------------------

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search items…',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                filled: true,
                fillColor: AppColors.surfaceDim,
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          const SizedBox(width: 16),
          FilledButton.icon(
            onPressed: () => _showAddItemDialog(context),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New Item'),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: () =>
                ref.read(inventoryNotifierProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Refresh'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Filtering
  // ---------------------------------------------------------------------------

  List<InventoryItem> _filterItems(List<InventoryItem> items) {
    if (_search.isEmpty) return items;
    final q = _search.toLowerCase();
    return items
        .where((i) =>
            i.name.toLowerCase().contains(q) ||
            (i.sku?.toLowerCase().contains(q) ?? false) ||
            (i.supplier?.toLowerCase().contains(q) ?? false))
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Navigation / dialogs
  // ---------------------------------------------------------------------------

  Future<void> _openMovementScreen(BuildContext context, InventoryItem item) async {
    final moved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => StockMovementScreen(item: item),
      ),
    );
    if (moved == true) {
      ref.read(inventoryNotifierProvider.notifier).refresh();
    }
  }

  Future<void> _showAddItemDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => const _AddItemDialog(),
    );
    if (result == true) {
      ref.read(inventoryNotifierProvider.notifier).refresh();
    }
  }

  Future<void> _confirmDelete(BuildContext context, InventoryItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete item?'),
        content: Text('Remove "${item.name}" from inventory?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      try {
        await ref.read(inventoryNotifierProvider.notifier).deleteItem(item.id);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Delete failed: $e')),
          );
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Item list
// ---------------------------------------------------------------------------

class _ItemList extends StatelessWidget {
  final List<InventoryItem> items;
  final void Function(InventoryItem) onMovement;
  final void Function(InventoryItem) onDelete;

  const _ItemList({
    required this.items,
    required this.onMovement,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _ItemCard(
        item: items[i],
        onMovement: () => onMovement(items[i]),
        onDelete: () => onDelete(items[i]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Item card
// ---------------------------------------------------------------------------

class _ItemCard extends StatelessWidget {
  final InventoryItem item;
  final VoidCallback onMovement;
  final VoidCallback onDelete;

  const _ItemCard({
    required this.item,
    required this.onMovement,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isLow = item.isLow;
    final statusColor = isLow ? AppColors.red : AppColors.green;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            // Status dot
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 16),

            // Item info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (item.sku != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            item.sku!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (item.supplier != null)
                    Text(
                      item.supplier!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textDim,
                      ),
                    ),
                ],
              ),
            ),

            // Qty
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${_fmt(item.currentQty)} ${item.unit}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isLow ? AppColors.red : AppColors.textPrimary,
                  ),
                ),
                Text(
                  'min ${_fmt(item.minQty)}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textDim,
                  ),
                ),
              ],
            ),

            const SizedBox(width: 16),

            // Low stock badge
            if (isLow)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'LOW',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.red,
                    letterSpacing: 0.5,
                  ),
                ),
              ),

            const SizedBox(width: 12),

            // Actions
            IconButton(
              onPressed: onMovement,
              tooltip: 'Record movement',
              icon: const Icon(Icons.swap_vert_rounded,
                  color: AppColors.primary, size: 20),
            ),
            IconButton(
              onPressed: onDelete,
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline,
                  color: AppColors.textDim, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(double v) {
    if (v == v.truncateToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2);
  }
}

// ---------------------------------------------------------------------------
// Add item dialog
// ---------------------------------------------------------------------------

class _AddItemDialog extends ConsumerStatefulWidget {
  const _AddItemDialog();

  @override
  ConsumerState<_AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends ConsumerState<_AddItemDialog> {
  final _nameCtrl = TextEditingController();
  final _skuCtrl = TextEditingController();
  final _unitCtrl = TextEditingController(text: 'unit');
  final _qtyCtrl = TextEditingController(text: '0');
  final _minQtyCtrl = TextEditingController(text: '0');
  final _supplierCtrl = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _skuCtrl.dispose();
    _unitCtrl.dispose();
    _qtyCtrl.dispose();
    _minQtyCtrl.dispose();
    _supplierCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name is required');
      return;
    }
    final qty = double.tryParse(_qtyCtrl.text) ?? 0;
    final minQty = double.tryParse(_minQtyCtrl.text) ?? 0;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await ref.read(inventoryNotifierProvider.notifier).createItem(
            name: name,
            sku: _skuCtrl.text.trim().isEmpty ? null : _skuCtrl.text.trim(),
            unit: _unitCtrl.text.trim().isEmpty ? 'unit' : _unitCtrl.text.trim(),
            currentQty: qty,
            minQty: minQty,
            supplier: _supplierCtrl.text.trim().isEmpty
                ? null
                : _supplierCtrl.text.trim(),
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Inventory Item'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!,
                    style: const TextStyle(color: AppColors.red)),
              ),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Name *'),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _skuCtrl,
                    decoration: const InputDecoration(labelText: 'SKU'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _unitCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Unit (kg, litre…)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _qtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Current Qty'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _minQtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Min Qty'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _supplierCtrl,
              decoration: const InputDecoration(labelText: 'Supplier'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _save,
          child: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Empty / error views
// ---------------------------------------------------------------------------

class _EmptyView extends StatelessWidget {
  final bool hasSearch;
  final VoidCallback onAdd;
  const _EmptyView({required this.hasSearch, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined,
              size: 56, color: AppColors.textDim),
          const SizedBox(height: 16),
          Text(
            hasSearch ? 'No items match your search' : 'No inventory items yet',
            style: const TextStyle(
                fontSize: 16, color: AppColors.textSecondary),
          ),
          if (!hasSearch) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add First Item'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded,
              size: 48, color: AppColors.textDim),
          const SizedBox(height: 16),
          Text('Could not load inventory',
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Text(message,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textDim),
              textAlign: TextAlign.center),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
