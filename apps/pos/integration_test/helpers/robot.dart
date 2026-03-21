/// Robot / Page-Object helpers for GastroCore POS integration tests.
///
/// Each public method encapsulates a compound UI action so that individual
/// test files stay readable and don't duplicate navigation boilerplate.
///
/// Usage:
///   final robot = PosRobot(tester);
///   await robot.launchAndLogin();
///   await robot.startShift();
///   await robot.navigateToOrderCenter();
///   await robot.addProductByName('Adana Kebap');
///   await robot.checkout();
///   await robot.payWithCash(amount: 5000);
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_app.dart';

class PosRobot {
  PosRobot(this.tester);

  final WidgetTester tester;

  // =========================================================================
  // App launch & login
  // =========================================================================

  /// Boot the app, wait for the PIN login screen.
  Future<void> launch() async {
    await launchTestApp(tester);
    await pumpUntilFound(tester, find.byKey(const Key('pin_login_screen')));
  }

  /// Tap a single PIN digit via Key('pin_numpad_$digit').
  Future<void> tapPinDigit(String digit) async {
    final finder = find.byKey(Key('pin_numpad_$digit'));
    expect(finder, findsOneWidget,
        reason: 'PIN numpad digit "$digit" expected on screen');
    await tester.tap(finder);
    await tester.pump(const Duration(milliseconds: 150));
  }

  /// Select a user avatar by [index] (0-based), enter [pin], tap ENTER.
  Future<void> login({int userIndex = 0, String pin = '1234'}) async {
    final avatar = find.byKey(Key('user_avatar_$userIndex'));
    if (avatar.evaluate().isNotEmpty) {
      await tester.tap(avatar);
      await tester.pumpAndSettle();
    }

    for (final digit in pin.split('')) {
      await tapPinDigit(digit);
    }

    await tester.tap(find.byKey(const Key('pin_enter_btn')));
    await tester.pumpAndSettle(const Duration(seconds: 3));
  }

  // =========================================================================
  // Shift
  // =========================================================================

  /// Open a shift using the default opening cash if the shift-open screen
  /// is presented.  Safe to call when a shift is already open.
  Future<void> startShiftIfNeeded() async {
    await tester.pumpAndSettle(const Duration(seconds: 1));
    final shiftScreen = find.byKey(const Key('shift_open_screen'));
    if (shiftScreen.evaluate().isNotEmpty) {
      final startBtn = find.byKey(const Key('shift_start_btn'));
      expect(startBtn, findsOneWidget);
      await tester.tap(startBtn);
      await tester.pumpAndSettle(const Duration(seconds: 3));
    }
  }

  /// Open a shift with a specific [openingCash] quick-amount key.
  /// [quickAmountKey] must match a Key like 'quick_amount_200'.
  Future<void> startShiftWithAmount(String quickAmountKey) async {
    await pumpUntilFound(tester, find.byKey(const Key('shift_open_screen')));
    final btn = find.byKey(Key(quickAmountKey));
    if (btn.evaluate().isNotEmpty) {
      await tester.tap(btn);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const Key('shift_start_btn')));
    await tester.pumpAndSettle(const Duration(seconds: 3));
  }

  // =========================================================================
  // Home → Order Center
  // =========================================================================

  /// Full composite: launch → login → shift → home.
  Future<void> launchLoginAndReachHome() async {
    await launch();
    await login();
    await startShiftIfNeeded();
    await pumpUntilFound(tester, find.byKey(const Key('home_screen')));
  }

  /// Tap the ORDER module card to reach the Order Center.
  Future<void> navigateToOrderCenter() async {
    await tester.tap(find.byKey(const Key('module_order')));
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  /// Switch to the Menu tab inside the Order Center.
  Future<void> switchToMenuTab() async {
    final menuTab = find.byKey(const Key('tab_menu'));
    await pumpUntilFound(tester, menuTab);
    await tester.tap(menuTab);
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  /// Switch to the Ongoing tab inside the Order Center.
  Future<void> switchToOngoingTab() async {
    final tab = find.byKey(const Key('tab_ongoing'));
    await pumpUntilFound(tester, tab);
    await tester.tap(tab);
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  /// Switch to the Table tab inside the Order Center.
  Future<void> switchToTableTab() async {
    final tab = find.byKey(const Key('tab_table'));
    await pumpUntilFound(tester, tab);
    await tester.tap(tab);
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  // =========================================================================
  // Menu & Products
  // =========================================================================

  /// Filter products by category at [index] (0-based).
  /// Pass -1 to select "All".
  Future<void> selectCategory(int index) async {
    final key = index < 0 ? 'category_all' : 'category_$index';
    final finder = find.byKey(Key(key));
    if (finder.evaluate().isNotEmpty) {
      await tester.tap(finder);
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
    }
  }

  /// Add the first product whose name appears in [candidates].
  /// Returns the name of the product added, or null if none found.
  Future<String?> addFirstAvailableProduct(List<String> candidates) async {
    for (final name in candidates) {
      final finder = find.text(name);
      if (finder.evaluate().isNotEmpty) {
        await tester.tap(finder.first);
        await tester.pumpAndSettle(const Duration(milliseconds: 500));
        await _dismissModifierDialogIfPresent();
        return name;
      }
    }
    return null;
  }

  /// Add a product by its exact display name.
  Future<void> addProductByName(String name) async {
    final finder = find.text(name);
    if (finder.evaluate().isEmpty) return;
    await tester.tap(finder.first);
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    await _dismissModifierDialogIfPresent();
  }

  Future<void> _dismissModifierDialogIfPresent() async {
    final addBtn = find.text('Add to Order');
    if (addBtn.evaluate().isNotEmpty) {
      await tester.tap(addBtn.first);
      await tester.pumpAndSettle();
    }
  }

  // =========================================================================
  // Order type
  // =========================================================================

  Future<void> selectOrderType(OrderTypeOption type) async {
    final key = switch (type) {
      OrderTypeOption.dineIn => 'order_type_dine_in',
      OrderTypeOption.takeaway => 'order_type_takeaway',
      OrderTypeOption.delivery => 'order_type_delivery',
    };
    final finder = find.byKey(Key(key));
    if (finder.evaluate().isNotEmpty) {
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }
  }

  // =========================================================================
  // Kitchen & Checkout
  // =========================================================================

  /// Tap the "Order" / send-to-kitchen button.
  Future<void> sendToKitchen() async {
    final btn = find.byKey(const Key('order_btn'));
    if (btn.evaluate().isNotEmpty) {
      await tester.tap(btn);
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }
  }

  /// Tap the "Check Out" button to reach the payment screen.
  Future<void> checkout() async {
    final btn = find.byKey(const Key('checkout_btn'));
    if (btn.evaluate().isNotEmpty) {
      await tester.tap(btn);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }
  }

  /// Complete a cash payment on the payment screen.
  Future<void> payWithCash() async {
    // Try key-based buttons first, then text-based fallbacks.
    final cashBtn = find.byKey(const Key('payment_method_cash'));
    if (cashBtn.evaluate().isNotEmpty) {
      await tester.tap(cashBtn);
      await tester.pumpAndSettle();
    }

    final completeKeys = [
      find.byKey(const Key('complete_payment_btn')),
      find.text('TAMAMLA'),
      find.text('Complete'),
      find.text('Pay'),
      find.text('COMPLETE'),
    ];
    for (final f in completeKeys) {
      if (f.evaluate().isNotEmpty) {
        await tester.tap(f.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        break;
      }
    }
  }

  // =========================================================================
  // Navigation
  // =========================================================================

  /// Navigate back to the home screen.
  Future<void> goHome() async {
    if (find.byKey(const Key('home_screen')).evaluate().isNotEmpty) return;

    final gridIcon = find.byIcon(Icons.grid_view_rounded);
    if (gridIcon.evaluate().isNotEmpty) {
      await tester.tap(gridIcon.first);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      return;
    }

    final backIcon = find.byIcon(Icons.arrow_back);
    if (backIcon.evaluate().isNotEmpty) {
      await tester.tap(backIcon.first);
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }
  }

  // =========================================================================
  // Shift close
  // =========================================================================

  /// Navigate to shift close if the module card is present.
  Future<void> navigateToShiftClose() async {
    final shiftModule = find.byKey(const Key('module_shift'));
    if (shiftModule.evaluate().isNotEmpty) {
      await tester.tap(shiftModule);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }
  }
}

/// Convenience enum for order type selection.
enum OrderTypeOption { dineIn, takeaway, delivery }
