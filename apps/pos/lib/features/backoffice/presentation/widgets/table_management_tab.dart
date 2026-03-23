/// Table Management tab for the Back Office screen.
///
/// Visual table layout editor with floor selector tabs. Managers can add,
/// edit, and remove tables and floors on-device.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/features/tables/presentation/providers/table_provider.dart';
import 'package:gastrocore_pos/features/tables/domain/entities/table_entity.dart';
import 'package:gastrocore_pos/shared/widgets/pos_text_field.dart';
import 'package:gastrocore_pos/shared/widgets/pos_button.dart';

// ---------------------------------------------------------------------------
// TableManagementTab
// ---------------------------------------------------------------------------

class TableManagementTab extends ConsumerStatefulWidget {
  const TableManagementTab({super.key});

  @override
  ConsumerState<TableManagementTab> createState() =>
      _TableManagementTabState();
}

class _TableManagementTabState extends ConsumerState<TableManagementTab> {
  String? _selectedFloorId;

  @override
  Widget build(BuildContext context) {
    final floorsAsync = ref.watch(floorsProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // -- Floor selector tabs --
            _buildFloorTabs(floorsAsync),

            // -- Table layout area --
            Expanded(
              child: _buildTableArea(),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // Floor tabs
  // =========================================================================

  Widget _buildFloorTabs(AsyncValue<List<FloorEntity>> floorsAsync) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: floorsAsync.when(
        data: (floors) {
          // Auto-select first floor
          if (_selectedFloorId == null && floors.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() => _selectedFloorId = floors.first.id);
                ref.read(selectedFloorProvider.notifier).state =
                    floors.first.id;
              }
            });
          }

          return Row(
            children: [
              // Floor tabs
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final floor in floors) ...[
                        _buildFloorTab(floor),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Add floor button
              Material(
                color: AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _showFloorDialog,
                  splashColor: AppColors.textPrimary.withValues(alpha: 0.06),
                  child: const SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(
                      Icons.add_rounded,
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const SizedBox(
          height: 44,
          child: Center(
            child: CircularProgressIndicator(
              color: AppColors.primary,
              strokeWidth: 2,
            ),
          ),
        ),
        error: (e, _) => Text(
          'Hata: $e',
          style: const TextStyle(color: AppColors.red, fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildFloorTab(FloorEntity floor) {
    final isSelected = _selectedFloorId == floor.id;

    return GestureDetector(
      onLongPress: () => _showFloorDialog(existing: floor),
      child: Material(
        color: isSelected ? AppColors.surfaceBright : AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            setState(() => _selectedFloorId = floor.id);
            ref.read(selectedFloorProvider.notifier).state = floor.id;
          },
          splashColor: AppColors.textPrimary.withValues(alpha: 0.06),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            alignment: Alignment.center,
            child: Text(
              floor.name,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // Table area
  // =========================================================================

  Widget _buildTableArea() {
    if (_selectedFloorId == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.table_bar_rounded, size: 48, color: AppColors.textDim),
            SizedBox(height: 16),
            Text(
              'Bir kat secin veya yeni kat ekleyin',
              style: TextStyle(color: AppColors.textDim, fontSize: 14),
            ),
          ],
        ),
      );
    }

    final tablesAsync = ref.watch(tablesProvider);

    return Column(
      children: [
        Expanded(
          child: tablesAsync.when(
            data: _buildTableGrid,
            loading: () => const Center(
              child: CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 2,
              ),
            ),
            error: (e, _) => Center(
              child: Text(
                'Hata: $e',
                style: const TextStyle(color: AppColors.red, fontSize: 13),
              ),
            ),
          ),
        ),

        // Add table button
        Padding(
          padding: const EdgeInsets.all(16),
          child: PosGradientButton(
            label: 'Masa Ekle',
            icon: Icons.add_rounded,
            height: 44,
            onPressed: _showTableDialog,
          ),
        ),
      ],
    );
  }

  Widget _buildTableGrid(List<RestaurantTableEntity> tables) {
    if (tables.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.table_restaurant_rounded,
                size: 40, color: AppColors.textDim),
            SizedBox(height: 12),
            Text(
              'Bu katta henuz masa yok',
              style: TextStyle(color: AppColors.textDim, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(20),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 160,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 1.0,
        ),
        itemCount: tables.length,
        itemBuilder: (context, index) => _buildTableTile(tables[index]),
      ),
    );
  }

  Widget _buildTableTile(RestaurantTableEntity table) {
    final statusColor = switch (table.status) {
      TableStatus.available => AppColors.green,
      TableStatus.occupied => AppColors.red,
      TableStatus.reserved => AppColors.orange,
      TableStatus.dirty => AppColors.yellow,
    };

    final isCircle = table.shape == TableShape.circle;

    return GestureDetector(
      onTap: () => _showTableDialog(existing: table),
      onLongPress: () => _showTableActions(table),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius:
              BorderRadius.circular(isCircle ? 999 : 12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Status dot
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(height: 8),

            // Table name
            Text(
              table.name,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),

            // Capacity
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.person_outline_rounded,
                    size: 14, color: AppColors.textDim),
                const SizedBox(width: 4),
                Text(
                  '${table.capacity}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textDim,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showTableActions(RestaurantTableEntity table) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainerHighest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_rounded,
                  color: AppColors.textPrimary),
              title: const Text(
                'Duzenle',
                style: TextStyle(color: AppColors.textPrimary),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _showTableDialog(existing: table);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_rounded, color: AppColors.red),
              title: const Text(
                'Sil',
                style: TextStyle(color: AppColors.red),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _deleteTable(table);
              },
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // Floor dialog
  // =========================================================================

  Future<void> _showFloorDialog({FloorEntity? existing}) async {
    final nameController =
        TextEditingController(text: existing?.name ?? '');

    final result = await showDialog<bool>(
      context: context,
      barrierColor: AppColors.bgOverlay,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.surfaceContainerHighest,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  existing != null ? 'Kat Duzenle' : 'Kat Ekle',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 20),
                PosTextField(
                  label: 'Kat Adi',
                  hint: 'ornegin: Ana Salon',
                  controller: nameController,
                  autofocus: true,
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: PosGhostButton(
                        label: 'Iptal',
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: PosGradientButton(
                        label: 'Kaydet',
                        height: 44,
                        onPressed: () => Navigator.pop(ctx, true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (result == true && nameController.text.trim().isNotEmpty) {
      final db = ref.read(databaseProvider);
      final tenantId = ref.read(tenantIdProvider);
      final now = DateTime.now();

      if (existing != null) {
        await (db.update(db.floors)
              ..where((f) => f.id.equals(existing.id)))
            .write(FloorsCompanion(
          name: Value(nameController.text.trim()),
          updatedAt: Value(now),
        ));
      } else {
        final floors = await ref.read(floorsProvider.future);
        await db.into(db.floors).insert(FloorsCompanion(
              id: Value(IdGenerator.generateId()),
              tenantId: Value(tenantId),
              name: Value(nameController.text.trim()),
              displayOrder: Value(floors.length),
              createdAt: Value(now),
              updatedAt: Value(now),
              isDeleted: const Value(false),
              syncStatus: const Value(0),
            ));
      }

      ref.invalidate(floorsProvider);
    }

    nameController.dispose();
  }

  // =========================================================================
  // Table dialog
  // =========================================================================

  Future<void> _showTableDialog({RestaurantTableEntity? existing}) async {
    final nameController =
        TextEditingController(text: existing?.name ?? '');
    final capacityController =
        TextEditingController(text: existing?.capacity.toString() ?? '4');
    TableShape selectedShape = existing?.shape ?? TableShape.rectangle;

    final result = await showDialog<bool>(
      context: context,
      barrierColor: AppColors.bgOverlay,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: AppColors.surfaceContainerHighest,
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    existing != null ? 'Masa Duzenle' : 'Masa Ekle',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Name
                  PosTextField(
                    label: 'Masa Adi',
                    hint: 'ornegin: T1, Bar 3',
                    controller: nameController,
                    autofocus: true,
                  ),
                  const SizedBox(height: 16),

                  // Capacity
                  PosTextField(
                    label: 'Kapasite',
                    hint: '4',
                    controller: capacityController,
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),

                  // Shape selector
                  const Text(
                    'Sekil',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _shapeOption(
                        'Dikdortgen',
                        Icons.crop_landscape_rounded,
                        TableShape.rectangle,
                        selectedShape,
                        (s) => setDialogState(() => selectedShape = s),
                      ),
                      const SizedBox(width: 8),
                      _shapeOption(
                        'Kare',
                        Icons.crop_square_rounded,
                        TableShape.square,
                        selectedShape,
                        (s) => setDialogState(() => selectedShape = s),
                      ),
                      const SizedBox(width: 8),
                      _shapeOption(
                        'Daire',
                        Icons.circle_outlined,
                        TableShape.circle,
                        selectedShape,
                        (s) => setDialogState(() => selectedShape = s),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Actions
                  Row(
                    children: [
                      Expanded(
                        child: PosGhostButton(
                          label: 'Iptal',
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: PosGradientButton(
                          label: 'Kaydet',
                          height: 44,
                          onPressed: () => Navigator.pop(ctx, true),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (result == true && nameController.text.trim().isNotEmpty) {
      final db = ref.read(databaseProvider);
      final tenantId = ref.read(tenantIdProvider);
      final now = DateTime.now();
      final capacity = int.tryParse(capacityController.text) ?? 4;
      final shapeStr = switch (selectedShape) {
        TableShape.rectangle => 'rectangle',
        TableShape.circle => 'circle',
        TableShape.square => 'square',
      };

      if (existing != null) {
        await (db.update(db.restaurantTables)
              ..where((t) => t.id.equals(existing.id)))
            .write(RestaurantTablesCompanion(
          name: Value(nameController.text.trim()),
          capacity: Value(capacity),
          shape: Value(shapeStr),
          updatedAt: Value(now),
        ));
      } else {
        // Calculate grid position for new table
        final tables = await ref.read(tablesProvider.future);
        final col = tables.length % 4;
        final row = tables.length ~/ 4;

        await db.into(db.restaurantTables).insert(RestaurantTablesCompanion(
              id: Value(IdGenerator.generateId()),
              tenantId: Value(tenantId),
              floorId: Value(_selectedFloorId!),
              name: Value(nameController.text.trim()),
              capacity: Value(capacity),
              shape: Value(shapeStr),
              posX: Value(col * 140.0 + 20),
              posY: Value(row * 140.0 + 20),
              width: const Value(120.0),
              height: const Value(120.0),
              status: const Value('available'),
              createdAt: Value(now),
              updatedAt: Value(now),
              isDeleted: const Value(false),
              syncStatus: const Value(0),
            ));
      }

      ref.invalidate(tablesProvider);
    }

    nameController.dispose();
    capacityController.dispose();
  }

  Widget _shapeOption(
    String label,
    IconData icon,
    TableShape shape,
    TableShape selected,
    void Function(TableShape) onSelect,
  ) {
    final isSelected = shape == selected;
    return Expanded(
      child: GestureDetector(
        onTap: () => onSelect(shape),
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.accentDim
                : AppColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? AppColors.primary : AppColors.textDim,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color:
                      isSelected ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteTable(RestaurantTableEntity table) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: AppColors.bgOverlay,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.surfaceContainerHighest,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Masa Sil',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '"${table.name}" masasini silmek istediginize emin misiniz?',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: PosGhostButton(
                        label: 'Iptal',
                        onPressed: () => Navigator.pop(ctx, false),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: PosSolidButton(
                        label: 'Sil',
                        color: AppColors.red,
                        height: 44,
                        onPressed: () => Navigator.pop(ctx, true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmed == true) {
      final db = ref.read(databaseProvider);
      await (db.update(db.restaurantTables)
            ..where((t) => t.id.equals(table.id)))
          .write(RestaurantTablesCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(DateTime.now()),
      ));
      ref.invalidate(tablesProvider);
    }
  }
}
