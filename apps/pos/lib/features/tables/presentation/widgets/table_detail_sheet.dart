/// Bottom sheet with contextual actions for a single table.
///
/// Actions vary by table status:
/// - Available → Open table (new order), Set reserved, Set dirty
/// - Occupied  → View order, Update guests, Transfer order, Merge tables,
///               Set dirty, Close table
/// - Reserved  → Open table, Mark available
/// - Dirty     → Mark available (cleaning done)
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/features/orders/presentation/providers/order_provider.dart';
import 'package:gastrocore_pos/features/tables/domain/entities/table_entity.dart';
import 'package:gastrocore_pos/features/tables/presentation/providers/table_provider.dart';
import 'package:gastrocore_pos/features/tables/presentation/widgets/merge_tables_dialog.dart';
import 'package:gastrocore_pos/features/tables/presentation/widgets/table_form_dialog.dart';
import 'package:gastrocore_pos/features/tables/presentation/widgets/transfer_order_dialog.dart';

/// Display the table detail bottom sheet.
Future<void> showTableDetailSheet(
  BuildContext context,
  RestaurantTableEntity table,
) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => TableDetailSheet(table: table),
  );
}

class TableDetailSheet extends ConsumerWidget {
  final RestaurantTableEntity table;
  const TableDetailSheet({super.key, required this.table});

  Color _statusColor(TableStatus s) => switch (s) {
        TableStatus.available => AppColors.green,
        TableStatus.occupied => AppColors.red,
        TableStatus.reserved => AppColors.accent,
        TableStatus.dirty => AppColors.textDim,
      };

  String _statusLabel(TableStatus s) => switch (s) {
        TableStatus.available => 'Available',
        TableStatus.occupied => 'Occupied',
        TableStatus.reserved => 'Reserved',
        TableStatus.dirty => 'Needs Cleaning',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Table header
          Row(
            children: [
              Text(
                table.name,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 12),
              _StatusBadge(table.status),
              const Spacer(),
              // Capacity
              Row(
                children: [
                  const Icon(Icons.person_rounded,
                      size: 14, color: AppColors.textDim),
                  const SizedBox(width: 4),
                  Text(
                    '${table.capacity} seats',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _statusLabel(table.status),
            style: TextStyle(
              fontSize: 13,
              color: _statusColor(table.status),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 20),

          // Context-sensitive action list
          ..._buildActions(context, ref),
        ],
      ),
    );
  }

  List<Widget> _buildActions(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(tableManagementProvider.notifier);

    switch (table.status) {
      case TableStatus.available:
        return [
          _ActionTile(
            icon: Icons.add_circle_outline_rounded,
            label: 'Open Table – New Order',
            color: AppColors.green,
            onTap: () => _openTable(context, ref),
          ),
          _ActionTile(
            icon: Icons.event_available_rounded,
            label: 'Mark as Reserved',
            color: AppColors.accent,
            onTap: () async {
              await notifier.updateTableStatus(
                  table.id, TableStatus.reserved);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
          _ActionTile(
            icon: Icons.cleaning_services_rounded,
            label: 'Mark as Needs Cleaning',
            color: AppColors.textDim,
            onTap: () async {
              await notifier.updateTableStatus(table.id, TableStatus.dirty);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
          _editDeleteActions(context, ref),
        ];

      case TableStatus.occupied:
        return [
          _ActionTile(
            icon: Icons.receipt_long_rounded,
            label: 'View / Edit Order',
            color: AppColors.accent,
            onTap: () async {
              if (table.currentOrderId != null) {
                await ref
                    .read(currentTicketProvider.notifier)
                    .loadTicket(table.currentOrderId!);
              }
              if (context.mounted) {
                Navigator.of(context).pop();
                context.go('/order-center');
              }
            },
          ),
          _ActionTile(
            icon: Icons.people_outline_rounded,
            label: 'Update Guest Count',
            color: AppColors.textSecondary,
            onTap: () => _showGuestCountDialog(context, ref),
          ),
          _ActionTile(
            icon: Icons.swap_horiz_rounded,
            label: 'Transfer Order to Another Table',
            color: AppColors.orange,
            onTap: () async {
              Navigator.of(context).pop();
              await showTransferOrderDialog(context, fromTable: table);
            },
          ),
          _ActionTile(
            icon: Icons.merge_rounded,
            label: 'Merge with Another Table',
            color: AppColors.purple,
            onTap: () async {
              Navigator.of(context).pop();
              await showMergeTablesDialog(context, primaryTable: table);
            },
          ),
          _ActionTile(
            icon: Icons.cleaning_services_rounded,
            label: 'Mark as Needs Cleaning',
            color: AppColors.textDim,
            onTap: () async {
              await notifier.updateTableStatus(table.id, TableStatus.dirty);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
          _ActionTile(
            icon: Icons.check_circle_outline_rounded,
            label: 'Close Table (payment done)',
            color: AppColors.red,
            onTap: () async {
              await ref.read(tableRepositoryProvider).clearTable(table.id);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
          _editDeleteActions(context, ref),
        ];

      case TableStatus.reserved:
        return [
          _ActionTile(
            icon: Icons.add_circle_outline_rounded,
            label: 'Open Table – New Order',
            color: AppColors.green,
            onTap: () => _openTable(context, ref),
          ),
          _ActionTile(
            icon: Icons.event_busy_rounded,
            label: 'Mark as Available',
            color: AppColors.textSecondary,
            onTap: () async {
              await notifier.updateTableStatus(
                  table.id, TableStatus.available);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
          _editDeleteActions(context, ref),
        ];

      case TableStatus.dirty:
        return [
          _ActionTile(
            icon: Icons.check_circle_outline_rounded,
            label: 'Mark as Available (cleaned)',
            color: AppColors.green,
            onTap: () async {
              await notifier.updateTableStatus(
                  table.id, TableStatus.available);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
          _editDeleteActions(context, ref),
        ];
    }
  }

  Widget _editDeleteActions(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        const Divider(height: 24, color: AppColors.border),
        _ActionTile(
          icon: Icons.edit_outlined,
          label: 'Edit Table',
          color: AppColors.textSecondary,
          onTap: () async {
            Navigator.of(context).pop();
            await showTableFormDialog(context, existing: table);
          },
        ),
        _ActionTile(
          icon: Icons.delete_outline_rounded,
          label: 'Delete Table',
          color: AppColors.red,
          onTap: () => _confirmDelete(context, ref),
        ),
      ],
    );
  }

  Future<void> _openTable(BuildContext context, WidgetRef ref) async {
    final user = ref.read(currentUserProvider);
    await ref.read(currentTicketProvider.notifier).createNewTicket(
          orderType: OrderType.dineIn,
          tableId: table.id,
          waiterId: user?.id,
          deviceId: 'DEV-POS-01',
        );
    if (context.mounted) {
      Navigator.of(context).pop();
      context.go('/order-center');
    }
  }

  Future<void> _showGuestCountDialog(
      BuildContext context, WidgetRef ref) async {
    if (table.currentOrderId == null) return;
    final result = await showDialog<int>(
      context: context,
      builder: (_) => _GuestCountDialog(tableId: table.id),
    );
    if (result != null && context.mounted) {
      await ref
          .read(tableManagementProvider.notifier)
          .updateGuestCount(table.currentOrderId!, result);
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteTableConfirmDialog(tableName: table.name),
    );
    if (confirmed == true && context.mounted) {
      await ref.read(tableManagementProvider.notifier).deleteTable(table.id);
      if (context.mounted) Navigator.of(context).pop();
    }
  }
}

// ---------------------------------------------------------------------------
// Action tile
// ---------------------------------------------------------------------------

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: 14),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
            const Spacer(),
            const Icon(Icons.chevron_right_rounded,
                size: 16, color: AppColors.textDim),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Status badge
// ---------------------------------------------------------------------------

class _StatusBadge extends StatelessWidget {
  final TableStatus status;
  const _StatusBadge(this.status);

  Color get _color => switch (status) {
        TableStatus.available => AppColors.green,
        TableStatus.occupied => AppColors.red,
        TableStatus.reserved => AppColors.accent,
        TableStatus.dirty => AppColors.textDim,
      };

  String get _label => switch (status) {
        TableStatus.available => 'Free',
        TableStatus.occupied => 'Occupied',
        TableStatus.reserved => 'Reserved',
        TableStatus.dirty => 'Dirty',
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        _label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: _color,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Guest count dialog
// ---------------------------------------------------------------------------

class _GuestCountDialog extends StatefulWidget {
  final String tableId;
  const _GuestCountDialog({required this.tableId});

  @override
  State<_GuestCountDialog> createState() => _GuestCountDialogState();
}

class _GuestCountDialogState extends State<_GuestCountDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Update Guest Count',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ctrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              autofocus: true,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: '0',
                hintStyle:
                    const TextStyle(fontSize: 28, color: AppColors.textDim),
                filled: true,
                fillColor: AppColors.bgInput,
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(null),
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
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      final n = int.tryParse(_ctrl.text.trim());
                      if (n != null && n > 0) {
                        Navigator.of(context).pop(n);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            AppColors.primary,
                            AppColors.primaryContainer
                          ],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: const Text('Confirm',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF0A1A3A))),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Delete table confirm
// ---------------------------------------------------------------------------

class _DeleteTableConfirmDialog extends StatelessWidget {
  final String tableName;
  const _DeleteTableConfirmDialog({required this.tableName});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.delete_outline_rounded,
                color: AppColors.red, size: 32),
            const SizedBox(height: 12),
            Text(
              'Delete "$tableName"?',
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            const Text(
              'This action cannot be undone.',
              style:
                  TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(false),
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
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      decoration: BoxDecoration(
                        color: AppColors.red,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: const Text('Delete',
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
    );
  }
}
