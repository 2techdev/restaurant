/// Widget test for the ColumnToggleButton.
///
/// Ensures the public Key('product_grid_column_toggle') is stable (used by
/// end-to-end and waiter-tablet tests) and that tapping the button flips
/// `productGridColumnsProvider` between 1 and 2.
///
/// Run with:
///   flutter test test/features/orders/widgets/column_toggle_button_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/features/orders/presentation/widgets/shell/column_toggle_button.dart';
import 'package:gastrocore_pos/features/orders/presentation/widgets/shell/product_grid.dart';

Widget _harness(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(
      home: Scaffold(body: Center(child: ColumnToggleButton())),
    ),
  );
}

void main() {
  testWidgets('exposes the stable product_grid_column_toggle key',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(_harness(container));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('product_grid_column_toggle')), findsOneWidget);
  });

  testWidgets('shows 2-sütun label when default is 2', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(_harness(container));
    await tester.pumpAndSettle();

    expect(find.text('2 sütun'), findsOneWidget);
    expect(find.text('1 sütun'), findsNothing);
  });

  testWidgets('tap flips columns 2 → 1 and updates label', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(_harness(container));
    await tester.pumpAndSettle();

    expect(container.read(productGridColumnsProvider), 2);

    await tester.tap(find.byKey(const Key('product_grid_column_toggle')));
    await tester.pumpAndSettle();

    expect(container.read(productGridColumnsProvider), 1);
    expect(find.text('1 sütun'), findsOneWidget);
    expect(find.text('2 sütun'), findsNothing);
  });
}
