/// Customer-facing receipt (fiş) template.
///
/// Layout (80mm, 48 cols):
///
///   [logo]
///   STORE NAME (center, h2)
///   address line
///   phone · MWST CHE-xxx
///   --------------------------------
///   Beleg:  R-2026-000123     Tisch 12
///   Datum:  2026-04-17 19:42  Gäste: 2
///   Kellner: Anna
///   --------------------------------
///   2x  Entrecôte              54.00
///        + Pfefferbutter (+2.00)
///   1x  Rotwein 2cl             9.50
///   --------------------------------
///   Zwischensumme              63.50
///   Service 10%                 6.35
///   --------------------------------
///   MWST 8.1% (Netto 58.19)     5.01
///   --------------------------------
///   TOTAL CHF                  69.85
///
///   Bar                        70.00
///   Rückgeld                    0.15
///
///   Danke für Ihren Besuch!
///   MWST-Nr: CHE-123.456.789
///   [QR code]
library;

import 'dart:typed_data';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image/image.dart' as img;

import '../models/printer_config.dart';
import '../models/receipt_data.dart';
import 'common.dart';

class ReceiptTemplate {
  final PrinterConfig config;
  final CapabilityProfile profile;

  const ReceiptTemplate(this.config, this.profile);

  /// Build the ESC/POS byte stream for [data].
  List<int> build(ReceiptData data) {
    final generator = Generator(paperSizeFor(config.paperWidth), profile);
    final bytes = <int>[];
    final cols = columnCountFor(config.paperWidth);

    // ── Logo ───────────────────────────────────────────────────────────
    final logoPng = data.logoPng ?? config.logoPng;
    if (logoPng != null && logoPng.isNotEmpty) {
      final decoded = img.decodeImage(Uint8List.fromList(logoPng));
      if (decoded != null) {
        final resized = img.copyResize(decoded,
            width: cols == 48 ? 384 : 320, interpolation: img.Interpolation.linear);
        bytes.addAll(generator.image(resized, align: PosAlign.center));
      }
    }

    // ── Header ─────────────────────────────────────────────────────────
    bytes.addAll(generator.text(
      data.storeName,
      styles: const PosStyles(
        align: PosAlign.center,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
        bold: true,
      ),
    ));
    if (data.storeAddress.isNotEmpty) {
      bytes.addAll(generator.text(data.storeAddress,
          styles: const PosStyles(align: PosAlign.center)));
    }
    final subHeader = [
      if (data.storePhone.isNotEmpty) 'Tel: ${data.storePhone}',
      if (data.vatNumber != null) 'MWST ${data.vatNumber}',
    ].join(' · ');
    if (subHeader.isNotEmpty) {
      bytes.addAll(generator.text(subHeader,
          styles: const PosStyles(align: PosAlign.center)));
    }
    bytes.addAll(generator.hr());

    // ── Ticket meta ────────────────────────────────────────────────────
    final date =
        '${data.issuedAt.year.toString().padLeft(4, '0')}-${data.issuedAt.month.toString().padLeft(2, '0')}-${data.issuedAt.day.toString().padLeft(2, '0')} '
        '${data.issuedAt.hour.toString().padLeft(2, '0')}:${data.issuedAt.minute.toString().padLeft(2, '0')}';
    bytes.addAll(generator.text(
      twoColumnRow('Beleg: ${data.ticketNumber}',
          data.tableLabel ?? 'Takeaway', cols),
    ));
    bytes.addAll(generator.text(
      twoColumnRow('Datum: $date', 'Gäste: ${data.guestCount}', cols),
    ));
    if (data.waiterName != null) {
      bytes.addAll(generator.text('Kellner: ${data.waiterName}'));
    }
    if (data.cashierName != null) {
      bytes.addAll(generator.text('Kasse: ${data.cashierName}'));
    }
    bytes.addAll(generator.hr());

    // ── Line items ─────────────────────────────────────────────────────
    for (final item in data.items) {
      final qty = formatQuantity(item.quantity);
      final left = '${qty}x  ${item.name}';
      final right = formatMoney(item.lineTotalCents);
      bytes.addAll(generator.text(twoColumnRow(left, right, cols)));

      for (final mod in item.modifierLines) {
        bytes.addAll(generator.text('     $mod',
            styles: const PosStyles(bold: false)));
      }
      if (item.note != null && item.note!.isNotEmpty) {
        bytes.addAll(generator.text('     // ${item.note}'));
      }
    }
    bytes.addAll(generator.hr());

    // ── Totals block ───────────────────────────────────────────────────
    bytes.addAll(generator.text(
        twoColumnRow('Zwischensumme', formatMoney(data.subtotalCents), cols)));

    if (data.discountCents != 0) {
      bytes.addAll(generator.text(
          twoColumnRow('Rabatt', '-${formatMoney(data.discountCents)}', cols)));
    }
    if (data.serviceChargeCents != 0) {
      bytes.addAll(generator.text(twoColumnRow(
          'Service', formatMoney(data.serviceChargeCents), cols)));
    }
    bytes.addAll(generator.hr());

    // ── MWST breakdown (Swiss 8.1% dine-in / 2.6% takeaway) ────────────
    for (final tax in data.taxLines) {
      bytes.addAll(generator.text(twoColumnRow(
        '${tax.label} (Netto ${formatMoney(tax.netCents)})',
        formatMoney(tax.taxCents),
        cols,
      )));
    }
    if (data.taxLines.isNotEmpty) {
      bytes.addAll(generator.hr());
    }

    // ── Grand total (big, bold) ────────────────────────────────────────
    bytes.addAll(generator.text(
      twoColumnRow('TOTAL CHF', formatMoney(data.grandTotalCents), cols ~/ 2),
      styles: const PosStyles(
        height: PosTextSize.size2,
        width: PosTextSize.size2,
        bold: true,
      ),
    ));
    bytes.addAll(generator.feed(1));

    // ── Payments ───────────────────────────────────────────────────────
    for (final pay in data.payments) {
      bytes.addAll(generator.text(
          twoColumnRow(_paymentLabel(pay.method), formatMoney(pay.amountCents), cols)));
      if (pay.changeCents > 0) {
        bytes.addAll(generator.text(
            twoColumnRow('Rückgeld', formatMoney(pay.changeCents), cols)));
      }
    }
    bytes.addAll(generator.feed(1));

    // ── Footer ─────────────────────────────────────────────────────────
    if (data.thankYouMessage != null) {
      bytes.addAll(generator.text(data.thankYouMessage!,
          styles: const PosStyles(align: PosAlign.center, bold: true)));
    }
    if (data.vatNumber != null) {
      bytes.addAll(generator.text('MWST-Nr: ${data.vatNumber}',
          styles: const PosStyles(align: PosAlign.center)));
    }

    if (data.qrPayload != null && data.qrPayload!.isNotEmpty) {
      bytes.addAll(generator.feed(1));
      bytes.addAll(generator.qrcode(
        data.qrPayload!,
        size: QRSize.size6,
        align: PosAlign.center,
      ));
    }

    bytes.addAll(generator.feed(2));
    bytes.addAll(generator.cut());
    return bytes;
  }

  String _paymentLabel(String method) {
    switch (method) {
      case 'cash':
        return 'Bar';
      case 'card':
        return 'Karte';
      case 'twint':
        return 'TWINT';
      case 'voucher':
        return 'Gutschein';
      default:
        return method;
    }
  }
}
