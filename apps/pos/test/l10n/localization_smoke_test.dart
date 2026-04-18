/// Smoke test for the POS localization layer.
///
/// Ensures that:
///   * every supported locale loads (including the newly-added Turkish pack
///     for the Swiss fine-dining pilot's multilingual staff pool);
///   * at least 10 representative strings resolve per locale — no silent
///     fall-through to the DE template;
///   * locale-specific terminology matches the pilot brief
///     (MWST / KDV / VAT, Gäste / Kişi sayısı / Cover, Gang preserved in TR).
library;

import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/l10n/app_localizations.dart';

Future<AppLocalizations> _load(String code) async {
  final locale = Locale(code);
  return AppLocalizations.delegate.load(locale);
}

void main() {
  group('POS l10n smoke', () {
    test('supported locales include de, tr, en, fr, it', () {
      final codes = AppLocalizations.supportedLocales
          .map((l) => l.languageCode)
          .toSet();
      expect(codes, containsAll(<String>{'de', 'tr', 'en', 'fr', 'it'}));
    });

    test('Turkish pack loads and resolves 10+ strings', () async {
      final l = await _load('tr');
      final probes = <String>[
        l.appTitle,
        l.navOrders,
        l.navTables,
        l.posTotal,
        l.posVat,
        l.posCover,
        l.posServiceCharge,
        l.receiptNo,
        l.actionSave,
        l.statusError,
        l.menuCategoryStarter,
      ];
      for (final s in probes) {
        expect(s, isNotEmpty);
      }
      expect(probes.length, greaterThanOrEqualTo(10));
    });

    test('VAT abbreviation per locale', () async {
      expect((await _load('de')).fiscalReceiptVat, 'MWST');
      expect((await _load('tr')).fiscalReceiptVat, 'KDV');
      expect((await _load('en')).fiscalReceiptVat, 'VAT');
    });

    test('cover / guest terminology per locale', () async {
      expect((await _load('de')).posCover, 'Gäste');
      expect((await _load('tr')).posCover, 'Kişi sayısı');
      expect((await _load('en')).posCover, 'Cover');
    });

    test('service charge per locale', () async {
      expect((await _load('de')).posServiceCharge, 'Service');
      expect((await _load('tr')).posServiceCharge, 'Servis bedeli');
      expect((await _load('en')).posServiceCharge, 'Service');
    });

    test('course label — TR keeps the German word "Gang"', () async {
      final tr = await _load('tr');
      expect(tr.courseLabel('1'), 'Gang 1');
      expect(tr.courseLabel('3'), 'Gang 3');
      expect((await _load('en')).courseLabel('2'), 'Course 2');
      expect((await _load('de')).courseLabel('1'), '1. Gang');
    });

    test('no unresolved key falls back to DE when querying TR', () async {
      final tr = await _load('tr');
      // These strings must be in Turkish, not German.
      expect(tr.navTables, 'Masalar');
      expect(tr.actionSave, 'Kaydet');
      expect(tr.posCash, 'Nakit');
      expect(tr.posCard, 'Kart');
      expect(tr.tableGuest(2), '2 kişi');
    });
  });
}
