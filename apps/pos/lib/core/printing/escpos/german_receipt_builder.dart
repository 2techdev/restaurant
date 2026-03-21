/// KassenSichV-compliant German receipt builder.
///
/// Extends the standard ESC/POS receipt with the mandatory TSE signature
/// block required by §6 KassenSichV:
///   • Transaktion-Nummer  (Transaction number)
///   • Signatur-Zähler     (Signature counter)
///   • Anfangs-Zeit        (Start time)
///   • End-Zeit            (End time)
///   • Signatur            (Base64 signature, truncated for readability)
///   • Seriennummer        (TSE serial number)
///   • Algorithmus         (Signature algorithm)
///   • QR code             (machine-readable signature for audit)
///
/// German receipts use EUR and MwSt terminology.
library;

import 'dart:typed_data';

import 'esc_pos_builder.dart';
import 'package:gastrocore_pos/features/fiscal_de/fiskaly_models.dart';

/// A line item on a German receipt.
class GermanReceiptItem {
  const GermanReceiptItem({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.vatRate,
    this.totalPrice,
  });

  final String name;
  final double quantity;
  final double unitPrice;

  /// VAT rate as a label, e.g. 'A' (19%) or 'B' (7%).
  final String vatRate;
  final double? totalPrice;

  double get total => totalPrice ?? quantity * unitPrice;
}

/// Payment line for German receipts.
class GermanReceiptPaymentLine {
  const GermanReceiptPaymentLine({
    required this.method,
    required this.amount,
  });

  final String method;
  final double amount;
}

/// VAT summary line (Mwst-Ausweis).
class GermanVatSummaryLine {
  const GermanVatSummaryLine({
    required this.label,
    required this.rate,
    required this.net,
    required this.vat,
    required this.gross,
  });

  /// Tax group label, e.g. 'A' (19%) or 'B' (7%).
  final String label;

  /// Rate as percentage.
  final double rate;
  final double net;
  final double vat;
  final double gross;
}

// ---------------------------------------------------------------------------
// GermanReceiptBuilder
// ---------------------------------------------------------------------------

/// Builds a KassenSichV-compliant German receipt as ESC/POS byte stream.
///
/// Usage:
/// ```dart
/// final bytes = GermanReceiptBuilder(
///   restaurantName: 'Gasthaus zum Adler',
///   receiptNo: '00042',
///   items: [...],
///   vatSummary: [...],
///   total: 23.80,
///   signature: tseSignatureData,
/// ).build();
/// ```
class GermanReceiptBuilder {
  GermanReceiptBuilder({
    required this.restaurantName,
    required this.receiptNo,
    required this.items,
    required this.vatSummary,
    required this.total,
    this.address,
    this.phone,
    this.taxNumber,
    this.ustIdNr,
    this.cashierName,
    this.tableName,
    this.payments = const [],
    this.subtotal,
    this.discountAmount,
    this.signature,
    this.footerText,
    this.printWidth = 42,
    this.openDrawer = false,
  });

  final String restaurantName;
  final String? address;
  final String? phone;

  /// Steuernummer (DE tax number, format: 123/456/78901).
  final String? taxNumber;

  /// Umsatzsteuer-Identifikationsnummer (e.g. DE123456789).
  final String? ustIdNr;

  final String receiptNo;
  final String? cashierName;
  final String? tableName;

  final List<GermanReceiptItem> items;
  final List<GermanVatSummaryLine> vatSummary;
  final List<GermanReceiptPaymentLine> payments;

  final double total;
  final double? subtotal;
  final double? discountAmount;

  /// TSE signature data — must be printed when country = DE (§6 KassenSichV).
  final TseSignatureData? signature;

  final String? footerText;
  final int printWidth;
  final bool openDrawer;

  Uint8List build() {
    final b = EscPosBuilder();
    b.initialize();

    _header(b);
    _divider(b);
    _meta(b);
    _divider(b);
    _itemLines(b);
    _divider(b);
    _totals(b);
    _divider(b);
    _vatSummaryBlock(b);
    if (payments.isNotEmpty) {
      _divider(b);
      _paymentLines(b);
    }
    if (signature != null) {
      _divider(b);
      _tseBlock(b, signature!);
    }
    _divider(b);
    _footer(b);

    if (openDrawer) b.openCashDrawer();
    b.feed(4).cut();
    return b.build();
  }

  // ---------------------------------------------------------------------------
  // Sections
  // ---------------------------------------------------------------------------

  void _header(EscPosBuilder b) {
    b
        .alignCenter()
        .boldOn()
        .textSizeDouble()
        .textLine(restaurantName)
        .textSizeNormal()
        .boldOff();

    if (address != null) b.textLine(address!);
    if (phone != null) b.textLine('Tel: $phone');
    if (taxNumber != null) b.textLine('Steuernummer: $taxNumber');
    if (ustIdNr != null) b.textLine('USt-IdNr.: $ustIdNr');
    b.newLine();
  }

  void _meta(EscPosBuilder b) {
    b.alignLeft();
    b.textLine('Beleg-Nr. : $receiptNo');
    b.textLine('Datum     : ${_fmtDateTime(DateTime.now())}');
    if (cashierName != null) b.textLine('Bediener  : $cashierName');
    if (tableName != null) b.textLine('Tisch     : $tableName');
  }

  void _itemLines(EscPosBuilder b) {
    b.alignLeft();
    for (final item in items) {
      final qty = _fmtQty(item.quantity);
      final price = _fmtMoney(item.unitPrice);
      final lineTotal = _fmtMoney(item.total);
      b.textLine('${item.name} [${item.vatRate}]');
      b.twoColumnLine(
        '  $qty x $price',
        lineTotal,
        width: printWidth,
      );
    }
  }

  void _totals(EscPosBuilder b) {
    b.alignLeft();
    if (subtotal != null) {
      b.twoColumnLine('Zwischensumme', _fmtMoney(subtotal!),
          width: printWidth);
    }
    if (discountAmount != null && discountAmount! > 0) {
      b.twoColumnLine(
        'Rabatt',
        '-${_fmtMoney(discountAmount!)}',
        width: printWidth,
      );
    }
    b.newLine().boldOn().textSizeDouble().alignLeft();
    b.twoColumnLine('GESAMT', _fmtMoney(total),
        width: printWidth ~/ 2);
    b.textSizeNormal().boldOff();
  }

  void _vatSummaryBlock(EscPosBuilder b) {
    b.alignLeft();
    b.textLine('MwSt-Ausweis:');
    b.textLine(
        '${'Satz'.padRight(4)} ${'Netto'.padLeft(8)} ${'MwSt'.padLeft(8)} ${'Brutto'.padLeft(8)}');
    for (final v in vatSummary) {
      final label = '${v.label} ${v.rate.toStringAsFixed(0)}%';
      b.textLine(
          '${label.padRight(6)}'
          '${_fmtMoney(v.net).padLeft(8)}'
          '${_fmtMoney(v.vat).padLeft(8)}'
          '${_fmtMoney(v.gross).padLeft(8)}');
    }
  }

  void _paymentLines(EscPosBuilder b) {
    b.alignLeft();
    for (final p in payments) {
      b.twoColumnLine(p.method, _fmtMoney(p.amount),
          width: printWidth);
    }
  }

  /// Mandatory TSE signature block (§6 KassenSichV).
  void _tseBlock(EscPosBuilder b, TseSignatureData sig) {
    b.alignLeft();
    b.textLine('--- TSE-Signatur (KassenSichV) ---');
    b.textLine('Transaktion-Nr.: ${sig.transactionNumber}');
    b.textLine('Signatur-Zaehler: ${sig.signatureCounter}');
    b.textLine('Anfangs-Zeit: ${_fmtDateTime(sig.startTime)}');
    b.textLine('End-Zeit    : ${_fmtDateTime(sig.endTime)}');
    b.textLine('Seriennummer:');
    b.textLine(_wrap(sig.tseSerialNumber, printWidth));
    b.textLine('Algorithmus : ${sig.algorithm}');
    b.textLine('Kassenbeleg : ${sig.processType}');
    b.textLine('Signatur:');
    // Print up to 80 chars of the Base64 signature for space.
    final sigDisplay = sig.signatureValue.length > 80
        ? '${sig.signatureValue.substring(0, 80)}...'
        : sig.signatureValue;
    b.textLine(_wrap(sigDisplay, printWidth));

    // QR code encodes the complete signature for machine verification.
    if (sig.signatureValue.isNotEmpty) {
      final qrPayload =
          'V0;${sig.tseSerialNumber};${sig.processType};'
          '${sig.startTime.millisecondsSinceEpoch};'
          '${sig.endTime.millisecondsSinceEpoch};'
          '${sig.signatureCounter};${sig.signatureValue}';
      b.newLine().alignCenter().qrCode(qrPayload).newLine();
    }
  }

  void _footer(EscPosBuilder b) {
    b.alignCenter();
    final text = footerText ?? 'Vielen Dank fuer Ihren Besuch!';
    b.textLine(text);
    b.newLine();
  }

  void _divider(EscPosBuilder b) =>
      b.alignLeft().divider(width: printWidth, char: '-');

  // ---------------------------------------------------------------------------
  // Formatting helpers
  // ---------------------------------------------------------------------------

  String _fmtMoney(double v) => '${v.toStringAsFixed(2)} EUR';

  String _fmtQty(double v) =>
      v == v.truncateToDouble()
          ? v.toInt().toString()
          : v.toStringAsFixed(2);

  String _fmtDateTime(DateTime dt) {
    final l = dt.toLocal();
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${pad(l.day)}.${pad(l.month)}.${l.year} '
        '${pad(l.hour)}:${pad(l.minute)}:${pad(l.second)}';
  }

  /// Wraps a long string at [width] characters.
  String _wrap(String s, int width) {
    if (s.length <= width) return s;
    final sb = StringBuffer();
    for (var i = 0; i < s.length; i += width) {
      final end = (i + width).clamp(0, s.length);
      sb.writeln(s.substring(i, end));
    }
    return sb.toString().trimRight();
  }
}
