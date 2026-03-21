/// GoRouter configuration for the GastroCore Kiosk app.
///
/// Navigation flow (linear, no bottom nav):
///   /kiosk (welcome)
///     ↓ tap "Order Here"
///   /kiosk/language
///     ↓ select language
///   /kiosk/menu
///     ↓ tap product
///   /kiosk/product/:productId  (optional detail/modifier screen)
///     ↓ add to cart
///   /kiosk/cart
///     ↓ confirm
///   /kiosk/payment
///     ↓ paid
///   /kiosk/confirmation
///     ↓ auto-return after 10 s → /kiosk
library;

import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/features/kiosk/presentation/screens/kiosk_welcome_screen.dart';
import 'package:gastrocore_pos/features/kiosk/presentation/screens/kiosk_language_screen.dart';
import 'package:gastrocore_pos/features/kiosk/presentation/screens/kiosk_menu_screen.dart';
import 'package:gastrocore_pos/features/kiosk/presentation/screens/kiosk_product_detail_screen.dart';
import 'package:gastrocore_pos/features/kiosk/presentation/screens/kiosk_cart_screen.dart';
import 'package:gastrocore_pos/features/kiosk/presentation/screens/kiosk_payment_screen.dart';
import 'package:gastrocore_pos/features/kiosk/presentation/screens/kiosk_confirmation_screen.dart';

// ---------------------------------------------------------------------------
// Route constants
// ---------------------------------------------------------------------------

abstract final class KioskRoutes {
  static const String welcome = '/kiosk';
  static const String language = '/kiosk/language';
  static const String menu = '/kiosk/menu';
  static const String product = '/kiosk/product/:productId';
  static const String cart = '/kiosk/cart';
  static const String payment = '/kiosk/payment';
  static const String confirmation = '/kiosk/confirmation';

  static String productFor(String productId) => '/kiosk/product/$productId';
}

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------

final GoRouter kioskRouter = GoRouter(
  initialLocation: KioskRoutes.welcome,
  routes: [
    GoRoute(
      path: KioskRoutes.welcome,
      builder: (context, state) => const KioskWelcomeScreen(),
    ),
    GoRoute(
      path: KioskRoutes.language,
      builder: (context, state) => const KioskLanguageScreen(),
    ),
    GoRoute(
      path: KioskRoutes.menu,
      builder: (context, state) => const KioskMenuScreen(),
    ),
    GoRoute(
      path: KioskRoutes.product,
      builder: (context, state) {
        final productId = state.pathParameters['productId'] ?? '';
        return KioskProductDetailScreen(productId: productId);
      },
    ),
    GoRoute(
      path: KioskRoutes.cart,
      builder: (context, state) => const KioskCartScreen(),
    ),
    GoRoute(
      path: KioskRoutes.payment,
      builder: (context, state) => const KioskPaymentScreen(),
    ),
    GoRoute(
      path: KioskRoutes.confirmation,
      builder: (context, state) => const KioskConfirmationScreen(),
    ),
  ],
);
