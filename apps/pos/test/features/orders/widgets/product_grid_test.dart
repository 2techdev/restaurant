/// Widget tests for ProductGrid's 1 ↔ 2 column toggle behaviour.
///
/// The column toggle is a contract with Product and the operators
/// (2026-04-17 decision): one tap to reflow the grid mid-service without
/// diving into Settings. These tests pin:
///
///   - `clampProductGridColumns` never emits an invalid column count.
///   - `toggleProductGridColumns` flips state between 1 and 2 deterministically.
///   - The grid re-keys itself when columns change so Flutter rebuilds it
///     instead of shifting children in place (important for animation + a11y).
///
/// Run with:
///   flutter test test/features/orders/widgets/product_grid_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/features/menu/domain/entities/product_entity.dart';
import 'package:gastrocore_pos/features/menu/presentation/providers/menu_provider.dart';
import 'package:gastrocore_pos/features/orders/presentation/widgets/shell/product_grid.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ProductEntity _product(String id, String name, int price) => ProductEntity(
      id: id,
      tenantId: 'T1',
      categoryId: 'C1',
      name: name,
      price: price,
      costPrice: 0,
      taxGroup: 'standard',
      isActive: true,
      displayOrder: 0,
      printerGroup: 'kitchen',
    );

final _stubProducts = [
  _product('p1', 'Forelle Müllerin', 3200),
  _product('p2', 'Kalbsbraten', 4800),
  _product('p3', 'Zürcher Geschnetzeltes', 4400),
];

Widget _harness({
  required int columns,
  required void Function(ProductEntity) onTap,
  List<ProductEntity>? products,
}) {
  return ProviderScope(
    overrides: [
      filteredProductsProvider
          .overrideWith((ref) async => products ?? _stubProducts),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: ProductGrid(columns: columns, onProductTap: onTap),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('clampProductGridColumns', () {
    test('clamps below minimum', () {
      expect(clampProductGridColumns(0), kProductGridMinColumns);
      expect(clampProductGridColumns(-5), kProductGridMinColumns);
    });

    test('clamps above maximum', () {
      expect(clampProductGridColumns(3), kProductGridMaxColumns);
      expect(clampProductGridColumns(99), kProductGridMaxColumns);
    });

    test('passes through valid counts', () {
      expect(clampProductGridColumns(1), 1);
      expect(clampProductGridColumns(2), 2);
    });
  });

  group('toggleProductGridColumns', () {
    testWidgets('flips 2 → 1 → 2', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(productGridColumnsProvider), 2);

      // First flip: 2 → 1.
      final refHarness = await _refHarness(tester, container);
      toggleProductGridColumns(refHarness);
      expect(container.read(productGridColumnsProvider), 1);

      // Second flip: 1 → 2.
      toggleProductGridColumns(refHarness);
      expect(container.read(productGridColumnsProvider), 2);
    });
  });

  group('ProductGrid rendering', () {
    testWidgets('renders with 1-column key', (tester) async {
      await tester.pumpWidget(_harness(columns: 1, onTap: (_) {}));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('product_grid_cols_1')), findsOneWidget);
      expect(find.byKey(const ValueKey('product_grid_cols_2')), findsNothing);
    });

    testWidgets('renders with 2-column key', (tester) async {
      await tester.pumpWidget(_harness(columns: 2, onTap: (_) {}));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('product_grid_cols_2')), findsOneWidget);
      expect(find.byKey(const ValueKey('product_grid_cols_1')), findsNothing);
    });

    testWidgets('clamps invalid column count when rendering', (tester) async {
      // Passing 5 should be clamped to max=2.
      await tester.pumpWidget(_harness(columns: 5, onTap: (_) {}));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('product_grid_cols_2')), findsOneWidget);
    });

    testWidgets('invokes onProductTap with the tapped product',
        (tester) async {
      final tapped = <String>[];
      await tester.pumpWidget(_harness(
        columns: 2,
        onTap: (p) => tapped.add(p.id),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('product_card_p1')));
      expect(tapped, ['p1']);
    });
  });
}

/// Build a throwaway ConsumerWidget so we can access a real [WidgetRef]
/// bound to [container]. This is the only clean way to exercise
/// [toggleProductGridColumns] — the helper takes a ref, not a container.
Future<WidgetRef> _refHarness(
  WidgetTester tester,
  ProviderContainer container,
) async {
  final completer = _RefCapture();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: _RefCaptureWidget(capture: completer)),
    ),
  );
  return completer.ref!;
}

class _RefCapture {
  WidgetRef? ref;
}

class _RefCaptureWidget extends ConsumerWidget {
  const _RefCaptureWidget({required this.capture});
  final _RefCapture capture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    capture.ref = ref;
    return const SizedBox.shrink();
  }
}
