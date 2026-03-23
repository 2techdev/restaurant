/// GoRouter configuration for the GastroCore Waiter app.
///
/// Navigation flow:
///   /waiter/login  →  /waiter/tables (select a table)
///                          ↓ tap a table
///                  /waiter/order/:tableId   (build the order)
///                          ↓ nav bar
///                  /waiter/my-orders        (active order list)
library;

import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/features/payments/presentation/screens/split_bill_screen.dart';
import 'package:gastrocore_pos/features/waiter/presentation/screens/waiter_login_screen.dart';
import 'package:gastrocore_pos/features/waiter/presentation/screens/table_select_screen.dart';
import 'package:gastrocore_pos/features/waiter/presentation/screens/waiter_order_screen.dart';
import 'package:gastrocore_pos/features/waiter/presentation/screens/waiter_active_orders_screen.dart';
import 'package:gastrocore_pos/features/waiter/presentation/screens/waiter_shell_screen.dart';

// ---------------------------------------------------------------------------
// Route constants
// ---------------------------------------------------------------------------

abstract final class WaiterRoutes {
  static const String login = '/waiter/login';
  static const String tables = '/waiter/tables';
  static const String order = '/waiter/order/:tableId';
  static const String myOrders = '/waiter/my-orders';
  static const String splitBill = '/waiter/split-bill/:ticketId';

  static String orderFor(String tableId) => '/waiter/order/$tableId';
  static String splitBillFor(String ticketId) => '/waiter/split-bill/$ticketId';
}

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------

/// Top-level waiter router. Starts at login; the shell wraps tables + order
/// screens with the persistent [WaiterBottomNav].
final GoRouter waiterRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      redirect: (_, __) => WaiterRoutes.login,
    ),
    GoRoute(
      path: WaiterRoutes.login,
      builder: (context, state) => const WaiterLoginScreen(),
    ),
    GoRoute(
      path: WaiterRoutes.splitBill,
      builder: (context, state) {
        final ticketId = state.pathParameters['ticketId'] ?? '';
        return SplitBillScreen(ticketId: ticketId);
      },
    ),
    // Shell route provides persistent bottom navigation bar.
    ShellRoute(
      builder: (context, state, child) => WaiterShellScreen(child: child),
      routes: [
        GoRoute(
          path: WaiterRoutes.tables,
          builder: (context, state) => const TableSelectScreen(),
        ),
        GoRoute(
          path: WaiterRoutes.order,
          builder: (context, state) {
            final tableId = state.pathParameters['tableId'] ?? '';
            return WaiterOrderScreen(tableId: tableId);
          },
        ),
        GoRoute(
          path: WaiterRoutes.myOrders,
          builder: (context, state) => const WaiterActiveOrdersScreen(),
        ),
      ],
    ),
  ],
);
