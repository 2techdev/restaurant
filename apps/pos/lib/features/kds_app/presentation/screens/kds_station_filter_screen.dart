/// KDS Station Filter Screen — select which kitchen station to display.
///
/// Stations match the [printerGroup] field on [KitchenTicketEntity] and are
/// loaded from the DB-backed [stationsProvider], so restaurants can manage
/// their own list from settings. Selecting a station filters the main KDS
/// grid to show only that station's tickets. Selecting "All Stations" clears
/// the filter.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/kitchen/presentation/providers/kitchen_provider.dart';
import 'package:gastrocore_pos/features/kds_app/presentation/providers/kds_providers.dart';
import 'package:gastrocore_pos/features/kds_app/router/kds_router.dart';
import 'package:gastrocore_pos/features/stations/presentation/providers/station_provider.dart';

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class KdsStationFilterScreen extends ConsumerWidget {
  const KdsStationFilterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentFilter = ref.watch(kdsStationFilterProvider);
    final ticketsAsync = ref.watch(activeKitchenTicketsProvider);
    final stationsAsync = ref.watch(stationsProvider);

    // Count active tickets per station code.
    final countByCode = <String, int>{};
    ticketsAsync.valueOrNull?.forEach((t) {
      countByCode[t.printerGroup] = (countByCode[t.printerGroup] ?? 0) + 1;
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
            _StationTile(
              icon: Icons.grid_view,
              label: 'All Stations',
              subtitle:
                  '${ticketsAsync.valueOrNull?.length ?? 0} active tickets',
              isSelected: currentFilter == null,
              onTap: () => select(null),
            ),
            const SizedBox(height: 12),
            const Divider(color: AppColors.outlineVariant),
            const SizedBox(height: 12),
            Expanded(
              child: stationsAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(),
                ),
                error: (err, _) => Center(
                  child: Text(
                    'Failed to load stations: $err',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ),
                data: (stations) {
                  if (stations.isEmpty) {
                    return const Center(
                      child: Text(
                        'No stations configured yet.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    );
                  }
                  return GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 280,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 2.8,
                    ),
                    itemCount: stations.length,
                    itemBuilder: (context, i) {
                      final station = stations[i];
                      final count = countByCode[station.code] ?? 0;
                      return _StationTile(
                        icon: station.iconData,
                        label: station.name,
                        subtitle: count > 0
                            ? '$count active ticket${count == 1 ? '' : 's'}'
                            : 'No active tickets',
                        isSelected: currentFilter == station.code,
                        onTap: () => select(station.code),
                        badgeCount: count,
                        accent: station.accentColor,
                      );
                    },
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
  final Color? accent;

  const _StationTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
    this.badgeCount = 0,
    this.accent,
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
                  : (accent ?? AppColors.textSecondary),
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
