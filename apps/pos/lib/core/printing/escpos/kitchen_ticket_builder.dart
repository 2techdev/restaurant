import 'dart:typed_data';

import '../models/print_models.dart';
import 'esc_pos_builder.dart';

/// Mutfak adisyonu (Bestellbon / Kitchen Order Ticket) oluşturucu.
///
/// Büyük font ürün adları, vurgulu modifikatörler ve kategori bölümleri
/// içerir. Garson adı, masa no ve zaman damgasıyla birlikte yazdırılır.
///
/// Kullanım:
/// ```dart
/// final bytes = KitchenTicketBuilder(
///   data: KitchenTicketData(
///     tableNo: '5',
///     orderNo: '0042',
///     printerGroup: 'Kueche',
///     waiterName: 'Max',
///     dateTime: DateTime.now(),
///     items: [
///       KitchenItem(
///         name: 'Cordon Bleu',
///         quantity: 2,
///         modifiers: ['ohne Pommes', 'Salat extra'],
///       ),
///     ],
///   ),
/// ).build();
/// ```
///
/// Adisyon yapısı:
/// 1. Başlık (yazıcı grubu, masa/bon, garson, saat)
/// 2. Ürünler (büyük font ad, >> modifier, ! not)
/// 3. Kurs etiketi (Gang 1, vb.)
class KitchenTicketBuilder {
  KitchenTicketBuilder({required this.data});

  final KitchenTicketData data;

  int get _w => data.printWidth;

  Uint8List build() {
    final b = EscPosBuilder()..initialize();

    _header(b);
    _divider(b);
    _items(b);
    _divider(b);
    _courseLabel(b);

    // Mutfak yazıcılarında tam kesim tercih edilir
    b.feed(4).fullCut();
    return b.build();
  }

  // ---------------------------------------------------------------------------
  // Bölümler
  // ---------------------------------------------------------------------------

  void _header(EscPosBuilder b) {
    // Yazıcı grubu başlığı: === KUECHE ===
    if (data.printerGroup != null) {
      b
          .alignCenter()
          .boldOn()
          .textSizeDouble()
          .textLine('=== ${data.printerGroup!.toUpperCase()} ===')
          .textSizeNormal()
          .boldOff();
    }

    // Masa + Bon numarası — tek satırda, kalın
    b.alignLeft().boldOn();
    b.twoColumnLine(
      'Tisch: ${data.tableNo}',
      'Bon: ${data.orderNo}',
      width: _w,
    );
    b.boldOff();

    if (data.waiterName != null) {
      b.textLine('Kellner: ${data.waiterName}');
    }

    b.textLine(_fmtDateTime(data.dateTime));
  }

  void _items(EscPosBuilder b) {
    b.alignLeft();

    for (final item in data.items) {
      if (item.isVoid) {
        _voidItem(b, item);
        continue;
      }

      // Ürün adı — 2× büyük font
      b.boldOn().textSizeDouble();
      b.textLine('${_fmtQty(item.quantity)}x ${item.name}');
      b.textSizeNormal().boldOff();

      // Modifikatörler — kalın, >> vurgusu
      for (final mod in item.modifiers) {
        b.boldOn().textLine('  >> $mod').boldOff();
      }

      // Not
      if (item.notes != null && item.notes!.isNotEmpty) {
        b.textLine('  ! ${item.notes}');
      }

      b.newLine();
    }

    // Genel sipariş notu
    if (data.notes != null && data.notes!.isNotEmpty) {
      b.divider(width: _w, char: '*');
      b.boldOn().textLine('NOT: ${data.notes}').boldOff();
    }
  }

  void _voidItem(EscPosBuilder b, KitchenItem item) {
    b.boldOn().textLine('*** STORNO ***').boldOff();
    b.textLine('${_fmtQty(item.quantity)}x ${item.name}');
    for (final mod in item.modifiers) {
      b.textLine('  $mod');
    }
    b.newLine();
  }

  void _courseLabel(EscPosBuilder b) {
    if (data.courseLabel != null) {
      b.alignCenter().textLine(data.courseLabel!);
    }
  }

  void _divider(EscPosBuilder b) =>
      b.alignLeft().divider(width: _w, char: '=');

  // ---------------------------------------------------------------------------
  // Yardımcı metodlar
  // ---------------------------------------------------------------------------

  String _fmtQty(double v) {
    if (v == v.truncateToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(3).replaceAll(RegExp(r'0+$'), '');
  }

  String _fmtDateTime(DateTime dt) {
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${pad(dt.hour)}:${pad(dt.minute)}:${pad(dt.second)}'
        '  ${pad(dt.day)}.${pad(dt.month)}.${dt.year}';
  }
}
