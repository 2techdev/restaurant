/// Widget tests for [CourseSelector] — the waiter's sticky gang-picker chip row.
///
/// Verifies the three RestaurantSettings knobs the user explicitly asked for:
///   * `gangsEnabled: false` → selector renders nothing (casual/quick-service
///     venues send orders without gang pacing).
///   * `maxGangs` → slot count is driven by the setting (1..5), not hardcoded.
///   * `gangLabels` → restaurant-provided labels replace the default
///     "Gang 1/2/3" on a per-slot basis (with fallback for blank entries).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/features/settings/domain/entities/restaurant_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/repositories/settings_repository.dart';
import 'package:gastrocore_pos/features/settings/presentation/providers/settings_provider.dart';
import 'package:gastrocore_pos/features/waiter/presentation/screens/waiter_menu_screen.dart';

/// Stand-in settings repository that returns a canned [RestaurantSettings]
/// from [loadRestaurantSettings] and ignores saves. Keeps the notifier's
/// real `_load()` path but avoids touching real storage.
class _StubSettingsRepo implements SettingsRepository {
  _StubSettingsRepo(this.restaurant);

  final RestaurantSettings restaurant;

  @override
  Future<RestaurantSettings> loadRestaurantSettings() async => restaurant;

  @override
  Future<void> saveRestaurantSettings(RestaurantSettings settings) async {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _harness({
  required RestaurantSettings settings,
}) {
  return ProviderScope(
    overrides: [
      settingsRepositoryProvider.overrideWith(
        (ref) async => _StubSettingsRepo(settings),
      ),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: CourseSelector(),
      ),
    ),
  );
}

void main() {
  group('CourseSelector', () {
    testWidgets('renders nothing when gangsEnabled=false', (tester) async {
      await tester.pumpWidget(_harness(
        settings: const RestaurantSettings(gangsEnabled: false),
      ));
      // settingsRepositoryProvider is async — let the FutureProvider resolve.
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('waiter.courseSelector')),
        findsNothing,
        reason: 'selector must not mount when gangs are disabled',
      );
    });

    testWidgets('renders maxGangs slots (3) with default labels',
        (tester) async {
      await tester.pumpWidget(_harness(
        settings: const RestaurantSettings(), // defaults: enabled, maxGangs=3
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('waiter.courseSelector')), findsOneWidget);
      expect(find.text('Gang 1'), findsOneWidget);
      expect(find.text('Gang 2'), findsOneWidget);
      expect(find.text('Gang 3'), findsOneWidget);
      expect(find.text('Gang 4'), findsNothing);
    });

    testWidgets('renders all 5 slots when maxGangs=5', (tester) async {
      await tester.pumpWidget(_harness(
        settings: const RestaurantSettings(maxGangs: 5),
      ));
      await tester.pumpAndSettle();

      for (var i = 1; i <= 5; i++) {
        expect(find.text('Gang $i'), findsOneWidget,
            reason: 'slot $i must render with default label');
      }
    });

    testWidgets('honours custom gangLabels override', (tester) async {
      await tester.pumpWidget(_harness(
        settings: const RestaurantSettings(
          maxGangs: 3,
          gangLabels: ['Entrée', 'Plat', 'Dessert'],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Entrée'), findsOneWidget);
      expect(find.text('Plat'), findsOneWidget);
      expect(find.text('Dessert'), findsOneWidget);
      // Defaults must not leak through when every slot is overridden.
      expect(find.text('Gang 1'), findsNothing);
    });

    testWidgets('blank override entry falls back to default label',
        (tester) async {
      await tester.pumpWidget(_harness(
        settings: const RestaurantSettings(
          maxGangs: 3,
          gangLabels: ['Entrée', '', 'Dessert'],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Entrée'), findsOneWidget);
      expect(find.text('Gang 2'), findsOneWidget,
          reason: 'blank override must fall back to the default label');
      expect(find.text('Dessert'), findsOneWidget);
    });

    testWidgets('maxGangs above ceiling clamps to 5', (tester) async {
      await tester.pumpWidget(_harness(
        settings: const RestaurantSettings(maxGangs: 99),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Gang 5'), findsOneWidget);
      expect(find.text('Gang 6'), findsNothing,
          reason: 'maxGangs must clamp to kMaxGangsSetting (5)');
    });

    testWidgets('maxGangs below floor clamps to 1', (tester) async {
      await tester.pumpWidget(_harness(
        settings: const RestaurantSettings(maxGangs: 0),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Gang 1'), findsOneWidget);
      expect(find.text('Gang 2'), findsNothing,
          reason: 'maxGangs must clamp to kMinGangsSetting (1)');
    });
  });
}
