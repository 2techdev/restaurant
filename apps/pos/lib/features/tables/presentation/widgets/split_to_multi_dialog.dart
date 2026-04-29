/// Dialog for splitting a table's ticket across two tables (Turkish: ayırma).
///
/// The [sourceTable] is pre-selected. The waiter ticks a subset of line
/// items, picks a TARGET table, and confirms — the selected items are
/// moved (not copied) to the target table's ticket. If the target has no
/// active ticket, a fresh ticket is opened on the target table first.
///
/// Contrast with merge (`merge_tables_dialog.dart`) which moves ALL items
/// and voids the source, and with the PAYMENT split screen which divides
/// the bill at payment time without touching line-item ownership.
///
/// Offline-safe: uses existing [OrderRepositoryImpl] methods
/// (`addItemToTicket` / `removeItemFromTicket` / `createTicket`) and
/// [TableRepositoryImpl.linkOrderToTable] — no network calls.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/order_item_entity.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/features/orders/presentation/providers/order_provider.dart';
import 'package:gastrocore_pos/features/tables/domain/entities/table_entity.dart';
import 'package:gastrocore_pos/features/tables/presentation/providers/table_provider.dart';

/// Display the split-to-multi dialog.
Future<void> showSplitToMultiDialog(
  BuildContext context, {
  required RestaurantTableEntity sourceTable,
}) {
  return showDialog(
    context: context,
    builder: (_) => SplitToMultiDialog(sourceTable: sourceTable),
  );
}

class SplitToMultiDialog extends ConsumerStatefulWidget {
  final RestaurantTableEntity sourceTable;
  const SplitToMultiDialog({super.key, required this.sourceTable});

  @override
  ConsumerState<SplitToMultiDialog> createState() =>
      _SplitToMultiDialogState();
}

class _SplitToMultiDialogState extends ConsumerState<SplitToMultiDialog> {
  TicketEntity? _sourceTicket;
  bool _loading = true;
  bool _splitting = false;
  String? _error;

  /// IDs of source line items the user selected to move.
  final Set<String> _selectedItemIds = {};

  String? _selectedTargetId;

  @override
  void initState() {
    super.initState();
    _loadSourceTicket();
  }

  Future<void> _loadSourceTicket() async {
    try {
      final orderId = widget.sourceTable.currentOrderId;
      if (orderId == null) {
        setState(() {
          _loading = false;
          _error = 'Source table has no active order.';
        });
        return;
      }
      final ticket =
          await ref.read(orderRepositoryProvider).getTicketById(orderId);
      setState(() {
        _sourceTicket = ticket;
        _loading = false;
        if (ticket == null) _error = 'Source ticket not found.';
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _doSplit() async {
    final targetId = _selectedTargetId;
    final source = _sourceTicket;
    if (targetId == null || source == null) return;
    if (_selectedItemIds.isEmpty) return;

    setState(() {
      _splitting = true;
      _error = null;
    });

    try {
      final orderRepo = ref.read(orderRepositoryProvider);
      final tableRepo = ref.read(tableRepositoryProvider);

      final allTables = await ref.read(allTablesProvider.future);
      final targetTable = allTables.firstWhere((t) => t.id == targetId);

      // Ensure a target ticket exists.
      String targetTicketId;
      if (targetTable.currentOrderId != null) {
        targetTicketId = targetTable.currentOrderId!;
      } else {
        final nextNumber = await orderRepo.getNextOrderNumber(source.tenantId);
        final newTicket = TicketEntity(
          id: IdGenerator.generateId(),
          tenantId: source.tenantId,
          orderNumber: IdGenerator.generateOrderNumber(nextNumber),
          orderType: source.orderType,
          tableId: targetTable.id,
          waiterId: source.waiterId,
          guestCount: 1,
          status: TicketStatus.open,
          channel: OrderChannel.pos,
          openedAt: DateTime.now(),
          deviceId: source.deviceId,
        );
        final saved = await orderRepo.createTicket(newTicket);
        targetTicketId = saved.id;
        await tableRepo.linkOrderToTable(targetTable.id, targetTicketId);
      }

      // Move each selected item: insert fresh copy on target, soft-delete
      // the original on source. Modifiers are re-keyed so they belong to
      // the new order_item row.
      final toMove =
          source.items.where((i) => _selectedItemIds.contains(i.id)).toList();
      for (final item in toMove) {
        final newItemId = IdGenerator.generateId();
        final cloned = item.copyWith(
          id: newItemId,
          ticketId: targetTicketId,
          modifiers: item.modifiers
              .map((m) => m.copyWith(
                    id: IdGenerator.generateId(),
                    orderItemId: newItemId,
                  ))
              .toList(),
        );
        await orderRepo.addItemToTicket(targetTicketId, cloned);
        await orderRepo.removeItemFromTicket(item.id);
      }

      // Totals on both sides are refreshed by add/remove calls above.

      // Refresh derived providers so open tickets list / table streams sync.
      ref.invalidate(allTablesProvider);
      ref.invalidate(openTicketsProvider);

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _splitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 520,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.call_split_rounded,
                        size: 18, color: AppColors.accent),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Split Items to Another Table',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded,
                        size: 18, color: AppColors.textDim),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Pick the line items to move, then choose a destination table. The selected items leave this ticket and join the target ticket.',
                style:
                    TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),

              _label('Source Table'),
              const SizedBox(height: 6),
              Text(
                widget.sourceTable.name,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary),
              ),
              const SizedBox(height: 16),

              // Items
              _label('Items to Move'),
              const SizedBox(height: 6),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                      child: CircularProgressIndicator(
                          color: AppColors.accent, strokeWidth: 2)),
                )
              else if (_sourceTicket == null ||
                  _sourceTicket!.items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    'Source ticket has no items.',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                )
              else
                SizedBox(
                  height: 180,
                  child: ListView.builder(
                    itemCount: _sourceTicket!.items.length,
                    itemBuilder: (_, i) {
                      final item = _sourceTicket!.items[i];
                      final checked = _selectedItemIds.contains(item.id);
                      return _ItemRow(
                        item: item,
                        checked: checked,
                        onToggle: () {
                          setState(() {
                            if (checked) {
                              _selectedItemIds.remove(item.id);
                            } else {
                              _selectedItemIds.add(item.id);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
              const SizedBox(height: 16),

              // Target table picker
              _label('Target Table'),
              const SizedBox(height: 6),
              Consumer(
                builder: (context, ref, _) {
                  final allAsync = ref.watch(allTablesProvider);
                  return allAsync.when(
                    loading: () => const SizedBox(
                      height: 40,
                      child: Center(
                          child: CircularProgressIndicator(
                              color: AppColors.accent, strokeWidth: 2)),
                    ),
                    error: (e, _) => Text('Error: $e',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.red)),
                    data: (tables) {
                      final candidates = tables
                          .where((t) =>
                              t.id != widget.sourceTable.id &&
                              t.status != TableStatus.dirty)
                          .toList();
                      if (candidates.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Text(
                            'No candidate target tables.',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary),
                          ),
                        );
                      }
                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: candidates.map((t) {
                          final selected = _selectedTargetId == t.id;
                          return _TargetChip(
                            table: t,
                            isSelected: selected,
                            onTap: () => setState(
                                () => _selectedTargetId = t.id),
                          );
                        }).toList(),
                      );
                    },
                  );
                },
              ),

              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style:
                      const TextStyle(fontSize: 11, color: AppColors.red),
                ),
              ],

              const SizedBox(height: 24),

              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: const Text('Cancel',
                            style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: (_selectedTargetId == null ||
                              _selectedItemIds.isEmpty ||
                              _splitting)
                          ? null
                          : _doSplit,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        decoration: BoxDecoration(
                          color: (_selectedTargetId != null &&
                                  _selectedItemIds.isNotEmpty)
                              ? AppColors.accent
                              : AppColors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: _splitting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : Text(
                                _selectedItemIds.isEmpty
                                    ? 'Split'
                                    : 'Split (${_selectedItemIds.length})',
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
            letterSpacing: 0.5),
      );
}

// ---------------------------------------------------------------------------
// Item checkbox row
// ---------------------------------------------------------------------------

class _ItemRow extends StatelessWidget {
  final OrderItemEntity item;
  final bool checked;
  final VoidCallback onToggle;

  const _ItemRow({
    required this.item,
    required this.checked,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final qtyLabel = item.quantity == item.quantity.roundToDouble()
        ? item.quantity.toInt().toString()
        : item.quantity.toStringAsFixed(2);

    return GestureDetector(
      onTap: onToggle,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: checked
              ? AppColors.accent.withValues(alpha: 0.10)
              : AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
          border: checked
              ? Border.all(color: AppColors.accent, width: 1.2)
              : null,
        ),
        child: Row(
          children: [
            Icon(
              checked
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              size: 18,
              color:
                  checked ? AppColors.accent : AppColors.textDim,
            ),
            const SizedBox(width: 10),
            Text(
              '$qtyLabel×',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.productName,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item.modifiers.isNotEmpty)
                    Text(
                      item.modifiers.map((m) => m.modifierName).join(', '),
                      style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              (item.subtotal / 100).toStringAsFixed(2),
              style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Compact target table chip
// ---------------------------------------------------------------------------

class _TargetChip extends StatelessWidget {
  final RestaurantTableEntity table;
  final bool isSelected;
  final VoidCallback onTap;

  const _TargetChip({
    required this.table,
    required this.isSelected,
    required this.onTap,
  });

  Color get _statusColor => switch (table.status) {
        TableStatus.available => AppColors.green,
        TableStatus.occupied => AppColors.red,
        TableStatus.reserved => AppColors.accent,
        TableStatus.dirty => AppColors.textDim,
      };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.accent.withValues(alpha: 0.14)
              : AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
          border: isSelected
              ? Border.all(color: AppColors.accent, width: 1.5)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _statusColor,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              table.name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? AppColors.accent
                    : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
