import 'package:flutter_test/flutter_test.dart';
import 'package:gastrocore_pos/core/printing/escpos/kitchen_ticket_builder.dart';
import 'package:gastrocore_pos/core/printing/models/print_models.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Test verileri
  // ---------------------------------------------------------------------------

  KitchenTicketData _data({
    String tableNo = '5',
    String orderNo = '0042',
    String? waiterName,
    String? courseLabel,
    String? printerGroup,
    String? notes,
    List<KitchenItem> items = const [],
    DateTime? dateTime,
  }) {
    return KitchenTicketData(
      tableNo: tableNo,
      orderNo: orderNo,
      waiterName: waiterName,
      courseLabel: courseLabel,
      printerGroup: printerGroup,
      notes: notes,
      items: items,
      dateTime: dateTime ?? DateTime(2026, 3, 20, 14, 35, 22),
    );
  }

  KitchenItem _item({
    String name = 'Cordon Bleu',
    double quantity = 1,
    List<String> modifiers = const [],
    String? notes,
    bool isVoid = false,
  }) {
    return KitchenItem(
      name: name,
      quantity: quantity,
      modifiers: modifiers,
      notes: notes,
      isVoid: isVoid,
    );
  }

  String _text(List<int> bytes) => String.fromCharCodes(
        bytes.where((b) => b >= 0x20 || b == 0x0A),
      );

  // ===========================================================================
  // Temel çıktı
  // ===========================================================================

  group('Temel çıktı', () {
    test('build() boş olmayan byte dizisi döndürür', () {
      final bytes = KitchenTicketBuilder(data: _data()).build();
      expect(bytes, isNotEmpty);
    });

    test('ESC @ (initialize) ile başlar', () {
      final bytes = KitchenTicketBuilder(data: _data()).build();
      expect(bytes[0], 0x1B);
      expect(bytes[1], 0x40);
    });

    test('GS V 0 (tam kesim) kullanılır', () {
      final bytes = KitchenTicketBuilder(data: _data()).build();
      // GS V 0 = [0x1D, 0x56, 0x00]
      bool hasFullCut = false;
      for (int i = 0; i < bytes.length - 2; i++) {
        if (bytes[i] == 0x1D && bytes[i + 1] == 0x56 && bytes[i + 2] == 0x00) {
          hasFullCut = true;
          break;
        }
      }
      expect(hasFullCut, isTrue);
    });
  });

  // ===========================================================================
  // Başlık bölümü
  // ===========================================================================

  group('Başlık bölümü', () {
    test('Masa numarası yazdırılır', () {
      final text = _text(KitchenTicketBuilder(data: _data(tableNo: '12')).build());
      expect(text, contains('12'));
    });

    test('Bon numarası yazdırılır', () {
      final text =
          _text(KitchenTicketBuilder(data: _data(orderNo: '0099')).build());
      expect(text, contains('0099'));
    });

    test('Yazıcı grubu büyük harfle yazdırılır', () {
      final text = _text(
        KitchenTicketBuilder(data: _data(printerGroup: 'Kueche')).build(),
      );
      expect(text, contains('KUECHE'));
    });

    test('Yazıcı grubu yoksa grup adı yazdırılmaz', () {
      final text = _text(KitchenTicketBuilder(data: _data()).build());
      // Yazıcı grubu başlığı formatı "=== GRUPADI ===" şeklindedir.
      // printerGroup null olduğunda bu format yazdırılmaz.
      expect(text, isNot(matches(RegExp(r'===\s+\w+\s+==='))));
    });

    test('Garson adı yazdırılır', () {
      final text = _text(
        KitchenTicketBuilder(data: _data(waiterName: 'Anna')).build(),
      );
      expect(text, contains('Anna'));
    });

    test('Garson adı yoksa "Kellner:" etiketi yazdırılmaz', () {
      final text = _text(KitchenTicketBuilder(data: _data()).build());
      expect(text, isNot(contains('Kellner:')));
    });

    test('Zaman damgası HH:MM:SS formatında yazdırılır', () {
      final dt = DateTime(2026, 3, 20, 9, 5, 7);
      final text = _text(KitchenTicketBuilder(data: _data(dateTime: dt)).build());
      expect(text, contains('09:05:07'));
    });
  });

  // ===========================================================================
  // Ürün bölümü
  // ===========================================================================

  group('Ürün bölümü', () {
    test('Ürün adı yazdırılır', () {
      final text = _text(
        KitchenTicketBuilder(
          data: _data(items: [_item(name: 'Wiener Schnitzel')]),
        ).build(),
      );
      expect(text, contains('Wiener Schnitzel'));
    });

    test('Adet bilgisi "Nx" formatında yazdırılır', () {
      final text = _text(
        KitchenTicketBuilder(
          data: _data(items: [_item(name: 'Pizza', quantity: 3)]),
        ).build(),
      );
      expect(text, contains('3x'));
    });

    test('Kesirli adet doğru formatlanır', () {
      final text = _text(
        KitchenTicketBuilder(
          data: _data(items: [_item(name: 'Steak', quantity: 0.5)]),
        ).build(),
      );
      expect(text, contains('0.5'));
    });

    test('Modifikatörler ">> " önekiyle yazdırılır', () {
      final text = _text(
        KitchenTicketBuilder(
          data: _data(
            items: [
              _item(modifiers: ['ohne Pommes', 'Salat extra']),
            ],
          ),
        ).build(),
      );
      expect(text, contains('>> ohne Pommes'));
      expect(text, contains('>> Salat extra'));
    });

    test('Not "! " önekiyle yazdırılır', () {
      final text = _text(
        KitchenTicketBuilder(
          data: _data(items: [_item(notes: 'Sehr scharf bitte')]),
        ).build(),
      );
      expect(text, contains('! Sehr scharf bitte'));
    });

    test('Birden fazla kalem yazdırılır', () {
      final text = _text(
        KitchenTicketBuilder(
          data: _data(
            items: [
              _item(name: 'Suppe'),
              _item(name: 'Steak'),
              _item(name: 'Dessert'),
            ],
          ),
        ).build(),
      );
      expect(text, contains('Suppe'));
      expect(text, contains('Steak'));
      expect(text, contains('Dessert'));
    });
  });

  // ===========================================================================
  // İptal (STORNO)
  // ===========================================================================

  group('İptal (STORNO)', () {
    test('isVoid=true kalemde STORNO yazdırılır', () {
      final text = _text(
        KitchenTicketBuilder(
          data: _data(items: [_item(isVoid: true)]),
        ).build(),
      );
      expect(text, contains('STORNO'));
    });

    test('Normal kalemlerde STORNO yazdırılmaz', () {
      final text = _text(
        KitchenTicketBuilder(
          data: _data(items: [_item()]),
        ).build(),
      );
      expect(text, isNot(contains('STORNO')));
    });

    test('STORNO kalemi adı hâlâ yazdırılır', () {
      final text = _text(
        KitchenTicketBuilder(
          data: _data(items: [_item(name: 'Gulasch', isVoid: true)]),
        ).build(),
      );
      expect(text, contains('Gulasch'));
    });
  });

  // ===========================================================================
  // Kurs etiketi
  // ===========================================================================

  group('Kurs etiketi', () {
    test('courseLabel yazdırılır', () {
      final text = _text(
        KitchenTicketBuilder(
          data: _data(courseLabel: 'Gang 1 - Vorspeise'),
        ).build(),
      );
      expect(text, contains('Gang 1 - Vorspeise'));
    });

    test('courseLabel yoksa yazdırılmaz', () {
      // Herhangi bir "Gang" metni içermemeli
      final text = _text(KitchenTicketBuilder(data: _data()).build());
      expect(text, isNot(contains('Gang')));
    });
  });

  // ===========================================================================
  // Genel sipariş notu
  // ===========================================================================

  group('Genel sipariş notu', () {
    test('Sipariş notu "NOT:" etiketi ile yazdırılır', () {
      final text = _text(
        KitchenTicketBuilder(
          data: _data(notes: 'Allergiker am Tisch!'),
        ).build(),
      );
      expect(text, contains('NOT:'));
      expect(text, contains('Allergiker am Tisch!'));
    });

    test('Not yoksa "NOT:" etiketi yazdırılmaz', () {
      final text = _text(KitchenTicketBuilder(data: _data()).build());
      expect(text, isNot(contains('NOT:')));
    });
  });
}
