/// Guards ARB parity so future commits cannot drift one locale ahead of
/// another.
///
/// `app_de.arb` is the template (configured via `l10n.yaml:template-arb-file`)
/// and carries the `@key` metadata blocks — callers should not copy those
/// to the other locales. This test only asserts that the set of value-keys
/// is identical across locales and that no value is an empty string.
///
/// Run with:
///   flutter test test/l10n/arb_parity_test.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _arbDir = 'lib/l10n';
const _locales = ['de', 'en', 'fr', 'it'];

Set<String> _valueKeys(Map<String, dynamic> arb) {
  return arb.keys.where((k) => !k.startsWith('@')).toSet();
}

Map<String, dynamic> _loadArb(String locale) {
  final f = File('$_arbDir/app_$locale.arb');
  if (!f.existsSync()) {
    fail('Missing ARB: ${f.path}');
  }
  return json.decode(f.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  group('ARB parity', () {
    final arbs = {for (final l in _locales) l: _loadArb(l)};

    test('every locale exposes the same set of value-keys', () {
      final template = _valueKeys(arbs['de']!);
      for (final l in _locales.where((x) => x != 'de')) {
        final actual = _valueKeys(arbs[l]!);
        final missing = template.difference(actual);
        final extra = actual.difference(template);
        expect(
          missing,
          isEmpty,
          reason: 'app_$l.arb is missing keys present in the DE template: '
              '$missing',
        );
        expect(
          extra,
          isEmpty,
          reason: 'app_$l.arb has keys not in the DE template (likely a '
              'typo or left-behind key): $extra',
        );
      }
    });

    test('no value is empty — empty string is almost always a mistake', () {
      for (final l in _locales) {
        final arb = arbs[l]!;
        for (final k in _valueKeys(arb)) {
          final v = arb[k];
          expect(
            v,
            isA<String>().having((s) => s.trim(), 'trimmed', isNotEmpty),
            reason: 'app_$l.arb has empty value for key "$k"',
          );
        }
      }
    });

    test('each locale declares its own @@locale', () {
      for (final l in _locales) {
        expect(arbs[l]!['@@locale'], l, reason: 'app_$l.arb @@locale mismatch');
      }
    });

    test('Swiss German uses "ss" not "ß" for the sharp-s', () {
      final de = arbs['de']!;
      for (final k in _valueKeys(de)) {
        final v = de[k] as String;
        expect(
          v.contains('ß'),
          isFalse,
          reason: 'Swiss German should use "ss" instead of "ß" in key "$k": '
              '${jsonEncode(v)}',
        );
      }
    });
  });
}
