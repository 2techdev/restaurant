/// Widget tests for the fine-dining OrderPanel.
///
/// Product invariant 2026-04-17: cap = [kMaxGangs] = 3. The empty ticket
/// state must still render every Gang slot so the operator sees the
/// structure — otherwise new waiters mis-tap items into Gang 1 blindly.
///
/// Run with:
///   flutter test test/features/orders/widgets/order_panel_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/core/pos_mode/pos_mode.dart';
import 'package:gastrocore_pos/features/orders/presentation/widgets/shell/order_panel.dart';
import 'package:gastrocore_pos/l10n/app_localizations.dart';

Widget _harness() {
  return const ProviderScope(
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: OrderPanel()),
    ),
  );
}

void main() {
  group('OrderPanel — empty ticket', () {
    testWidgets('renders the empty-ticket placeholder', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      expect(find.text('Masa seçin veya ürün ekleyin'), findsOneWidget);
    });

    testWidgets('renders a Gang chip for every Gang (1..$kMaxGangs)',
        (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      for (final g in kGangNumbers) {
        expect(
          find.text('Gang $g'),
          findsWidgets,
          reason: 'Gang $g must be visible even when ticket is empty',
        );
      }
    });
  });

  group('activeGangProvider', () {
    testWidgets('defaults to Gang 1', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(activeGangProvider), 1);
    });
  });

  group('kMaxGangs contract', () {
    test('is 3 — matches product decision 2026-04-17', () {
      expect(kMaxGangs, 3);
      expect(kGangNumbers, const [1, 2, 3]);
    });
  });
}
