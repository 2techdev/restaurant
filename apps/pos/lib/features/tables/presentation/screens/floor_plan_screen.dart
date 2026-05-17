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
import 'package:gastrocore_pos/features/orders/presentation/widgets/mode_switcher_pill.dart';
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

  // Floor plan v4 (2026-05-17 UX overhaul) — premium tinted palette.
  // Saturated borders + soft fills so each state reads at a glance from
  // across the bar. BILL flag overrides occupied tint with orange.
  static const _v4Available = Color(0xFF22C55E);
  static const _v4AvailableBg = Color(0xFFFFFFFF);
  static const _v4Busy = Color(0xFFFB7185);
  static const _v4BusyBg = Color(0xFFFFF1F2);
  static const _v4Bill = Color(0xFFEA580C);
  static const _v4BillBg = Color(0xFFFFEDD5);
  static const _v4Clean = Color(0xFFEAB308);
  static const _v4CleanBg = Color(0xFFFEF9C3);
  static const _v4Reserved = Color(0xFF8B5CF6);
  static const _v4ReservedBg = Color(0xFFF3E8FF);

  Color _statusColor(TableStatus status) => switch (status) {
        TableStatus.available => _v4Available,
        TableStatus.occupied => _v4Busy,
        TableStatus.reserved => _v4Reserved,
        TableStatus.dirty => _v4Clean,
      };

  /// (border, fill) for the v4 tile shell, honouring the BILL flag.
  ({Color border, Color fill}) _statusPalette(
    TableStatus status,
    Set<TableFlag> flags,
  ) {
    if (flags.contains(TableFlag.billRequested)) {
      return (border: _v4Bill, fill: _v4BillBg);
    }
    return switch (status) {
      TableStatus.available => (border: _v4Available, fill: _v4AvailableBg),
      TableStatus.occupied => (border: _v4Busy, fill: _v4BusyBg),
      TableStatus.reserved => (border: _v4Reserved, fill: _v4ReservedBg),
      TableStatus.dirty => (border: _v4Clean, fill: _v4CleanBg),
    };
  }

  String _statusLabel(TableStatus status) => switch (status) {
        TableStatus.available => 'AVAILABLE',
        TableStatus.occupied => 'BUSY',
        TableStatus.reserved => 'RESERVED',
        TableStatus.dirty => 'CHECK',
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
      // Kitchen & Inventory entries removed — out of scope for the pilot POS.
      ('Reports', Icons.analytics_rounded),
    ];

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      color: AppColors.surfaceContainerLow,
      child: Row(
        children: [
          // Mode-switcher pill — one-tap mode change from anywhere.
          // 2026-05-17 UX overhaul: replaces the Settings → POS Modu
          // round-trip with an inline header affordance.
          const ModeSwitcherPill(),
          const SizedBox(width: 14),
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

          // 2026-05-17: dropdown promoted to inline chip row below
          // the top-nav. Single chip in the nav is dead weight when
          // the count rail is right under it.

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

  /// v4 inline filter chip row — replaces the v3 dropdown. Chips show
  /// per-state counts so the operator can see how many tables match
  /// each filter without opening a popup. Counts are computed from
  /// `enrichedTablesProvider` so they stay live as tickets open/close.
  Widget _buildFilterChipRow() {
    final selected = ref.watch(floorPlanFilterProvider);
    final enriched =
        ref.watch(enrichedTablesProvider).value ?? const <EnrichedTable>[];
    final activeCount = enriched
        .where((e) =>
            e.isOccupied || e.table.status == TableStatus.occupied)
        .length;
    final pendingCount = enriched
        .where((e) => e.table.flags.contains(TableFlag.billRequested))
        .length;
    final freeCount = enriched
        .where((e) =>
            !e.isOccupied &&
            (e.table.status == TableStatus.available ||
                e.table.status == TableStatus.dirty))
        .length;
    final reservedCount = enriched
        .where((e) => e.table.status == TableStatus.reserved)
        .length;
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _FloorFilterChip(
            label: 'Tümü',
            icon: Icons.apps_rounded,
            count: enriched.length,
            tint: AppColors.textPrimary,
            tintBg: AppColors.surfaceContainerHigh,
            selected: selected == FloorPlanFilter.all,
            onTap: () => ref.read(floorPlanFilterProvider.notifier).state =
                FloorPlanFilter.all,
          ),
          const SizedBox(width: 8),
          _FloorFilterChip(
            label: 'Açık',
            icon: Icons.local_fire_department_rounded,
            count: activeCount,
            tint: _v4Busy,
            tintBg: _v4BusyBg,
            selected: selected == FloorPlanFilter.active,
            onTap: () => ref.read(floorPlanFilterProvider.notifier).state =
                FloorPlanFilter.active,
          ),
          const SizedBox(width: 8),
          _FloorFilterChip(
            label: 'Ödeme',
            icon: Icons.payments_outlined,
            count: pendingCount,
            tint: _v4Bill,
            tintBg: _v4BillBg,
            selected: selected == FloorPlanFilter.pending,
            onTap: () => ref.read(floorPlanFilterProvider.notifier).state =
                FloorPlanFilter.pending,
          ),
          const SizedBox(width: 8),
          _FloorFilterChip(
            label: 'Boş',
            icon: Icons.event_seat_outlined,
            count: freeCount,
            tint: _v4Available,
            tintBg: const Color(0xFFDCFCE7),
            selected: selected == FloorPlanFilter.free,
            onTap: () => ref.read(floorPlanFilterProvider.notifier).state =
                FloorPlanFilter.free,
          ),
          if (reservedCount > 0) ...[
            const SizedBox(width: 8),
            _FloorFilterChip(
              label: 'Rezerve',
              icon: Icons.event_available_outlined,
              count: reservedCount,
              tint: _v4Reserved,
              tintBg: _v4ReservedBg,
              // Reserved doesn't have its own filter enum yet; tapping
              // surfaces a soft hint until that lands.
              selected: false,
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Rezerve filtre — yakında.'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
          ],
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
      color: AppColors.surfaceContainerLow,
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
      data: (allTables) {
        // Apply pilot zone filter (Hepsi = no filter).
        final selectedZone = ref.watch(selectedTableZoneProvider);
        final assignments = ref.watch(tableZoneAssignmentsProvider);
        final tables = selectedZone == TableZone.hepsi
            ? allTables
            : allTables
                .where((t) =>
                    tableZoneForId(assignments, t.id) == selectedZone)
                .toList();
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

            // Zone filter chips (Turkish labels). Hidden in edit mode
            // because drag positions are scoped to a floor, not a zone.
            if (!editMode) _buildZoneFilterBar(selectedZone),

            // v4 (2026-05-17) — state-filter chip row with live counts.
            // Sits under the zone filter so the two filter dimensions
            // (zone × state) read top-to-bottom.
            if (!editMode && _isGridView)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: _buildFilterChipRow(),
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

  // -------------------------------------------------------------------------
  // Zone filter bar (Hepsi / İç Salon / Teras / Bar)
  // -------------------------------------------------------------------------

  Widget _buildZoneFilterBar(TableZone selected) {
    const zones = TableZone.values;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
      child: SizedBox(
        height: 34,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: zones.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final zone = zones[i];
            final isActive = zone == selected;
            return GestureDetector(
              onTap: () => ref
                  .read(selectedTableZoneProvider.notifier)
                  .state = zone,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppColors.accentDim
                      : AppColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(999),
                  border: isActive
                      ? Border.all(color: AppColors.accent, width: 1)
                      : null,
                ),
                child: Text(
                  tableZoneLabel(zone),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        isActive ? FontWeight.w600 : FontWeight.w400,
                    color: isActive
                        ? AppColors.accent
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            );
          },
        ),
      ),
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
    // Faz 2 (2026-05-15): pull the joined view so each tile can render
    // guest count + sitting duration + gross total + waiter initials.
    // The provider drops to AsyncLoading only on first paint; subsequent
    // table / ticket updates push through without flicker.
    final enrichedAsync = ref.watch(enrichedTablesProvider);
    final filter = ref.watch(floorPlanFilterProvider);
    final enrichedAll = enrichedAsync.value ?? const <EnrichedTable>[];
    // Cross-reference with the zone-filtered `tables` list (the caller
    // already applied the Hepsi/İç/Teras/Bar filter, so we honour that).
    final tableIds = tables.map((t) => t.id).toSet();
    final enriched = enrichedAll
        .where((e) => tableIds.contains(e.table.id))
        .where((e) => _matchesFilter(e, filter))
        .toList(growable: false);

    if (enriched.isEmpty && filter != FloorPlanFilter.all) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Text(
            'Bu filtreye uyan masa yok.',
            style: const TextStyle(
              color: AppColors.textDim,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(builder: (context, constraints) {
      // Tiles got more content in v3 — slightly bigger target (~200dp)
      // and shorter aspect ratio so guest / duration / total / waiter
      // fit without squishing.
      final cols = (constraints.maxWidth / 200).floor().clamp(3, 6);
      return GridView.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          // 0.85 = slightly taller than wide → leaves vertical room for
          // the 4-line occupied-state body.
          childAspectRatio: 0.85,
        ),
        itemCount: enriched.length,
        itemBuilder: (_, i) => _buildTableTile(enriched[i]),
      );
    });
  }

  /// Map a [FloorPlanFilter] to a predicate against the enriched row.
  bool _matchesFilter(EnrichedTable e, FloorPlanFilter f) {
    return switch (f) {
      FloorPlanFilter.all => true,
      FloorPlanFilter.active =>
        e.isOccupied || e.table.status == TableStatus.occupied,
      FloorPlanFilter.pending =>
        e.table.flags.contains(TableFlag.billRequested),
      FloorPlanFilter.free =>
        !e.isOccupied &&
            (e.table.status == TableStatus.available ||
                e.table.status == TableStatus.dirty),
    };
  }

  /// v4 tile — premium card. Tinted background + saturated border per
  /// status (BILL flag overrides to orange). InkWell ripple + scale
  /// feedback on press. Long-press still surfaces the detail sheet so
  /// power-user flows (transfer / merge / split) remain reachable.
  Widget _buildTableTile(EnrichedTable enriched) {
    final table = enriched.table;
    final ticket = enriched.ticket;
    final occupied = enriched.isOccupied;
    final palette = _statusPalette(table.status, table.flags.toSet());
    final isRound = table.shape == TableShape.circle;
    final billRequested = table.flags.contains(TableFlag.billRequested);

    return _TilePressable(
      onTap: () => _onTableTap(table),
      onLongPress: () => showTableDetailSheet(context, table),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: palette.fill,
              borderRadius: isRound
                  ? BorderRadius.circular(100)
                  : BorderRadius.circular(10),
              border: Border.all(color: palette.border, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: palette.border.withValues(alpha: 0.10),
                  blurRadius: 6,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Stack(
              children: [
                // 4dp left bar — kept as a secondary cue (helps tile
                // scanning at a glance when the fill tint is subtle on
                // white backgrounds like Available).
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 4,
                    decoration: BoxDecoration(
                      color: palette.border,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(10),
                        bottomLeft: Radius.circular(10),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              table.name,
                              style: const TextStyle(
                                fontFamily: 'WorkSans',
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                                color: AppColors.textPrimary,
                                letterSpacing: -0.8,
                                height: 1.0,
                              ),
                            ),
                          ),
                          if (billRequested)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: palette.border,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'BILL',
                                style: TextStyle(
                                  fontFamily: 'WorkSans',
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: palette.border.withValues(alpha: 0.20),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _statusLabel(table.status),
                                style: TextStyle(
                                  fontFamily: 'WorkSans',
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  color: palette.border,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: occupied
                            ? _OccupiedBody(table: table, ticket: ticket!)
                            : _FreeBody(table: table),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (table.flags.isNotEmpty)
            Positioned(
              top: 4,
              right: 4,
              child: _TableFlagBadges(flags: table.flags, iconSize: 12),
            ),
        ],
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
      color: AppColors.surfaceContainerLow,
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

    return Semantics(
      button: true,
      label:
          '${table.name}, $statusLabel, ${table.capacity} kişilik',
      child: GestureDetector(
      onTap: onTap,
      onPanUpdate: (details) => onDragUpdate(details.delta),
      onPanEnd: (_) => onDragEnd(),
      child: SizedBox(
        width: table.width,
        height: table.height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
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
            if (table.flags.isNotEmpty)
              Positioned(
                top: 2,
                right: 2,
                child: _TableFlagBadges(flags: table.flags, iconSize: 10),
              ),
          ],
        ),
      ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// TableFlag badge overlay
// ---------------------------------------------------------------------------

/// Renders up to 3 small pill badges in priority order:
/// vip > billRequested > reservationSoon > needsAttention.
///
/// Priority cap keeps the tile from being drowned by simultaneous flags
/// (a VIP table can also have a bill request and an upcoming reservation;
/// showing all four would overflow the tile on small grid sizes).
class _TableFlagBadges extends StatelessWidget {
  const _TableFlagBadges({
    required this.flags,
    this.iconSize = 12,
  });

  final Set<TableFlag> flags;
  final double iconSize;

  static const _priority = <TableFlag>[
    TableFlag.vip,
    TableFlag.billRequested,
    TableFlag.reservationSoon,
    TableFlag.needsAttention,
  ];

  @override
  Widget build(BuildContext context) {
    final visible = _priority.where(flags.contains).take(3).toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 2,
      children: [
        for (final f in visible)
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: _bgFor(f),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Icon(_iconFor(f), size: iconSize, color: _fgFor(f)),
          ),
      ],
    );
  }

  IconData _iconFor(TableFlag f) {
    switch (f) {
      case TableFlag.vip:
        return Icons.star_rounded;
      case TableFlag.billRequested:
        return Icons.receipt_long_rounded;
      case TableFlag.reservationSoon:
        return Icons.schedule_rounded;
      case TableFlag.needsAttention:
        return Icons.priority_high_rounded;
    }
  }

  Color _bgFor(TableFlag f) {
    switch (f) {
      case TableFlag.vip:
        return const Color(0xFFFFD60A).withValues(alpha: 0.22);
      case TableFlag.billRequested:
        return const Color(0xFF4F8CFF).withValues(alpha: 0.22);
      case TableFlag.reservationSoon:
        return const Color(0xFFFF9F0A).withValues(alpha: 0.22);
      case TableFlag.needsAttention:
        return const Color(0xFFFF453A).withValues(alpha: 0.22);
    }
  }

  Color _fgFor(TableFlag f) {
    switch (f) {
      case TableFlag.vip:
        return const Color(0xFFFFD60A);
      case TableFlag.billRequested:
        return const Color(0xFF4F8CFF);
      case TableFlag.reservationSoon:
        return const Color(0xFFFF9F0A);
      case TableFlag.needsAttention:
        return const Color(0xFFFF453A);
    }
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

// ---------------------------------------------------------------------------
// Faz 2 grid-tile bodies — occupied / free states.
// Kept as separate widgets so the tile builder stays small and each
// state's content can evolve independently (e.g. reserved-state body
// will likely add the booking time + guest name next sprint).
// ---------------------------------------------------------------------------

class _OccupiedBody extends StatelessWidget {
  const _OccupiedBody({required this.table, required this.ticket});
  final RestaurantTableEntity table;
  final TicketEntity ticket;

  String _waiterInitials() {
    final id = ticket.waiterId ?? '';
    if (id.isEmpty) return '—';
    // Display first two ASCII letters of the id as a stable initial
    // for the pilot. Faz 3+ will swap to a real `waiterId → name`
    // lookup once the users provider is wired through this widget.
    final clean = id.replaceAll(RegExp(r'[^A-Za-z]'), '');
    if (clean.isEmpty) return id.substring(0, id.length.clamp(0, 2)).toUpperCase();
    return clean.substring(0, clean.length.clamp(0, 2)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final guests = ticket.guestCount;
    final capacity = table.capacity;
    final delta = DateTime.now().difference(ticket.openedAt);
    final durationLabel = delta.inHours > 0
        ? '${delta.inHours}h${(delta.inMinutes % 60).toString().padLeft(2, '0')}'
        : "${delta.inMinutes}'";
    final totalLabel = 'CHF ${(ticket.total / 100).toStringAsFixed(2)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Icon(Icons.person_rounded, size: 12, color: AppColors.textDim),
            const SizedBox(width: 4),
            Text(
              '$guests/$capacity',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const Spacer(),
            const Icon(Icons.timer_outlined, size: 12, color: AppColors.textDim),
            const SizedBox(width: 3),
            Text(
              durationLabel,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          totalLabel,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: AppColors.textPrimary,
            fontFeatures: [FontFeature.tabularFigures()],
            letterSpacing: -0.3,
          ),
        ),
        const Spacer(),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.accentDim,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                '↳ ${_waiterInitials()}',
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: AppColors.accent,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Press-feedback wrapper for the v4 tile — adds a Material ripple +
/// a 0.97 scale on press. Keeps the tap target square so tablet thumb
/// hits land cleanly.
class _TilePressable extends StatefulWidget {
  const _TilePressable({
    required this.child,
    required this.onTap,
    required this.onLongPress,
  });
  final Widget child;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  State<_TilePressable> createState() => _TilePressableState();
}

class _TilePressableState extends State<_TilePressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      scale: _pressed ? 0.97 : 1.0,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          onHighlightChanged: (v) => setState(() => _pressed = v),
          borderRadius: BorderRadius.circular(10),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Floor-plan v4 filter chip with live count badge.
class _FloorFilterChip extends StatelessWidget {
  const _FloorFilterChip({
    required this.label,
    required this.icon,
    required this.count,
    required this.tint,
    required this.tintBg,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final int count;
  final Color tint;
  final Color tintBg;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : tint;
    return Material(
      color: selected ? tint : tintBg,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? tint : tint.withValues(alpha: 0.30),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: fg,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(width: 7),
              Container(
                constraints: const BoxConstraints(minWidth: 18),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.22)
                      : tint.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: fg,
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FreeBody extends StatelessWidget {
  const _FreeBody({required this.table});
  final RestaurantTableEntity table;

  @override
  Widget build(BuildContext context) {
    final dirty = table.status == TableStatus.dirty;
    final reserved = table.status == TableStatus.reserved;
    final label = dirty
        ? 'CHECK'
        : reserved
            ? 'RESERVE'
            : 'FREE';
    final caption = dirty
        ? 'needs clean'
        : reserved
            ? null
            : 'tippen → öffnen';
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Spacer(),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: dirty
                ? AppColors.yellow
                : reserved
                    ? AppColors.orange
                    : AppColors.green,
            letterSpacing: 1.4,
          ),
        ),
        if (caption != null) ...[
          const SizedBox(height: 4),
          Text(
            caption,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textDim,
            ),
          ),
        ],
        const Spacer(),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.person_outline_rounded,
                size: 12, color: AppColors.textDim),
            const SizedBox(width: 4),
            Text(
              'kap. ${table.capacity}',
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textDim,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
