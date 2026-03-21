/// Inventory list screen — main entry point for stock management.
///
/// Shows all inventory items with search, filter chips (All / Low / Out),
/// stock status badges, and quick access to Alerts and Suppliers.
/// Inventory list screen for the Back Office.
///
/// Shows all stock items with their current quantities.
/// Items below min_qty are highlighted in red.
/// Supports creating new items and recording stock movements.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/features/inventory/domain/entities/inventory_item_entity.dart';
import 'package:gastrocore_pos/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:gastrocore_pos/features/inventory/presentation/screens/inventory_detail_screen.dart';
import 'package:gastrocore_pos/features/inventory/presentation/screens/stock_alert_screen.dart';
import 'package:gastrocore_pos/features/inventory/presentation/screens/supplier_list_screen.dart';
import 'package:gastrocore_pos/l10n/app_localizations.dart';

// ---------------------------------------------------------------------------
// Filter enum
// ---------------------------------------------------------------------------

enum _StockFilter { all, low, out }

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/inventory/domain/inventory_item.dart';
import 'package:gastrocore_pos/features/inventory/domain/stock_movement.dart';
import 'package:gastrocore_pos/features/inventory/presentation/providers/inventory_providers.dart';
import 'package:gastrocore_pos/features/inventory/presentation/screens/stock_movement_screen.dart';

class InventoryListScreen extends ConsumerStatefulWidget {
  const InventoryListScreen({super.key});

  @override
  ConsumerState<InventoryListScreen> createState() =>
      _InventoryListScreenState();
}

class _InventoryListScreenState extends ConsumerState<InventoryListScreen> {
  final _searchController = TextEditingController();
  _StockFilter _filter = _StockFilter.all;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<InventoryItemEntity> _applyFilter(List<InventoryItemEntity> all) {
    var list = all;
    if (_filter == _StockFilter.low) {
      list = list.where((i) => i.isLowStock).toList();
    } else if (_filter == _StockFilter.out) {
      list = list.where((i) => i.isOutOfStock).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list.where((i) => i.name.toLowerCase().contains(q)).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final items = ref.watch(inventoryItemsStreamProvider);
    final alertCount = ref.watch(stockAlertCountProvider);

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      body: Column(
        children: [
          _buildTopBar(context, l10n, alertCount),
          _buildSearchAndFilter(l10n),
          Expanded(
            child: items.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(
                  e.toString(),
                  style: const TextStyle(color: AppColors.red),
                ),
              ),
              data: (all) {
                final filtered = _applyFilter(all);
                if (filtered.isEmpty) {
                  return _buildEmpty(l10n);
                }
                return _buildList(filtered, l10n);
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddItemSheet(context),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.surfaceDim,
        icon: const Icon(Icons.add_rounded),
        label: Text(l10n.invAddItem),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Top bar
  // -------------------------------------------------------------------------

  Widget _buildTopBar(
    BuildContext context,
    AppLocalizations l10n,
    AsyncValue<int> alertCount,
  ) {
    return Container(
      height: 56,
      color: AppColors.surfaceContainer,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.pop(),
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 18,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            l10n.invTitle,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),

          // Alert button with badge
          alertCount.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (count) => _TopBarButton(
              icon: Icons.warning_amber_rounded,
              label: l10n.invAlerts,
              badge: count > 0 ? count.toString() : null,
              badgeColor: AppColors.orange,
              onTap: () => _pushScreen(context, const StockAlertScreen()),
            ),
          ),
          const SizedBox(width: 8),

          // Suppliers button
          _TopBarButton(
            icon: Icons.local_shipping_rounded,
            label: l10n.invSuppliers,
            onTap: () => _pushScreen(context, const SupplierListScreen()),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Search + filter chips
  // -------------------------------------------------------------------------

  Widget _buildSearchAndFilter(AppLocalizations l10n) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search
          Container(
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.bgInput,
              borderRadius: BorderRadius.circular(10),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: l10n.actionSearch,
                hintStyle: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textDim,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: AppColors.textDim,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Filter chips
          Row(
            children: [
              _FilterChip(
                label: l10n.invFilterAll,
                selected: _filter == _StockFilter.all,
                onTap: () => setState(() => _filter = _StockFilter.all),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: l10n.invFilterLow,
                selected: _filter == _StockFilter.low,
                color: AppColors.orange,
                onTap: () => setState(() => _filter = _StockFilter.low),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: l10n.invFilterOut,
                selected: _filter == _StockFilter.out,
                color: AppColors.red,
                onTap: () => setState(() => _filter = _StockFilter.out),
              ),
            ],
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

  // -------------------------------------------------------------------------
  // Item list
  // -------------------------------------------------------------------------

  Widget _buildList(List<InventoryItemEntity> items, AppLocalizations l10n) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        return _InventoryItemCard(
          item: item,
          onTap: () => _pushScreen(context, InventoryDetailScreen(itemId: item.id)),
        );
      },
    );
  }

  Widget _buildEmpty(AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.inventory_2_outlined,
            size: 56,
            color: AppColors.textDim,
          ),
          const SizedBox(height: 16),
          Text(
            l10n.statusNoData,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Add item bottom sheet
  // -------------------------------------------------------------------------

  void _showAddItemSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _AddItemSheet(
        tenantId: ref.read(tenantIdProvider),
        onSaved: () {
          ref.invalidate(inventoryItemsStreamProvider);
          ref.invalidate(inventoryItemsProvider);
        },
      ),
    );
  }

  void _pushScreen(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }
}

// ---------------------------------------------------------------------------
// Top-bar button helper
// ---------------------------------------------------------------------------

class _TopBarButton extends StatelessWidget {
  const _TopBarButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge,
    this.badgeColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? badge;
  final Color? badgeColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
        ),
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
            if (badge != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor ?? AppColors.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  badge!,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filter chip
// ---------------------------------------------------------------------------

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? AppColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.15) : AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
          border: selected
              ? Border.all(color: accent.withValues(alpha: 0.5), width: 1)
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? accent : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Inventory item card
// ---------------------------------------------------------------------------

class _InventoryItemCard extends StatelessWidget {
  const _InventoryItemCard({required this.item, required this.onTap});

  final InventoryItemEntity item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = item.stockStatus;
    final statusColor = switch (status) {
      StockStatus.out => AppColors.red,
      StockStatus.low => AppColors.orange,
      StockStatus.normal => AppColors.green,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: AppColors.primary.withValues(alpha: 0.06),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Status indicator dot
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),

                // Name + unit
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                      const SizedBox(height: 2),
                      Text(
                        item.unit,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textDim,
                        ),
                      ),
                    ],
                  ),
                ),

                // Quantity
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _fmtQty(item.quantity),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: status == StockStatus.out
                            ? AppColors.red
                            : AppColors.textPrimary,
                      ),
                    ),
                    if (item.minQuantity > 0)
                      Text(
                        'min ${_fmtQty(item.minQuantity)}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textDim,
                        ),
                      ),
                  ],
                ),

                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: AppColors.textDim,
                ),
              ],
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

  String _fmtQty(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
}

// ---------------------------------------------------------------------------
// Add item bottom sheet
// ---------------------------------------------------------------------------

class _AddItemSheet extends ConsumerStatefulWidget {
  const _AddItemSheet({required this.tenantId, required this.onSaved});

  final String tenantId;
  final VoidCallback onSaved;

  @override
  ConsumerState<_AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends ConsumerState<_AddItemSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '0');
  final _minQtyCtrl = TextEditingController(text: '0');
  final _costCtrl = TextEditingController(text: '0');
  String _unit = 'pcs';
  bool _saving = false;

  static const _units = ['pcs', 'kg', 'g', 'L', 'mL', 'box', 'portion'];
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
    _qtyCtrl.dispose();
    _minQtyCtrl.dispose();
    _costCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.invAddItem,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 20),
              _field(l10n.menuProduct, _nameCtrl, required: true),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _field(l10n.invQuantity, _qtyCtrl, numeric: true)),
                  const SizedBox(width: 12),
                  Expanded(child: _field(l10n.invMinStock, _minQtyCtrl, numeric: true)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _field(l10n.invCostPrice, _costCtrl, numeric: true)),
                  const SizedBox(width: 12),
                  Expanded(child: _unitPicker(l10n)),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.surfaceDim,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          l10n.actionSave,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl, {
    bool required = false,
    bool numeric = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: ctrl,
          keyboardType: numeric
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.bgInput,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          validator: required
              ? (v) => (v == null || v.trim().isEmpty) ? '!' : null
              : null,
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

  Widget _unitPicker(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.invUnit,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          initialValue: _unit,
          dropdownColor: AppColors.surfaceContainer,
          style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.bgInput,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          items: _units
              .map((u) => DropdownMenuItem(value: u, child: Text(u)))
              .toList(),
          onChanged: (v) => setState(() => _unit = v ?? 'pcs'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);

    final actions = ref.read(inventoryActionsProvider.notifier);
    final item = actions.buildNewItem(
      tenantId: widget.tenantId,
      name: _nameCtrl.text.trim(),
      quantity: double.tryParse(_qtyCtrl.text) ?? 0,
      minQuantity: double.tryParse(_minQtyCtrl.text) ?? 0,
      unit: _unit,
      costPriceCents: ((double.tryParse(_costCtrl.text) ?? 0) * 100).round(),
    );

    final ok = await actions.createItem(item);
    if (mounted) {
      setState(() => _saving = false);
      if (ok) {
        widget.onSaved();
        Navigator.of(context).pop();
      }
    }
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
