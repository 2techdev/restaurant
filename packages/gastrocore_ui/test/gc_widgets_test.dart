import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gastrocore_ui/gastrocore_ui.dart';

/// Smoke tests for the Gc* widget family. We're not asserting pixel-perfect
/// layout — only that each widget renders, responds to interaction, and
/// exposes the semantic hooks an app would rely on.

Widget _wrap(Widget child) => MaterialApp(
      theme: GastrocoreTheme.dark(),
      home: Scaffold(body: Padding(padding: GcSpacing.paddingLg, child: child)),
    );

void main() {
  group('Design tokens', () {
    test('GcColors re-exports AppColors values', () {
      expect(GcColors.brand, AppColors.primary);
      expect(GcColors.surface, AppColors.surface);
      expect(GcColors.danger, AppColors.red);
    });

    test('GcSpacing values follow a 4-pt baseline', () {
      expect(GcSpacing.xs, 4);
      expect(GcSpacing.sm, 8);
      expect(GcSpacing.md, 12);
      expect(GcSpacing.lg, 16);
      expect(GcSpacing.xl, 24);
      expect(GcSpacing.xxl, 32);
    });

    test('GcTextStyles.priceTabular uses tabular figures', () {
      final features = GcTextStyles.priceTabular.fontFeatures;
      expect(features, isNotNull);
      expect(features!.any((f) => f.feature == 'tnum'), isTrue);
    });
  });

  group('GcButton', () {
    testWidgets('fires onPressed', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_wrap(GcButton.primary(
        onPressed: () => taps++,
        child: const Text('Save'),
      )));
      await tester.tap(find.text('Save'));
      expect(taps, 1);
    });

    testWidgets('suppresses onPressed while loading', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_wrap(GcButton.primary(
        onPressed: () => taps++,
        loading: true,
        child: const Text('Save'),
      )));
      // While loading, the label is replaced by a spinner.
      expect(find.text('Save'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byType(GcButton));
      expect(taps, 0);
    });

    testWidgets('disabled (onPressed=null) does not fire', (tester) async {
      await tester.pumpWidget(_wrap(const GcButton.primary(
        onPressed: null,
        child: Text('Disabled'),
      )));
      await tester.tap(find.text('Disabled'));
      // No callback set — nothing to assert beyond that no exception is thrown.
      expect(find.text('Disabled'), findsOneWidget);
    });
  });

  group('GcCard', () {
    testWidgets('renders its child and fires onTap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_wrap(GcCard(
        onTap: () => taps++,
        child: const Text('Card content'),
      )));
      expect(find.text('Card content'), findsOneWidget);
      await tester.tap(find.text('Card content'));
      expect(taps, 1);
    });
  });

  group('GcDialog.confirm', () {
    testWidgets('returns true when the confirm action is tapped',
        (tester) async {
      bool? result;
      await tester.pumpWidget(_wrap(Builder(builder: (ctx) {
        return GcButton.primary(
          onPressed: () async {
            result = await GcDialog.confirm(
              ctx,
              title: 'Void ticket?',
              message: 'This cannot be undone.',
              destructive: true,
            );
          },
          child: const Text('Open'),
        );
      })));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Void ticket?'), findsOneWidget);

      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });
  });

  group('GcSnackbar', () {
    testWidgets('renders a message with the success icon', (tester) async {
      await tester.pumpWidget(_wrap(Builder(builder: (ctx) {
        return GcButton.primary(
          onPressed: () => GcSnackbar.success(ctx, 'Saved!'),
          child: const Text('Save'),
        );
      })));
      await tester.tap(find.text('Save'));
      await tester.pump(); // start animation
      expect(find.text('Saved!'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });
  });

  group('GcBottomSheet', () {
    testWidgets('show() presents the body and a drag handle', (tester) async {
      await tester.pumpWidget(_wrap(Builder(builder: (ctx) {
        return GcButton.primary(
          onPressed: () => GcBottomSheet.show<void>(
            ctx,
            title: 'Pay',
            child: const Text('Bottom sheet body'),
          ),
          child: const Text('Open'),
        );
      })));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Pay'), findsOneWidget);
      expect(find.text('Bottom sheet body'), findsOneWidget);
    });
  });

  group('GcTextField', () {
    testWidgets('reports edits via onChanged', (tester) async {
      String value = '';
      await tester.pumpWidget(_wrap(GcTextField(
        label: 'Name',
        onChanged: (v) => value = v,
      )));
      await tester.enterText(find.byType(TextField), 'Rösti');
      expect(value, 'Rösti');
    });

    testWidgets('shows the error text when provided', (tester) async {
      await tester.pumpWidget(_wrap(const GcTextField(
        label: 'PIN',
        errorText: 'PIN is required',
      )));
      expect(find.text('PIN is required'), findsOneWidget);
    });
  });

  group('GcDropdown', () {
    testWidgets('selecting an item fires onChanged with the typed value',
        (tester) async {
      int? selected = 1;
      await tester.pumpWidget(_wrap(StatefulBuilder(
        builder: (ctx, setState) => GcDropdown<int>(
          label: 'Bucket',
          value: selected,
          items: const [
            GcDropdownItem(value: 1, label: 'Standard'),
            GcDropdownItem(value: 2, label: 'Reduced'),
          ],
          onChanged: (v) => setState(() => selected = v),
        ),
      )));
      // Open the dropdown (tap the currently-displayed value).
      await tester.tap(find.text('Standard'));
      await tester.pumpAndSettle();
      // Pick the other option from the expanded menu.
      await tester.tap(find.text('Reduced').last);
      await tester.pumpAndSettle();
      expect(selected, 2);
    });
  });
}
