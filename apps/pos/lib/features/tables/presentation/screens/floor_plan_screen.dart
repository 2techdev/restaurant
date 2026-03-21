/// Floor Plan Screen for GastroCore POS.
///
/// Features:
/// - Real-time table status with color coding
/// - Floor/zone sidebar with create/edit support
/// - Grid view and free-form canvas view (drag-and-drop in edit mode)
/// - FAB to add tables
/// - Long-press (or edit-mode tap) to open the table detail sheet
/// - Merge tables, transfer orders, update guest count
/// - Occupancy statistics in the bottom bar
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/features/orders/presentation/providers/order_provider.dart';
import 'package:gastrocore_pos/features/tables/domain/entities/table_entity.dart';
import 'package:gastrocore_pos/features/tables/presentation/providers/table_provider.dart';
import 'package:gastrocore_pos/features/tables/presentation/widgets/floor_form_dialog.dart';
import 'package:gastrocore_pos/features/tables/presentation/widgets/table_detail_sheet.dart';
import 'package:gastrocore_pos/features/tables/presentation/widgets/table_form_dialog.dart';

// Canvas size for the free-form floor plan.
const double _kCanvasWidth = 1200;
const double _kCanvasHeight = 800;

// ---------------------------------------------------------------------------
// Floor Plan Screen
// ---------------------------------------------------------------------------

class FloorPlanScreen extends ConsumerStatefulWidget {
  const FloorPlanScreen({super.key});

  @override
  ConsumerState<FloorPlanScreen> createState() => _FloorPlanScreenState();
}

class _FloorPlanScreenState extends ConsumerState<FloorPlanScreen> {
  bool _isGridView = true;
  int _selectedNavIndex = 0;

  // Tracks positions being dragged (table ID → Offset) before committing to DB.
  final Map<String, Offset> _dragOffsets = {};

  // Shows a brief "Saved" indicator after a position is persisted to SQLite.
  String? _savedLabel;

  Color _statusColor(TableStatus status) => switch (status) {
        TableStatus.available => AppColors.green,
        TableStatus.occupied => AppColors.primary,
        TableStatus.reserved => AppColors.orange,
        TableStatus.dirty => AppColors.red,
      };

  String _statusLabel(TableStatus status) => switch (status) {
        TableStatus.available => 'Free',
        TableStatus.occupied => 'Occupied',
        TableStatus.reserved => 'Reserved',
        TableStatus.dirty => 'Dirty',
      };

  @override
  Widget build(BuildContext context) {
    final floorsAsync = ref.watch(floorsProvider);
    final editMode = ref.watch(tableEditModeProvider);

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      floatingActionButton: _buildFab(editMode),
      body: floorsAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.accent)),
        error: (err, _) => Center(
          child: Text('Error loading floors: $err',
              style: const TextStyle(color: AppColors.textDim)),
        ),
        data: (floors) {
          // Auto-select the first floor.
          final selectedFloorId = ref.watch(selectedFloorProvider);
          if (selectedFloorId == null && floors.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref.read(selectedFloorProvider.notifier).state = floors.first.id;
            });
          }

          return Column(
            children: [
              _buildTopNav(editMode),
              Expanded(
                child: Row(
                  children: [
                    _buildLeftSidebar(floors, selectedFloorId, editMode),
                    Expanded(
                        child: _buildMainCanvas(
                            floors, selectedFloorId, editMode)),
                  ],
                ),
              ),
              _buildBottomBar(),
            ],
          );
        },
      ),
    );
  }

  // -------------------------------------------------------------------------
  // FAB
  // -------------------------------------------------------------------------

  Widget? _buildFab(bool editMode) {
    final selectedFloorId = ref.watch(selectedFloorProvider);
    if (selectedFloorId == null) return null;

    return FloatingActionButton.extended(
      onPressed: () => showTableFormDialog(
        context,
        floorId: selectedFloorId,
      ),
      backgroundColor: AppColors.accent,
      foregroundColor: Colors.white,
      icon: const Icon(Icons.add_rounded, size: 20),
      label: const Text('Add Table',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
    );
  }

  // -------------------------------------------------------------------------
  // Top navigation bar
  // -------------------------------------------------------------------------

  Widget _buildTopNav(bool editMode) {
    final navItems = [
      ('Floor Plan', Icons.grid_view_rounded),
      ('Orders', Icons.receipt_long_rounded),
      ('Kitchen', Icons.kitchen_rounded),
      ('Inventory', Icons.inventory_2_rounded),
      ('Reports', Icons.analytics_rounded),
    ];

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      color: AppColors.surface,
      child: Row(
        children: [
          ...navItems.asMap().entries.map((entry) {
            final i = entry.key;
            final (label, icon) = entry.value;
            final isActive = i == _selectedNavIndex;
            return GestureDetector(
              onTap: () {
                if (i == 0) {
                  setState(() => _selectedNavIndex = 0);
                } else if (i == 1) {
                  context.go('/order-center');
                } else if (i == 2) {
                  context.go('/kitchen');
                }
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  color: isActive ? AppColors.accentDim : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon,
                        size: 16,
                        color: isActive
                            ? AppColors.accent
                            : AppColors.textDim),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            isActive ? FontWeight.w600 : FontWeight.w400,
                        color: isActive
                            ? AppColors.accent
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          const Spacer(),

          // Edit mode toggle
          GestureDetector(
            onTap: () {
              ref.read(tableEditModeProvider.notifier).state = !editMode;
              if (editMode) _dragOffsets.clear();
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: editMode
                    ? AppColors.orangeDim
                    : AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
                border: editMode
                    ? Border.all(color: AppColors.orange, width: 1)
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    editMode
                        ? Icons.check_rounded
                        : Icons.edit_rounded,
                    size: 13,
                    color:
                        editMode ? AppColors.orange : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    editMode ? 'Done Editing' : 'Edit Layout',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: editMode
                          ? AppColors.orange
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),

          // View toggle (Grid / Canvas) – only visible outside edit mode
          if (!editMode)
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  _buildViewToggle('Grid', true, Icons.grid_view_rounded),
                  _buildViewToggle('Canvas', false, Icons.map_rounded),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildViewToggle(String label, bool isGrid, IconData icon) {
    final isActive = _isGridView == isGrid;
    return GestureDetector(
      onTap: () => setState(() => _isGridView = isGrid),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color:
              isActive ? AppColors.surfaceContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 12,
                color: isActive
                    ? AppColors.textPrimary
                    : AppColors.textDim),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive
                    ? AppColors.textPrimary
                    : AppColors.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Left sidebar (floors / zones)
  // -------------------------------------------------------------------------

  Widget _buildLeftSidebar(
      List<FloorEntity> floors, String? selectedFloorId, bool editMode) {
    return Container(
      width: 180,
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text(
                  'ZONES',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDim,
                    letterSpacing: 1.5,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => showFloorFormDialog(
                    context,
                    nextDisplayOrder: floors.length,
                  ),
                  child: const Icon(Icons.add_rounded,
                      size: 16, color: AppColors.accent),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Floor list
          Expanded(
            child: ListView(
              children: [
                ...floors.map((floor) {
                  final isActive = floor.id == selectedFloorId;
                  return GestureDetector(
                    onTap: () {
                      ref.read(selectedFloorProvider.notifier).state =
                          floor.id;
                      if (editMode) _dragOffsets.clear();
                    },
                    onLongPress: () => showFloorFormDialog(
                      context,
                      existing: floor,
                    ),
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: isActive
                            ? AppColors.accentDim
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 4,
                            height: 20,
                            decoration: BoxDecoration(
                              color: isActive
                                  ? AppColors.accent
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              floor.name,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isActive
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: isActive
                                    ? AppColors.accent
                                    : AppColors.textSecondary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (editMode)
                            GestureDetector(
                              onTap: () => showFloorFormDialog(
                                context,
                                existing: floor,
                              ),
                              child: const Icon(Icons.more_vert_rounded,
                                  size: 14, color: AppColors.textDim),
                            ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),

          // Bottom sidebar buttons
          _buildSidebarButton(Icons.settings_rounded, 'Settings', () {}),
          _buildSidebarButton(Icons.lock_outline_rounded, 'Lock Screen',
              () => context.go('/login')),
        ],
      ),
    );
  }

  Widget _buildSidebarButton(
      IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.textDim),
            const SizedBox(width: 10),
            Text(label,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textDim)),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Main canvas area
  // -------------------------------------------------------------------------

  Widget _buildMainCanvas(
      List<FloorEntity> floors, String? selectedFloorId, bool editMode) {
    final tablesAsync = ref.watch(tablesProvider);
    final currentFloor =
        floors.where((f) => f.id == selectedFloorId);
    final floorName =
        currentFloor.isNotEmpty ? currentFloor.first.name : '';

    return tablesAsync.when(
      loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.accent)),
      error: (err, _) => Center(
        child: Text('Error: $err',
            style: const TextStyle(color: AppColors.textDim)),
      ),
      data: (tables) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Canvas header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Row(
                children: [
                  Text(
                    floorName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  _CountBadge('${tables.length} Tables'),
                  if (editMode) ...[
                    const SizedBox(width: 8),
                    _CountBadge(
                      'Edit Mode',
                      color: AppColors.orangeDim,
                      textColor: AppColors.orange,
                    ),
                  ],
                  if (_savedLabel != null) ...[
                    const SizedBox(width: 8),
                    _CountBadge(
                      '✓ $_savedLabel',
                      color: AppColors.green.withValues(alpha: 0.15),
                      textColor: AppColors.green,
                    ),
                  ],
                  const Spacer(),
                  // Status legend
                  ...[
                    (TableStatus.available, 'Free'),
                    (TableStatus.occupied, 'Occupied'),
                    (TableStatus.reserved, 'Reserved'),
                    (TableStatus.dirty, 'Dirty'),
                  ].map((entry) => Padding(
                        padding: const EdgeInsets.only(left: 14),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _statusColor(entry.$1),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(entry.$2,
                                style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.textDim)),
                          ],
                        ),
                      )),
                ],
              ),
            ),

            // Table area
            Expanded(
              child: Padding(
                padding: editMode
                    ? EdgeInsets.zero
                    : const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: tables.isEmpty
                    ? _buildEmptyState(selectedFloorId)
                    : editMode
                        ? _buildDragCanvas(tables)
                        : _isGridView
                            ? _buildFloorGrid(tables)
                            : _buildTableList(tables),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState(String? floorId) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.table_restaurant_rounded,
              size: 48, color: AppColors.textDim.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          const Text(
            'No tables on this floor',
            style: TextStyle(fontSize: 14, color: AppColors.textDim),
          ),
          const SizedBox(height: 8),
          if (floorId != null)
            GestureDetector(
              onTap: () =>
                  showTableFormDialog(context, floorId: floorId),
              child: Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.accentDim,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '+ Add first table',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Grid view
  // -------------------------------------------------------------------------

  Widget _buildFloorGrid(List<RestaurantTableEntity> tables) {
    return LayoutBuilder(builder: (context, constraints) {
      final cols = (constraints.maxWidth / 160).floor().clamp(2, 6);
      return GridView.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.4,
        ),
        itemCount: tables.length,
        itemBuilder: (_, i) => _buildTableTile(tables[i]),
      );
    });
  }

  Widget _buildTableTile(RestaurantTableEntity table) {
    final borderColor = _statusColor(table.status);
    final isRound = table.shape == TableShape.circle;

    return GestureDetector(
      onTap: () => _onTableTap(table),
      onLongPress: () => showTableDetailSheet(context, table),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: isRound
              ? BorderRadius.circular(100)
              : BorderRadius.circular(12),
          border:
              Border.all(color: borderColor.withValues(alpha: 0.6), width: 2),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              table.name,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              _statusLabel(table.status),
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: borderColor),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.person_rounded,
                    size: 12, color: AppColors.textDim),
                const SizedBox(width: 2),
                Text('${table.capacity}',
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.textDim)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // List view
  // -------------------------------------------------------------------------

  Widget _buildTableList(List<RestaurantTableEntity> tables) {
    return ListView.builder(
      itemCount: tables.length,
      itemBuilder: (_, i) {
        final table = tables[i];
        final borderColor = _statusColor(table.status);
        return GestureDetector(
          onTap: () => _onTableTap(table),
          onLongPress: () => showTableDetailSheet(context, table),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(10),
              border:
                  Border(left: BorderSide(color: borderColor, width: 3)),
            ),
            child: Row(
              children: [
                Text(
                  table.name,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary),
                ),
                const SizedBox(width: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: borderColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _statusLabel(table.status),
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: borderColor),
                  ),
                ),
                const Spacer(),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person_rounded,
                        size: 14, color: AppColors.textDim),
                    const SizedBox(width: 4),
                    Text('${table.capacity}',
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary)),
                  ],
                ),
                const SizedBox(width: 12),
                const Icon(Icons.chevron_right_rounded,
                    size: 18, color: AppColors.textDim),
              ],
            ),
          ),
        );
      },
    );
  }

  // -------------------------------------------------------------------------
  // Drag-and-drop canvas
  // -------------------------------------------------------------------------

  Widget _buildDragCanvas(List<RestaurantTableEntity> tables) {
    return ClipRect(
      child: InteractiveViewer(
        boundaryMargin: const EdgeInsets.all(80),
        minScale: 0.4,
        maxScale: 2.0,
        child: SizedBox(
          width: _kCanvasWidth,
          height: _kCanvasHeight,
          child: Stack(
            children: [
              // Canvas grid background
              CustomPaint(
                size: const Size(_kCanvasWidth, _kCanvasHeight),
                painter: _GridPainter(),
              ),

              // Table widgets
              ...tables.map((table) {
                final offset = _dragOffsets[table.id];
                final x = offset?.dx ?? table.posX;
                final y = offset?.dy ?? table.posY;

                return Positioned(
                  left: x,
                  top: y,
                  child: _DraggableTableTile(
                    table: table,
                    statusColor: _statusColor(table.status),
                    statusLabel: _statusLabel(table.status),
                    onTap: () => showTableDetailSheet(context, table),
                    onDragUpdate: (delta) {
                      setState(() {
                        final cur = _dragOffsets[table.id] ??
                            Offset(table.posX, table.posY);
                        final newX =
                            (cur.dx + delta.dx).clamp(0.0, _kCanvasWidth - table.width);
                        final newY =
                            (cur.dy + delta.dy).clamp(0.0, _kCanvasHeight - table.height);
                        _dragOffsets[table.id] = Offset(newX, newY);
                      });
                    },
                    onDragEnd: () async {
                      final pos = _dragOffsets[table.id];
                      if (pos != null) {
                        await ref
                            .read(tableManagementProvider.notifier)
                            .updateTablePosition(table.id, pos.dx, pos.dy);
                        // Show brief "Saved" indicator
                        setState(() => _savedLabel = '${table.name} saved');
                        Future.delayed(const Duration(seconds: 2), () {
                          if (mounted) setState(() => _savedLabel = null);
                        });
                      }
                    },
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Table tap handler
  // -------------------------------------------------------------------------

  Future<void> _onTableTap(RestaurantTableEntity table) async {
    if (table.status == TableStatus.occupied &&
        table.currentOrderId != null) {
      await ref
          .read(currentTicketProvider.notifier)
          .loadTicket(table.currentOrderId!);
      if (mounted) context.go('/order-center');
    } else if (table.isAvailable) {
      final user = ref.read(currentUserProvider);
      await ref.read(currentTicketProvider.notifier).createNewTicket(
            orderType: OrderType.dineIn,
            tableId: table.id,
            waiterId: user?.id,
            deviceId: 'DEV-POS-01',
          );
      if (mounted) context.go('/order-center');
    } else {
      // Reserved or dirty – show detail sheet.
      if (mounted) showTableDetailSheet(context, table);
    }
  }

  // -------------------------------------------------------------------------
  // Bottom bar
  // -------------------------------------------------------------------------

  Widget _buildBottomBar() {
    final tablesAsync = ref.watch(tablesProvider);
    final tables = tablesAsync.valueOrNull ?? [];

    final totalSeats =
        tables.fold<int>(0, (s, t) => s + t.capacity);
    final occupiedCount =
        tables.where((t) => t.status == TableStatus.occupied).length;
    final reservedCount =
        tables.where((t) => t.status == TableStatus.reserved).length;
    final dirtyCount =
        tables.where((t) => t.status == TableStatus.dirty).length;
    final occupancyPct =
        tables.isEmpty ? 0.0 : occupiedCount / tables.length * 100;

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      color: AppColors.surface,
      child: Row(
        children: [
          _BottomStat(Icons.event_seat_rounded, 'Seats: $totalSeats'),
          const SizedBox(width: 20),
          _BottomStat(Icons.pie_chart_rounded,
              'Occupancy: ${occupancyPct.toStringAsFixed(0)}%'),
          const SizedBox(width: 20),
          _BottomStat(Icons.table_restaurant_rounded,
              '$occupiedCount/${tables.length} Occupied'),
          if (reservedCount > 0) ...[
            const SizedBox(width: 20),
            _BottomStat(Icons.event_available_rounded,
                '$reservedCount Reserved',
                color: AppColors.accent),
          ],
          if (dirtyCount > 0) ...[
            const SizedBox(width: 20),
            _BottomStat(Icons.cleaning_services_rounded,
                '$dirtyCount Dirty',
                color: AppColors.orange),
          ],
          const Spacer(),
          GestureDetector(
            onTap: () => context.go('/order-center'),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryContainer],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.point_of_sale_rounded,
                      size: 14, color: Color(0xFF0A1A3A)),
                  SizedBox(width: 4),
                  Text('Back to POS',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0A1A3A))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Draggable table tile (used in canvas edit mode)
// ---------------------------------------------------------------------------

class _DraggableTableTile extends StatelessWidget {
  final RestaurantTableEntity table;
  final Color statusColor;
  final String statusLabel;
  final VoidCallback onTap;
  final void Function(Offset delta) onDragUpdate;
  final VoidCallback onDragEnd;

  const _DraggableTableTile({
    required this.table,
    required this.statusColor,
    required this.statusLabel,
    required this.onTap,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    final isRound = table.shape == TableShape.circle;

    return GestureDetector(
      onTap: onTap,
      onPanUpdate: (details) => onDragUpdate(details.delta),
      onPanEnd: (_) => onDragEnd(),
      child: Container(
        width: table.width,
        height: table.height,
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: isRound
              ? BorderRadius.circular(200)
              : table.shape == TableShape.square
                  ? BorderRadius.circular(8)
                  : BorderRadius.circular(10),
          border: Border.all(
              color: statusColor.withValues(alpha: 0.8), width: 2),
          boxShadow: [
            BoxShadow(
              color: statusColor.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              table.name,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              statusLabel,
              style: TextStyle(fontSize: 9, color: statusColor),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.person_rounded,
                    size: 10, color: AppColors.textDim),
                const SizedBox(width: 2),
                Text('${table.capacity}',
                    style: const TextStyle(
                        fontSize: 9, color: AppColors.textDim)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Canvas grid background painter
// ---------------------------------------------------------------------------

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.border.withValues(alpha: 0.4)
      ..strokeWidth = 0.5;

    const step = 40.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter _) => false;
}

// ---------------------------------------------------------------------------
// Small reusable widgets
// ---------------------------------------------------------------------------

class _CountBadge extends StatelessWidget {
  final String text;
  final Color? color;
  final Color? textColor;

  const _CountBadge(this.text, {this.color, this.textColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color ?? AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
            fontSize: 11,
            color: textColor ?? AppColors.textSecondary),
      ),
    );
  }
}

class _BottomStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _BottomStat(this.icon, this.label, {this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color ?? AppColors.textDim),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontSize: 11,
                color: color ?? AppColors.textSecondary)),
      ],
    );
  }
}
