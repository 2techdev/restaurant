/// Dialog for merging two tables.
///
/// The [primaryTable] is pre-selected. The user picks a secondary table
/// from the same floor. The primary table absorbs the secondary's order
/// (if any) and the secondary is marked dirty.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/tables/domain/entities/table_entity.dart';
import 'package:gastrocore_pos/features/tables/presentation/providers/table_provider.dart';

/// Display the merge dialog.
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
  final RestaurantTableEntity primaryTable;
  const MergeTablesDialog({super.key, required this.primaryTable});

  @override
  ConsumerState<MergeTablesDialog> createState() => _MergeTablesDialogState();
}

class _MergeTablesDialogState extends ConsumerState<MergeTablesDialog> {
  String? _selectedSecondaryId;
  bool _merging = false;

  Future<void> _doMerge() async {
    if (_selectedSecondaryId == null) return;
    setState(() => _merging = true);
    await ref.read(tableManagementProvider.notifier).mergeTables(
          primaryTableId: widget.primaryTable.id,
          secondaryTableId: _selectedSecondaryId!,
        );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tablesAsync = ref.watch(tablesProvider);

    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 420,
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
                "The secondary table's order (if any) will move to the primary. The secondary table will be marked as dirty.",
                style:
                    TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),

              // Primary table indicator
              _label('Primary Table (receiving)'),
              const SizedBox(height: 8),
              _TableChip(
                table: widget.primaryTable,
                isSelected: true,
                onTap: null,
              ),
              const SizedBox(height: 20),

              // Secondary table picker
              _label('Secondary Table (to be merged)'),
              const SizedBox(height: 8),
              tablesAsync.when(
                loading: () => const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.accent, strokeWidth: 2)),
                error: (e, _) => Text('Error: $e',
                    style:
                        const TextStyle(fontSize: 12, color: AppColors.red)),
                data: (tables) {
                  // Exclude the primary table itself.
                  final candidates =
                      tables.where((t) => t.id != widget.primaryTable.id).toList();

                  if (candidates.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'No other tables on this floor.',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                    );
                  }

                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: candidates.map((t) {
                      return _TableChip(
                        table: t,
                        isSelected: _selectedSecondaryId == t.id,
                        onTap: () =>
                            setState(() => _selectedSecondaryId = t.id),
                      );
                    }).toList(),
                  );
                },
              ),
              const SizedBox(height: 28),

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
                      onTap: (_selectedSecondaryId == null || _merging)
                          ? null
                          : _doMerge,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        decoration: BoxDecoration(
                          color: _selectedSecondaryId != null
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
                                    strokeWidth: 2,
                                    color: Colors.white))
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    ? AppColors.purple
                    : AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              _statusLabel,
              style: TextStyle(
                fontSize: 10,
                color: _statusColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
