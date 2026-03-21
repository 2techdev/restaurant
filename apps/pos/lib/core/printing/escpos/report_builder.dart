import 'dart:typed_data';

import '../models/print_models.dart';
import 'esc_pos_builder.dart';

/// Z/X Raporu ESC/POS oluşturucu.
///
/// Gün sonu (Z) veya ara (X) kasa kapanış raporunu üretir.
///
/// - **Z-Raporu** ([ShiftReportData.reportTitle] = 'Z-RAPPORT'):
///   Kasa sıfırlanır, gün kapanır. "KASSE GESCHLOSSEN" ile biter.
/// - **X-Raporu** ([ShiftReportData.reportTitle] = 'X-RAPPORT'):
///   Aynı format, ancak kasa sıfırlanmaz (ara kontrol raporu).
///   "ZWISCHENBERICHT" ile biter.
///
/// Rapor yapısı:
/// 1. Başlık (rapor adı büyük, rapor no, kasiyer, tarih, vardiya bilgisi)
/// 2. UMSATZ (brüt satış, indirim, netto satış, iade, net gelir)
/// 3. ZAHLUNGEN (ödeme yöntemi kırılımı, toplam)
/// 4. MWST-ABRECHNUNG (vergi kodu tablosu)
/// 5. STATISTIK (bon sayısı, storno, iade)
/// 6. KASSENSTAND (açılış/kapanış kasa, fark) — opsiyonel
/// 7. Kapanış mesajı
///
/// Kullanım:
/// ```dart
/// final bytes = ReportBuilder(
///   data: ShiftReportData(
///     reportTitle: 'Z-RAPPORT',
///     reportNo: 12,
///     shiftStart: DateTime(2026, 3, 20, 8, 0),
///     printedAt: DateTime.now(),
///     grossSales: 425000,     // CHF 4250.00
///     netSales: 412500,
///     netRevenue: 407500,
///     paymentBreakdown: {'Bar': 125000, 'Karte': 250000, 'TWINT': 32500},
///     mwstEntries: [
///       MwStReportEntry(code: MwStCode.a, grossAmount: 351325),
///       MwStReportEntry(code: MwStCode.b, grossAmount: 44631),
///       MwStReportEntry(code: MwStCode.c, grossAmount: 10588),
///     ],
///     orderCount: 45,
///   ),
/// ).build();
/// ```
class ReportBuilder {
  ReportBuilder({required this.data});

  final ShiftReportData data;

  int get _w => data.printWidth;

  Uint8List build() {
    final b = EscPosBuilder()..initialize();

    _header(b);
    _divider(b);
    _salesSection(b);
    _divider(b);
    _paymentSection(b);
    _divider(b);
    _mwstSection(b);
    _divider(b);
    _statsSection(b);
    if (data.openingFloat != null) {
      _divider(b);
      _cashSection(b);
    }
    _divider(b);
    _closing(b);

    b.feed(4).cut();
    return b.build();
  }

  // ---------------------------------------------------------------------------
  // Bölümler
  // ---------------------------------------------------------------------------

  void _header(EscPosBuilder b) {
    // Rapor başlığı — büyük font
    b
        .alignCenter()
        .boldOn()
        .textSizeDouble()
        .textLine(data.reportTitle)
        .textSizeNormal()
        .boldOff()
        .newLine();

    b.alignLeft();
    b.twoColumnLine(
      '${data.reportTitle}-Nr:',
      data.reportNo.toString(),
      width: _w,
    );
    if (data.terminalNo != null) {
      b.twoColumnLine('Terminal:', data.terminalNo!, width: _w);
    }
    if (data.cashierName != null) {
      b.twoColumnLine('Kassier:', data.cashierName!, width: _w);
    }
    b.twoColumnLine('Datum:', _fmtDate(data.printedAt), width: _w);
    b.twoColumnLine('Zeit:', _fmtTime(data.printedAt), width: _w);
    b.newLine();
    b.twoColumnLine('Schichtbeginn:', _fmtTime(data.shiftStart), width: _w);
    if (data.shiftEnd != null) {
      b.twoColumnLine('Schichtende:', _fmtTime(data.shiftEnd!), width: _w);
    }
  }

  void _salesSection(EscPosBuilder b) {
    b.boldOn().textLine('UMSATZ').boldOff();
    b.newLine().alignLeft();

    b.twoColumnLine('Brutto-Umsatz', _chf(data.grossSales), width: _w);
    if (data.totalDiscount > 0) {
      b.twoColumnLine(
        'Rabatte',
        '-${_chf(data.totalDiscount)}',
        width: _w,
      );
    }
    b.twoColumnLine('Netto-Umsatz', _chf(data.netSales), width: _w);
    if (data.totalReturns > 0) {
      b.twoColumnLine(
        'Retouren',
        '-${_chf(data.totalReturns)}',
        width: _w,
      );
    }
    b.newLine();
    b.boldOn();
    b.twoColumnLine('Nettoumsatz gesamt', _chf(data.netRevenue), width: _w);
    b.boldOff();
  }

  void _paymentSection(EscPosBuilder b) {
    b.boldOn().textLine('ZAHLUNGEN').boldOff();
    b.newLine().alignLeft();

    int total = 0;
    for (final entry in data.paymentBreakdown.entries) {
      b.twoColumnLine(entry.key, _chf(entry.value), width: _w);
      total += entry.value;
    }
    b.textLine('-' * _w);
    b.boldOn();
    b.twoColumnLine('Total', _chf(total), width: _w);
    b.boldOff();
  }

  void _mwstSection(EscPosBuilder b) {
    if (data.mwstEntries.isEmpty) return;

    b.boldOn().textLine('MWST-ABRECHNUNG').boldOff();
    b.newLine().alignLeft();

    b.textLine(_mwstHeader());
    b.textLine('-' * _w);

    int totalNet = 0;
    int totalTax = 0;
    int totalGross = 0;

    final sorted = data.mwstEntries.toList()
      ..sort((a, b) => a.code.code.compareTo(b.code.code));

    for (final entry in sorted) {
      totalNet += entry.netAmount;
      totalTax += entry.taxAmount;
      totalGross += entry.grossAmount;
      b.textLine(_mwstRow(entry));
    }

    b.textLine('-' * _w);
    b.textLine(_mwstTotalRow(totalNet, totalTax, totalGross));
  }

  void _statsSection(EscPosBuilder b) {
    b.boldOn().textLine('STATISTIK').boldOff();
    b.newLine().alignLeft();

    b.twoColumnLine('Bons gesamt', data.orderCount.toString(), width: _w);
    b.twoColumnLine('Stornierungen', data.voidCount.toString(), width: _w);
    b.twoColumnLine('Retouren', data.returnCount.toString(), width: _w);
  }

  void _cashSection(EscPosBuilder b) {
    b.boldOn().textLine('KASSENSTAND').boldOff();
    b.newLine().alignLeft();

    if (data.openingFloat != null) {
      b.twoColumnLine(
        'Kassenanfangsstand',
        _chf(data.openingFloat!),
        width: _w,
      );
    }
    if (data.closingFloat != null) {
      b.twoColumnLine(
        'Kassenendstand',
        _chf(data.closingFloat!),
        width: _w,
      );
    }

    final diff = data.cashDifference;
    if (diff != null) {
      final sign = diff >= 0 ? '+' : '';
      b.twoColumnLine('Differenz', '$sign${_chf(diff)}', width: _w);
    }
  }

  void _closing(EscPosBuilder b) {
    b.alignCenter().boldOn();
    if (data.reportTitle.contains('Z')) {
      b.textLine('*** KASSE GESCHLOSSEN ***');
    } else {
      b.textLine('*** ZWISCHENBERICHT ***');
    }
    b.boldOff().newLine();
  }

  void _divider(EscPosBuilder b) => b.alignLeft().divider(width: _w);

  // ---------------------------------------------------------------------------
  // MwSt tablo formatlama
  // ---------------------------------------------------------------------------

  // Sütun genişlikleri (toplam ≤ printWidth):
  //   Cod(6) + Satz(5) + Netto(10) + MwSt(9) + Brutto(10) = 40  (42-char kağıt)
  static const int _cCod = 6;
  static const int _cSatz = 5;
  static const int _cNetto = 10;
  static const int _cMwst = 9;
  static const int _cBrutto = 10;

  String _mwstHeader() {
    return '${_lCol('Cod', _cCod)}'
        '${_lCol('Satz', _cSatz)}'
        '${_rCol('Netto', _cNetto)}'
        '${_rCol('MwSt', _cMwst)}'
        '${_rCol('Brutto', _cBrutto)}';
  }

  String _mwstRow(MwStReportEntry e) {
    final rateStr = '${e.code.rate.toStringAsFixed(1)}%';
    return '${_lCol(e.code.code, _cCod)}'
        '${_lCol(rateStr, _cSatz)}'
        '${_rCol(formatChfAmt(e.netAmount), _cNetto)}'
        '${_rCol(formatChfAmt(e.taxAmount), _cMwst)}'
        '${_rCol(formatChfAmt(e.grossAmount), _cBrutto)}';
  }

  String _mwstTotalRow(int net, int tax, int gross) {
    return '${_lCol('Total', _cCod)}'
        '${_lCol('', _cSatz)}'
        '${_rCol(formatChfAmt(net), _cNetto)}'
        '${_rCol(formatChfAmt(tax), _cMwst)}'
        '${_rCol(formatChfAmt(gross), _cBrutto)}';
  }

  // ---------------------------------------------------------------------------
  // Yardımcı metodlar
  // ---------------------------------------------------------------------------

  String _chf(int cents) => formatChf(cents);

  String _fmtDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}'
      '.${dt.month.toString().padLeft(2, '0')}'
      '.${dt.year}';

  String _fmtTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}'
      ':${dt.minute.toString().padLeft(2, '0')}'
      ':${dt.second.toString().padLeft(2, '0')}';

  String _lCol(String s, int width) {
    if (s.length >= width) return s.substring(0, width);
    return s.padRight(width);
  }

  String _rCol(String s, int width) {
    if (s.length >= width) return s;
    return s.padLeft(width);
  }
}
