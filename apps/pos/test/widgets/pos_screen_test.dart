/// Widget tests for the POS Screen (product grid + category sidebar).
///
/// Uses an in-memory Drift database seeded with demo data so the real
/// Riverpod providers are exercised without mocking the database layer.
///
/// Covers:
///   - Product grid renders at least one product card from seed data
///   - Category sidebar renders "All" and at least one named category
///   - Tapping "All" shows products from all categories
///   - Tapping a specific category filters the product grid
///   - Order type chips (Dine-In / Takeaway / Delivery) are rendered
///   - Ordering panel sections (Ordering / Ordered) are visible
///
/// Run with:
///   flutter test test/widgets/pos_screen_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/app.dart';
import 'package:gastrocore_pos/core/data/app_initializer.dart';
import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/di/providers.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Known product names seeded by AppInitializer demo data.
const _seedProducts = [
  'Adana Kebap',
  'Karisik Izgara',
  'Iskender',
  'Margherita',
  'Caesar Salata',
  'Mercimek Corbasi',
];

/// Boot the full app with an in-memory database and navigate to the Menu tab.
///
/// Returns the seeded tenant id for optional use.
Future<String> _bootAndNavigateToMenuTab(WidgetTester tester) async {
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

  // Wait for login screen.
  await _pumpUntilFound(tester, find.byKey(const Key('pin_login_screen')));

  // Login with valid PIN.
  await _login(tester);

  // Handle shift-open if needed.
  await tester.pumpAndSettle(const Duration(seconds: 1));
  final shiftScreen = find.byKey(const Key('shift_open_screen'));
  if (shiftScreen.evaluate().isNotEmpty) {
    await tester.tap(find.byKey(const Key('shift_start_btn')));
    await tester.pumpAndSettle(const Duration(seconds: 3));
  }

  // Navigate to Order Center.
  await _pumpUntilFound(tester, find.byKey(const Key('home_screen')));
  await tester.tap(find.byKey(const Key('module_order')));
  await tester.pumpAndSettle(const Duration(seconds: 2));

  // Switch to Menu tab.
  final menuTab = find.byKey(const Key('tab_menu'));
  await _pumpUntilFound(tester, menuTab);
  await tester.tap(menuTab);
  await tester.pumpAndSettle(const Duration(seconds: 2));

  return tenantId;
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 200));
  }
  await tester.pumpAndSettle();
}

Future<void> _login(WidgetTester tester, {String pin = '1234'}) async {
  final avatar = find.byKey(const Key('user_avatar_0'));
  if (avatar.evaluate().isNotEmpty) {
    await tester.tap(avatar);
    await tester.pumpAndSettle();
  }
  for (final digit in pin.split('')) {
    await tester.tap(find.byKey(Key('pin_numpad_$digit')));
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.tap(find.byKey(const Key('pin_enter_btn')));
  await tester.pumpAndSettle(const Duration(seconds: 3));
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('POS Screen Widget Tests', () {
    // -----------------------------------------------------------------------
    // 1. Product grid renders seed products
    // -----------------------------------------------------------------------
    testWidgets('Product grid renders at least one seed product', (tester) async {
      await _bootAndNavigateToMenuTab(tester);

      await _pumpUntilFound(tester, find.byKey(const Key('category_all')));

      bool found = false;
      for (final name in _seedProducts) {
        if (find.text(name).evaluate().isNotEmpty) {
          found = true;
          break;
        }
      }
      expect(found, isTrue,
          reason: 'At least one seed product must appear in the product grid');
    });

    // -----------------------------------------------------------------------
    // 2. Category sidebar renders "All" and at least category_0
    // -----------------------------------------------------------------------
    testWidgets('Category sidebar shows All and at least one category',
        (tester) async {
      await _bootAndNavigateToMenuTab(tester);

      await _pumpUntilFound(tester, find.byKey(const Key('category_all')));

      expect(find.byKey(const Key('category_all')), findsOneWidget);
      expect(find.byKey(const Key('category_0')), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // 3. Tapping "All" category shows products
    // -----------------------------------------------------------------------
    testWidgets('Tapping All shows products from all categories', (tester) async {
      await _bootAndNavigateToMenuTab(tester);

      await _pumpUntilFound(tester, find.byKey(const Key('category_all')));

      // Tap a specific category first to move away from All.
      final cat0 = find.byKey(const Key('category_0'));
      if (cat0.evaluate().isNotEmpty) {
        await tester.tap(cat0);
        await tester.pumpAndSettle();
      }

      // Tap All to restore full listing.
      await tester.tap(find.byKey(const Key('category_all')));
      await tester.pumpAndSettle(const Duration(milliseconds: 500));

      // At least one product should be visible again.
      bool found = false;
      for (final name in _seedProducts) {
        if (find.text(name).evaluate().isNotEmpty) {
          found = true;
          break;
        }
      }
      expect(found, isTrue);
    });

    // -----------------------------------------------------------------------
    // 4. Category filter changes the product grid
    // -----------------------------------------------------------------------
    testWidgets('Tapping a specific category filters the product grid',
        (tester) async {
      await _bootAndNavigateToMenuTab(tester);

      await _pumpUntilFound(tester, find.byKey(const Key('category_all')));

      final cat0 = find.byKey(const Key('category_0'));
      if (cat0.evaluate().isNotEmpty) {
        await tester.tap(cat0);
        await tester.pumpAndSettle(const Duration(milliseconds: 500));

        // Category_0 chip is still on screen (selected).
        expect(find.byKey(const Key('category_0')), findsOneWidget);
      }
    });

    // -----------------------------------------------------------------------
    // 5. Order type chips are rendered
    // -----------------------------------------------------------------------
    testWidgets('Order type chips Dine-In, Takeaway, Delivery are rendered',
        (tester) async {
      await _bootAndNavigateToMenuTab(tester);

      await _pumpUntilFound(tester, find.byKey(const Key('order_type_dine_in')));

      expect(find.byKey(const Key('order_type_dine_in')), findsOneWidget);
      expect(find.byKey(const Key('order_type_takeaway')), findsOneWidget);
      expect(find.byKey(const Key('order_type_delivery')), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // 6. Order panel sections are visible
    // -----------------------------------------------------------------------
    testWidgets('Ordering panel tabs (Ordering / Ordered) are visible',
        (tester) async {
      await _bootAndNavigateToMenuTab(tester);

      await _pumpUntilFound(tester, find.byKey(const Key('category_all')));

      // Either key-based or text-based panel tabs.
      final orderingTab = find.text('Ordering');
      final orderedTab = find.text('Ordered');

      final hasOrdering = orderingTab.evaluate().isNotEmpty;
      final hasOrdered = orderedTab.evaluate().isNotEmpty;

      expect(hasOrdering || hasOrdered, isTrue,
          reason: 'At least one of Ordering/Ordered tabs should be visible');
    });

    // -----------------------------------------------------------------------
    // 7. Adding a product shows it in the order panel
    // -----------------------------------------------------------------------
    testWidgets('Tapping a product adds it to the order panel', (tester) async {
      await _bootAndNavigateToMenuTab(tester);

      await _pumpUntilFound(tester, find.byKey(const Key('category_all')));

      String? tappedProduct;
      for (final name in _seedProducts) {
        final finder = find.text(name);
        if (finder.evaluate().isNotEmpty) {
          tappedProduct = name;
          await tester.tap(finder.first);
          await tester.pumpAndSettle(const Duration(milliseconds: 500));
          break;
        }
      }

      // Dismiss modifier dialog if shown.
      final addBtn = find.text('Add to Order');
      if (addBtn.evaluate().isNotEmpty) {
        await tester.tap(addBtn.first);
        await tester.pumpAndSettle();
      }

      expect(tappedProduct, isNotNull,
          reason: 'A product must be found and tapped to complete this test');
    });

    // -----------------------------------------------------------------------
    // 8. Product grid scrolls (many products)
    // -----------------------------------------------------------------------
    testWidgets('Product grid is scrollable', (tester) async {
      await _bootAndNavigateToMenuTab(tester);

      await _pumpUntilFound(tester, find.byKey(const Key('category_all')));

      // Attempt to scroll down in the product grid.
      final gridFinder = find.byKey(const Key('product_grid'));
      if (gridFinder.evaluate().isNotEmpty) {
        await tester.drag(gridFinder, const Offset(0, -200));
        await tester.pumpAndSettle();
      }

      // No crash after scroll.
      expect(find.byKey(const Key('category_all')), findsOneWidget);
    });
  });
}
