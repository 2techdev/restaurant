/// Shared formatting helpers used by both receipt and kitchen templates.
library;

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

import '../models/printer_target.dart';

/// Convert our enum to the esc_pos_utils_plus paper constant.
PaperSize paperSizeFor(PrinterPaperWidth width) {
  switch (width) {
    case PrinterPaperWidth.mm58:
      return PaperSize.mm58;
    case PrinterPaperWidth.mm80:
      return PaperSize.mm80;
  }
}

/// Format an integer cents amount as CHF-style "12.50". No currency symbol —
/// templates add "CHF" explicitly where needed.
String formatMoney(int cents) {
  final sign = cents < 0 ? '-' : '';
  final abs = cents.abs();
  final whole = abs ~/ 100;
  final frac = (abs % 100).toString().padLeft(2, '0');
  return '$sign$whole.$frac';
}

/// Format a line-item quantity. Integers strip the ".00", decimals keep two
/// digits (for weight-based items like "0.45 kg").
String formatQuantity(double qty) {
  if (qty == qty.truncate()) return qty.truncate().toString();
  return qty.toStringAsFixed(2);
}

/// 80mm thermal printers at default font A have 48 columns; 58mm have 32.
int columnCountFor(PrinterPaperWidth width) =>
    width == PrinterPaperWidth.mm80 ? 48 : 32;

/// Format a two-column row (label left, value right) padded to [width] cols.
/// Used for subtotals, tax lines, payment lines on the receipt.
String twoColumnRow(String left, String right, int width) {
  if (left.length + right.length + 1 >= width) {
    // truncate left to fit
    final maxLeft = width - right.length - 1;
    final truncated = maxLeft > 0 ? left.substring(0, maxLeft) : '';
    return '$truncated $right';
  }
  final pad = width - left.length - right.length;
  return '$left${' ' * pad}$right';
}
