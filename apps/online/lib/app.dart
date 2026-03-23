/// App router and root widget for GastroCore Online Ordering.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gastrocore_online/core/theme/app_theme.dart';
import 'package:gastrocore_online/l10n/app_localizations.dart';
import 'package:gastrocore_online/providers/locale_provider.dart';
import 'package:gastrocore_online/screens/landing_screen.dart';
import 'package:gastrocore_online/screens/menu_screen.dart';
import 'package:gastrocore_online/screens/product_detail_screen.dart';
import 'package:gastrocore_online/screens/cart_screen.dart';
import 'package:gastrocore_online/screens/checkout_screen.dart';
import 'package:gastrocore_online/screens/order_confirmation_screen.dart';
import 'package:gastrocore_online/screens/order_tracking_screen.dart';

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------

final _router = GoRouter(
  initialLocation: '/',
  redirect: (context, state) {
    // Root without restaurant ID → demo restaurant
    if (state.uri.path == '/') return '/demo';
    return null;
  },
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const _NoRestaurantPage(),
    ),
    GoRoute(
      path: '/:restaurantId',
      builder: (context, state) {
        final restaurantId = state.pathParameters['restaurantId']!;
        final table = state.uri.queryParameters['table'];
        return LandingScreen(
          restaurantId: restaurantId,
          tableFromQr: table != null ? int.tryParse(table) : null,
        );
      },
      routes: [
        GoRoute(
          path: 'menu',
          builder: (context, state) {
            final restaurantId = state.pathParameters['restaurantId']!;
            final table = state.uri.queryParameters['table'];
            return MenuScreen(
              restaurantId: restaurantId,
              tableFromQr: table != null ? int.tryParse(table) : null,
            );
          },
          routes: [
            GoRoute(
              path: 'product/:productId',
              builder: (context, state) {
                final restaurantId =
                    state.pathParameters['restaurantId']!;
                final productId = state.pathParameters['productId']!;
                return ProductDetailScreen(
                  restaurantId: restaurantId,
                  productId: productId,
                );
              },
            ),
          ],
        ),
        GoRoute(
          path: 'cart',
          builder: (context, state) {
            final restaurantId = state.pathParameters['restaurantId']!;
            return CartScreen(restaurantId: restaurantId);
          },
        ),
        GoRoute(
          path: 'checkout',
          builder: (context, state) {
            final restaurantId = state.pathParameters['restaurantId']!;
            return CheckoutScreen(restaurantId: restaurantId);
          },
        ),
        GoRoute(
          path: 'confirmation/:orderId',
          builder: (context, state) {
            final restaurantId = state.pathParameters['restaurantId']!;
            final orderId = state.pathParameters['orderId']!;
            final orderNumber =
                state.uri.queryParameters['number'] ?? orderId;
            return OrderConfirmationScreen(
              restaurantId: restaurantId,
              orderId: orderId,
              orderNumber: orderNumber,
            );
          },
        ),
        GoRoute(
          path: 'tracking/:orderId',
          builder: (context, state) {
            final restaurantId = state.pathParameters['restaurantId']!;
            final orderId = state.pathParameters['orderId']!;
            return OrderTrackingScreen(
              restaurantId: restaurantId,
              orderId: orderId,
            );
          },
        ),
      ],
    ),
  ],
);

// ---------------------------------------------------------------------------
// Root app widget
// ---------------------------------------------------------------------------

class OnlineOrderingApp extends ConsumerWidget {
  const OnlineOrderingApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    return MaterialApp.router(
      title: 'GastroCore Order',
      theme: buildOnlineTheme(),
      routerConfig: _router,
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('de'),
        Locale('fr'),
        Locale('it'),
      ],
      debugShowCheckedModeBanner: false,
    );
  }
}

// ---------------------------------------------------------------------------
// Fallback page when no restaurant ID is in the URL
// ---------------------------------------------------------------------------

class _NoRestaurantPage extends StatelessWidget {
  const _NoRestaurantPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.qr_code_2, size: 80, color: OnlineColors.primary),
            SizedBox(height: 16),
            Text(
              'QR-Code am Tisch scannen,\num die Speisekarte zu öffnen.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                color: OnlineColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
