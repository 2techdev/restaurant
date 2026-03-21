import 'dart:typed_data';

import '../models/print_models.dart';
import 'esc_pos_builder.dart';

/// İsviçre standardında satış fişi (Verkaufsbeleg) oluşturucu.
///
/// CHF para birimi, MwSt oranları (A=%8.1, B=%2.6, C=%3.8) ve MWST-Nr
/// desteğiyle İsviçre pazarına özel ESC/POS byte dizisi üretir.
///
/// Kullanım:
/// ```dart
/// final bytes = SwissReceiptBuilder(
///   data: SwissReceiptData(
///     restaurantName: 'Gastro Cafe AG',
///     mwstNr: 'CHE-123.456.789 MWST',
///     receiptNo: '00042',
///     items: [
///       SwissReceiptItem(
///         name: 'Cordon Bleu',
///         quantity: 1,
///         unitPrice: 2850,    // CHF 28.50 in cents
///         totalPrice: 2850,
///         mwstCode: MwStCode.a,
///       ),
///     ],
///     total: 2850,
///     mwstBreakdown: {'A': 2850},
///   ),
/// ).build();
/// ```
///
/// Fiş yapısı:
/// 1. Başlık (restoran adı, adres, telefon, MWST-Nr)
/// 2. Meta (beleg-nr, tarih, saat, kasiyer, masa)
/// 3. Kalemler (ürün, adet×fiyat, modifier, not)
/// 4. Toplamlar (subtotal, indirim, TOTAL büyük font)
/// 5. Ödeme (Bar/Karte/TWINT, verilen, üstü)
/// 6. MwSt tablosu (Cod | Satz | Netto | MwSt | Brutto)
/// 7. Footer (QR kod, teşekkür mesajı)
class SwissReceiptBuilder {
  SwissReceiptBuilder({required this.data});

  final SwissReceiptData data;

  int get _w => data.printWidth;

  Uint8List build() {
    final b = EscPosBuilder()..initialize();

    _header(b);
    _divider(b);
    _meta(b);
    _divider(b);
    _itemLines(b);
    _divider(b);
    _totals(b);
    _divider(b);
    _paymentSection(b);
    if (data.mwstBreakdown.isNotEmpty) {
      _divider(b);
      _mwstBreakdown(b);
    }
    _divider(b);
    _footer(b);

    if (data.openDrawer) b.openCashDrawer();
    b.feed(4).cut();
    return b.build();
  }

  // ---------------------------------------------------------------------------
  // Bölümler
  // ---------------------------------------------------------------------------

  void _header(EscPosBuilder b) {
    b
        .alignCenter()
        .boldOn()
        .textSizeDouble()
        .textLine(data.restaurantName)
        .textSizeNormal()
        .boldOff();

    if (data.address != null) b.textLine(data.address!);
    if (data.phone != null) b.textLine('Tel: ${data.phone}');
    if (data.mwstNr != null) {
      b.newLine();
      b.textLine('MWST-Nr: ${data.mwstNr}');
    }
    b.newLine();
  }

  void _meta(EscPosBuilder b) {
    b.alignLeft();
    b.textLine('Beleg-Nr  : ${data.receiptNo}');

    final dt = data.dateTime ?? DateTime.now();
    b.textLine('Datum     : ${_fmtDate(dt)}');
    b.textLine('Zeit      : ${_fmtTime(dt)}');
    if (data.cashierName != null) b.textLine('Kassier   : ${data.cashierName}');
    if (data.tableName != null) b.textLine('Tisch     : ${data.tableName}');
    if (data.orderNo != null) b.textLine('Bon-Nr    : ${data.orderNo}');
    // Service type: critical for MWST rate traceability on the receipt
    if (data.orderTypeLabel != null) {
      b.textLine('Bestellart: ${data.orderTypeLabel}');
    }
  }

  void _itemLines(EscPosBuilder b) {
    b.alignLeft();
    for (final item in data.items) {
      // Ürün adı + MwSt kodu (sağda köşeli parantez içinde)
      b.twoColumnLine(item.name, '[${item.mwstCode.code}]', width: _w);

      // Adet × birim fiyat → satır toplamı
      final qtyStr = _fmtQty(item.quantity);
      final unitStr = '  $qtyStr ${item.unit} x ${_chf(item.unitPrice)}';
      b.twoColumnLine(unitStr, _chf(item.totalPrice), width: _w);

      // Kalem indirimi
      if (item.discountAmount > 0) {
        b.twoColumnLine(
          '  Rabatt',
          '-${_chf(item.discountAmount)}',
          width: _w,
        );
      }

      // Modifikatörler
      for (final mod in item.modifiers) {
        b.textLine('  + $mod');
      }

      // Not
      if (item.notes != null && item.notes!.isNotEmpty) {
        b.textLine('  ! ${item.notes}');
      }
    }
  }

  void _totals(EscPosBuilder b) {
    b.alignLeft();

    // Subtotal ve indirim satırları (yalnızca ikisi de mevcutsa)
    if (data.subtotal != null) {
      b.twoColumnLine('Subtotal', _chf(data.subtotal!), width: _w);
    }
    if (data.discountAmount > 0) {
      b.twoColumnLine(
        'Rabatt',
        '-${_chf(data.discountAmount)}',
        width: _w,
      );
    }

    // TOTAL — 2× büyük font
    b.newLine().boldOn().textSizeDouble().alignLeft();
    b.twoColumnLine('TOTAL', _chf(data.total), width: _w ~/ 2);
    b.textSizeNormal().boldOff();
  }

  void _paymentSection(EscPosBuilder b) {
    b.alignLeft();
    for (final p in data.payments) {
      b.twoColumnLine(p.method, _chf(p.amount), width: _w);
    }
    // 5-Rappen rounding line (cash payments only; 0 = not shown)
    if (data.roundingAmount != 0) {
      final sign = data.roundingAmount > 0 ? '+' : '';
      b.twoColumnLine(
        'Rundung',
        '$sign${_chf(data.roundingAmount)}',
        width: _w,
      );
    }
    if (data.tenderedAmount > 0) {
      b.twoColumnLine('Gegeben', _chf(data.tenderedAmount), width: _w);
    }
    if (data.changeAmount > 0) {
      b.twoColumnLine('Rueckgeld', _chf(data.changeAmount), width: _w);
    }
  }

  /// MwSt tablosu: Cod | Satz | Netto | MwSt | Brutto
  ///
  /// Vergi hesabı: MwSt = Brutto × rate / (100 + rate)
  /// Netto = Brutto − MwSt
  void _mwstBreakdown(EscPosBuilder b) {
    b.alignLeft();
    b.textLine('MwSt-Abrechnung:');
    b.textLine(_mwstHeader());
    b.textLine('-' * _w);

    int totalNet = 0;
    int totalTax = 0;
    int totalGross = 0;

    // Kodları sıralı yazdır (A → B → C)
    final sorted = data.mwstBreakdown.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    for (final entry in sorted) {
      final reportEntry = MwStReportEntry(
        code: MwStCode.fromCode(entry.key),
        grossAmount: entry.value,
      );
      totalNet += reportEntry.netAmount;
      totalTax += reportEntry.taxAmount;
      totalGross += reportEntry.grossAmount;
      b.textLine(_mwstRow(reportEntry));
    }

    b.textLine('-' * _w);
    b.textLine(_mwstTotalRow(totalNet, totalTax, totalGross));
  }

  void _footer(EscPosBuilder b) {
    b.alignCenter();
    if (data.qrData != null) {
      b.newLine().qrCode(data.qrData!).newLine();
    }
    b.textLine(data.footerText ?? 'Vielen Dank fuer Ihren Besuch!');
    b.newLine();
  }

  void _divider(EscPosBuilder b) => b.alignLeft().divider(width: _w);

  // ---------------------------------------------------------------------------
  // MwSt tablo formatlama
  // ---------------------------------------------------------------------------

  // Sütun genişlikleri (toplam ≤ printWidth):
  //   Cod(6) + Satz(6) + Netto(9) + MwSt(9) + Brutto(10) = 40  (42-char kağıt)
  static const int _cCod = 6;
  static const int _cSatz = 6;
  static const int _cNetto = 9;
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

  String _fmtQty(double v) {
    if (v == v.truncateToDouble()) return v.toInt().toString();
    // Gereksiz sıfırları temizle: 2.500 → '2.5'
    return v.toStringAsFixed(3).replaceAll(RegExp(r'0+$'), '');
  }

  String _fmtDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}'
      '.${dt.month.toString().padLeft(2, '0')}'
      '.${dt.year}';

  String _fmtTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}'
      ':${dt.minute.toString().padLeft(2, '0')}'
      ':${dt.second.toString().padLeft(2, '0')}';

  /// Sola hizalı sütun (tam [width] karakter).
  String _lCol(String s, int width) {
    if (s.length >= width) return s.substring(0, width);
    return s.padRight(width);
  }

  /// Sağa hizalı sütun (tam [width] karakter).
  String _rCol(String s, int width) {
    if (s.length >= width) return s;
    return s.padLeft(width);
  }
}
