/// Inventory list screen — main entry point for stock management.
///
/// Shows all inventory items with search, filter chips (All / Low / Out),
/// stock status badges, and quick access to Alerts and Suppliers.
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
        label: const Text('Add Item'),
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
          const Text(
            'Inventory',
            style: TextStyle(
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
              label: 'Alerts',
              badge: count > 0 ? count.toString() : null,
              badgeColor: AppColors.orange,
              onTap: () => _pushScreen(context, const StockAlertScreen()),
            ),
          ),
          const SizedBox(width: 8),

          // Suppliers button
          _TopBarButton(
            icon: Icons.local_shipping_rounded,
            label: 'Suppliers',
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
                label: 'All',
                selected: _filter == _StockFilter.all,
                onTap: () => setState(() => _filter = _StockFilter.all),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: 'Low Stock',
                selected: _filter == _StockFilter.low,
                color: AppColors.orange,
                onTap: () => setState(() => _filter = _StockFilter.low),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: 'Out of Stock',
                selected: _filter == _StockFilter.out,
                color: AppColors.red,
                onTap: () => setState(() => _filter = _StockFilter.out),
              ),
            ],
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
          onTap: () =>
              _pushScreen(context, InventoryDetailScreen(itemId: item.id)),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
          color: selected
              ? accent.withValues(alpha: 0.15)
              : AppColors.surfaceContainerHigh,
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
              const Text(
                'Add Item',
                style: TextStyle(
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
                  Expanded(
                      child: _field('Quantity', _qtyCtrl, numeric: true)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _field('Min. Stock', _minQtyCtrl, numeric: true)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                      child: _field('Cost Price', _costCtrl, numeric: true)),
                  const SizedBox(width: 12),
                  Expanded(child: _unitPicker()),
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
                          style:
                              const TextStyle(fontWeight: FontWeight.w700),
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
          style: const TextStyle(
              fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: ctrl,
          keyboardType: numeric
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          style: const TextStyle(
              fontSize: 14, color: AppColors.textPrimary),
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
        ),
      ],
    );
  }

  Widget _unitPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Unit',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          initialValue: _unit,
          dropdownColor: AppColors.surfaceContainer,
          style: const TextStyle(
              fontSize: 14, color: AppColors.textPrimary),
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
      costPriceCents:
          ((double.tryParse(_costCtrl.text) ?? 0) * 100).round(),
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
