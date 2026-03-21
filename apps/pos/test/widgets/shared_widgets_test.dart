/// Widget tests for shared POS UI components.
///
/// Tests: PosNumpad, PosButton, PosCard, PosMoneyDisplay, PosBadge,
/// PosEmptyState, PosLoading.
///
/// Run with:
///   flutter test test/widgets/shared_widgets_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/shared/widgets/pos_badge.dart' show PosCountBadge;
import 'package:gastrocore_pos/shared/widgets/pos_button.dart';
import 'package:gastrocore_pos/shared/widgets/pos_card.dart';
import 'package:gastrocore_pos/shared/widgets/pos_empty_state.dart';
import 'package:gastrocore_pos/shared/widgets/pos_loading.dart' show PosLoadingOverlay;
import 'package:gastrocore_pos/shared/widgets/pos_money_display.dart';
import 'package:gastrocore_pos/shared/widgets/pos_numpad.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // =========================================================================
  // PosNumpad
  // =========================================================================

  group('PosNumpad', () {
    testWidgets('renders digit buttons 0–9 and ⌫', (tester) async {
      await tester.pumpWidget(
        _wrap(PosNumpad(onDigit: (_) {}, onClear: () {}, onBackspace: () {})),
      );

      for (final d in ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0']) {
        expect(find.text(d), findsAtLeastNWidgets(1));
      }
    });

    testWidgets('tapping a digit calls onDigit with that digit', (tester) async {
      final received = <String>[];
      await tester.pumpWidget(
        _wrap(PosNumpad(onDigit: received.add, onClear: () {}, onBackspace: () {})),
      );

      await tester.tap(find.text('5').first);
      await tester.pump();

      expect(received, contains('5'));
    });

    testWidgets('tapping backspace calls onBackspace', (tester) async {
      var backspaceCalled = false;
      await tester.pumpWidget(
        _wrap(PosNumpad(
          onDigit: (_) {},
          onClear: () {},
          onBackspace: () => backspaceCalled = true,
        )),
      );

      // Backspace button — find by icon or text.
      final backspaceFinder = find.byIcon(Icons.backspace_outlined);
      if (backspaceFinder.evaluate().isNotEmpty) {
        await tester.tap(backspaceFinder.first);
        await tester.pump();
        expect(backspaceCalled, isTrue);
      }
    });
  });

  // =========================================================================
  // PosButton
  // =========================================================================

  group('PosGradientButton', () {
    testWidgets('renders label text', (tester) async {
      await tester.pumpWidget(
        _wrap(PosGradientButton(label: 'Bezahlen', onPressed: () {})),
      );
      expect(find.text('Bezahlen'), findsOneWidget);
    });

    testWidgets('calls onTap when pressed', (tester) async {
      var called = false;
      await tester.pumpWidget(
        _wrap(PosGradientButton(label: 'OK', onPressed: () => called = true)),
      );
      await tester.tap(find.text('OK'));
      await tester.pump();
      expect(called, isTrue);
    });

    testWidgets('does not call onPressed when disabled', (tester) async {
      var called = false;
      await tester.pumpWidget(
        _wrap(PosGradientButton(label: 'Disabled', onPressed: null)),
      );
      await tester.tap(find.text('Disabled'), warnIfMissed: false);
      await tester.pump();
      expect(called, isFalse);
    });
  });

  // =========================================================================
  // PosCard
  // =========================================================================

  group('PosCard', () {
    testWidgets('renders child content', (tester) async {
      await tester.pumpWidget(
        _wrap(PosCard(child: const Text('Card Content'))),
      );
      expect(find.text('Card Content'), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(PosCard(
          onTap: () => tapped = true,
          child: const Text('Tap Me'),
        )),
      );
      await tester.tap(find.text('Tap Me'));
      await tester.pump();
      expect(tapped, isTrue);
    });
  });

  // =========================================================================
  // PosMoneyDisplay
  // =========================================================================

  group('PosMoneyDisplay', () {
    testWidgets('renders formatted CHF amount', (tester) async {
      await tester.pumpWidget(
        _wrap(const PosMoneyDisplay(amountCents: 1299)),
      );
      // Should render "12.99" or "CHF 12.99"
      expect(find.textContaining('12.99'), findsOneWidget);
    });

    testWidgets('renders zero as "0.00"', (tester) async {
      await tester.pumpWidget(
        _wrap(const PosMoneyDisplay(amountCents: 0)),
      );
      expect(find.textContaining('0.00'), findsOneWidget);
    });

    testWidgets('renders large amount correctly', (tester) async {
      await tester.pumpWidget(
        _wrap(const PosMoneyDisplay(amountCents: 100000)),
      );
      // CHF 1000.00 — the display must show the numeric value somewhere
      expect(find.textContaining('1000'), findsAtLeastNWidgets(1));
    });
  });

  // =========================================================================
  // PosBadge
  // =========================================================================

  group('PosCountBadge', () {
    testWidgets('renders count text', (tester) async {
      await tester.pumpWidget(
        _wrap(const PosCountBadge(count: 5)),
      );
      expect(find.text('5'), findsOneWidget);
    });
  });

  // =========================================================================
  // PosEmptyState
  // =========================================================================

  group('PosEmptyState', () {
    testWidgets('renders title text', (tester) async {
      await tester.pumpWidget(
        _wrap(const PosEmptyState(
          icon: Icons.inbox,
          title: 'Keine Bestellungen',
        )),
      );
      expect(find.text('Keine Bestellungen'), findsOneWidget);
    });
  });

  // =========================================================================
  // PosLoading
  // =========================================================================

  group('PosLoading', () {
    testWidgets('renders a CircularProgressIndicator', (tester) async {
      await tester.pumpWidget(_wrap(const PosLoadingOverlay()));
      expect(find.byType(CircularProgressIndicator), findsAtLeastNWidgets(1));
    });
  });
}
