/// KDS Station Filter Screen — select which kitchen station to display.
///
/// Stations match the [printerGroup] field on [KitchenTicketEntity].
/// Selecting a station filters the main KDS grid to show only that station's
/// tickets. Selecting "All Stations" clears the filter.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/kitchen/presentation/providers/kitchen_provider.dart';
import 'package:gastrocore_pos/features/kds_app/presentation/providers/kds_providers.dart';
import 'package:gastrocore_pos/features/kds_app/router/kds_router.dart';

// ---------------------------------------------------------------------------
// Builtin station definitions
// ---------------------------------------------------------------------------

class _Station {
  final String id; // matches printerGroup value
  final String label;
  final IconData icon;

  const _Station(this.id, this.label, this.icon);
}

const _kBuiltinStations = [
  _Station('kitchen', 'Kitchen', Icons.local_fire_department),
  _Station('grill', 'Grill', Icons.outdoor_grill),
  _Station('bar', 'Bar', Icons.local_bar),
  _Station('dessert', 'Dessert', Icons.cake),
  _Station('cold', 'Cold / Salads', Icons.ac_unit),
  _Station('fryer', 'Fryer', Icons.set_meal),
  _Station('expo', 'Expo / Pass', Icons.restaurant),
];

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class KdsStationFilterScreen extends ConsumerWidget {
  const KdsStationFilterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentFilter = ref.watch(kdsStationFilterProvider);
    final ticketsAsync = ref.watch(activeKitchenTicketsProvider);

    // Count active tickets per station group.
    final countByGroup = <String, int>{};
    ticketsAsync.valueOrNull?.forEach((t) {
      countByGroup[t.printerGroup] =
          (countByGroup[t.printerGroup] ?? 0) + 1;
    });

    void select(String? stationId) {
      ref.read(kdsStationFilterProvider.notifier).state = stationId;
      context.go(KdsRoutes.main);
    }

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1D27),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textSecondary),
          onPressed: () => context.go(KdsRoutes.main),
        ),
        title: const Text(
          'Station Filter',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select a station to show only its tickets on the main display.',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),

            // All stations tile
            _StationTile(
              icon: Icons.grid_view,
              label: 'All Stations',
              subtitle: '${ticketsAsync.valueOrNull?.length ?? 0} active tickets',
              isSelected: currentFilter == null,
              onTap: () => select(null),
            ),
            const SizedBox(height: 12),

            const Divider(color: AppColors.outlineVariant),
            const SizedBox(height: 12),

            Expanded(
              child: GridView.builder(
                gridDelegate:
                    const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 280,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 2.8,
                ),
                itemCount: _kBuiltinStations.length,
                itemBuilder: (context, i) {
                  final station = _kBuiltinStations[i];
                  final count = countByGroup[station.id] ?? 0;
                  return _StationTile(
                    icon: station.icon,
                    label: station.label,
                    subtitle: count > 0
                        ? '$count active ticket${count == 1 ? '' : 's'}'
                        : 'No active tickets',
                    isSelected: currentFilter == station.id,
                    onTap: () => select(station.id),
                    badgeCount: count,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tile widget
// ---------------------------------------------------------------------------

class _StationTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;
  final int badgeCount;

  const _StationTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.accentDim
              : AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? AppColors.primary.withValues(alpha: 0.6)
                : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 22,
              color: isSelected
                  ? AppColors.primary
                  : AppColors.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (badgeCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$badgeCount',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.orange,
                  ),
                ),
              ),
            if (isSelected)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(
                  Icons.check_circle,
                  size: 18,
                  color: AppColors.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
