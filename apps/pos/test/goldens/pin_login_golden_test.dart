/// Golden baseline: PIN login shell.
///
/// Renders a fixed-size stand-in for the PIN keypad at 1920×1200 so layout
/// regressions (keypad padding, dot indicator size, colour token drift)
/// surface as a pixel diff.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  testWidgets('golden :: pin login shell', (tester) async {
    await pumpGolden(
      tester,
      child: const _PinShellMock(),
    );
    await matchScreenGolden(tester, 'pin_login');
  });
}

class _PinShellMock extends StatelessWidget {
  const _PinShellMock();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 480,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1D24),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF282C35), width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'PIN girin',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                4,
                (i) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  width: 16,
                  height: 16,
                  decoration: const BoxDecoration(
                    color: Color(0xFF3b82f6),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            for (final row in const [
              ['1', '2', '3'],
              ['4', '5', '6'],
              ['7', '8', '9'],
              ['BACK', '0', 'CLEAR'],
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    for (final key in row)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Container(
                            height: 64,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xFF23272F),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              key,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
