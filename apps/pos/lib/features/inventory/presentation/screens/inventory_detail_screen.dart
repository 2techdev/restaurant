/// Inventory item detail screen.
///
/// Shows current stock level, full movement history, and quick action buttons
/// for Restock, Waste, and Adjustment.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/inventory/domain/entities/inventory_item_entity.dart';
import 'package:gastrocore_pos/features/inventory/domain/entities/inventory_transaction_entity.dart';
import 'package:gastrocore_pos/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:gastrocore_pos/features/inventory/presentation/screens/restock_screen.dart';
import 'package:gastrocore_pos/features/inventory/presentation/screens/waste_screen.dart';
import 'package:gastrocore_pos/l10n/app_localizations.dart';

class InventoryDetailScreen extends ConsumerWidget {
  const InventoryDetailScreen({super.key, required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final itemAsync = ref.watch(inventoryItemDetailProvider(itemId));
    final txAsync = ref.watch(itemTransactionsProvider(itemId));

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      body: itemAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            Center(child: Text(e.toString(), style: const TextStyle(color: AppColors.red))),
        data: (item) {
          if (item == null) {
            return Center(
              child: Text(l10n.statusNoData,
                  style: const TextStyle(color: AppColors.textSecondary)),
            );
          }
          return _DetailBody(item: item, txAsync: txAsync, l10n: l10n);
        },
      ),
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({
    required this.item,
    required this.txAsync,
    required this.l10n,
  });

  final InventoryItemEntity item;
  final AsyncValue<List<InventoryTransactionEntity>> txAsync;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CustomScrollView(
      slivers: [
        _buildAppBar(context),
        SliverToBoxAdapter(child: _buildStockCard()),
        SliverToBoxAdapter(child: _buildActionRow(context, ref)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text(
              l10n.invTransactionHistory,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ),
        _buildTransactions(),
      ],
    );
  }

  SliverAppBar _buildAppBar(BuildContext context) {
    return SliverAppBar(
      backgroundColor: AppColors.surfaceContainer,
      pinned: true,
      leading: IconButton(
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(
          Icons.arrow_back_ios_new_rounded,
          size: 18,
          color: AppColors.textSecondary,
        ),
      ),
      title: Text(
        item.name,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }

  Widget _buildStockCard() {
    final status = item.stockStatus;
    final statusColor = switch (status) {
      StockStatus.out => AppColors.red,
      StockStatus.low => AppColors.orange,
      StockStatus.normal => AppColors.green,
    };
    final statusLabel = switch (status) {
      StockStatus.out => l10n.invOutOfStock,
      StockStatus.low => l10n.invLowStock,
      StockStatus.normal => l10n.invNormal,
    };

    final currencyFmt = NumberFormat.currency(symbol: 'CHF ', decimalDigits: 2);

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: statusColor,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Quantity display
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _fmtQty(item.quantity),
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w800,
                  color: status == StockStatus.out
                      ? AppColors.red
                      : AppColors.textPrimary,
                  height: 1,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                item.unit,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          if (item.minQuantity > 0)
            Text(
              '${l10n.invMinStock}: ${_fmtQty(item.minQuantity)} ${item.unit}',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textDim,
              ),
            ),

          if (item.minQuantity > 0) ...[
            const SizedBox(height: 12),
            _StockBar(
              current: item.quantity,
              min: item.minQuantity,
              statusColor: statusColor,
            ),
          ],

          const SizedBox(height: 16),
          const Divider(color: AppColors.surfaceContainerHigh, height: 1),
          const SizedBox(height: 16),

          // Meta row
          Row(
            children: [
              _MetaCell(
                label: l10n.invCostPrice,
                value: currencyFmt
                    .format(item.costPriceCents / 100)
                    .replaceFirst('CHF ', 'CHF '),
              ),
              const SizedBox(width: 24),
              _MetaCell(
                label: l10n.invStockValue,
                value: currencyFmt.format(item.stockValueCents / 100),
              ),
              if (item.lastRestockDate != null) ...[
                const SizedBox(width: 24),
                _MetaCell(
                  label: l10n.invLastRestock,
                  value: DateFormat('dd.MM.yy').format(item.lastRestockDate!),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionRow(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _ActionButton(
              icon: Icons.add_circle_outline_rounded,
              label: l10n.invRestock,
              color: AppColors.green,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => RestockScreen(itemId: item.id),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ActionButton(
              icon: Icons.delete_sweep_outlined,
              label: l10n.invRecordWaste,
              color: AppColors.orange,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => WasteScreen(itemId: item.id),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ActionButton(
              icon: Icons.tune_rounded,
              label: l10n.invAdjustment,
              color: AppColors.primary,
              onTap: () => _showAdjustDialog(context, ref),
            ),
          ),
        ],
      ),
    );
  }

  void _showAdjustDialog(BuildContext context, WidgetRef ref) {
    final ctrl = TextEditingController(text: _fmtQty(item.quantity));
    final notesCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceContainer,
        title: Text(
          l10n.invAdjustment,
          style: const TextStyle(color: AppColors.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                labelText: l10n.invQuantity,
                labelStyle: const TextStyle(color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.bgInput,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notesCtrl,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                labelText: l10n.invNotes,
                labelStyle: const TextStyle(color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.bgInput,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.actionCancel,
                style: const TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              final qty = double.tryParse(ctrl.text);
              if (qty == null) return;
              Navigator.pop(context);
              await ref.read(inventoryActionsProvider.notifier).adjust(
                    itemId: item.id,
                    newQuantity: qty,
                    notes: notesCtrl.text.trim().isEmpty
                        ? null
                        : notesCtrl.text.trim(),
                  );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.surfaceDim,
            ),
            child: Text(l10n.actionSave),
          ),
        ],
      ),
    );
  }

  SliverList _buildTransactions() {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          return txAsync.when(
            loading: () => index == 0
                ? const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : null,
            error: (e, _) => index == 0
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(e.toString(),
                        style: const TextStyle(color: AppColors.red)),
                  )
                : null,
            data: (txs) {
              if (txs.isEmpty && index == 0) {
                return Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      l10n.statusNoData,
                      style: const TextStyle(color: AppColors.textDim),
                    ),
                  ),
                );
              }
              if (index >= txs.length) return null;
              return _TransactionRow(tx: txs[index], unit: item.unit);
            },
          );
        },
        childCount: txAsync.when(
          loading: () => 1,
          error: (_, __) => 1,
          data: (txs) => txs.isEmpty ? 1 : txs.length,
        ),
      ),
    );
  }

  String _fmtQty(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
}

// ---------------------------------------------------------------------------
// Supporting widgets
// ---------------------------------------------------------------------------

class _StockBar extends StatelessWidget {
  const _StockBar({
    required this.current,
    required this.min,
    required this.statusColor,
  });

  final double current;
  final double min;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    final safeLevel = min * 3;
    final ratio = (current / safeLevel).clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: ratio,
        backgroundColor: AppColors.surfaceContainerHigh,
        valueColor: AlwaysStoppedAnimation<Color>(statusColor),
        minHeight: 6,
      ),
    );
  }
}

class _MetaCell extends StatelessWidget {
  const _MetaCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11, color: AppColors.textDim)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            )),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.tx, required this.unit});

  final InventoryTransactionEntity tx;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final isIn = tx.quantity > 0;
    final color = switch (tx.type) {
      TransactionType.restock => AppColors.green,
      TransactionType.sale => AppColors.primary,
      TransactionType.waste => AppColors.orange,
      TransactionType.adjustment => AppColors.yellow,
    };
    final icon = switch (tx.type) {
      TransactionType.restock => Icons.add_circle_outline_rounded,
      TransactionType.sale => Icons.shopping_cart_outlined,
      TransactionType.waste => Icons.delete_sweep_outlined,
      TransactionType.adjustment => Icons.tune_rounded,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tx.type.name.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: color,
                      letterSpacing: 0.5,
                    ),
                  ),
                  if (tx.notes != null && tx.notes!.isNotEmpty)
                    Text(
                      tx.notes!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textDim,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  Text(
                    DateFormat('dd.MM.yy HH:mm').format(tx.timestamp),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textDim,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${isIn ? '+' : ''}${_fmtQty(tx.quantity)} $unit',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isIn ? AppColors.green : AppColors.red,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtQty(double v) {
    final abs = v.abs();
    return abs == abs.roundToDouble()
        ? abs.toInt().toString()
        : abs.toStringAsFixed(2);
  }
}
