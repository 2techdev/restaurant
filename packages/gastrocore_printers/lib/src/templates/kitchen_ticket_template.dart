/// Kitchen / bar ticket template.
///
/// Layout (80mm, 48 cols):
///
///   ================================
///   ***  TISCH 12   (2 Gäste)  ***
///   Kellner: Anna · 19:42  #R-000123
///   >> Allergie: Nüsse <<
///   ================================
///   -- VORSPEISE --
///    2   SALAT NIÇOISE         (48pt)
///        + ohne Sardellen
///   -- HAUPTGANG --
///    1   ENTRECÔTE 300G        (48pt)
///        + medium-rare
///        + Pfefferbutter
///        >> ALLERGEN: Milch <<
///
///   (cut)
library;

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

import '../models/kitchen_ticket_data.dart';
import '../models/printer_config.dart';
import 'common.dart';

class KitchenTicketTemplate {
  final PrinterConfig config;
  final CapabilityProfile profile;

  const KitchenTicketTemplate(this.config, this.profile);

  List<int> build(KitchenTicketData data) {
    final generator = Generator(paperSizeFor(config.paperWidth), profile);
    final bytes = <int>[];
    final cols = columnCountFor(config.paperWidth);

    // ── Header (tall, inverted for visibility across noisy kitchen) ────
    bytes.addAll(generator.text(
      '=' * cols,
      styles: const PosStyles(align: PosAlign.center),
    ));

    final headerMain = data.tableLabel != null
        ? '*** ${data.tableLabel} (${data.guestCount}) ***'
        : '*** TAKEAWAY #${data.ticketNumber} ***';
    bytes.addAll(generator.text(
      headerMain,
      styles: const PosStyles(
        align: PosAlign.center,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
        bold: true,
      ),
    ));

    final time =
        '${data.firedAt.hour.toString().padLeft(2, '0')}:${data.firedAt.minute.toString().padLeft(2, '0')}';
    final metaParts = <String>[
      if (data.waiterName != null) 'Kellner: ${data.waiterName}',
      time,
      '#${data.ticketNumber}',
    ];
    bytes.addAll(generator.text(
      metaParts.join(' · '),
      styles: const PosStyles(align: PosAlign.center),
    ));

    if (data.isFireDelta == false) {
      bytes.addAll(generator.text(
        '[ NEUAUSDRUCK - GESAMT ]',
        styles: const PosStyles(
          align: PosAlign.center,
          reverse: true,
          bold: true,
        ),
      ));
    }

    if (data.headerNote != null && data.headerNote!.isNotEmpty) {
      bytes.addAll(generator.text(
        '>> ${data.headerNote} <<',
        styles: const PosStyles(
          align: PosAlign.center,
          reverse: true,
          bold: true,
        ),
      ));
    }

    bytes.addAll(generator.text(
      '=' * cols,
      styles: const PosStyles(align: PosAlign.center),
    ));

    // ── Gangs ──────────────────────────────────────────────────────────
    for (var i = 0; i < data.gangs.length; i++) {
      final gang = data.gangs[i];
      if (gang.items.isEmpty) continue;

      bytes.addAll(generator.text(
        '-- ${gang.label.toUpperCase()} --',
        styles: const PosStyles(
          align: PosAlign.left,
          bold: true,
        ),
      ));

      for (final item in gang.items) {
        // Big quantity + name row — size2 ≈ 48pt on standard thermals.
        final qtyStr = item.quantity.toString().padLeft(2);
        bytes.addAll(generator.text(
          ' $qtyStr  ${item.name}',
          styles: const PosStyles(
            height: PosTextSize.size2,
            width: PosTextSize.size2,
            bold: true,
          ),
        ));

        // Modifiers — italic isn't universal in ESC/POS, use normal but
        // indented and slightly emphasised with underline.
        for (final mod in item.modifierLines) {
          bytes.addAll(generator.text(
            '     $mod',
            styles: const PosStyles(underline: true),
          ));
        }

        if (item.note != null && item.note!.isNotEmpty) {
          bytes.addAll(generator.text(
            '     // ${item.note}',
          ));
        }

        // Allergens — inverted (white-on-black) + bold. Most ESC/POS
        // printers support reverse printing. Red-ink requires a two-color
        // printer — we stay safe with reverse which all thermals handle.
        if (item.allergens.isNotEmpty) {
          bytes.addAll(generator.text(
            '     >> ALLERGEN: ${item.allergens.join(", ")} <<',
            styles: const PosStyles(
              reverse: true,
              bold: true,
            ),
          ));
        }
      }

      // Separator between courses (skip after last)
      if (i < data.gangs.length - 1) {
        bytes.addAll(generator.text('-' * cols,
            styles: const PosStyles(align: PosAlign.center)));
      }
    }

    bytes.addAll(generator.feed(3));
    bytes.addAll(generator.cut());
    return bytes;
  }
}
