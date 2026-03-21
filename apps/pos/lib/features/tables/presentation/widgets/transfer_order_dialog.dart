/// Dialog for transferring an active order from one table to another.
///
/// The user selects a destination table (must be available or on a
/// different floor). The source table is cleared and marked dirty.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/tables/domain/entities/table_entity.dart';
import 'package:gastrocore_pos/features/tables/presentation/providers/table_provider.dart';

/// Display the transfer order dialog.
Future<void> showTransferOrderDialog(
  BuildContext context, {
  required RestaurantTableEntity fromTable,
}) {
  return showDialog(
    context: context,
    builder: (_) => TransferOrderDialog(fromTable: fromTable),
  );
}

class TransferOrderDialog extends ConsumerStatefulWidget {
  final RestaurantTableEntity fromTable;
  const TransferOrderDialog({super.key, required this.fromTable});

  @override
  ConsumerState<TransferOrderDialog> createState() =>
      _TransferOrderDialogState();
}

class _TransferOrderDialogState extends ConsumerState<TransferOrderDialog> {
  String? _selectedTargetId;
  bool _transferring = false;

  Future<void> _doTransfer() async {
    if (_selectedTargetId == null) return;
    setState(() => _transferring = true);
    await ref.read(tableManagementProvider.notifier).transferOrder(
          fromTableId: widget.fromTable.id,
          toTableId: _selectedTargetId!,
        );
    if (mounted) Navigator.of(context).pop();
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
                      color: AppColors.orangeDim,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.swap_horiz_rounded,
                        size: 18, color: AppColors.orange),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Transfer Order',
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
                'Move the active order to another table. The source table will be marked as dirty.',
                style:
                    TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),

              // From table
              _sectionLabel('From'),
              const SizedBox(height: 8),
              _TableRow(table: widget.fromTable, isHighlighted: true),
              const SizedBox(height: 20),

              // To table
              _sectionLabel('To – Select Destination Table'),
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
                      // Filter: exclude the source table and occupied tables
                      // (unless the user explicitly wants to send to occupied).
                      final candidates = tables
                          .where((t) =>
                              t.id != widget.fromTable.id &&
                              t.status != TableStatus.dirty)
                          .toList();

                      if (candidates.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'No available destination tables.',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary),
                          ),
                        );
                      }

                      return SizedBox(
                        height: 200,
                        child: ListView.builder(
                          itemCount: candidates.length,
                          itemBuilder: (_, i) {
                            final t = candidates[i];
                            final isSelected = _selectedTargetId == t.id;
                            return GestureDetector(
                              onTap: () => setState(
                                  () => _selectedTargetId = t.id),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 120),
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.orangeDim
                                      : AppColors.surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(10),
                                  border: isSelected
                                      ? Border.all(
                                          color: AppColors.orange, width: 1.5)
                                      : null,
                                ),
                                child: _TableRow(
                                    table: t, isHighlighted: isSelected),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 24),

              // Actions
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
                      onTap: (_selectedTargetId == null || _transferring)
                          ? null
                          : _doTransfer,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        decoration: BoxDecoration(
                          color: _selectedTargetId != null
                              ? AppColors.orange
                              : AppColors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: _transferring
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white))
                            : const Text('Transfer',
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

  Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
            letterSpacing: 0.5),
      );
}

// ---------------------------------------------------------------------------
// Table row widget (used inside the list)
// ---------------------------------------------------------------------------

class _TableRow extends StatelessWidget {
  final RestaurantTableEntity table;
  final bool isHighlighted;

  const _TableRow({required this.table, this.isHighlighted = false});

  Color get _statusColor => switch (table.status) {
        TableStatus.available => AppColors.green,
        TableStatus.occupied => AppColors.red,
        TableStatus.reserved => AppColors.accent,
        TableStatus.dirty => AppColors.textDim,
      };

  String get _statusLabel => switch (table.status) {
        TableStatus.available => 'Available',
        TableStatus.occupied => 'Occupied',
        TableStatus.reserved => 'Reserved',
        TableStatus.dirty => 'Dirty',
      };

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _statusColor,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          table.name,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color:
                isHighlighted ? AppColors.orange : AppColors.textPrimary,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _statusLabel,
          style: TextStyle(fontSize: 11, color: _statusColor),
        ),
        const Spacer(),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
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
      ],
    );
  }
}
