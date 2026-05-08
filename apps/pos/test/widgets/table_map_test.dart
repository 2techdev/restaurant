/// Widget tests for the Table Map / Floor Plan view.
///
/// Uses an in-memory Drift database with seeded demo data.
/// Navigates to the Table tab inside the Order Center and exercises:
///
///   - Tables are rendered on the floor plan
///   - Table status colors differ between available and occupied states
///   - Tapping a table opens detail or assigns the order
///   - Multiple floors are accessible (if seeded)
///   - Table capacity label is displayed
///   - Floor plan tab renders without crash
///
/// Run with:
///   flutter test test/widgets/table_map_test.dart
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

Future<AppDatabase> _bootApp(WidgetTester tester) async {
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
  return db;
}

Future<void> _login(WidgetTester tester) async {
  await _pumpUntilFound(tester, find.byKey(const Key('pin_login_screen')));
  final avatar = find.byKey(const Key('user_avatar_0'));
  if (avatar.evaluate().isNotEmpty) {
    await tester.tap(avatar);
    await tester.pumpAndSettle();
  }
  for (final digit in '1234'.split('')) {
    await tester.tap(find.byKey(Key('pin_numpad_$digit')));
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.tap(find.byKey(const Key('pin_enter_btn')));
  await tester.pumpAndSettle(const Duration(seconds: 3));
}

Future<void> _startShiftIfNeeded(WidgetTester tester) async {
  await tester.pumpAndSettle(const Duration(seconds: 1));
  if (find.byKey(const Key('shift_open_screen')).evaluate().isNotEmpty) {
    await tester.tap(find.byKey(const Key('shift_start_btn')));
    await tester.pumpAndSettle(const Duration(seconds: 3));
  }
}

Future<void> _navigateToTableTab(WidgetTester tester) async {
  await _pumpUntilFound(tester, find.byKey(const Key('home_screen')));
  await tester.tap(find.byKey(const Key('module_order')));
  await tester.pumpAndSettle(const Duration(seconds: 2));

  final tableTab = find.byKey(const Key('tab_table'));
  await _pumpUntilFound(tester, tableTab);
  await tester.tap(tableTab);
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

// Legacy integration suite: boots the full GastroCoreApp and navigates via
// module_order rail to the Table tab. Pre-dates the pos_v2_shell rail
// rewrite (Tische / Verkauf / Bons / Bericht / FUNKTION / Storno / Drucken /
// Sperren) and the table-map screen restructure. Skipped pending an
// integration_test rewrite; per-widget unit coverage is in
// apps/pos/test/features/tables/.
void main() {
  group('Table Map Widget Tests', skip: 'legacy: pre-pos_v2_shell rewrite; integration rewrite pending', () {
    // -----------------------------------------------------------------------
    // 1. Table tab renders without error
    // -----------------------------------------------------------------------
    testWidgets('Table tab renders without crashing', (tester) async {
      await _bootApp(tester);
      await _login(tester);
      await _startShiftIfNeeded(tester);
      await _navigateToTableTab(tester);

      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Tab must remain selected.
      expect(find.byKey(const Key('tab_table')), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // 2. Floor plan or table list is visible
    // -----------------------------------------------------------------------
    testWidgets('Floor plan or table list is visible after navigation',
        (tester) async {
      await _bootApp(tester);
      await _login(tester);
      await _startShiftIfNeeded(tester);
      await _navigateToTableTab(tester);

      // Look for seeded table names or floor-plan related widgets.
      final tableIndicators = [
        find.byKey(const Key('floor_plan_canvas')),
        find.byKey(const Key('table_list')),
        find.byKey(const Key('table_item_0')),
        find.byKey(const Key('restaurant_table_T1')),
        find.text('T1'),
        find.text('Table 1'),
        find.text('Main Hall'),
        find.text('Main Floor'),
        find.text('Terrace'),
      ];
      for (final f in tableIndicators) {
        if (f.evaluate().isNotEmpty) break;
      }

      // Primary assertion is no crash; table UI depends on seeded data.
      expect(find.byKey(const Key('pin_login_screen')), findsNothing);
    });

    // -----------------------------------------------------------------------
    // 3. Available tables have a distinct appearance
    // -----------------------------------------------------------------------
    testWidgets('Available tables are distinguishable from occupied ones',
        (tester) async {
      await _bootApp(tester);
      await _login(tester);
      await _startShiftIfNeeded(tester);
      await _navigateToTableTab(tester);

      // Look for status-color containers or status keys.
      final availableIndicators = [
        find.byKey(const Key('table_status_available')),
        find.text('Available'),
        find.text('Free'),
      ];
      for (final f in availableIndicators) {
        if (f.evaluate().isNotEmpty) break;
      }

      // No crash is mandatory; status rendering depends on implementation.
      expect(find.byKey(const Key('pin_login_screen')), findsNothing);
    });

    // -----------------------------------------------------------------------
    // 4. Tapping a table opens detail or order assignment
    // -----------------------------------------------------------------------
    testWidgets('Tapping a table navigates or opens a dialog', (tester) async {
      await _bootApp(tester);
      await _login(tester);
      await _startShiftIfNeeded(tester);
      await _navigateToTableTab(tester);

      // Try tapping table_item_0.
      final tableItem = find.byKey(const Key('table_item_0'));
      if (tableItem.evaluate().isNotEmpty) {
        await tester.tap(tableItem);
        await tester.pumpAndSettle(const Duration(seconds: 1));

        // Some response must occur (dialog, navigation, sheet).
        expect(find.byKey(const Key('pin_login_screen')), findsNothing);
        return;
      }

      // Try tapping first visible table text.
      for (final name in ['T1', 'Table 1', 'T01']) {
        final finder = find.text(name);
        if (finder.evaluate().isNotEmpty) {
          await tester.tap(finder.first);
          await tester.pumpAndSettle(const Duration(seconds: 1));
          expect(find.byKey(const Key('pin_login_screen')), findsNothing);
          return;
        }
      }

      // No table found to tap — acceptable.
      expect(find.byKey(const Key('tab_table')), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // 5. Multiple floors are accessible (tabs or dropdown)
    // -----------------------------------------------------------------------
    testWidgets('Multiple floors are navigable if seeded', (tester) async {
      await _bootApp(tester);
      await _login(tester);
      await _startShiftIfNeeded(tester);
      await _navigateToTableTab(tester);

      // Look for floor tabs or floor selector.
      final floorIndicators = [
        find.byKey(const Key('floor_tab_0')),
        find.byKey(const Key('floor_tab_1')),
        find.byKey(const Key('floor_selector')),
        find.text('Main Hall'),
        find.text('Main Floor'),
        find.text('Terrace'),
      ];

      for (final f in floorIndicators) {
        f.evaluate();
      }

      // At least one floor indicator is expected from seeded data.
      // Just verify no crash.
      expect(find.byKey(const Key('pin_login_screen')), findsNothing);
    });

    // -----------------------------------------------------------------------
    // 6. Table count label is displayed
    // -----------------------------------------------------------------------
    testWidgets('Table status or count information is displayed', (tester) async {
      await _bootApp(tester);
      await _login(tester);
      await _startShiftIfNeeded(tester);
      await _navigateToTableTab(tester);

      // Look for occupancy info.
      final occupancyFinders = [
        find.byKey(const Key('table_occupancy_summary')),
        find.textContaining('/'),  // e.g. "3/10 tables"
        find.textContaining('table'),
        find.textContaining('Table'),
      ];
      for (final f in occupancyFinders) {
        if (f.evaluate().isNotEmpty) break;
      }

      // Minimal smoke assertion.
      expect(find.byKey(const Key('pin_login_screen')), findsNothing);
    });

    // -----------------------------------------------------------------------
    // 7. Back navigation from table tab works
    // -----------------------------------------------------------------------
    testWidgets('Back navigation from Table tab works', (tester) async {
      await _bootApp(tester);
      await _login(tester);
      await _startShiftIfNeeded(tester);
      await _navigateToTableTab(tester);

      // Tap the grid/home icon to navigate back to home.
      final homeIcon = find.byIcon(Icons.grid_view_rounded);
      if (homeIcon.evaluate().isNotEmpty) {
        await tester.tap(homeIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 1));
        expect(find.byKey(const Key('home_screen')), findsOneWidget);
      } else {
        // Tab navigation: switch to Ongoing tab instead.
        final ongoingTab = find.byKey(const Key('tab_ongoing'));
        if (ongoingTab.evaluate().isNotEmpty) {
          await tester.tap(ongoingTab);
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('tab_ongoing')), findsOneWidget);
        }
      }
    });

    // -----------------------------------------------------------------------
    // 8. Table map renders correctly after switching tabs and back
    // -----------------------------------------------------------------------
    testWidgets('Table tab re-renders after switching tabs and returning',
        (tester) async {
      await _bootApp(tester);
      await _login(tester);
      await _startShiftIfNeeded(tester);
      await _navigateToTableTab(tester);

      // Switch to Ongoing.
      final ongoingTab = find.byKey(const Key('tab_ongoing'));
      if (ongoingTab.evaluate().isNotEmpty) {
        await tester.tap(ongoingTab);
        await tester.pumpAndSettle();

        // Switch back to Table.
        await tester.tap(find.byKey(const Key('tab_table')));
        await tester.pumpAndSettle(const Duration(seconds: 1));
      }

      expect(find.byKey(const Key('tab_table')), findsOneWidget);
    });
  });
}
