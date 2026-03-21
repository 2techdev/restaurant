/// Table View tab content - Stitch V2 Design.
///
/// Large table cards with T01-T10 naming, price display, waiter info,
/// status colors. Filter chips and floor tabs.
/// Matches Stitch V2 table_map design exactly.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/features/orders/presentation/providers/order_provider.dart';
import 'package:gastrocore_pos/features/tables/domain/entities/table_entity.dart';
import 'package:gastrocore_pos/features/tables/presentation/providers/table_provider.dart';

// ---------------------------------------------------------------------------
// Table View Tab
// ---------------------------------------------------------------------------

class TableViewTab extends ConsumerStatefulWidget {
  final VoidCallback onSwitchToMenu;

  const TableViewTab({super.key, required this.onSwitchToMenu});

  @override
  ConsumerState<TableViewTab> createState() => _TableViewTabState();
}

class _TableViewTabState extends ConsumerState<TableViewTab> {
  _TableFilter _activeFilter = _TableFilter.all;
  int _activeFloorTab = 0; // 0 = Ana Salon, 1 = Teras

  Color _statusColor(TableStatus status) {
    switch (status) {
      case TableStatus.available:
        return const Color(0xFF22C55E);
      case TableStatus.occupied:
        return AppColors.primary;
      case TableStatus.reserved:
        return const Color(0xFFFB923C);
      case TableStatus.dirty:
        return AppColors.textDim;
    }
  }

  @override
  Widget build(BuildContext context) {
    final floorsAsync = ref.watch(floorsProvider);

    return Container(
      color: AppColors.surfaceDim,
      child: floorsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primaryLight),
        ),
        error: (err, _) => Center(
          child: Text(
            'Error: $err',
            style: const TextStyle(fontSize: 13, color: AppColors.textDim),
          ),
        ),
        data: (floors) {
          if (floors.isEmpty) {
            return const Center(
              child: Text(
                'No floors configured',
                style: TextStyle(fontSize: 14, color: AppColors.textDim),
              ),
            );
          }

          final selectedFloorId = ref.watch(selectedFloorProvider);
          if (selectedFloorId == null && floors.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref.read(selectedFloorProvider.notifier).state = floors.first.id;
            });
          }

          return Column(
            children: [
              // Filter chips + Floor tabs
              _buildFilterBar(floors, selectedFloorId),
              // Main content: sidebar + grid
              Expanded(
                child: Row(
                  children: [
                    // Floor stats sidebar
                    _buildFloorStatsSidebar(),
                    // Table grid
                    Expanded(child: _buildTableGrid()),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Filter Bar + Floor Tabs
  // -------------------------------------------------------------------------

  Widget _buildFilterBar(List<FloorEntity> floors, String? selectedFloorId) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
      child: Row(
        children: [
          // Filter chips – wrapped in Flexible so they shrink at small sizes
          Flexible(
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _buildFilterChip('All Tables', _TableFilter.all, null),
                _buildFilterChip('Available', _TableFilter.available, const Color(0xFF22C55E)),
                _buildFilterChip('Occupied', _TableFilter.occupied, AppColors.primary),
                _buildFilterChip('Unpaid', _TableFilter.unpaid, const Color(0xFFFB923C)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Floor tabs
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildFloorTab('Ana Salon', 0),
                _buildFloorTab('Teras', 1),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, _TableFilter filter, Color? dotColor) {
    final isActive = _activeFilter == filter;
    return GestureDetector(
      onTap: () => setState(() => _activeFilter = filter),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.surfaceContainerHigh
              : AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dotColor != null) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dotColor,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color: isActive
                    ? AppColors.primaryLight
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloorTab(String label, int index) {
    final isActive = _activeFloorTab == index;
    return GestureDetector(
      onTap: () => setState(() => _activeFloorTab = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? AppColors.surfaceContainerHigh : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            color: isActive
                ? const Color(0xFFE2E2EB)
                : const Color(0xFFC3C6D7),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Floor Stats Sidebar (120px)
  // -------------------------------------------------------------------------

  Widget _buildFloorStatsSidebar() {
    final tablesAsync = ref.watch(tablesProvider);
    final tables = tablesAsync.valueOrNull ?? [];

    final freeCount = tables.where((t) => t.status == TableStatus.available).length;
    final busyCount = tables.where((t) => t.status == TableStatus.occupied).length;
    final checkCount = tables.where((t) => t.status == TableStatus.reserved).length;

    return Padding(
      padding: const EdgeInsets.only(left: 32),
      child: SizedBox(
        width: 120,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Floor label
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  const Text(
                    'FLOOR',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFC3C6D7),
                      letterSpacing: 2.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'MAIN',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFE2E2EB),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Stats
            _buildStatCard('$freeCount', 'Free', const Color(0xFF22C55E)),
            const SizedBox(height: 12),
            _buildStatCard('${busyCount.toString().padLeft(2, '0')}', 'Busy', AppColors.primary),
            const SizedBox(height: 12),
            _buildStatCard('${checkCount.toString().padLeft(2, '0')}', 'Check', const Color(0xFFFB923C)),
            const SizedBox(height: 12),
            // Add table button
            Container(
              width: double.infinity,
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFF33343B),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.add, size: 24, color: AppColors.primaryLight),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String count, String label, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            count,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFFC3C6D7),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Table Grid
  // -------------------------------------------------------------------------

  Widget _buildTableGrid() {
    final tablesAsync = ref.watch(tablesProvider);

    return tablesAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.primaryLight),
      ),
      error: (err, _) => Center(
        child: Text(
          'Error: $err',
          style: const TextStyle(fontSize: 13, color: AppColors.textDim),
        ),
      ),
      data: (tables) {
        final filtered = _applyTableFilter(tables);

        if (filtered.isEmpty) {
          return const Center(
            child: Text(
              'No tables found',
              style: TextStyle(fontSize: 14, color: AppColors.textDim),
            ),
          );
        }

        return Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 32, 32),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final cols = (constraints.maxWidth / 220).floor().clamp(2, 5);
                  return GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      mainAxisSpacing: 24,
                      crossAxisSpacing: 24,
                      childAspectRatio: 1.1,
                    ),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      return _buildTableCard(filtered[index], index);
                    },
                  );
                },
              ),
            ),
            // FAB: Open New Table
            Positioned(
              bottom: 40,
              right: 40,
              child: GestureDetector(
                onTap: () {
                  // Open new table
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primaryLight, AppColors.primary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, color: Colors.white, size: 22),
                      SizedBox(width: 12),
                      Text(
                        'Open New Table',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTableCard(RestaurantTableEntity table, int index) {
    final isAvailable = table.status == TableStatus.available;
    final isOccupied = table.status == TableStatus.occupied;
    final isUnpaid = table.status == TableStatus.reserved;
    final statusColor = _statusColor(table.status);
    final tableNumber = 'T${(index + 1).toString().padLeft(2, '0')}';

    return GestureDetector(
      onTap: () => _onTableTap(table),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isAvailable
              ? AppColors.surfaceContainerHigh
              : AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isOccupied
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    blurRadius: 15,
                  ),
                ]
              : null,
        ),
        child: Stack(
          children: [
            // Left indicator strip
            if (!isAvailable)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 6,
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      bottomLeft: Radius.circular(12),
                    ),
                  ),
                ),
              ),
            // Content
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top: Table number + guest count
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tableNumber,
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                          color: isAvailable
                              ? const Color(0xFFE2E2EB).withValues(alpha: 0.4)
                              : isUnpaid
                                  ? const Color(0xFFFB923C)
                                  : AppColors.primary,
                          letterSpacing: -2.0,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isAvailable
                              ? Colors.transparent
                              : statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.group,
                              size: 14,
                              color: isAvailable
                                  ? AppColors.textDim
                                  : statusColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${table.capacity}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: isAvailable
                                    ? AppColors.textDim
                                    : statusColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Bottom info
                  if (isAvailable)
                    Text(
                      'AVAILABLE',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF22C55E).withValues(alpha: 0.6),
                        letterSpacing: 2.0,
                      ),
                    )
                  else ...[
                    if (isUnpaid)
                      Row(
                        children: [
                          const Icon(Icons.notifications_active, size: 12, color: Color(0xFFFB923C)),
                          const SizedBox(width: 4),
                          const Text(
                            'CHECK REQUESTED',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFFB923C),
                              letterSpacing: 2.0,
                            ),
                          ),
                        ],
                      )
                    else ...[
                      const Text(
                        'Waiter: Sarah W.',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFC3C6D7),
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Active: 42 mins',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFFC3C6D7),
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    const Text(
                      '\$142.50',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFE2E2EB),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<RestaurantTableEntity> _applyTableFilter(
      List<RestaurantTableEntity> tables) {
    switch (_activeFilter) {
      case _TableFilter.all:
        return tables;
      case _TableFilter.available:
        return tables
            .where((t) => t.status == TableStatus.available)
            .toList();
      case _TableFilter.occupied:
        return tables
            .where((t) => t.status == TableStatus.occupied)
            .toList();
      case _TableFilter.unpaid:
        return tables
            .where((t) => t.status == TableStatus.reserved)
            .toList();
    }
  }

  Future<void> _onTableTap(RestaurantTableEntity table) async {
    if (table.status == TableStatus.occupied &&
        table.currentOrderId != null) {
      await ref
          .read(currentTicketProvider.notifier)
          .loadTicket(table.currentOrderId!);
    } else if (table.isAvailable) {
      final user = ref.read(currentUserProvider);
      await ref.read(currentTicketProvider.notifier).createNewTicket(
            orderType: OrderType.dineIn,
            tableId: table.id,
            waiterId: user?.id,
            deviceId: 'DEV-POS-01',
          );
    }
    widget.onSwitchToMenu();
  }
}

// ---------------------------------------------------------------------------
// Filter enum
// ---------------------------------------------------------------------------

enum _TableFilter { all, available, occupied, unpaid }
