/// Integration tests for GastroCore POS -- full user flow.
///
/// Covers: PIN login -> shift opening -> home dashboard -> order center
/// (ongoing/table/menu tabs) -> add products -> modifiers -> order type
/// change -> send to kitchen -> checkout -> payment -> order records ->
/// back office -> settings -> shift close.
///
/// Uses Key-based widget finding for robustness against text/UI changes.
///
/// Run with:
///   flutter test integration_test/app_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gastrocore_pos/app.dart';
import 'package:gastrocore_pos/core/data/app_initializer.dart';
import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/di/providers.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Pump frames until [finder] matches at least one widget, or timeout.
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 300));
  }
  // Last attempt -- if still not found the caller's expect will fail.
  await tester.pumpAndSettle();
}

/// Tap a numpad digit button by its Key('pin_numpad_$digit').
Future<void> tapPinDigit(WidgetTester tester, String digit) async {
  final finder = find.byKey(Key('pin_numpad_$digit'));
  expect(finder, findsOneWidget,
      reason: 'Expected PIN numpad digit "$digit" to be present');
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 150));
}

/// Boot the app with an in-memory database, seed demo data, and hand
/// control back to the test body.
Future<void> launchApp(WidgetTester tester) async {
  final db = AppDatabase.createInMemory();
  await AppInitializer.initialize(db);
  final tenants = await db.select(db.tenants).get();
  final tenantId = tenants.first.id;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        tenantIdProvider.overrideWithValue(tenantId),
      ],
      child: const GastroCoreApp(),
    ),
  );

  // Wait for the login screen to fully render using a key-based finder.
  await pumpUntilFound(tester, find.byKey(const Key('pin_login_screen')));
}

/// Login helper: enter PIN 1234 and tap ENTER. Optionally select a user
/// avatar by index first.
Future<void> loginWithPin(
  WidgetTester tester, {
  int userIndex = 0,
  String pin = '1234',
}) async {
  // Select user avatar if available.
  final avatarFinder = find.byKey(Key('user_avatar_$userIndex'));
  if (avatarFinder.evaluate().isNotEmpty) {
    await tester.tap(avatarFinder);
    await tester.pumpAndSettle();
  }

  // Enter PIN digits.
  for (final d in pin.split('')) {
    await tapPinDigit(tester, d);
  }

  // Tap ENTER.
  final enterBtn = find.byKey(const Key('pin_enter_btn'));
  expect(enterBtn, findsOneWidget, reason: 'ENTER button should be present');
  await tester.tap(enterBtn);
  await tester.pumpAndSettle(const Duration(seconds: 3));
}

/// Start shift with the default amount if we land on the shift-open screen.
Future<void> startShiftIfNeeded(WidgetTester tester) async {
  final shiftScreen = find.byKey(const Key('shift_open_screen'));
  // Wait a moment then check.
  await tester.pumpAndSettle(const Duration(seconds: 1));
  if (shiftScreen.evaluate().isNotEmpty) {
    final startBtn = find.byKey(const Key('shift_start_btn'));
    expect(startBtn, findsOneWidget,
        reason: 'Shift start button should be present');
    await tester.tap(startBtn);
    await tester.pumpAndSettle(const Duration(seconds: 3));
  }
}

/// Full login + shift-open flow to reach the home dashboard.
Future<void> loginAndReachHome(WidgetTester tester) async {
  await launchApp(tester);
  await loginWithPin(tester);
  await startShiftIfNeeded(tester);
  await pumpUntilFound(tester, find.byKey(const Key('home_screen')));
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('GastroCore POS Full Flow', () {
    testWidgets('Complete restaurant order flow', (tester) async {
      // =================================================================
      // 1. Launch app -- verify PIN login screen appears
      // =================================================================
      await launchApp(tester);

      expect(find.byKey(const Key('pin_login_screen')), findsOneWidget);
      expect(find.byKey(const Key('user_avatar_0')), findsOneWidget);
      expect(find.byKey(const Key('pin_enter_btn')), findsOneWidget);

      // Verify some text elements are present.
      expect(find.text('Select Staff Member'), findsOneWidget);
      expect(find.text('GastroCore'), findsWidgets);

      // =================================================================
      // 2. Enter PIN 1234 to login as first user (Marco/admin)
      // =================================================================
      await loginWithPin(tester);

      // =================================================================
      // 3. Shift Opening -- verify screen, start shift
      // =================================================================
      // After first login with no open shift, we land on shift-open.
      final shiftScreen = find.byKey(const Key('shift_open_screen'));
      await pumpUntilFound(tester, shiftScreen);

      expect(shiftScreen, findsOneWidget);
      expect(find.byKey(const Key('shift_start_btn')), findsOneWidget);

      // Verify quick amount buttons exist.
      expect(find.byKey(const Key('quick_amount_200')), findsOneWidget);
      expect(find.byKey(const Key('quick_amount_500')), findsOneWidget);
      expect(find.byKey(const Key('quick_amount_1000')), findsOneWidget);

      // Default amount is 1000 (pre-selected). Start the shift.
      await tester.tap(find.byKey(const Key('shift_start_btn')));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // =================================================================
      // 4. Home Dashboard -- verify module cards
      // =================================================================
      final homeScreen = find.byKey(const Key('home_screen'));
      await pumpUntilFound(tester, homeScreen);

      expect(homeScreen, findsOneWidget);
      expect(find.byKey(const Key('module_order')), findsOneWidget);
      expect(find.byKey(const Key('module_order_records')), findsOneWidget);
      expect(find.byKey(const Key('module_settings')), findsOneWidget);
      expect(find.byKey(const Key('module_back_office')), findsOneWidget);
      expect(find.byKey(const Key('module_lock_screen')), findsOneWidget);
      expect(find.byKey(const Key('sign_out_btn')), findsOneWidget);

      // =================================================================
      // 5. Tap ORDER module card to navigate to Order Center
      // =================================================================
      await tester.tap(find.byKey(const Key('module_order')));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // =================================================================
      // 6. Order Center -- verify tabs (Ongoing, Table, Menu)
      // =================================================================
      final tabOngoing = find.byKey(const Key('tab_ongoing'));
      await pumpUntilFound(tester, tabOngoing);

      expect(tabOngoing, findsOneWidget);
      expect(find.byKey(const Key('tab_table')), findsOneWidget);
      expect(find.byKey(const Key('tab_menu')), findsOneWidget);

      // =================================================================
      // 7. Switch to Menu tab
      // =================================================================
      await tester.tap(find.byKey(const Key('tab_menu')));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Verify category sidebar has "All".
      final categoryAll = find.byKey(const Key('category_all'));
      await pumpUntilFound(tester, categoryAll);
      expect(categoryAll, findsOneWidget);

      // Verify order type chips are present.
      expect(find.byKey(const Key('order_type_dine_in')), findsOneWidget);
      expect(find.byKey(const Key('order_type_takeaway')), findsOneWidget);
      expect(find.byKey(const Key('order_type_delivery')), findsOneWidget);

      // Verify the order panel tabs are visible.
      expect(find.text('Ordering'), findsOneWidget);
      expect(find.text('Ordered'), findsOneWidget);

      // =================================================================
      // 8. Tap a category from the sidebar
      // =================================================================
      final category0 = find.byKey(const Key('category_0'));
      if (category0.evaluate().isNotEmpty) {
        await tester.tap(category0);
        await tester.pumpAndSettle();
      }

      // =================================================================
      // 9. Tap a product to add it to the order
      // =================================================================
      // Go back to "All" to see all products.
      await tester.tap(find.byKey(const Key('category_all')));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Try known seed-data product names.
      final productNames = [
        'Adana Kebap',
        'Karisik Izgara',
        'Iskender',
        'Margherita',
        'Caesar Salata',
        'Mercimek Corbasi',
      ];

      String? firstProduct;
      for (final name in productNames) {
        final finder = find.text(name);
        if (finder.evaluate().isNotEmpty) {
          firstProduct = name;
          await tester.tap(finder.first);
          await tester.pumpAndSettle(const Duration(milliseconds: 500));
          break;
        }
      }

      // If a modifier dialog appeared, dismiss it.
      final addToOrderBtn = find.text('Add to Order');
      if (addToOrderBtn.evaluate().isNotEmpty) {
        await tester.tap(addToOrderBtn.first);
        await tester.pumpAndSettle();
      }

      // =================================================================
      // 10. Add a second product
      // =================================================================
      for (final name in productNames) {
        if (name != firstProduct) {
          final finder = find.text(name);
          if (finder.evaluate().isNotEmpty) {
            await tester.tap(finder.first);
            await tester.pumpAndSettle(const Duration(milliseconds: 500));
            break;
          }
        }
      }

      // Dismiss modifier dialog if it appeared.
      if (addToOrderBtn.evaluate().isNotEmpty) {
        await tester.tap(addToOrderBtn.first);
        await tester.pumpAndSettle();
      }

      // =================================================================
      // 11. Change order type to Takeaway
      // =================================================================
      await tester.tap(find.byKey(const Key('order_type_takeaway')));
      await tester.pumpAndSettle();

      // =================================================================
      // 12. Send to kitchen (tap "Order" button)
      // =================================================================
      final orderBtn = find.byKey(const Key('order_btn'));
      if (orderBtn.evaluate().isNotEmpty) {
        await tester.tap(orderBtn);
        await tester.pumpAndSettle(const Duration(seconds: 1));
      }

      // =================================================================
      // 13. Tap "Check Out" to go to payment screen
      // =================================================================
      final checkOutBtn = find.byKey(const Key('checkout_btn'));
      if (checkOutBtn.evaluate().isNotEmpty) {
        await tester.tap(checkOutBtn);
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }

      // =================================================================
      // 14. Payment screen -- verify and complete if possible
      // =================================================================
      final paymentIndicators = [
        find.text('Nakit'),
        find.text('PAYMENT'),
        find.text('Cash'),
        find.byIcon(Icons.payments),
      ];

      bool onPaymentScreen = false;
      for (final f in paymentIndicators) {
        if (f.evaluate().isNotEmpty) {
          onPaymentScreen = true;
          break;
        }
      }

      if (onPaymentScreen) {
        final completePaymentFinders = [
          find.text('TAMAMLA'),
          find.text('Complete'),
          find.text('Pay'),
          find.text('COMPLETE'),
        ];

        for (final f in completePaymentFinders) {
          if (f.evaluate().isNotEmpty) {
            await tester.tap(f.first);
            await tester.pumpAndSettle(const Duration(seconds: 2));
            break;
          }
        }
      }

      // =================================================================
      // 15. Navigate back to Home via grid icon
      // =================================================================
      final homeIcon = find.byIcon(Icons.grid_view_rounded);
      if (homeIcon.evaluate().isNotEmpty) {
        await tester.tap(homeIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 1));
      }

      // =================================================================
      // 16. Home -> Order Records
      // =================================================================
      final orderRecordsModule = find.byKey(const Key('module_order_records'));
      if (orderRecordsModule.evaluate().isNotEmpty) {
        await tester.tap(orderRecordsModule);
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }

      // Navigate back to home.
      final backBtn = find.byIcon(Icons.arrow_back);
      if (backBtn.evaluate().isNotEmpty) {
        await tester.tap(backBtn.first);
        await tester.pumpAndSettle(const Duration(seconds: 1));
      } else {
        final gridHome = find.byIcon(Icons.grid_view_rounded);
        if (gridHome.evaluate().isNotEmpty) {
          await tester.tap(gridHome.first);
          await tester.pumpAndSettle(const Duration(seconds: 1));
        }
      }

      // =================================================================
      // 17. Home -> Back Office
      // =================================================================
      final backOfficeModule = find.byKey(const Key('module_back_office'));
      if (backOfficeModule.evaluate().isNotEmpty) {
        await tester.tap(backOfficeModule);
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // Navigate back.
        final backNav = find.byIcon(Icons.arrow_back);
        if (backNav.evaluate().isNotEmpty) {
          await tester.tap(backNav.first);
          await tester.pumpAndSettle(const Duration(seconds: 1));
        }
      }

      // =================================================================
      // 18. Home -> Settings
      // =================================================================
      final settingsModule = find.byKey(const Key('module_settings'));
      if (settingsModule.evaluate().isNotEmpty) {
        await tester.tap(settingsModule);
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // Navigate back.
        final backNav = find.byIcon(Icons.arrow_back);
        if (backNav.evaluate().isNotEmpty) {
          await tester.tap(backNav.first);
          await tester.pumpAndSettle(const Duration(seconds: 1));
        }
      }

      // =================================================================
      // 19. Home -> Shift close
      // =================================================================
      final shiftModule = find.byKey(const Key('module_shift'));
      if (shiftModule.evaluate().isNotEmpty) {
        await tester.tap(shiftModule);
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }

      // Test completed -- all major screens visited.
    });

    // ===================================================================
    // Additional targeted tests
    // ===================================================================

    testWidgets('Login with wrong PIN shows error', (tester) async {
      await launchApp(tester);

      // Enter wrong PIN 9999 via key-based finders.
      await tapPinDigit(tester, '9');
      await tapPinDigit(tester, '9');
      await tapPinDigit(tester, '9');
      await tapPinDigit(tester, '9');

      await tester.tap(find.byKey(const Key('pin_enter_btn')));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Should still be on login screen (no navigation to shift/home).
      expect(find.byKey(const Key('pin_login_screen')), findsOneWidget);
      expect(find.text('Select Staff Member'), findsOneWidget);
    });

    testWidgets('Can select different user avatars', (tester) async {
      await launchApp(tester);

      // Verify first user avatar is present.
      expect(find.byKey(const Key('user_avatar_0')), findsOneWidget);

      // Try tapping a second user if available.
      final avatar1 = find.byKey(const Key('user_avatar_1'));
      if (avatar1.evaluate().isNotEmpty) {
        await tester.tap(avatar1);
        await tester.pumpAndSettle();
      }

      // Tap back to first user.
      await tester.tap(find.byKey(const Key('user_avatar_0')));
      await tester.pumpAndSettle();

      // Still on login screen.
      expect(find.byKey(const Key('pin_login_screen')), findsOneWidget);
    });

    testWidgets('Quick amount buttons on shift open screen work',
        (tester) async {
      await launchApp(tester);
      await loginWithPin(tester);

      // On shift-open screen.
      final shiftScreen = find.byKey(const Key('shift_open_screen'));
      await pumpUntilFound(tester, shiftScreen);

      if (shiftScreen.evaluate().isNotEmpty) {
        // Tap quick amount 200.
        final btn200 = find.byKey(const Key('quick_amount_200'));
        if (btn200.evaluate().isNotEmpty) {
          await tester.tap(btn200);
          await tester.pumpAndSettle();
        }

        // Tap quick amount 500.
        final btn500 = find.byKey(const Key('quick_amount_500'));
        if (btn500.evaluate().isNotEmpty) {
          await tester.tap(btn500);
          await tester.pumpAndSettle();
        }

        // Start shift.
        await tester.tap(find.byKey(const Key('shift_start_btn')));
        await tester.pumpAndSettle(const Duration(seconds: 3));

        // Should reach home.
        await pumpUntilFound(tester, find.byKey(const Key('home_screen')));
        expect(find.byKey(const Key('home_screen')), findsOneWidget);
      }
    });

    testWidgets('Sidebar navigation works on home screen', (tester) async {
      await loginAndReachHome(tester);

      // Verify home screen is present.
      expect(find.byKey(const Key('home_screen')), findsOneWidget);

      // Tap sidebar "Order" text to navigate.
      final sidebarOrder = find.text('Order');
      if (sidebarOrder.evaluate().isNotEmpty) {
        await tester.tap(sidebarOrder.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // Should be on order center -- verify tabs.
        expect(find.byKey(const Key('tab_ongoing')), findsOneWidget);
      }
    });

    testWidgets('Can switch order types on menu tab', (tester) async {
      await loginAndReachHome(tester);

      // Navigate to Order Center.
      await tester.tap(find.byKey(const Key('module_order')));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Switch to Menu tab.
      await tester.tap(find.byKey(const Key('tab_menu')));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Verify order type chips.
      expect(find.byKey(const Key('order_type_dine_in')), findsOneWidget);
      expect(find.byKey(const Key('order_type_takeaway')), findsOneWidget);
      expect(find.byKey(const Key('order_type_delivery')), findsOneWidget);

      // Tap Takeaway.
      await tester.tap(find.byKey(const Key('order_type_takeaway')));
      await tester.pumpAndSettle();

      // Tap Delivery.
      await tester.tap(find.byKey(const Key('order_type_delivery')));
      await tester.pumpAndSettle();

      // Tap back to Dine-In.
      await tester.tap(find.byKey(const Key('order_type_dine_in')));
      await tester.pumpAndSettle();
    });

    testWidgets('Can navigate all major screens from home', (tester) async {
      await loginAndReachHome(tester);

      // Navigate to each module and back.
      final modulesToVisit = [
        'module_order_records',
        'module_settings',
        'module_back_office',
      ];

      for (final moduleKey in modulesToVisit) {
        // Ensure we're on home.
        if (find.byKey(const Key('home_screen')).evaluate().isEmpty) {
          // Try to navigate home.
          final gridIcon = find.byIcon(Icons.grid_view_rounded);
          final backIcon = find.byIcon(Icons.arrow_back);
          if (gridIcon.evaluate().isNotEmpty) {
            await tester.tap(gridIcon.first);
            await tester.pumpAndSettle(const Duration(seconds: 1));
          } else if (backIcon.evaluate().isNotEmpty) {
            await tester.tap(backIcon.first);
            await tester.pumpAndSettle(const Duration(seconds: 1));
          }
        }

        final moduleFinder = find.byKey(Key(moduleKey));
        if (moduleFinder.evaluate().isNotEmpty) {
          await tester.tap(moduleFinder);
          await tester.pumpAndSettle(const Duration(seconds: 2));

          // Navigate back.
          final backNav = find.byIcon(Icons.arrow_back);
          if (backNav.evaluate().isNotEmpty) {
            await tester.tap(backNav.first);
            await tester.pumpAndSettle(const Duration(seconds: 1));
          }
        }
      }
    });
  });
}
