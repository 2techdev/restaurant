/// Unit tests for [PosMode] persistence.
///
/// Invariant: setMode writes to SharedPreferences and a new notifier
/// spun up on the same prefs reads the saved value back. An unknown or
/// corrupt string falls back to [PosMode.fineDining] — never throws.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gastrocore_pos/core/pos_mode/pos_mode.dart';

void main() {
  group('PosMode.fromName', () {
    test('recognises the canonical enum names', () {
      expect(PosMode.fromName('fineDining'), PosMode.fineDining);
      expect(PosMode.fromName('fastFood'), PosMode.fastFood);
      expect(PosMode.fromName('quickService'), PosMode.quickService);
    });

    test('falls back to fineDining for null or unknown', () {
      expect(PosMode.fromName(null), PosMode.fineDining);
      expect(PosMode.fromName(''), PosMode.fineDining);
      expect(PosMode.fromName('garbage'), PosMode.fineDining);
    });
  });

  group('PosModeNotifier persistence', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('defaults to fineDining when prefs are empty', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = PosModeNotifier(prefs);
      expect(notifier.state, PosMode.fineDining);
    });

    test('setMode writes to prefs and persists across notifier lifecycles',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final first = PosModeNotifier(prefs);

      await first.setMode(PosMode.fastFood);
      expect(first.state, PosMode.fastFood);
      expect(prefs.getString('pos.mode'), 'fastFood');

      // Spin up a new notifier on the same prefs — the setting survives.
      final second = PosModeNotifier(prefs);
      expect(second.state, PosMode.fastFood);
    });

    test('handles a null prefs gracefully and stays in-memory', () async {
      final notifier = PosModeNotifier(null);
      expect(notifier.state, PosMode.fineDining);
      await notifier.setMode(PosMode.quickService);
      expect(notifier.state, PosMode.quickService);
    });
  });
}
