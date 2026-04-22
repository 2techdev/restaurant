/// Dialog for merging two tables' tickets (Turkish: birleştirme).
///
/// The [primaryTable] is pre-selected as the SOURCE. The waiter picks a
/// TARGET table. On confirm all line items from the source ticket are
/// copied onto the target ticket, the source ticket is voided with a
/// `Merge to <target>` reason stamped onto its notes field, and the
/// source table is cleared + marked dirty.
///
/// Pure DB/offline flow: uses [OrderRepositoryImpl.addItemToTicket] /
/// [OrderRepositoryImpl.updateTicketStatus] / [OrderRepositoryImpl.updateTicketNotes]
/// plus [TableRepositoryImpl.clearTable] — no network calls.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/audit_log/domain/entities/audit_action.dart';
import 'package:gastrocore_pos/features/audit_log/presentation/providers/audit_log_provider.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/features/orders/presentation/providers/order_provider.dart';
import 'package:gastrocore_pos/features/tables/domain/entities/table_entity.dart';
import 'package:gastrocore_pos/features/tables/presentation/providers/table_provider.dart';

/// Display the merge-tables dialog.
Future<void> showMergeTablesDialog(
  BuildContext context, {
  required RestaurantTableEntity primaryTable,
}) {
  return showDialog(
    context: context,
    builder: (_) => MergeTablesDialog(primaryTable: primaryTable),
  );
}

class MergeTablesDialog extends ConsumerStatefulWidget {
  /// The source table — its ticket will be merged INTO the target.
  final RestaurantTableEntity primaryTable;
  const MergeTablesDialog({super.key, required this.primaryTable});

  @override
  ConsumerState<MergeTablesDialog> createState() => _MergeTablesDialogState();
}

class _MergeTablesDialogState extends ConsumerState<MergeTablesDialog> {
  String? _selectedTargetId;
  bool _merging = false;
  String? _error;

  Future<void> _doMerge() async {
    final targetId = _selectedTargetId;
    if (targetId == null) return;

    setState(() {
      _merging = true;
      _error = null;
    });

    try {
      final orderRepo = ref.read(orderRepositoryProvider);
      final tableRepo = ref.read(tableRepositoryProvider);

      // Resolve target entity + target ticket.
      final allTables = await ref.read(allTablesProvider.future);
      final targetTable = allTables.firstWhere((t) => t.id == targetId);

      final sourceOrderId = widget.primaryTable.currentOrderId;
      if (sourceOrderId == null) {
        setState(() {
          _error = 'Source table has no active order.';
          _merging = false;
        });
        return;
      }

      final sourceTicket = await orderRepo.getTicketById(sourceOrderId);
      if (sourceTicket == null) {
        setState(() {
          _error = 'Source ticket not found.';
          _merging = false;
        });
        return;
      }

      // Ensure target has a ticket. If it doesn't, create a new open ticket
      // for the target table so we have somewhere to pour the items.
      String targetTicketId;
      if (targetTable.currentOrderId != null) {
        targetTicketId = targetTable.currentOrderId!;
      } else {
        final nextNumber =
            await orderRepo.getNextOrderNumber(sourceTicket.tenantId);
        final newTicket = TicketEntity(
          id: IdGenerator.generateId(),
          tenantId: sourceTicket.tenantId,
          orderNumber: IdGenerator.generateOrderNumber(nextNumber),
          orderType: sourceTicket.orderType,
          tableId: targetTable.id,
          waiterId: sourceTicket.waiterId,
          guestCount: sourceTicket.guestCount,
          status: TicketStatus.open,
          channel: OrderChannel.pos,
          openedAt: DateTime.now(),
          deviceId: sourceTicket.deviceId,
        );
        final saved = await orderRepo.createTicket(newTicket);
        targetTicketId = saved.id;
        await tableRepo.linkOrderToTable(targetTable.id, targetTicketId);
      }

      // Copy each source item into the target ticket with a fresh id.
      // Concatenate strategy (per spec): don't try to combine matching
      // product+variant lines — simpler and preserves modifier variety.
      for (final item in sourceTicket.items) {
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
      }

      // Stamp reason + void the source ticket.
      final reason = 'Merge to ${targetTable.name}';
      await orderRepo.updateTicketNotes(sourceTicket.id, reason);
      await orderRepo.updateTicketStatus(
          sourceTicket.id, TicketStatus.voided);

      // Free the source table.
      await tableRepo.clearTable(widget.primaryTable.id);
      await tableRepo.updateTableStatus(
          widget.primaryTable.id, TableStatus.dirty);

      // Audit the merge. Uses entityId = source ticket (the one voided) so
      // the history view anchors the record to the ticket that disappeared;
      // newValueJson carries the full pair so operators can reconstruct
      // which target received which items.
      final audit = ref.read(auditServiceProvider);
      await audit.log(
        action: AuditAction.tableMerged,
        entityType: 'ticket',
        entityId: sourceTicket.id,
        reason: reason,
        newValueJson: jsonEncode({
          'sourceTableId': widget.primaryTable.id,
          'sourceTableName': widget.primaryTable.name,
          'sourceTicketId': sourceTicket.id,
          'targetTableId': targetTable.id,
          'targetTableName': targetTable.name,
          'targetTicketId': targetTicketId,
          'itemCount': sourceTicket.items.length,
        }),
      );

      // Refresh derived providers so open tickets list / table streams sync.
      ref.invalidate(allTablesProvider);
      ref.invalidate(openTicketsProvider);

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _merging = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 440,
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
                      color: AppColors.purpleDim,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.merge_rounded,
                        size: 18, color: AppColors.purple),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Merge Tables',
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
                "All items from the source ticket will be copied to the target. The source ticket is voided with reason 'Merge to <target>' and the source table is cleared.",
                style:
                    TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),

              _label('Source Table (merged from)'),
              const SizedBox(height: 8),
              _TableChip(
                table: widget.primaryTable,
                isSelected: true,
                onTap: null,
              ),
              const SizedBox(height: 20),

              _label('Target Table (receiving)'),
              const SizedBox(height: 8),
              Consumer(
                builder: (context, ref, _) {
                  final allAsync = ref.watch(allTablesProvider);
                  return allAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                          child: CircularProgressIndicator(
                              color: AppColors.accent, strokeWidth: 2)),
                    ),
                    error: (e, _) => Text('Error: $e',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.red)),
                    data: (tables) {
                      // Exclude source table + dirty tables.
                      final candidates = tables
                          .where((t) =>
                              t.id != widget.primaryTable.id &&
                              t.status != TableStatus.dirty)
                          .toList();

                      if (candidates.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'No candidate target tables.',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary),
                          ),
                        );
                      }

                      return SizedBox(
                        height: 180,
                        child: ListView.builder(
                          itemCount: candidates.length,
                          itemBuilder: (_, i) {
                            final t = candidates[i];
                            final isSelected = _selectedTargetId == t.id;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: _TableChip(
                                table: t,
                                isSelected: isSelected,
                                onTap: () => setState(
                                    () => _selectedTargetId = t.id),
                              ),
                            );
                          },
                        ),
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
                      onTap: (_selectedTargetId == null || _merging)
                          ? null
                          : _doMerge,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        decoration: BoxDecoration(
                          color: _selectedTargetId != null
                              ? AppColors.purple
                              : AppColors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: _merging
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('Merge',
                                style: TextStyle(
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
// Table chip widget
// ---------------------------------------------------------------------------

class _TableChip extends StatelessWidget {
  final RestaurantTableEntity table;
  final bool isSelected;
  final VoidCallback? onTap;

  const _TableChip({
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

  String get _statusLabel => switch (table.status) {
        TableStatus.available => 'Free',
        TableStatus.occupied => 'Occupied',
        TableStatus.reserved => 'Reserved',
        TableStatus.dirty => 'Dirty',
      };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.purpleDim
              : AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
          border: isSelected
              ? Border.all(color: AppColors.purple, width: 1.5)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _statusColor,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              table.name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? AppColors.purple
                    : AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _statusLabel,
              style: TextStyle(
                fontSize: 10,
                color: _statusColor,
              ),
            ),
            const Spacer(),
            const Icon(Icons.person_rounded,
                size: 12, color: AppColors.textDim),
            const SizedBox(width: 4),
            Text(
              '${table.capacity}',
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
