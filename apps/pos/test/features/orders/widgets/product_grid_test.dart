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

import 'package:gastrocore_pos/features/inventory/domain/entities/inventory_item_entity.dart';
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
  required double width,
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
        body: Center(
          child: SizedBox(
            width: width,
            height: 600,
            child: ProductGrid(onProductTap: onTap),
          ),
        ),
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
    testWidgets('renders 2-column layout at narrow width', (tester) async {
      await tester.pumpWidget(_harness(width: 400, onTap: (_) {}));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('product_grid_cols_2')), findsOneWidget);
    });

    testWidgets('renders 3-column layout at mid width', (tester) async {
      await tester.pumpWidget(_harness(width: 620, onTap: (_) {}));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('product_grid_cols_3')), findsOneWidget);
    });

    testWidgets('renders 4-column layout at tablet width', (tester) async {
      await tester.pumpWidget(_harness(width: 780, onTap: (_) {}));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('product_grid_cols_4')), findsOneWidget);
    });

    testWidgets('invokes onProductTap with the tapped product',
        (tester) async {
      final tapped = <String>[];
      await tester.pumpWidget(_harness(
        width: 620,
        onTap: (p) => tapped.add(p.id),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('product_card_p1')));
      expect(tapped, ['p1']);
    });

    testWidgets(
        'ProductCard exposes a single button-labelled semantics node per tile',
        (tester) async {
      // a11y guard: the tile must collapse to one semantic button with a
      // readable label so TalkBack / VoiceOver announces the whole tile
      // as one tap target, not three separate text leaves.
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(_harness(width: 620, onTap: (_) {}));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel(RegExp(r'Forelle Müllerin.*CHF 32\.00')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'Kalbsbraten.*CHF 48\.00')),
        findsOneWidget,
      );

      handle.dispose();
    });
  });

  group('ProductCard stock badge', () {
    Widget cardHarness({StockStatus? status}) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 120,
              child: ProductCard(
                product: _product('p1', 'Forelle', 3200),
                onTap: () {},
                stockStatus: status,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('renders no badge when stockStatus is null (untracked)',
        (tester) async {
      await tester.pumpWidget(cardHarness());
      await tester.pumpAndSettle();
      expect(find.text('Az'), findsNothing);
      expect(find.text('Bitti'), findsNothing);
    });

    testWidgets('renders no badge when stockStatus is normal', (tester) async {
      await tester.pumpWidget(cardHarness(status: StockStatus.normal));
      await tester.pumpAndSettle();
      expect(find.text('Az'), findsNothing);
      expect(find.text('Bitti'), findsNothing);
    });

    testWidgets('renders "Az" badge when stockStatus is low', (tester) async {
      await tester.pumpWidget(cardHarness(status: StockStatus.low));
      await tester.pumpAndSettle();
      expect(find.text('Az'), findsOneWidget);
      expect(find.text('Bitti'), findsNothing);
    });

    testWidgets('renders "Bitti" badge when stockStatus is out',
        (tester) async {
      await tester.pumpWidget(cardHarness(status: StockStatus.out));
      await tester.pumpAndSettle();
      expect(find.text('Bitti'), findsOneWidget);
      expect(find.text('Az'), findsNothing);
    });

    testWidgets('out-of-stock status surfaces in the semantics label',
        (tester) async {
      // a11y: a sighted operator sees the red "Bitti" pill, but a screen
      // reader needs the stock hint folded into the one-button label so
      // it lands in the same announcement as the name and price.
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(cardHarness(status: StockStatus.out));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel(RegExp(r'Forelle.*stokta yok')),
        findsOneWidget,
      );
      handle.dispose();
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
