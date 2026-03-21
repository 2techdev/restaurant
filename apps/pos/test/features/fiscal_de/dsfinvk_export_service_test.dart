import 'package:flutter_test/flutter_test.dart';
import 'package:gastrocore_pos/features/fiscal_de/dsfinvk_export_service.dart';

void main() {
  final stammdaten = DsfinvkStammdaten(
    kasseId: 'KASSE-001',
    kasseSerialNumber: 'SN-12345',
    kasseFirmwareVersion: '1.0.0',
    taxIdNumber: '123/456/78901',
    companyName: 'Gasthaus Zum Adler',
    companyStreet: 'Hauptstr. 1',
    companyZip: '10115',
    companyCity: 'Berlin',
    companyCountry: 'DE',
  );

  final record1 = DsfinvkReceiptRecord(
    receiptId: 'REC-001',
    receiptNumber: '0001',
    receiptDatetime: DateTime.utc(2024, 3, 15, 12, 30, 0),
    kasseSerialNumber: 'SN-12345',
    netAmountStandard: 20.0,
    vatAmountStandard: 3.80,
    netAmountReduced: 0.0,
    vatAmountReduced: 0.0,
    paymentType: 'Bar',
    totalAmount: 23.80,
    tseSerialNumber: 'DEADBEEF',
    transactionNumber: 1,
    signatureCounter: 42,
    signatureValue: 'BASE64SIG==',
    signatureAlgorithm: 'ecdsa-plain-SHA384',
    signatureStartTime: DateTime.utc(2024, 3, 15, 12, 30, 0),
    signatureEndTime: DateTime.utc(2024, 3, 15, 12, 30, 1),
  );

  final record2 = DsfinvkReceiptRecord(
    receiptId: 'REC-002',
    receiptNumber: '0002',
    receiptDatetime: DateTime.utc(2024, 3, 15, 14, 0, 0),
    kasseSerialNumber: 'SN-12345',
    netAmountStandard: 0.0,
    vatAmountStandard: 0.0,
    netAmountReduced: 9.35,
    vatAmountReduced: 0.65,
    paymentType: 'Unbar',
    totalAmount: 10.00,
  );

  final service = DsfinvkExportService();

  group('DsfinvkExportService.generateExport', () {
    late DsfinvkExportResult result;

    setUp(() {
      result = service.generateExport(
        stammdaten: stammdaten,
        records: [record1, record2],
        exportStart: DateTime.utc(2024, 3, 1),
        exportEnd: DateTime.utc(2024, 3, 31),
      );
    });

    test('result has correct record count', () {
      expect(result.recordCount, equals(2));
    });

    test('exportedAt is set', () {
      expect(result.exportedAt, isNotNull);
    });

    test('files map contains all four required files', () {
      expect(result.files.keys, containsAll([
        'Z_STAMM_KASSE.csv',
        'Z_KASSE_ABSCHLUSS.csv',
        'Z_TRANS.csv',
        'Z_TSE.csv',
      ]));
    });

    group('Stammdaten CSV', () {
      test('contains header row', () {
        expect(result.stammdatenCsv, contains('Z_KASSE_ID'));
        expect(result.stammdatenCsv, contains('TAXONOMIE_VERSION'));
      });

      test('contains company data', () {
        expect(result.stammdatenCsv, contains('KASSE-001'));
        expect(result.stammdatenCsv, contains('SN-12345'));
        expect(result.stammdatenCsv, contains('123/456/78901'));
        expect(result.stammdatenCsv, contains('Gasthaus Zum Adler'));
        expect(result.stammdatenCsv, contains('10115'));
        expect(result.stammdatenCsv, contains('Berlin'));
      });

      test('contains DSFinV-K version 2.3', () {
        expect(result.stammdatenCsv, contains('2.3'));
      });
    });

    group('Kassendaten CSV', () {
      test('contains header row', () {
        expect(result.kassendatenCsv, contains('Z_GV_TYP'));
        expect(result.kassendatenCsv, contains('Z_GV_BETRAG_BRUTTO'));
      });

      test('contains 19% row for record1', () {
        expect(result.kassendatenCsv, contains('Umsatz 19%'));
        // brutto19 = 20.00 + 3.80 = 23.80
        expect(result.kassendatenCsv, contains('23,80000'));
      });

      test('contains 7% row for record2', () {
        expect(result.kassendatenCsv, contains('Umsatz 7%'));
        // brutto7 = 9.35 + 0.65 = 10.00
        expect(result.kassendatenCsv, contains('10,00000'));
      });
    });

    group('Einzelaufzeichnung CSV', () {
      test('contains header row', () {
        expect(result.einzelaufzeichnungCsv, contains('BON_ID'));
        expect(result.einzelaufzeichnungCsv, contains('GV_TYP'));
        expect(result.einzelaufzeichnungCsv, contains('ZAHLART_TYP'));
      });

      test('contains receipt IDs', () {
        expect(result.einzelaufzeichnungCsv, contains('REC-001'));
        expect(result.einzelaufzeichnungCsv, contains('REC-002'));
      });

      test('contains payment types', () {
        expect(result.einzelaufzeichnungCsv, contains('Bar'));
        expect(result.einzelaufzeichnungCsv, contains('Unbar'));
      });
    });

    group('TSE-Daten CSV', () {
      test('contains header row', () {
        expect(result.tseDatenCsv, contains('TSE_ID'));
        expect(result.tseDatenCsv, contains('TSE_SIG'));
        expect(result.tseDatenCsv, contains('TSE_TANR'));
      });

      test('contains TSE signature data for record1', () {
        expect(result.tseDatenCsv, contains('DEADBEEF'));
        expect(result.tseDatenCsv, contains('BASE64SIG=='));
        expect(result.tseDatenCsv, contains('ecdsa-plain-SHA384'));
      });

      test('does not include record2 (no TSE data)', () {
        // record2 has no tseSerialNumber — should not appear
        expect(result.tseDatenCsv, isNot(contains('REC-002')));
      });
    });
  });

  group('DsfinvkExportService — CSV escaping', () {
    test('fields with semicolons are quoted', () {
      final r = DsfinvkReceiptRecord(
        receiptId: 'REC;SEMI',
        receiptNumber: '0001',
        receiptDatetime: DateTime.utc(2024, 3, 15),
        kasseSerialNumber: 'SN',
        netAmountStandard: 10.0,
        vatAmountStandard: 1.9,
        netAmountReduced: 0,
        vatAmountReduced: 0,
        paymentType: 'Bar',
        totalAmount: 11.9,
      );
      final res = service.generateExport(
        stammdaten: stammdaten,
        records: [r],
        exportStart: DateTime.utc(2024, 1, 1),
        exportEnd: DateTime.utc(2024, 12, 31),
      );
      // The receipt ID with semicolon should be CSV-escaped
      expect(res.einzelaufzeichnungCsv, contains('"REC;SEMI"'));
    });
  });

  group('DsfinvkExportService — empty records', () {
    test('generates valid CSV with only headers for empty record set', () {
      final res = service.generateExport(
        stammdaten: stammdaten,
        records: [],
        exportStart: DateTime.utc(2024, 1, 1),
        exportEnd: DateTime.utc(2024, 12, 31),
      );
      expect(res.recordCount, equals(0));
      // All CSVs should have at least the header row
      expect(res.stammdatenCsv, contains('Z_KASSE_ID'));
      expect(res.kassendatenCsv, contains('Z_GV_TYP'));
      expect(res.einzelaufzeichnungCsv, contains('BON_ID'));
      expect(res.tseDatenCsv, contains('TSE_ID'));
    });
  });
}
