/// GoRouter configuration for GastroCore POS.
///
/// Defines all application routes and maps them to their screen widgets.
/// The navigation flow is: login -> shift-open -> home (dashboard) ->
/// order-center (main POS with Ongoing/Table/Menu tabs).
library;

import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/features/auth/presentation/screens/pin_login_screen.dart';
import 'package:gastrocore_pos/features/shifts/presentation/screens/shift_open_screen.dart';
import 'package:gastrocore_pos/features/home/presentation/screens/home_screen.dart';
import 'package:gastrocore_pos/features/orders/presentation/screens/order_center_screen.dart';
// Legacy screens kept for reference but routes redirect to order-center
// import 'package:gastrocore_pos/features/orders/presentation/screens/pos_screen.dart';
// import 'package:gastrocore_pos/features/tables/presentation/screens/floor_plan_screen.dart';
import 'package:gastrocore_pos/features/kitchen/presentation/screens/kitchen_display_screen.dart';
import 'package:gastrocore_pos/features/payments/presentation/screens/payment_screen.dart';
import 'package:gastrocore_pos/features/shifts/presentation/screens/shift_close_screen.dart';
import 'package:gastrocore_pos/features/shifts/presentation/screens/day_close_screen.dart';
import 'package:gastrocore_pos/features/orders/presentation/screens/receipt_preview_screen.dart';
import 'package:gastrocore_pos/features/payments/presentation/screens/split_bill_screen.dart';
import 'package:gastrocore_pos/features/orders/presentation/screens/refund_screen.dart';
import 'package:gastrocore_pos/features/settings/presentation/screens/settings_screen.dart';
import 'package:gastrocore_pos/features/orders/presentation/screens/order_history_screen.dart';
import 'package:gastrocore_pos/features/backoffice/presentation/screens/back_office_screen.dart';
import 'package:gastrocore_pos/features/shifts/presentation/screens/shift_history_screen.dart';
import 'package:gastrocore_pos/features/audit_log/presentation/screens/audit_log_screen.dart';
import 'package:gastrocore_pos/features/menu/presentation/screens/menu_management_screen.dart';
import 'package:gastrocore_pos/features/customers/presentation/screens/customer_list_screen.dart';
import 'package:gastrocore_pos/features/customers/presentation/screens/customer_detail_screen.dart';

// ---------------------------------------------------------------------------
// Route path constants
// ---------------------------------------------------------------------------

abstract final class AppRoutes {
  static const String login = '/login';
  static const String shiftOpen = '/shift-open';
  static const String home = '/home';
  static const String orderCenter = '/order-center';
  static const String kitchen = '/kitchen';
  static const String payment = '/payment/:ticketId';
  static const String shiftClose = '/shift-close';
  static const String dayClose = '/day-close';
  static const String settings = '/settings';
  static const String backOffice = '/back-office';
  static const String orderHistory = '/order-history';
  static const String receipt = '/receipt/:ticketId';
  static const String splitBill = '/split-bill/:ticketId';
  static const String refund = '/refund/:ticketId';
  static const String shiftHistory = '/shift-history';
  static const String menuManagement = '/menu-management';
  static const String auditLog = '/audit-log';
  static const String customers = '/customers';
  static const String customerDetail = '/customers/:customerId';

  // Legacy routes kept for backward compatibility
  static const String pos = '/pos';
  static const String tables = '/tables';

  /// Build a payment route for a specific ticket.
  static String paymentFor(String ticketId) => '/payment/$ticketId';

  /// Build a receipt preview route for a specific ticket.
  static String receiptFor(String ticketId) => '/receipt/$ticketId';

  /// Build a split-bill route for a specific ticket.
  static String splitBillFor(String ticketId) => '/split-bill/$ticketId';

  /// Build a refund route for a specific ticket.
  static String refundFor(String ticketId) => '/refund/$ticketId';

  /// Build a customer detail route.
  static String customerDetailFor(String customerId) =>
      '/customers/$customerId';
}

// ---------------------------------------------------------------------------
// Router factory
// ---------------------------------------------------------------------------

/// Creates a new [GoRouter] instance for the application.
///
/// Each call returns a **fresh** router so that widget tests can obtain an
/// independent navigation stack without sharing state from a previous run.
///
/// Redirect `/` to `/login` so the app always starts at the PIN login screen.
/// After login with an open shift, navigate to `/home` (dashboard).
/// After opening a shift, navigate to `/home`.
/// Legacy `/pos` and `/tables` redirect to `/order-center`.
GoRouter createAppRouter() => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      redirect: (_, __) => AppRoutes.login,
    ),
    GoRoute(
      path: AppRoutes.login,
      builder: (context, state) => const PinLoginScreen(),
    ),
    GoRoute(
      path: AppRoutes.shiftOpen,
      builder: (context, state) => const ShiftOpenScreen(),
    ),
    GoRoute(
      path: AppRoutes.home,
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: AppRoutes.orderCenter,
      builder: (context, state) => const OrderCenterScreen(),
    ),
    // Legacy routes redirect to order-center
    GoRoute(
      path: AppRoutes.pos,
      redirect: (_, __) => AppRoutes.orderCenter,
    ),
    GoRoute(
      path: AppRoutes.tables,
      redirect: (_, __) => AppRoutes.orderCenter,
    ),
    GoRoute(
      path: AppRoutes.kitchen,
      builder: (context, state) => const KitchenDisplayScreen(),
    ),
    GoRoute(
      path: AppRoutes.payment,
      builder: (context, state) {
        final ticketId = state.pathParameters['ticketId'] ?? '';
        return PaymentScreen(ticketId: ticketId);
      },
    ),
    GoRoute(
      path: AppRoutes.shiftClose,
      builder: (context, state) => const ShiftCloseScreen(),
    ),
    GoRoute(
      path: AppRoutes.dayClose,
      builder: (context, state) => const DayCloseScreen(),
    ),
    GoRoute(
      path: AppRoutes.receipt,
      builder: (context, state) {
        final ticketId = state.pathParameters['ticketId'] ?? '';
        return ReceiptPreviewScreen(ticketId: ticketId);
      },
    ),
    GoRoute(
      path: AppRoutes.splitBill,
      builder: (context, state) {
        final ticketId = state.pathParameters['ticketId'] ?? '';
        return SplitBillScreen(ticketId: ticketId);
      },
    ),
    GoRoute(
      path: AppRoutes.refund,
      builder: (context, state) {
        final ticketId = state.pathParameters['ticketId'] ?? '';
        return RefundScreen(ticketId: ticketId);
      },
    ),
    GoRoute(
      path: AppRoutes.settings,
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: AppRoutes.orderHistory,
      builder: (context, state) => const OrderHistoryScreen(),
    ),
    GoRoute(
      path: AppRoutes.backOffice,
      builder: (context, state) => const BackOfficeScreen(),
    ),
    GoRoute(
      path: AppRoutes.shiftHistory,
      builder: (context, state) => const ShiftHistoryScreen(),
    ),
    GoRoute(
      path: AppRoutes.menuManagement,
      builder: (context, state) => const MenuManagementScreen(),
    ),
    GoRoute(
      path: AppRoutes.auditLog,
      builder: (context, state) => const AuditLogScreen(),
    ),
    GoRoute(
      path: AppRoutes.customers,
      builder: (context, state) => const CustomerListScreen(),
    ),
    GoRoute(
      path: AppRoutes.customerDetail,
      builder: (context, state) {
        final customerId = state.pathParameters['customerId'] ?? '';
        return CustomerDetailScreen(customerId: customerId);
      },
    ),
  ],
);
