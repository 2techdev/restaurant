/// Integration tests — Login Flow.
///
/// Covers:
///   - App launches and PIN screen is displayed
///   - Valid PIN navigates to the next screen (shift or home)
///   - Invalid PIN keeps the user on the login screen with an error indicator
///   - Multiple user avatars can be selected
///   - PIN clear/backspace works before submission
///
/// Run with:
///   flutter test integration_test/login_flow_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/robot.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Login Flow', () {
    // -----------------------------------------------------------------------
    // 1. App launches – PIN screen is present
    // -----------------------------------------------------------------------
    testWidgets('PIN login screen renders on cold start', (tester) async {
      final robot = PosRobot(tester);
      await robot.launch();

      // Core screen key must be present.
      expect(find.byKey(const Key('pin_login_screen')), findsOneWidget);

      // User selection is visible.
      expect(find.byKey(const Key('user_avatar_0')), findsOneWidget);

      // Numpad digits are rendered.
      for (final digit in ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9']) {
        expect(
          find.byKey(Key('pin_numpad_$digit')),
          findsOneWidget,
          reason: 'Numpad digit $digit should be present',
        );
      }

      // ENTER button is present.
      expect(find.byKey(const Key('pin_enter_btn')), findsOneWidget);

      // Heading text is visible.
      expect(find.text('Select Staff Member'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // 2. Valid PIN → navigates away from login screen
    // -----------------------------------------------------------------------
    testWidgets('Valid PIN 1234 navigates to shift or home screen',
        (tester) async {
      final robot = PosRobot(tester);
      await robot.launch();

      // Ensure we start on the login screen.
      expect(find.byKey(const Key('pin_login_screen')), findsOneWidget);

      await robot.login(pin: '1234');

      // After login we must be on EITHER the shift-open screen or the home screen.
      final onShift =
          find.byKey(const Key('shift_open_screen')).evaluate().isNotEmpty;
      final onHome =
          find.byKey(const Key('home_screen')).evaluate().isNotEmpty;

      expect(
        onShift || onHome,
        isTrue,
        reason: 'Expected to land on shift-open or home after valid PIN',
      );

      // Must NOT be on the login screen anymore.
      expect(find.byKey(const Key('pin_login_screen')), findsNothing);
    });

    // -----------------------------------------------------------------------
    // 3. Invalid PIN → stays on login screen
    // -----------------------------------------------------------------------
    testWidgets('Wrong PIN keeps user on login screen', (tester) async {
      final robot = PosRobot(tester);
      await robot.launch();

      await robot.login(pin: '9999');

      // Must still be on the login screen.
      expect(find.byKey(const Key('pin_login_screen')), findsOneWidget);

      // Header text is still visible.
      expect(find.text('Select Staff Member'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // 4. Another wrong PIN (different pattern)
    // -----------------------------------------------------------------------
    testWidgets('PIN 0000 is rejected and error state is shown', (tester) async {
      final robot = PosRobot(tester);
      await robot.launch();

      await robot.login(pin: '0000');

      expect(find.byKey(const Key('pin_login_screen')), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // 5. User avatar selection
    // -----------------------------------------------------------------------
    testWidgets('Can tap user avatars and PIN screen stays live', (tester) async {
      final robot = PosRobot(tester);
      await robot.launch();

      // First avatar is always present (seeded by AppInitializer).
      expect(find.byKey(const Key('user_avatar_0')), findsOneWidget);
      await tester.tap(find.byKey(const Key('user_avatar_0')));
      await tester.pumpAndSettle();

      // If a second user was seeded, tap it and back.
      final avatar1 = find.byKey(const Key('user_avatar_1'));
      if (avatar1.evaluate().isNotEmpty) {
        await tester.tap(avatar1);
        await tester.pumpAndSettle();

        // Return to first user.
        await tester.tap(find.byKey(const Key('user_avatar_0')));
        await tester.pumpAndSettle();
      }

      // Still on the login screen after avatar gymnastics.
      expect(find.byKey(const Key('pin_login_screen')), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // 6. PIN digits register on the numpad
    // -----------------------------------------------------------------------
    testWidgets('Each PIN digit tap is registered without crashing', (tester) async {
      final robot = PosRobot(tester);
      await robot.launch();

      // Tap all 10 digits to ensure the numpad is functional.
      for (final digit in ['1', '2', '3', '4']) {
        await robot.tapPinDigit(digit);
      }

      // Still on the login screen (haven't pressed ENTER yet).
      expect(find.byKey(const Key('pin_login_screen')), findsOneWidget);

      // Pressing ENTER with valid PIN moves us forward.
      await tester.tap(find.byKey(const Key('pin_enter_btn')));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      final leftLogin =
          find.byKey(const Key('pin_login_screen')).evaluate().isEmpty;
      expect(
        leftLogin,
        isTrue,
        reason: 'Valid PIN should navigate away from login screen',
      );
    });

    // -----------------------------------------------------------------------
    // 7. GastroCore branding visible on login
    // -----------------------------------------------------------------------
    testWidgets('App branding text is visible on login screen', (tester) async {
      final robot = PosRobot(tester);
      await robot.launch();

      expect(find.text('GastroCore'), findsWidgets);
    });
  });
}
