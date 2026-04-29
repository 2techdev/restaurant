/// Harness for golden-baseline tests.
///
/// Pins the viewport to the pilot's physical tablet resolution (1920×1200)
/// so a layout / padding regression is surfaced as a pixel diff. Every
/// test in `test/goldens/` uses [pumpGolden] + [matchScreenGolden] so a
/// single knob (viewport size, theme, safe area) governs the whole suite.
///
/// Regenerate every baseline with:
///   flutter test --update-goldens test/goldens/
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pilot tablet resolution.
const Size kPilotViewport = Size(1920, 1200);

/// Pumps [child] inside a fixed-size MaterialApp, awaits settle, and
/// registers a tear-down that resets the surface size.
Future<void> pumpGolden(
  WidgetTester tester, {
  required Widget child,
  Size size = kPilotViewport,
  ThemeData? theme,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme ?? ThemeData.dark(useMaterial3: true),
      home: MediaQuery(
        data: MediaQueryData(size: size, devicePixelRatio: 1.0),
        child: Scaffold(body: Center(child: child)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Shoots the whole viewport and matches against `goldens/<name>.png`.
Future<void> matchScreenGolden(
  WidgetTester tester,
  String name,
) async {
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('$name.png'),
  );
}
