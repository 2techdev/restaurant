/// Shell screen wrapping the three main waiter destinations with
/// a persistent [WaiterBottomNav].
///
/// GoRouter's [ShellRoute] supplies the [child] widget; we overlay our
/// bottom nav on top and sync the selected-index with the current route.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/features/waiter/presentation/widgets/waiter_bottom_nav.dart';
import 'package:gastrocore_pos/features/waiter/router/waiter_router.dart';

// ---------------------------------------------------------------------------
// WaiterShellScreen
// ---------------------------------------------------------------------------

class WaiterShellScreen extends StatelessWidget {
  final Widget child;

  const WaiterShellScreen({super.key, required this.child});

  int _selectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    if (location.startsWith('/waiter/order')) return 1;
    if (location.startsWith(WaiterRoutes.myOrders)) return 2;
    return 0; // Tables
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _selectedIndex(context);

    return Scaffold(
      body: child,
      bottomNavigationBar: WaiterBottomNav(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) {
          switch (index) {
            case 0:
              context.go(WaiterRoutes.tables);
            case 1:
              // Navigate to the order for whichever table is selected.
              // If no table is selected, fall back to tables screen.
              final current = GoRouterState.of(context).uri.toString();
              if (!current.startsWith('/waiter/order')) {
                context.go(WaiterRoutes.tables);
              }
            case 2:
              context.go(WaiterRoutes.myOrders);
          }
        },
      ),
    );
  }
}
