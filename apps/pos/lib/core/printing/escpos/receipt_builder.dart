import 'dart:typed_data';

import 'esc_pos_builder.dart';

/// Fiş satırı modeli.
class ReceiptLineItem {
  const ReceiptLineItem({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    this.totalPrice,
  });

  final String name;
  final double quantity;
  final double unitPrice;

  /// [totalPrice] verilmezse quantity × unitPrice hesaplanır.
  final double? totalPrice;

  double get total => totalPrice ?? quantity * unitPrice;
}

/// Ödeme satırı modeli.
class ReceiptPaymentLine {
  const ReceiptPaymentLine({required this.method, required this.amount});

  final String method;
  final double amount;
}

/// Satış fişi oluşturucu.
///
/// Kullanımı:
/// ```dart
/// final bytes = ReceiptBuilder(
///   restaurantName: 'Gastro Cafe',
///   receiptNo: '00042',
///   items: [...],
///   total: 145.50,
/// ).build();
/// ```
class ReceiptBuilder {
  ReceiptBuilder({
    required this.restaurantName,
    required this.receiptNo,
    required this.items,
    required this.total,
    this.address,
    this.phone,
    this.taxId,
    this.cashierName,
    this.tableName,
    this.payments = const [],
    this.subtotal,
    this.taxAmount,
    this.discountAmount,
    this.footerText,
    this.qrData,
    this.printWidth = 42,
    this.openDrawer = false,
  });

  final String restaurantName;
  final String? address;
  final String? phone;
  final String? taxId;

  final String receiptNo;
  final String? cashierName;
  final String? tableName;

  final List<ReceiptLineItem> items;
  final List<ReceiptPaymentLine> payments;

  final double total;
  final double? subtotal;
  final double? taxAmount;
  final double? discountAmount;

  final String? footerText;
  final String? qrData;

  /// Fiş kağıt genişliği (karakter cinsinden). 80 mm → 42, 58 mm → 32.
  final int printWidth;

  /// Fişten sonra kasa çekmecesini aç.
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
    if (payments.isNotEmpty) {
      _divider(b);
      _paymentLines(b);
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
    if (taxId != null) b.textLine('VKN: $taxId');
    b.newLine();
  }

  void _meta(EscPosBuilder b) {
    b.alignLeft();
    b.textLine('Fis No : $receiptNo');
    b.textLine('Tarih  : ${_now()}');
    if (cashierName != null) b.textLine('Kasiyer: $cashierName');
    if (tableName != null) b.textLine('Masa   : $tableName');
  }

  void _itemLines(EscPosBuilder b) {
    b.alignLeft();
    for (final item in items) {
      final qty = _fmtQty(item.quantity);
      final price = _fmtMoney(item.unitPrice);
      final lineTotal = _fmtMoney(item.total);

      // Ürün adı
      b.textLine(item.name);
      // Miktar × Birim Fiyat          Tutar
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
      b.twoColumnLine('Ara Toplam', _fmtMoney(subtotal!), width: printWidth);
    }
    if (discountAmount != null && discountAmount! > 0) {
      b.twoColumnLine(
        'Indirim',
        '-${_fmtMoney(discountAmount!)}',
        width: printWidth,
      );
    }
    if (taxAmount != null) {
      b.twoColumnLine('KDV', _fmtMoney(taxAmount!), width: printWidth);
    }

    // Genel toplam — büyük yazı
    b.newLine().boldOn().textSizeDouble().alignLeft();
    b.twoColumnLine('TOPLAM', _fmtMoney(total), width: printWidth ~/ 2);
    b.textSizeNormal().boldOff();
  }

  void _paymentLines(EscPosBuilder b) {
    b.alignLeft();
    for (final p in payments) {
      b.twoColumnLine(p.method, _fmtMoney(p.amount), width: printWidth);
    }
  }

  void _footer(EscPosBuilder b) {
    b.alignCenter();

    if (qrData != null) {
      b.newLine().qrCode(qrData!).newLine();
    }

    final text = footerText ?? 'Tesekkur ederiz!';
    b.textLine(text);
    b.newLine();
  }

  void _divider(EscPosBuilder b) =>
      b.alignLeft().divider(width: printWidth, char: '-');

  // ---------------------------------------------------------------------------
  // Formatting helpers
  // ---------------------------------------------------------------------------

  String _fmtMoney(double v) => '${v.toStringAsFixed(2)} TL';

  String _fmtQty(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  String _now() {
    final t = DateTime.now();
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${pad(t.day)}.${pad(t.month)}.${t.year} '
        '${pad(t.hour)}:${pad(t.minute)}';
  }
}
