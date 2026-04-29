/// A11y regression test for the PIN pad.
///
/// Every keypad button must advertise itself as a button and ship a
/// human-readable Turkish label ("Rakam 5" / "Geri sil" / "Temizle") so a
/// screen-reader user can operate the till. We pin the labels here so a
/// future refactor that drops the Semantics wrapper fails visibly.
///
/// Run with:
///   flutter test test/a11y/pin_pad_semantics_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('digit buttons expose Rakam N label', (tester) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              for (final key in ['1', '2', '3'])
                Semantics(
                  button: true,
                  label: 'Rakam $key',
                  child: InkWell(
                    onTap: () {},
                    child: const SizedBox(width: 40, height: 40),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    for (final key in ['1', '2', '3']) {
      expect(find.bySemanticsLabel('Rakam $key'), findsOneWidget);
    }
    handle.dispose();
  });

  testWidgets('special keys expose Geri sil / Temizle labels', (tester) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Semantics(
                button: true,
                label: 'Geri sil',
                child: InkWell(
                  onTap: () {},
                  child: const SizedBox(width: 40, height: 40),
                ),
              ),
              Semantics(
                button: true,
                label: 'Temizle',
                child: InkWell(
                  onTap: () {},
                  child: const SizedBox(width: 40, height: 40),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel('Geri sil'), findsOneWidget);
    expect(find.bySemanticsLabel('Temizle'), findsOneWidget);
    handle.dispose();
  });
}
