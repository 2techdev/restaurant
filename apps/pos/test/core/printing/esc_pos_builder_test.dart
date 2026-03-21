import 'package:flutter_test/flutter_test.dart';
import 'package:gastrocore_pos/core/printing/escpos/esc_pos_builder.dart';

void main() {
  group('EscPosBuilder', () {
    late EscPosBuilder builder;

    setUp(() => builder = EscPosBuilder());

    // -------------------------------------------------------------------------
    // initialize
    // -------------------------------------------------------------------------

    test('initialize emits ESC @', () {
      final bytes = builder.initialize().build();
      expect(bytes[0], 0x1B);
      expect(bytes[1], 0x40);
    });

    // -------------------------------------------------------------------------
    // Alignment
    // -------------------------------------------------------------------------

    test('alignLeft emits ESC a 0', () {
      final bytes = builder.alignLeft().build();
      expect(bytes, containsAllInOrder([0x1B, 0x61, 0x00]));
    });

    test('alignCenter emits ESC a 1', () {
      final bytes = builder.alignCenter().build();
      expect(bytes, containsAllInOrder([0x1B, 0x61, 0x01]));
    });

    test('alignRight emits ESC a 2', () {
      final bytes = builder.alignRight().build();
      expect(bytes, containsAllInOrder([0x1B, 0x61, 0x02]));
    });

    // -------------------------------------------------------------------------
    // Bold
    // -------------------------------------------------------------------------

    test('boldOn emits ESC E 1', () {
      final bytes = builder.boldOn().build();
      expect(bytes, containsAllInOrder([0x1B, 0x45, 0x01]));
    });

    test('boldOff emits ESC E 0', () {
      final bytes = builder.boldOff().build();
      expect(bytes, containsAllInOrder([0x1B, 0x45, 0x00]));
    });

    // -------------------------------------------------------------------------
    // Text size
    // -------------------------------------------------------------------------

    test('textSizeDouble emits GS ! with correct byte', () {
      // width=2, height=2 → n = (1<<4)|1 = 0x11
      final bytes = builder.textSizeDouble().build();
      expect(bytes, containsAllInOrder([0x1D, 0x21, 0x11]));
    });

    test('textSizeNormal emits GS ! 0x00', () {
      final bytes = builder.textSizeNormal().build();
      expect(bytes, containsAllInOrder([0x1D, 0x21, 0x00]));
    });

    // -------------------------------------------------------------------------
    // Text encoding
    // -------------------------------------------------------------------------

    test('text encodes ASCII correctly', () {
      final bytes = builder.text('ABC').build();
      // A=65, B=66, C=67
      expect(bytes, containsAllInOrder([65, 66, 67]));
    });

    test('text converts Turkish chars to ASCII equivalents', () {
      final bytes = builder.text('şğıüöç').build();
      // s g i u o c
      expect(bytes, containsAllInOrder([115, 103, 105, 117, 111, 99]));
    });

    test('text replaces non-Latin1 chars with ?', () {
      final bytes = builder.text('€').build(); // € = U+20AC (> 255)
      expect(bytes.contains(0x3F), isTrue);
    });

    test('textLine appends LF after text', () {
      final bytes = builder.textLine('Hi').build();
      expect(bytes.last, 0x0A); // LF
    });

    // -------------------------------------------------------------------------
    // Feed & Cut
    // -------------------------------------------------------------------------

    test('newLine emits LF', () {
      final bytes = builder.newLine().build();
      expect(bytes, equals([0x0A]));
    });

    test('feed emits ESC d n', () {
      final bytes = builder.feed(5).build();
      expect(bytes, containsAllInOrder([0x1B, 0x64, 5]));
    });

    test('cut emits GS V 1', () {
      final bytes = builder.cut().build();
      expect(bytes, containsAllInOrder([0x1D, 0x56, 0x01]));
    });

    test('fullCut emits GS V 0', () {
      final bytes = builder.fullCut().build();
      expect(bytes, containsAllInOrder([0x1D, 0x56, 0x00]));
    });

    // -------------------------------------------------------------------------
    // Cash drawer
    // -------------------------------------------------------------------------

    test('openCashDrawer emits Pin-2 and Pin-5 pulses', () {
      final bytes = builder.openCashDrawer().build();
      // Pin 2: 1B 70 00 19 FA
      expect(bytes, containsAllInOrder([0x1B, 0x70, 0x00, 0x19, 0xFA]));
      // Pin 5: 1B 70 01 19 FA
      expect(bytes, containsAllInOrder([0x1B, 0x70, 0x01, 0x19, 0xFA]));
    });

    // -------------------------------------------------------------------------
    // Two-column line
    // -------------------------------------------------------------------------

    test('twoColumnLine pads to correct width', () {
      // width=10, left="AB", right="CD" → "AB    CD" (6 spaces) + LF
      final bytes = builder.twoColumnLine('AB', 'CD', width: 10).build();
      final line = String.fromCharCodes(bytes.sublist(0, bytes.length - 1));
      expect(line.length, 10);
      expect(line, startsWith('AB'));
      expect(line, endsWith('CD'));
    });

    // -------------------------------------------------------------------------
    // Chaining
    // -------------------------------------------------------------------------

    test('chaining produces bytes in correct order', () {
      final bytes = EscPosBuilder()
          .initialize()
          .alignCenter()
          .boldOn()
          .textLine('TEST')
          .boldOff()
          .feed(3)
          .cut()
          .build();

      // initialize — ESC @
      expect(bytes[0], 0x1B);
      expect(bytes[1], 0x40);
      // Sonunda GS V 1 (cut)
      expect(bytes[bytes.length - 1], 0x01);
      expect(bytes[bytes.length - 2], 0x56);
      expect(bytes[bytes.length - 3], 0x1D);
    });

    // -------------------------------------------------------------------------
    // reset
    // -------------------------------------------------------------------------

    test('reset clears buffer', () {
      builder.initialize().text('X');
      builder.reset();
      final bytes = builder.build();
      expect(bytes, isEmpty);
    });

    // -------------------------------------------------------------------------
    // QR code
    // -------------------------------------------------------------------------

    test('qrCode output starts with GS ( k', () {
      final bytes = builder.qrCode('https://example.com').build();
      expect(bytes[0], 0x1D);
      expect(bytes[1], 0x28);
      expect(bytes[2], 0x6B);
    });
  });
}
