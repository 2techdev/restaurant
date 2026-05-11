/// Persistent bottom navigation bar for the Waiter app shell.
///
/// Three destinations:
///   0 – Tables       (table-select grid)
///   1 – Order        (current order — shows item-count badge)
///   2 – My Orders    (active orders list)
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/waiter/presentation/providers/waiter_provider.dart';

// ---------------------------------------------------------------------------
// WaiterBottomNav
// ---------------------------------------------------------------------------

class WaiterBottomNav extends ConsumerWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const WaiterBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticket = ref.watch(waiterActiveTicketProvider);
    final itemCount = ticket?.itemCount ?? 0;
    final activeOrdersAsync = ref.watch(waiterActiveOrdersProvider);
    final activeOrderCount = activeOrdersAsync.asData?.value.length ?? 0;

    return NavigationBar(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.accentDim,
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      destinations: [
        const NavigationDestination(
          icon: Icon(Icons.table_restaurant_outlined),
          selectedIcon: Icon(Icons.table_restaurant, color: AppColors.primary),
          label: 'Masalar',
        ),
        NavigationDestination(
          icon: _BadgedIcon(
            icon: Icons.receipt_long_outlined,
            count: itemCount,
          ),
          selectedIcon: _BadgedIcon(
            icon: Icons.receipt_long,
            count: itemCount,
            iconColor: AppColors.primary,
          ),
          label: 'Sipariş',
        ),
        NavigationDestination(
          icon: _BadgedIcon(
            icon: Icons.list_alt_outlined,
            count: activeOrderCount,
          ),
          selectedIcon: _BadgedIcon(
            icon: Icons.list_alt,
            count: activeOrderCount,
            iconColor: AppColors.primary,
          ),
          label: 'Siparişlerim',
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _BadgedIcon — icon with optional count badge
// ---------------------------------------------------------------------------

class _BadgedIcon extends StatelessWidget {
  final IconData icon;
  final int count;
  final Color iconColor;

  const _BadgedIcon({
    required this.icon,
    required this.count,
    this.iconColor = AppColors.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    if (count <= 0) {
      return Icon(icon, color: iconColor);
    }
    return Badge(
      label: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      backgroundColor: AppColors.orange,
      child: Icon(icon, color: iconColor),
    );
  }
}
