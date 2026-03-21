/// Stock alert screen — shows items at or below minimum threshold.
///
/// Sorted by severity: out-of-stock first, then low, then alphabetically.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/inventory/domain/entities/inventory_item_entity.dart';
import 'package:gastrocore_pos/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:gastrocore_pos/features/inventory/presentation/screens/inventory_detail_screen.dart';
import 'package:gastrocore_pos/l10n/app_localizations.dart';

class StockAlertScreen extends ConsumerWidget {
  const StockAlertScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final alertsAsync = ref.watch(alertItemsProvider);

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceContainer,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 18,
            color: AppColors.textSecondary,
          ),
        ),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: AppColors.orange, size: 20),
            const SizedBox(width: 8),
            Text(
              l10n.invAlerts,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => ref.invalidate(alertItemsProvider),
            icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
          ),
        ],
      ),
      body: alertsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(e.toString(), style: const TextStyle(color: AppColors.red)),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.check_circle_outline_rounded,
                    size: 64,
                    color: AppColors.green,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.invNoAlerts,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.invAllStockOk,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textDim,
                    ),
                  ),
                ],
              ),
            );
          }

          // Group: out-of-stock vs low
          final outItems = items.where((i) => i.isOutOfStock).toList();
          final lowItems =
              items.where((i) => i.isLowStock && !i.isOutOfStock).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (outItems.isNotEmpty) ...[
                _SectionHeader(
                  label: l10n.invOutOfStock,
                  count: outItems.length,
                  color: AppColors.red,
                ),
                const SizedBox(height: 8),
                ...outItems.map((i) => _AlertCard(item: i)),
                const SizedBox(height: 20),
              ],
              if (lowItems.isNotEmpty) ...[
                _SectionHeader(
                  label: l10n.invLowStock,
                  count: lowItems.length,
                  color: AppColors.orange,
                ),
                const SizedBox(height: 8),
                ...lowItems.map((i) => _AlertCard(item: i)),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.item});

  final InventoryItemEntity item;

  @override
  Widget build(BuildContext context) {
    final isOut = item.isOutOfStock;
    final color = isOut ? AppColors.red : AppColors.orange;
    final bgColor = isOut ? AppColors.redDim : AppColors.orangeDim;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => InventoryDetailScreen(itemId: item.id),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isOut
                        ? Icons.remove_shopping_cart_outlined
                        : Icons.warning_amber_rounded,
                    color: color,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
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
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _Pill(
                            label:
                                '${_fmtQty(item.quantity)} ${item.unit}',
                            color: color,
                          ),
                          if (item.minQuantity > 0) ...[
                            const SizedBox(width: 6),
                            Text(
                              '/ min ${_fmtQty(item.minQuantity)}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textDim,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textDim,
                  size: 18,
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

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
