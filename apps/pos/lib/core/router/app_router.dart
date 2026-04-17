/// GoRouter configuration for GastroCore POS.
///
/// Navigation flow:
///   1. App launch → auth guard checks brand JWT.
///   2. No valid JWT → `/brand-login` (email/password).
///   3. Valid JWT → `/login` (staff PIN selection).
///   4. Successful PIN → `/shift-open` or `/home`.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/auth/presentation/screens/pin_login_screen.dart';
import 'package:gastrocore_pos/features/brand_auth/presentation/screens/brand_login_screen.dart';
import 'package:gastrocore_pos/features/brand_auth/presentation/screens/register_screen.dart';
import 'package:gastrocore_pos/features/shifts/presentation/screens/shift_open_screen.dart';
import 'package:gastrocore_pos/features/shifts/presentation/screens/z_report_screen.dart';
import 'package:gastrocore_pos/features/home/presentation/screens/home_screen.dart';
import 'package:gastrocore_pos/features/orders/presentation/screens/order_center_screen.dart';
import 'package:gastrocore_pos/features/orders/presentation/shells/pos_shell_router.dart';
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
import 'package:gastrocore_pos/features/license/flag_gate_widget.dart';
import 'package:gastrocore_pos/features/license/license_models.dart';
import 'package:gastrocore_pos/features/license/license_screen.dart';
import 'package:gastrocore_pos/features/orders/presentation/screens/void_screen.dart';
import 'package:gastrocore_pos/features/orders/presentation/screens/qr_bill_screen.dart';
import 'package:gastrocore_pos/features/reservations/presentation/screens/reservation_calendar_screen.dart';
import 'package:gastrocore_pos/features/reservations/presentation/screens/reservation_detail_screen.dart';
import 'package:gastrocore_pos/features/reservations/presentation/screens/reservation_form_screen.dart';
import 'package:gastrocore_pos/features/reservations/presentation/screens/reservation_list_screen.dart';
import 'package:gastrocore_pos/features/customers/presentation/screens/customer_list_screen.dart';
import 'package:gastrocore_pos/features/customers/presentation/screens/customer_detail_screen.dart';
import 'package:gastrocore_pos/features/dashboard/presentation/screens/analytics_screen.dart';

// ---------------------------------------------------------------------------
// Route path constants
// ---------------------------------------------------------------------------

abstract final class AppRoutes {
  // ── Brand auth (new) ──────────────────────────────────────────────────────
  static const String brandLogin = '/brand-login';
  static const String register = '/register';
  static const String forgotPassword = '/forgot-password';

  // ── Staff PIN login ───────────────────────────────────────────────────────
  static const String login = '/login';

  // ── Core POS screens ─────────────────────────────────────────────────────
  static const String shiftOpen = '/shift-open';
  static const String home = '/home';
  static const String orderCenter = '/order-center';

  /// Legacy Ongoing / Tables / Menu three-tab screen. Kept as an escape
  /// hatch while the new [PosShellRouter] is the default for /order-center.
  /// Remove once the fine-dining shell has covered everything the legacy
  /// tabs exposed (tracked in Obsidian: Restaurant - POS - Redesign Plan).
  static const String orderCenterLegacy = '/order-center-legacy';
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
  static const String license = '/license';
  static const String voidOrder = '/void/:ticketId';
  static const String qrBill = '/qr-bill';
  static const String zReport = '/z-report';
  static const String reservations = '/reservations';
  static const String reservationCalendar = '/reservations/calendar';
  static const String reservationNew = '/reservations/new';
  static const String _reservationDetail = '/reservations/:id';
  static const String _reservationEdit = '/reservations/:id/edit';

  static String reservationDetail(String id) => '/reservations/$id';
  static String reservationEdit(String id) => '/reservations/$id/edit';
  static const String customers = '/customers';
  static const String customerDetail = '/customers/:customerId';
  static const String analytics = '/analytics';

  /// Build a void route for a specific ticket.
  static String voidFor(String ticketId) => '/void/$ticketId';

  /// Build a customer detail route.
  static String customerDetailFor(String customerId) =>
      '/customers/$customerId';

  // ── Legacy aliases ────────────────────────────────────────────────────────
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

  // ---------------------------------------------------------------------------
  // Auth guard helpers
  // ---------------------------------------------------------------------------

  /// Routes accessible without brand JWT authentication.
  static const _publicRoutes = {brandLogin, register, forgotPassword};

  /// Returns `true` when [path] requires brand authentication.
  static bool requiresBrandAuth(String path) =>
      !_publicRoutes.contains(path);
}

// ---------------------------------------------------------------------------
// Auth state accessor type
// ---------------------------------------------------------------------------

/// Provides the current brand auth state to the router redirect.
typedef BrandAuthReader = ({bool isInitialized, bool isAuthenticated});

// ---------------------------------------------------------------------------
// Router factory
// ---------------------------------------------------------------------------

/// Creates a new [GoRouter] instance for the application.
///
/// [authReader] is called on every redirect evaluation and returns the
/// current brand auth snapshot. Pass `null` for flavors that skip brand auth
/// (KDS, kiosk, etc.).
///
/// [authListenable] is used to tell GoRouter when to re-evaluate the redirect
/// (e.g. when the user logs in or out). Pass `null` for no auto-redirect.
GoRouter createAppRouter({
  BrandAuthReader Function()? authReader,
  Listenable? authListenable,
}) =>
    GoRouter(
      initialLocation: '/',
      refreshListenable: authListenable,
      redirect: (context, state) {
        if (authReader == null) return null;

        final auth = authReader();

        // While startup token-restore is running, don't redirect.
        if (!auth.isInitialized) return null;

        final path = state.matchedLocation;
        final isPublic = !AppRoutes.requiresBrandAuth(path);

        if (!auth.isAuthenticated && !isPublic) {
          return AppRoutes.brandLogin;
        }

        if (auth.isAuthenticated && isPublic) {
          // Already logged in — bounce away from auth screens.
          return AppRoutes.login;
        }

        return null;
      },
      routes: [
        GoRoute(
          path: '/',
          redirect: (_, __) => AppRoutes.login,
        ),

        // ── Brand auth ─────────────────────────────────────────────────────
        GoRoute(
          path: AppRoutes.brandLogin,
          builder: (context, state) => const BrandLoginScreen(),
        ),
        GoRoute(
          path: AppRoutes.register,
          builder: (context, state) => const RegisterScreen(),
        ),
        GoRoute(
          path: AppRoutes.forgotPassword,
          builder: (context, state) => const _ForgotPasswordScreen(),
        ),

        // ── Staff PIN login ────────────────────────────────────────────────
        GoRoute(
          path: AppRoutes.login,
          builder: (context, state) => const PinLoginScreen(),
        ),

        // ── POS screens ────────────────────────────────────────────────────
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
          builder: (context, state) => const PosShellRouter(),
        ),
        GoRoute(
          path: AppRoutes.orderCenterLegacy,
          builder: (context, state) => const OrderCenterScreen(),
        ),
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
          // KDS access requires the Pro plan or higher.
          builder: (context, state) => const FlagGate(
            flag: FeatureFlag.kds,
            child: KitchenDisplayScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.license,
          builder: (context, state) => const LicenseScreen(),
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
          path: AppRoutes.zReport,
          builder: (context, state) => const ZReportScreen(),
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
          path: AppRoutes.voidOrder,
          builder: (context, state) {
            final ticketId = state.pathParameters['ticketId'] ?? '';
            return VoidScreen(ticketId: ticketId);
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
          path: AppRoutes.qrBill,
          builder: (context, state) {
            final extra = state.extra as Map<String, dynamic>?;
            return QRBillScreen(
              ticketId: extra?['ticketId'] as String?,
              amountCents: extra?['amountCents'] as int?,
              customerName: extra?['customerName'] as String?,
              invoiceId: extra?['invoiceId'] as String?,
            );
          },
        ),
        GoRoute(
          path: AppRoutes.reservations,
          builder: (context, state) => const ReservationListScreen(),
        ),
        GoRoute(
          path: AppRoutes.reservationCalendar,
          builder: (context, state) => const ReservationCalendarScreen(),
        ),
        GoRoute(
          path: AppRoutes.reservationNew,
          builder: (context, state) => const ReservationFormScreen(),
        ),
        GoRoute(
          path: AppRoutes._reservationDetail,
          builder: (context, state) => ReservationDetailScreen(
            reservationId: state.pathParameters['id'] ?? '',
          ),
        ),
        GoRoute(
          path: AppRoutes._reservationEdit,
          builder: (context, state) => ReservationFormScreen(
            reservationId: state.pathParameters['id'],
          ),
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
        GoRoute(
          path: AppRoutes.analytics,
          builder: (context, state) => const AnalyticsScreen(),
        ),
      ],
    );

// ---------------------------------------------------------------------------
// Forgot-password placeholder screen
// ---------------------------------------------------------------------------

class _ForgotPasswordScreen extends StatelessWidget {
  const _ForgotPasswordScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceDim,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textSecondary),
        title: const Text(
          'Passwort vergessen',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_reset_rounded,
                size: 64,
                color: AppColors.primary,
              ),
              SizedBox(height: 24),
              Text(
                'Passwort zurücksetzen',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 12),
              Text(
                'Bitte besuchen Sie pos.2tech.ch/reset-password '
                'in Ihrem Browser, um Ihr Passwort zurückzusetzen.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: AppColors.textSecondary,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
