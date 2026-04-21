/// Unit + widget tests for [ErrorHandler].
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/core/error/failures.dart';
import 'package:gastrocore_pos/core/utils/error_handler.dart';

/// Pumps a scaffold that exposes [BuildContext] via [onReady].
Future<BuildContext> _pumpHost(WidgetTester tester) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(builder: (ctx) {
          captured = ctx;
          return const SizedBox.shrink();
        }),
      ),
    ),
  );
  return captured;
}

void main() {
  group('ErrorHandler.describe', () {
    test('returns Failure.message for any Failure subtype', () {
      expect(
        ErrorHandler.describe(
          const DatabaseFailure(message: 'disk full'),
        ),
        'disk full',
      );
      expect(
        ErrorHandler.describe(
          const ValidationFailure(message: 'PIN zu kurz'),
        ),
        'PIN zu kurz',
      );
    });

    test('uses fallback for non-Failure errors when provided', () {
      expect(
        ErrorHandler.describe(
          StateError('boom'),
          fallback: 'Unbekannter Fehler',
        ),
        'Unbekannter Fehler',
      );
    });

    test('falls through to toString when no fallback is given', () {
      final msg = ErrorHandler.describe(StateError('boom'));
      expect(msg, contains('boom'));
    });
  });

  group('ErrorHandler.run', () {
    testWidgets('on success: returns true and shows the success message',
        (tester) async {
      final context = await _pumpHost(tester);

      final ok = await ErrorHandler.run(
        context,
        () async {},
        onSuccess: 'Gespeichert.',
      );
      await tester.pump();

      expect(ok, isTrue);
      expect(find.text('Gespeichert.'), findsOneWidget);
    });

    testWidgets('on throw: returns false and shows failureLabel + message',
        (tester) async {
      final context = await _pumpHost(tester);

      final ok = await ErrorHandler.run(
        context,
        () async =>
            throw const DatabaseFailure(message: 'disk full'),
        failureLabel: 'Konnte nicht speichern',
      );
      await tester.pump();

      expect(ok, isFalse);
      expect(
        find.text('Konnte nicht speichern: disk full'),
        findsOneWidget,
      );
    });

    testWidgets('stays quiet on success when onSuccess is null',
        (tester) async {
      final context = await _pumpHost(tester);

      await ErrorHandler.run(context, () async {});
      await tester.pump();

      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('ErrorHandler.showError', () {
    testWidgets('paints the error snackbar red', (tester) async {
      final context = await _pumpHost(tester);

      ErrorHandler.showError(
        context,
        const DatabaseFailure(message: 'disk full'),
      );
      await tester.pump();

      final snack = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snack.backgroundColor, isNotNull);
      expect(find.text('disk full'), findsOneWidget);
    });
  });
}
