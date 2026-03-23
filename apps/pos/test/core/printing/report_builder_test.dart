import 'package:flutter_test/flutter_test.dart';
import 'package:gastrocore_pos/core/printing/escpos/report_builder.dart';
import 'package:gastrocore_pos/core/printing/models/print_models.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Test verileri
  // ---------------------------------------------------------------------------

  ShiftReportData makeData({
    String title = 'Z-RAPPORT',
    int reportNo = 1,
    String? cashierName,
    String? terminalNo,
    DateTime? shiftStart,
    DateTime? shiftEnd,
    int grossSales = 0,
    int totalDiscount = 0,
    int netSales = 0,
    int totalReturns = 0,
    int netRevenue = 0,
    Map<String, int> paymentBreakdown = const {},
    List<MwStReportEntry> mwstEntries = const [],
    int orderCount = 0,
    int voidCount = 0,
    int returnCount = 0,
    int? openingFloat,
    int? closingFloat,
  }) {
    final now = DateTime(2026, 3, 20, 19, 45, 0);
    return ShiftReportData(
      reportTitle: title,
      reportNo: reportNo,
      cashierName: cashierName,
      terminalNo: terminalNo,
      shiftStart: shiftStart ?? DateTime(2026, 3, 20, 8, 0, 0),
      shiftEnd: shiftEnd,
      printedAt: now,
      grossSales: grossSales,
      totalDiscount: totalDiscount,
      netSales: netSales,
      totalReturns: totalReturns,
      netRevenue: netRevenue,
      paymentBreakdown: paymentBreakdown,
      mwstEntries: mwstEntries,
      orderCount: orderCount,
      voidCount: voidCount,
      returnCount: returnCount,
      openingFloat: openingFloat,
      closingFloat: closingFloat,
    );
  }

  String extractText(List<int> bytes) => String.fromCharCodes(
        bytes.where((b) => b >= 0x20 || b == 0x0A),
      );

  // ===========================================================================
  // Temel çıktı
  // ===========================================================================

  group('Temel çıktı', () {
    test('build() boş olmayan byte dizisi döndürür', () {
      final bytes = ReportBuilder(data: makeData()).build();
      expect(bytes, isNotEmpty);
    });

    test('ESC @ (initialize) ile başlar', () {
      final bytes = ReportBuilder(data: makeData()).build();
      expect(bytes[0], 0x1B);
      expect(bytes[1], 0x40);
    });

    test('GS V 1 (partial cut) ile biter', () {
      final bytes = ReportBuilder(data: makeData()).build();
      bool hasCut = false;
      for (int i = 0; i < bytes.length - 2; i++) {
        if (bytes[i] == 0x1D && bytes[i + 1] == 0x56 && bytes[i + 2] == 0x01) {
          hasCut = true;
          break;
        }
      }
      expect(hasCut, isTrue);
    });
  });

  // ===========================================================================
  // Başlık bölümü
  // ===========================================================================

  group('Başlık bölümü', () {
    test('Z-RAPPORT başlığı yazdırılır', () {
      final text = extractText(ReportBuilder(data: makeData(title: 'Z-RAPPORT')).build());
      expect(text, contains('Z-RAPPORT'));
    });

    test('X-RAPPORT başlığı yazdırılır', () {
      final text = extractText(ReportBuilder(data: makeData(title: 'X-RAPPORT')).build());
      expect(text, contains('X-RAPPORT'));
    });

    test('Rapor numarası yazdırılır', () {
      final text = extractText(ReportBuilder(data: makeData(reportNo: 42)).build());
      expect(text, contains('42'));
    });

    test('Kasiyer adı yazdırılır', () {
      final text = extractText(
        ReportBuilder(data: makeData(cashierName: 'Anna Mueller')).build(),
      );
      expect(text, contains('Anna Mueller'));
    });

    test('Terminal numarası yazdırılır', () {
      final text = extractText(
        ReportBuilder(data: makeData(terminalNo: 'POS-01')).build(),
      );
      expect(text, contains('POS-01'));
    });

    test('Şift başlangıcı yazdırılır', () {
      final text = extractText(
        ReportBuilder(
          data: makeData(shiftStart: DateTime(2026, 3, 20, 8, 0, 0)),
        ).build(),
      );
      expect(text, contains('08:00:00'));
    });

    test('Şift bitişi varsa yazdırılır', () {
      final text = extractText(
        ReportBuilder(
          data: makeData(shiftEnd: DateTime(2026, 3, 20, 19, 45, 0)),
        ).build(),
      );
      expect(text, contains('19:45:00'));
    });
  });

  // ===========================================================================
  // Satış bölümü
  // ===========================================================================

  group('Satış (UMSATZ) bölümü', () {
    test('UMSATZ başlığı yazdırılır', () {
      final text = extractText(ReportBuilder(data: makeData()).build());
      expect(text, contains('UMSATZ'));
    });

    test('Brüt satış tutarı yazdırılır', () {
      final text = extractText(
        ReportBuilder(data: makeData(grossSales: 425000)).build(),
      );
      expect(text, contains('4250.00'));
    });

    test('İndirim tutarı varsa yazdırılır', () {
      final text = extractText(
        ReportBuilder(data: makeData(grossSales: 425000, totalDiscount: 12500)).build(),
      );
      expect(text, contains('Rabatte'));
      expect(text, contains('125.00'));
    });

    test('İndirim yoksa "Rabatte" yazdırılmaz', () {
      final text = extractText(
        ReportBuilder(data: makeData(totalDiscount: 0)).build(),
      );
      expect(text, isNot(contains('Rabatte')));
    });

    test('İade tutarı varsa yazdırılır', () {
      final text = extractText(
        ReportBuilder(data: makeData(totalReturns: 5000)).build(),
      );
      expect(text, contains('Retouren'));
      expect(text, contains('50.00'));
    });

    test('Net gelir (Nettoumsatz gesamt) yazdırılır', () {
      final text = extractText(
        ReportBuilder(data: makeData(netRevenue: 407500)).build(),
      );
      expect(text, contains('Nettoumsatz gesamt'));
      expect(text, contains('4075.00'));
    });
  });

  // ===========================================================================
  // Ödeme bölümü
  // ===========================================================================

  group('Ödeme (ZAHLUNGEN) bölümü', () {
    test('ZAHLUNGEN başlığı yazdırılır', () {
      final text = extractText(ReportBuilder(data: makeData()).build());
      expect(text, contains('ZAHLUNGEN'));
    });

    test('Ödeme yöntemleri ve tutarları yazdırılır', () {
      final text = extractText(
        ReportBuilder(
          data: makeData(paymentBreakdown: {
            'Bar': 125000,
            'Karte': 250000,
            'TWINT': 32500,
          }),
        ).build(),
      );
      expect(text, contains('Bar'));
      expect(text, contains('1250.00'));
      expect(text, contains('Karte'));
      expect(text, contains('2500.00'));
      expect(text, contains('TWINT'));
      expect(text, contains('325.00'));
    });

    test('Ödeme toplamı yazdırılır', () {
      final text = extractText(
        ReportBuilder(
          data: makeData(paymentBreakdown: {'Bar': 125000, 'Karte': 250000}),
        ).build(),
      );
      // Toplam: 125000 + 250000 = 375000 = CHF 3750.00
      expect(text, contains('3750.00'));
    });
  });

  // ===========================================================================
  // MwSt tablosu
  // ===========================================================================

  group('MWST-ABRECHNUNG bölümü', () {
    test('mwstEntries boşsa MWST-ABRECHNUNG başlığı yazdırılmaz', () {
      final text = extractText(ReportBuilder(data: makeData(mwstEntries: [])).build());
      expect(text, isNot(contains('MWST-ABRECHNUNG')));
    });

    test('MWST-ABRECHNUNG başlığı yazdırılır', () {
      final text = extractText(
        ReportBuilder(
          data: makeData(mwstEntries: [
            MwStReportEntry(code: MwStCode.a, grossAmount: 10000),
          ]),
        ).build(),
      );
      expect(text, contains('MWST-ABRECHNUNG'));
    });

    test('MwSt kodu, oranı ve tutarı yazdırılır', () {
      final text = extractText(
        ReportBuilder(
          data: makeData(mwstEntries: [
            MwStReportEntry(code: MwStCode.a, grossAmount: 10000),
            MwStReportEntry(code: MwStCode.b, grossAmount: 5000),
          ]),
        ).build(),
      );
      expect(text, contains('8.1%'));
      expect(text, contains('2.6%'));
    });

    test('Toplam satırı yazdırılır', () {
      final text = extractText(
        ReportBuilder(
          data: makeData(mwstEntries: [
            MwStReportEntry(code: MwStCode.a, grossAmount: 10000),
          ]),
        ).build(),
      );
      expect(text, contains('Total'));
    });

    test('Kodlar alfabetik sırada yazdırılır (A → B → C)', () {
      final text = extractText(
        ReportBuilder(
          data: makeData(mwstEntries: [
            MwStReportEntry(code: MwStCode.c, grossAmount: 1000),
            MwStReportEntry(code: MwStCode.a, grossAmount: 5000),
            MwStReportEntry(code: MwStCode.b, grossAmount: 2000),
          ]),
        ).build(),
      );
      final aIdx = text.lastIndexOf('8.1%');
      final bIdx = text.lastIndexOf('2.6%');
      final cIdx = text.lastIndexOf('3.8%');
      expect(aIdx, lessThan(bIdx));
      expect(bIdx, lessThan(cIdx));
    });
  });

  // ===========================================================================
  // İstatistik bölümü
  // ===========================================================================

  group('İstatistik (STATISTIK) bölümü', () {
    test('STATISTIK başlığı yazdırılır', () {
      final text = extractText(ReportBuilder(data: makeData()).build());
      expect(text, contains('STATISTIK'));
    });

    test('Bon sayısı yazdırılır', () {
      final text =
          extractText(ReportBuilder(data: makeData(orderCount: 45)).build());
      expect(text, contains('45'));
    });

    test('Storno sayısı yazdırılır', () {
      final text =
          extractText(ReportBuilder(data: makeData(voidCount: 3)).build());
      expect(text, contains('Stornierungen'));
    });

    test('İade sayısı yazdırılır', () {
      final text =
          extractText(ReportBuilder(data: makeData(returnCount: 1)).build());
      expect(text, contains('Retouren'));
    });
  });

  // ===========================================================================
  // Kasa bölümü
  // ===========================================================================

  group('Kasa (KASSENSTAND) bölümü', () {
    test('openingFloat yoksa KASSENSTAND bölümü yazdırılmaz', () {
      final text = extractText(ReportBuilder(data: makeData()).build());
      expect(text, isNot(contains('KASSENSTAND')));
    });

    test('Kasa açılış tutarı yazdırılır', () {
      final text = extractText(
        ReportBuilder(data: makeData(openingFloat: 50000)).build(),
      );
      expect(text, contains('KASSENSTAND'));
      expect(text, contains('500.00'));
    });

    test('Kasa kapanış tutarı yazdırılır', () {
      final text = extractText(
        ReportBuilder(
          data: makeData(openingFloat: 50000, closingFloat: 175000),
        ).build(),
      );
      expect(text, contains('Kassenendstand'));
      expect(text, contains('1750.00'));
    });

    test('cashDifference hesabı doğru: nakit ödeme + açılış - kapanış', () {
      // Açılış: CHF 500, Nakit ödeme: CHF 1250, Beklenen kapanış: CHF 1750
      // Gerçek kapanış: CHF 1750, Fark: 0
      final reportData = makeData(
        openingFloat: 50000,
        closingFloat: 175000,
        paymentBreakdown: {'Bar': 125000, 'Karte': 100000},
      );
      expect(reportData.cashDifference, 0);
    });

    test('cashDifference negatif ise fazla ödeme yapılmış', () {
      // Açılış: CHF 500, Nakit ödeme: CHF 1250, Beklenen: CHF 1750
      // Gerçek kapanış: CHF 1740, Fark: -10 CHF (1000 cent)
      final reportData = makeData(
        openingFloat: 50000,
        closingFloat: 174000,
        paymentBreakdown: {'Bar': 125000},
      );
      expect(reportData.cashDifference, -1000);
    });
  });

  // ===========================================================================
  // Kapanış mesajı
  // ===========================================================================

  group('Kapanış mesajı', () {
    test('Z raporu "KASSE GESCHLOSSEN" ile biter', () {
      final text =
          extractText(ReportBuilder(data: makeData(title: 'Z-RAPPORT')).build());
      expect(text, contains('KASSE GESCHLOSSEN'));
    });

    test('X raporu "ZWISCHENBERICHT" ile biter', () {
      final text =
          extractText(ReportBuilder(data: makeData(title: 'X-RAPPORT')).build());
      expect(text, contains('ZWISCHENBERICHT'));
    });
  });

  // ===========================================================================
  // MwStReportEntry hesaplama
  // ===========================================================================

  group('MwStReportEntry', () {
    test('%8.1 — 100000 cent brüt doğru hesaplanır', () {
      // MwSt = 100000 * 8.1 / 108.1 = 810000 / 108.1 = 7493.06... ≈ 7493
      // Netto = 100000 - 7493 = 92507
      final e = MwStReportEntry(code: MwStCode.a, grossAmount: 100000);
      expect(e.taxAmount, 7493);
      expect(e.netAmount, 92507);
    });

    test('%2.6 — 100000 cent brüt doğru hesaplanır', () {
      // MwSt = 100000 * 2.6 / 102.6 = 2534.11... ≈ 2534
      // Netto = 100000 - 2534 = 97466
      final e = MwStReportEntry(code: MwStCode.b, grossAmount: 100000);
      expect(e.taxAmount, 2534);
      expect(e.netAmount, 97466);
    });

    test('%3.8 — 100000 cent brüt doğru hesaplanır', () {
      // MwSt = 100000 * 3.8 / 103.8 = 380000 / 103.8 = 3660.88... ≈ 3661
      // Netto = 100000 - 3661 = 96339
      final e = MwStReportEntry(code: MwStCode.c, grossAmount: 100000);
      expect(e.taxAmount, 3661);
      expect(e.netAmount, 96339);
    });

    test('grossAmount=0 için tax=0 ve net=0', () {
      final e = MwStReportEntry(code: MwStCode.a, grossAmount: 0);
      expect(e.taxAmount, 0);
      expect(e.netAmount, 0);
    });
  });
}
