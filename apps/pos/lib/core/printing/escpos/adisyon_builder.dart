import 'dart:typed_data';

import '../models/print_models.dart';
import 'esc_pos_builder.dart';

/// Adisyon (check/bill) ESC/POS builder.
///
/// Prints an interim bill for the customer WITHOUT closing the order and
/// WITHOUT any payment information. Ends with a polite payment request
/// in German and French — standard in Swiss restaurants.
///
/// Layout:
/// 1. Header   — restaurant name + address
/// 2. Meta     — date, time, table, order number
/// 3. Items    — product lines with quantity × unit price
/// 4. Totals   — subtotal (if discount), TOTAL (2× font)
/// 5. MwSt     — informational tax breakdown (optional)
/// 6. Footer   — "Bitte zahlen / L'addition s'il vous plaît"
///
/// Usage:
/// ```dart
/// final bytes = AdisyonBuilder(
///   data: AdisyonData(
///     restaurantName: 'Gastro Cafe AG',
///     tableName: 'Tisch 5',
///     orderNo: '#0042',
///     items: [...],
///     total: 4850,
///   ),
/// ).build();
/// ```
class AdisyonBuilder {
  AdisyonBuilder({required this.data});

  final AdisyonData data;

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
    if (data.mwstBreakdown.isNotEmpty) {
      _divider(b);
      _mwstInfo(b);
    }
    _divider(b);
    _footer(b);

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
        .textLine(data.restaurantName)
        .textSizeNormal()
        .boldOff();
    if (data.address != null) b.textLine(data.address!);
    b.newLine();
  }

  void _meta(EscPosBuilder b) {
    b.alignLeft();
    final dt = data.dateTime ?? DateTime.now();
    b.textLine('Datum     : ${_fmtDate(dt)}');
    b.textLine('Zeit      : ${_fmtTime(dt)}');
    if (data.tableName != null) b.textLine('Tisch     : ${data.tableName}');
    if (data.orderNo != null) b.textLine('Bon-Nr    : ${data.orderNo}');
    if (data.cashierName != null) b.textLine('Kassier   : ${data.cashierName}');
  }

  void _itemLines(EscPosBuilder b) {
    b.alignLeft();
    String? currentCourse;

    for (final item in data.items) {
      // Print a course/gang header whenever the course label changes.
      if (item.course != null && item.course != currentCourse) {
        currentCourse = item.course!;
        b.newLine();
        b.boldOn().textLine('-- $currentCourse --').boldOff();
      }

      // Item name on its own line
      b.twoColumnLine(item.name, '', width: _w);
      // Qty × unit price → line total
      final qtyStr = _fmtQty(item.quantity);
      final unitStr = '  $qtyStr ${item.unit} x ${_chf(item.unitPrice)}';
      b.twoColumnLine(unitStr, _chf(item.totalPrice), width: _w);
      // Item discount
      if (item.discountAmount > 0) {
        b.twoColumnLine('  Rabatt', '-${_chf(item.discountAmount)}', width: _w);
      }
      // Modifiers
      for (final mod in item.modifiers) {
        b.textLine('  + $mod');
      }
      // Special preparation note
      if (item.notes != null && item.notes!.isNotEmpty) {
        b.textLine('  ! ${item.notes}');
      }
    }
  }

  void _totals(EscPosBuilder b) {
    b.alignLeft();
    // Show subtotal line only when there is an order-level discount.
    if (data.subtotal != null && data.discountAmount > 0) {
      b.twoColumnLine('Subtotal', _chf(data.subtotal!), width: _w);
      b.twoColumnLine('Rabatt', '-${_chf(data.discountAmount)}', width: _w);
    }
    // TOTAL — double-size font
    b.newLine().boldOn().textSizeDouble().alignLeft();
    b.twoColumnLine('TOTAL', _chf(data.total), width: _w ~/ 2);
    b.textSizeNormal().boldOff();
  }

  /// Informational MWST breakdown: Inkl. MwSt lines.
  void _mwstInfo(EscPosBuilder b) {
    b.alignLeft().textLine('Inkl. MwSt:');
    final sorted = data.mwstBreakdown.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final e in sorted) {
      final code = MwStCode.fromCode(e.key);
      final tax = (e.value * code.rate / (100 + code.rate)).round();
      b.twoColumnLine(
        '  ${code.code} ${code.rate.toStringAsFixed(1)}% '
        'auf ${formatChfAmt(e.value)}',
        formatChfAmt(tax),
        width: _w,
      );
    }
  }

  void _footer(EscPosBuilder b) {
    b.alignCenter().newLine();
    b.boldOn();
    if (data.footerText != null) {
      b.textLine(data.footerText!);
    } else {
      b.textLine('Bitte zahlen');
      b.textLine("L'addition s'il vous plait");
    }
    b.boldOff().newLine();
  }

  void _divider(EscPosBuilder b) => b.alignLeft().divider(width: _w);

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _chf(int cents) => formatChf(cents);

  String _fmtQty(double v) {
    if (v == v.truncateToDouble()) return v.toInt().toString();
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
}
