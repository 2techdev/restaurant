/// Sprint 4 widget tests for the SambaPOS richness additions to
/// [showModifierDialog]:
///   * `askQuantity`  — per-option stepper (1..10), price scales.
///   * `freeTagging`  — per-option note (≤ 100 chars, surfaced in result).
///   * Result propagation through [ModifierDialogResult.flattened].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/features/orders/presentation/widgets/modifier_dialog.dart';

void main() {
  group('askQuantity stepper', () {
    testWidgets('stepper appears only when option is selected', (tester) async {
      await _pump(tester, groups: [
        const ModifierGroupData(
          name: 'Extras',
          isMultiSelect: true,
          maxSelections: 3,
          askQuantity: true,
          options: [
            ModifierOptionData(id: 'cheese', name: 'Extra Cheese', priceDelta: 200),
          ],
        ),
      ]);

      // Stepper is hidden until the chip is tapped.
      expect(find.text('×1'), findsNothing);

      await tester.tap(find.text('Extra Cheese'));
      await tester.pump();
      expect(find.text('×1'), findsOneWidget);
    });

    testWidgets('stepper increments and clamps at 10, updates total',
        (tester) async {
      await _pump(
        tester,
        productPrice: 1000,
        groups: [
          const ModifierGroupData(
            name: 'Extras',
            isMultiSelect: true,
            maxSelections: 3,
            askQuantity: true,
            options: [
              ModifierOptionData(
                id: 'cheese',
                name: 'Extra Cheese',
                priceDelta: 200,
              ),
            ],
          ),
        ],
      );

      await tester.tap(find.text('Extra Cheese'));
      await tester.pump();

      // Baseline: qty=1 → total = 1000 + 200 = 1200
      expect(find.text('CHF 12.00'), findsOneWidget);

      // Tap + eleven times, clamp should stop at 10.
      for (var i = 0; i < 11; i++) {
        await tester.tap(find.byIcon(Icons.add).first);
        await tester.pump();
      }
      expect(find.text('×10'), findsOneWidget);

      // Total at qty=10 → 1000 + 200*10 = 3000
      expect(find.text('CHF 30.00'), findsOneWidget);
    });

    testWidgets('result carries per-option quantity via flattened', (tester) async {
      ModifierDialogResult? captured;

      await _pump(
        tester,
        groups: [
          const ModifierGroupData(
            name: 'Extras',
            isMultiSelect: true,
            maxSelections: 3,
            askQuantity: true,
            options: [
              ModifierOptionData(
                id: 'cheese',
                name: 'Extra Cheese',
                priceDelta: 200,
              ),
            ],
          ),
        ],
        onResult: (r) => captured = r,
      );

      await tester.tap(find.text('Extra Cheese'));
      await tester.pump();

      // Bump to ×3.
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pump();

      await tester.tap(find.text('Zur Bestellung'));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      final flat = captured!.flattened().toList();
      expect(flat, hasLength(1));
      expect(flat.first.option.id, 'cheese');
      expect(flat.first.quantity, 3);
      expect(flat.first.note, isNull);
    });
  });

  group('freeTagging notes', () {
    testWidgets('note field appears after selection and caps at 100 chars',
        (tester) async {
      await _pump(tester, groups: [
        const ModifierGroupData(
          name: 'Extras',
          isMultiSelect: true,
          maxSelections: 3,
          freeTagging: true,
          options: [
            ModifierOptionData(id: 'salt', name: 'Salt'),
          ],
        ),
      ]);

      expect(find.widgetWithText(TextField, 'Not...'), findsNothing);

      await tester.tap(find.text('Salt'));
      await tester.pump();

      final field = find.widgetWithText(TextField, 'Not...');
      expect(field, findsOneWidget);

      final widget = tester.widget<TextField>(field);
      expect(widget.maxLength, 100);
    });

    testWidgets('trimmed non-empty note propagates to flattened().note',
        (tester) async {
      ModifierDialogResult? captured;

      await _pump(
        tester,
        groups: [
          const ModifierGroupData(
            name: 'Extras',
            isMultiSelect: true,
            maxSelections: 3,
            freeTagging: true,
            options: [
              ModifierOptionData(id: 'salt', name: 'Salt'),
            ],
          ),
        ],
        onResult: (r) => captured = r,
      );

      await tester.tap(find.text('Salt'));
      await tester.pump();

      await tester.enterText(
          find.widgetWithText(TextField, 'Not...'), '  less salt  ');
      await tester.pump();

      await tester.tap(find.text('Zur Bestellung'));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      final flat = captured!.flattened().toList();
      expect(flat, hasLength(1));
      expect(flat.first.note, 'less salt');
    });

    testWidgets('empty note is dropped — flattened().note stays null',
        (tester) async {
      ModifierDialogResult? captured;

      await _pump(
        tester,
        groups: [
          const ModifierGroupData(
            name: 'Extras',
            isMultiSelect: true,
            maxSelections: 3,
            freeTagging: true,
            options: [
              ModifierOptionData(id: 'salt', name: 'Salt'),
            ],
          ),
        ],
        onResult: (r) => captured = r,
      );

      await tester.tap(find.text('Salt'));
      await tester.pump();
      // Leave note empty.

      await tester.tap(find.text('Zur Bestellung'));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.flattened().first.note, isNull);
    });
  });

  group('combined askQuantity + freeTagging', () {
    testWidgets('per-option qty and note reach flattened() together',
        (tester) async {
      ModifierDialogResult? captured;

      await _pump(
        tester,
        groups: [
          const ModifierGroupData(
            name: 'Extras',
            isMultiSelect: true,
            maxSelections: 3,
            askQuantity: true,
            freeTagging: true,
            options: [
              ModifierOptionData(
                id: 'cheese',
                name: 'Extra Cheese',
                priceDelta: 150,
              ),
            ],
          ),
        ],
        onResult: (r) => captured = r,
      );

      await tester.tap(find.text('Extra Cheese'));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.add).first);
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pump();

      await tester.enterText(
          find.widgetWithText(TextField, 'Not...'), 'light melt');
      await tester.pump();

      await tester.tap(find.text('Zur Bestellung'));
      await tester.pumpAndSettle();

      final sel = captured!.flattened().single;
      expect(sel.quantity, 3);
      expect(sel.note, 'light melt');
      expect(sel.option.priceDelta, 150);
    });
  });
}

// ---------------------------------------------------------------------------
// Helper: pump a host widget with a button that opens the dialog.
// ---------------------------------------------------------------------------

Future<void> _pump(
  WidgetTester tester, {
  required List<ModifierGroupData> groups,
  int productPrice = 1000,
  void Function(ModifierDialogResult?)? onResult,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  final r = await showModifierDialog(
                    context: ctx,
                    productName: 'Pizza Test',
                    productPrice: productPrice,
                    modifierGroups: groups,
                  );
                  if (onResult != null) onResult(r);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}
