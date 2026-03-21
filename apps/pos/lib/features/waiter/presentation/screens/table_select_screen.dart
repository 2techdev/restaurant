/// Table selection screen for the Waiter app.
///
/// Shows all restaurant tables in a grid, colour-coded by status.
/// Tap a free table to start a new order; tap an occupied table to
/// resume the existing order. A waiter's own tables are highlighted.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:gastrocore_pos/features/tables/domain/entities/table_entity.dart';
import 'package:gastrocore_pos/features/tables/presentation/providers/table_provider.dart';
import 'package:gastrocore_pos/features/waiter/presentation/providers/waiter_provider.dart'
    show waiterActiveTicketProvider, waiterAllTablesProvider;
import 'package:gastrocore_pos/features/waiter/router/waiter_router.dart';

// ---------------------------------------------------------------------------
// TableSelectScreen
// ---------------------------------------------------------------------------

class TableSelectScreen extends ConsumerWidget {
  const TableSelectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tablesAsync = ref.watch(waiterAllTablesProvider);
    final floorsAsync = ref.watch(floorsProvider);
    final selectedFloor = ref.watch(selectedFloorProvider);
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: const Text(
          'Select Table',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          if (user != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  user.name.split(' ').first,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Floor tabs ────────────────────────────────────────────────────
          floorsAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (floors) {
              if (floors.isEmpty) return const SizedBox.shrink();
              // Auto-select first floor.
              if (selectedFloor == null && floors.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  ref.read(selectedFloorProvider.notifier).state =
                      floors.first.id;
                });
              }
              return _FloorTabBar(
                floors: floors,
                selectedFloorId: selectedFloor,
                onSelect: (id) =>
                    ref.read(selectedFloorProvider.notifier).state = id,
              );
            },
          ),
          // ── Legend ────────────────────────────────────────────────────────
          _buildLegend(),
          // ── Table grid ───────────────────────────────────────────────────
          Expanded(
            child: tablesAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
              error: (e, _) => Center(
                child: Text(e.toString(),
                    style: const TextStyle(color: AppColors.red)),
              ),
              data: (allTables) {
                // Filter by selected floor.
                final tables = selectedFloor == null
                    ? allTables
                    : allTables
                        .where((t) => t.floorId == selectedFloor)
                        .toList();

                if (tables.isEmpty) {
                  return const Center(
                    child: Text(
                      'No tables on this floor',
                      style: TextStyle(color: AppColors.textDim, fontSize: 15),
                    ),
                  );
                }

                return GridView.builder(
                  padding: const EdgeInsets.all(20),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 1.1,
                  ),
                  itemCount: tables.length,
                  itemBuilder: (context, index) {
                    final table = tables[index];
                    return _TableTile(
                      table: table,
                      myWaiterId: user?.id,
                      onTap: () => _onTableTap(context, ref, table),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          _LegendDot(color: AppColors.green, label: 'Free'),
          const SizedBox(width: 16),
          _LegendDot(color: AppColors.orange, label: 'Occupied'),
          const SizedBox(width: 16),
          _LegendDot(color: AppColors.primary, label: 'My Tables'),
          const SizedBox(width: 16),
          _LegendDot(color: AppColors.yellow, label: 'Reserved'),
        ],
      ),
    );
  }

  Future<void> _onTableTap(
    BuildContext context,
    WidgetRef ref,
    RestaurantTableEntity table,
  ) async {
    if (table.status == TableStatus.available) {
      // Start a new order.
      await ref.read(waiterActiveTicketProvider.notifier).startOrder(table);
      if (context.mounted) {
        context.go(WaiterRoutes.orderFor(table.id));
      }
    } else if (table.status == TableStatus.occupied) {
      // Navigate to order screen — the WaiterOrderScreen will load the
      // existing ticket for this table on mount.
      if (context.mounted) {
        context.go(WaiterRoutes.orderFor(table.id));
      }
    } else {
      // Reserved / dirty — show a snackbar.
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Table ${table.name} is ${table.status.name}',
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: AppColors.surfaceContainerHigh,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Floor tab bar
// ---------------------------------------------------------------------------

class _FloorTabBar extends StatelessWidget {
  final List<FloorEntity> floors;
  final String? selectedFloorId;
  final ValueChanged<String> onSelect;

  const _FloorTabBar({
    required this.floors,
    required this.selectedFloorId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      color: AppColors.surface,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: floors.length,
        itemBuilder: (context, index) {
          final floor = floors[index];
          final isSelected = floor.id == selectedFloorId;
          return GestureDetector(
            onTap: () => onSelect(floor.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.accentDim
                    : AppColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
                border: isSelected
                    ? Border.all(color: AppColors.primary, width: 1.5)
                    : null,
              ),
              child: Center(
                child: Text(
                  floor.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Table tile
// ---------------------------------------------------------------------------

class _TableTile extends StatelessWidget {
  final RestaurantTableEntity table;
  final String? myWaiterId;
  final VoidCallback onTap;

  const _TableTile({
    required this.table,
    required this.myWaiterId,
    required this.onTap,
  });

  Color get _statusColor {
    switch (table.status) {
      case TableStatus.available:
        return AppColors.green;
      case TableStatus.occupied:
        // Highlight tables that belong to this waiter.
        return AppColors.orange;
      case TableStatus.reserved:
        return AppColors.yellow;
      case TableStatus.dirty:
        return AppColors.red;
    }
  }

  IconData get _statusIcon {
    switch (table.status) {
      case TableStatus.available:
        return Icons.event_seat_outlined;
      case TableStatus.occupied:
        return Icons.people_alt_outlined;
      case TableStatus.reserved:
        return Icons.bookmark_outlined;
      case TableStatus.dirty:
        return Icons.cleaning_services_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOccupied = table.status == TableStatus.occupied;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _statusColor.withValues(alpha: 0.6),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _statusColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(_statusIcon, color: _statusColor, size: 22),
            ),
            const SizedBox(height: 8),
            Text(
              table.name,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              isOccupied ? 'Occupied' : table.status.name.capitalize(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: _statusColor,
              ),
            ),
            Text(
              '${table.capacity} seats',
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Legend dot
// ---------------------------------------------------------------------------

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Extension
// ---------------------------------------------------------------------------

extension _Capitalize on String {
  String capitalize() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}
