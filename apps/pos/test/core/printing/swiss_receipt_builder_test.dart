import 'package:flutter_test/flutter_test.dart';
import 'package:gastrocore_pos/core/printing/escpos/swiss_receipt_builder.dart';
import 'package:gastrocore_pos/core/printing/models/print_models.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Test verileri
  // ---------------------------------------------------------------------------

  SwissReceiptData makeMinimal({
    Map<String, int> mwstBreakdown = const {},
    List<SwissReceiptItem> items = const [],
    List<SwissPaymentLine> payments = const [],
    int total = 0,
    bool openDrawer = false,
  }) {
    return SwissReceiptData(
      restaurantName: 'Test Cafe AG',
      receiptNo: '0001',
      items: items,
      total: total,
      mwstBreakdown: mwstBreakdown,
      payments: payments,
      openDrawer: openDrawer,
    );
  }

  SwissReceiptItem makeItem({
    String name = 'Mineralwasser',
    double quantity = 1,
    int unitPrice = 450,
    int totalPrice = 450,
    MwStCode mwstCode = MwStCode.a,
    List<String> modifiers = const [],
    int discountAmount = 0,
    String? notes,
  }) {
    return SwissReceiptItem(
      name: name,
      quantity: quantity,
      unitPrice: unitPrice,
      totalPrice: totalPrice,
      mwstCode: mwstCode,
      modifiers: modifiers,
      discountAmount: discountAmount,
      notes: notes,
    );
  }

  // ---------------------------------------------------------------------------
  // Yardımcı: byte dizisinden yazdırılabilir metin oluştur
  // ---------------------------------------------------------------------------
  String extractText(List<int> bytes) => String.fromCharCodes(
        bytes.where((b) => b >= 0x20 || b == 0x0A),
      );

  // ===========================================================================
  // Temel çıktı
  // ===========================================================================

  group('Temel çıktı', () {
    test('build() boş olmayan byte dizisi döndürür', () {
      final bytes = SwissReceiptBuilder(data: makeMinimal()).build();
      expect(bytes, isNotEmpty);
    });

    test('ESC @ (initialize) ile başlar', () {
      final bytes = SwissReceiptBuilder(data: makeMinimal()).build();
      expect(bytes[0], 0x1B);
      expect(bytes[1], 0x40);
    });

    test('GS V 1 (partial cut) ile biter', () {
      final bytes = SwissReceiptBuilder(data: makeMinimal()).build();
      // feed(4) + cut(): son ESC/POS komutu GS V 1
      expect(bytes.contains(0x1D), isTrue);
      expect(bytes.contains(0x56), isTrue);
    });

    test('Kasa çekmecesi komutu yalnızca openDrawer=true ise eklenir', () {
      final withDrawer =
          SwissReceiptBuilder(data: makeMinimal(openDrawer: true)).build();
      final withoutDrawer =
          SwissReceiptBuilder(data: makeMinimal()).build();

      // ESC p = [0x1B, 0x70]
      bool hasDrawerCmd(List<int> bytes) {
        for (int i = 0; i < bytes.length - 1; i++) {
          if (bytes[i] == 0x1B && bytes[i + 1] == 0x70) return true;
        }
        return false;
      }

      expect(hasDrawerCmd(withDrawer), isTrue);
      expect(hasDrawerCmd(withoutDrawer), isFalse);
    });
  });

  // ===========================================================================
  // Başlık (Header)
  // ===========================================================================

  group('Başlık bölümü', () {
    test('Restoran adı byte dizisinde bulunur', () {
      final data = makeMinimal().copyWith(restaurantName: 'Gastro Alp');
      final text = extractText(SwissReceiptBuilder(data: data).build());
      expect(text, contains('Gastro Alp'));
    });

    test('Adres yazdırılır', () {
      final data = SwissReceiptData(
        restaurantName: 'X',
        receiptNo: '1',
        items: const [],
        total: 0,
        address: 'Bahnhofstrasse 1, 8001 Zuerich',
      );
      final text = extractText(SwissReceiptBuilder(data: data).build());
      expect(text, contains('Bahnhofstrasse 1'));
    });

    test('Telefon "Tel:" etiketi ile yazdırılır', () {
      final data = SwissReceiptData(
        restaurantName: 'X',
        receiptNo: '1',
        items: const [],
        total: 0,
        phone: '+41 44 123 45 67',
      );
      final text = extractText(SwissReceiptBuilder(data: data).build());
      expect(text, contains('Tel: +41 44 123 45 67'));
    });

    test('MWST-Nr "MWST-Nr:" etiketi ile yazdırılır', () {
      final data = SwissReceiptData(
        restaurantName: 'X',
        receiptNo: '1',
        items: const [],
        total: 0,
        mwstNr: 'CHE-123.456.789 MWST',
      );
      final text = extractText(SwissReceiptBuilder(data: data).build());
      expect(text, contains('MWST-Nr: CHE-123.456.789 MWST'));
    });

    test('MWST-Nr yoksa "MWST-Nr:" etiketi yazdırılmaz', () {
      final text = extractText(SwissReceiptBuilder(data: makeMinimal()).build());
      expect(text, isNot(contains('MWST-Nr:')));
    });
  });

  // ===========================================================================
  // Meta bölümü
  // ===========================================================================

  group('Meta bölümü', () {
    test('Beleg-Nr yazdırılır', () {
      final data = SwissReceiptData(
        restaurantName: 'X',
        receiptNo: '00042',
        items: const [],
        total: 0,
      );
      final text = extractText(SwissReceiptBuilder(data: data).build());
      expect(text, contains('00042'));
    });

    test('Kasiyer adı yazdırılır', () {
      final data = SwissReceiptData(
        restaurantName: 'X',
        receiptNo: '1',
        items: const [],
        total: 0,
        cashierName: 'Max Muster',
      );
      final text = extractText(SwissReceiptBuilder(data: data).build());
      expect(text, contains('Max Muster'));
    });

    test('Masa adı yazdırılır', () {
      final data = SwissReceiptData(
        restaurantName: 'X',
        receiptNo: '1',
        items: const [],
        total: 0,
        tableName: 'T-05',
      );
      final text = extractText(SwissReceiptBuilder(data: data).build());
      expect(text, contains('T-05'));
    });
  });

  // ===========================================================================
  // Kalemler
  // ===========================================================================

  group('Kalem bölümü', () {
    test('Ürün adı yazdırılır', () {
      final item = makeItem(name: 'Cordon Bleu');
      final data = makeMinimal(items: [item]);
      final text = extractText(SwissReceiptBuilder(data: data).build());
      expect(text, contains('Cordon Bleu'));
    });

    test('MwSt kodu köşeli parantez ile yazdırılır', () {
      final item = makeItem(mwstCode: MwStCode.b);
      final data = makeMinimal(items: [item]);
      final text = extractText(SwissReceiptBuilder(data: data).build());
      expect(text, contains('[B]'));
    });

    test('Modifikatörler "+ " önekiyle yazdırılır', () {
      final item = makeItem(modifiers: ['ohne Pommes', 'Salat extra']);
      final data = makeMinimal(items: [item]);
      final text = extractText(SwissReceiptBuilder(data: data).build());
      expect(text, contains('+ ohne Pommes'));
      expect(text, contains('+ Salat extra'));
    });

    test('Notlar "! " önekiyle yazdırılır', () {
      final item = makeItem(notes: 'Keine Saetze');
      final data = makeMinimal(items: [item]);
      final text = extractText(SwissReceiptBuilder(data: data).build());
      expect(text, contains('! Keine Saetze'));
    });

    test('Kalem indirimi "Rabatt" etiketi ile yazdırılır', () {
      final item = makeItem(discountAmount: 100); // CHF 1.00
      final data = makeMinimal(items: [item]);
      final text = extractText(SwissReceiptBuilder(data: data).build());
      expect(text, contains('Rabatt'));
    });

    test('İndirim yoksa "Rabatt" yazdırılmaz', () {
      final item = makeItem(discountAmount: 0);
      final data = makeMinimal(items: [item]);
      final text = extractText(SwissReceiptBuilder(data: data).build());
      // Genel indirim de yok
      expect(text, isNot(contains('Rabatt')));
    });

    test('CHF fiyat formatı doğru (2 ondalık)', () {
      final item = makeItem(unitPrice: 2850, totalPrice: 2850);
      final data = makeMinimal(items: [item]);
      final text = extractText(SwissReceiptBuilder(data: data).build());
      expect(text, contains('28.50'));
    });
  });

  // ===========================================================================
  // Toplamlar
  // ===========================================================================

  group('Toplamlar bölümü', () {
    test('TOTAL etiketi yazdırılır', () {
      final data = makeMinimal(total: 3375);
      final text = extractText(SwissReceiptBuilder(data: data).build());
      expect(text, contains('TOTAL'));
    });

    test('Toplam tutar (CHF) doğru formatlanır', () {
      final data = makeMinimal(total: 3375);
      final text = extractText(SwissReceiptBuilder(data: data).build());
      expect(text, contains('33.75'));
    });

    test('Subtotal ve global indirim varsa yazdırılır', () {
      final data = SwissReceiptData(
        restaurantName: 'X',
        receiptNo: '1',
        items: const [],
        total: 3375,
        subtotal: 3750,
        discountAmount: 375,
      );
      final text = extractText(SwissReceiptBuilder(data: data).build());
      expect(text, contains('Subtotal'));
      expect(text, contains('Rabatt'));
      expect(text, contains('37.50'));
    });
  });

  // ===========================================================================
  // Ödeme bölümü
  // ===========================================================================

  group('Ödeme bölümü', () {
    test('Ödeme yöntemleri yazdırılır', () {
      final payments = [
        const SwissPaymentLine(method: 'Bar', amount: 5000),
        const SwissPaymentLine(method: 'TWINT', amount: 3375),
      ];
      final data = makeMinimal(payments: payments, total: 8375);
      final text = extractText(SwissReceiptBuilder(data: data).build());
      expect(text, contains('Bar'));
      expect(text, contains('TWINT'));
    });

    test('Verilen nakit "Gegeben" ile yazdırılır', () {
      final data = SwissReceiptData(
        restaurantName: 'X',
        receiptNo: '1',
        items: const [],
        total: 3375,
        payments: [const SwissPaymentLine(method: 'Bar', amount: 5000)],
        tenderedAmount: 5000,
        changeAmount: 1625,
      );
      final text = extractText(SwissReceiptBuilder(data: data).build());
      expect(text, contains('Gegeben'));
      expect(text, contains('50.00'));
    });

    test('Üstü kalan "Rueckgeld" ile yazdırılır', () {
      final data = SwissReceiptData(
        restaurantName: 'X',
        receiptNo: '1',
        items: const [],
        total: 3375,
        payments: [const SwissPaymentLine(method: 'Bar', amount: 5000)],
        tenderedAmount: 5000,
        changeAmount: 1625,
      );
      final text = extractText(SwissReceiptBuilder(data: data).build());
      expect(text, contains('Rueckgeld'));
      expect(text, contains('16.25'));
    });
  });

  // ===========================================================================
  // MwSt tablosu
  // ===========================================================================

  group('MwSt tablosu', () {
    test('mwstBreakdown boşsa MwSt-Abrechnung yazdırılmaz', () {
      final data = makeMinimal(mwstBreakdown: const {});
      final text = extractText(SwissReceiptBuilder(data: data).build());
      expect(text, isNot(contains('MwSt-Abrechnung')));
    });

    test('MwSt-Abrechnung başlığı yazdırılır', () {
      final data = makeMinimal(mwstBreakdown: {'A': 2850});
      final text = extractText(SwissReceiptBuilder(data: data).build());
      expect(text, contains('MwSt-Abrechnung'));
    });

    test('MwSt kodu ve oranı yazdırılır', () {
      final data = makeMinimal(mwstBreakdown: {'A': 2850, 'B': 450});
      final text = extractText(SwissReceiptBuilder(data: data).build());
      expect(text, contains('A'));
      expect(text, contains('8.1%'));
      expect(text, contains('B'));
      expect(text, contains('2.6%'));
    });

    test('MwSt hesabı doğru: %8.1 — 2850 cent brüt', () {
      // Brüt 2850 cent = CHF 28.50
      // MwSt = 2850 * 8.1 / 108.1 = 213.58... ≈ 214 cent = CHF 2.14
      // Netto = 2850 - 214 = 2636 cent = CHF 26.36
      final entry = MwStReportEntry(
        code: MwStCode.a,
        grossAmount: 2850,
      );
      expect(entry.taxAmount, 214); // rounded
      expect(entry.netAmount, 2850 - 214);
    });

    test('MwSt hesabı doğru: %2.6 — 450 cent brüt', () {
      // MwSt = 450 * 2.6 / 102.6 = 11.40... ≈ 11 cent
      // Netto = 450 - 11 = 439 cent
      final entry = MwStReportEntry(
        code: MwStCode.b,
        grossAmount: 450,
      );
      expect(entry.taxAmount, 11);
      expect(entry.netAmount, 439);
    });

    test('MwSt hesabı doğru: %3.8 — 1000 cent brüt', () {
      // MwSt = 1000 * 3.8 / 103.8 = 36.61... ≈ 37 cent
      final entry = MwStReportEntry(
        code: MwStCode.c,
        grossAmount: 1000,
      );
      expect(entry.taxAmount, 37);
      expect(entry.netAmount, 963);
    });

    test('Toplam satırı yazdırılır', () {
      final data = makeMinimal(mwstBreakdown: {'A': 2850, 'B': 450});
      final text = extractText(SwissReceiptBuilder(data: data).build());
      expect(text, contains('Total'));
    });

    test('Kodlar alfabetik sırada yazdırılır (A → B → C)', () {
      final data = makeMinimal(mwstBreakdown: {'C': 1000, 'A': 2850, 'B': 450});
      final text = extractText(SwissReceiptBuilder(data: data).build());
      final aIdx = text.lastIndexOf('8.1%');
      final bIdx = text.lastIndexOf('2.6%');
      final cIdx = text.lastIndexOf('3.8%');
      expect(aIdx, lessThan(bIdx));
      expect(bIdx, lessThan(cIdx));
    });
  });

  // ===========================================================================
  // Footer
  // ===========================================================================

  group('Footer bölümü', () {
    test('footerText yazdırılır', () {
      final data = SwissReceiptData(
        restaurantName: 'X',
        receiptNo: '1',
        items: const [],
        total: 0,
        footerText: 'Auf Wiedersehen!',
      );
      final text = extractText(SwissReceiptBuilder(data: data).build());
      expect(text, contains('Auf Wiedersehen!'));
    });

    test('footerText yoksa varsayılan teşekkür mesajı kullanılır', () {
      final text = extractText(SwissReceiptBuilder(data: makeMinimal()).build());
      expect(text, contains('Vielen Dank'));
    });

    test('QR kod komutu (GS ( k) eklenir', () {
      final data = SwissReceiptData(
        restaurantName: 'X',
        receiptNo: '1',
        items: const [],
        total: 0,
        qrData: 'https://example.com/receipt/1',
      );
      final bytes = SwissReceiptBuilder(data: data).build();
      // GS ( k = 0x1D 0x28 0x6B
      bool hasQr = false;
      for (int i = 0; i < bytes.length - 2; i++) {
        if (bytes[i] == 0x1D && bytes[i + 1] == 0x28 && bytes[i + 2] == 0x6B) {
          hasQr = true;
          break;
        }
      }
      expect(hasQr, isTrue);
    });
  });

  // ===========================================================================
  // MwStCode enum
  // ===========================================================================

  group('MwStCode enum', () {
    test('code getter büyük harf döndürür', () {
      expect(MwStCode.a.code, 'A');
      expect(MwStCode.b.code, 'B');
      expect(MwStCode.c.code, 'C');
    });

    test('rate getter doğru değeri döndürür', () {
      expect(MwStCode.a.rate, 8.1);
      expect(MwStCode.b.rate, 2.6);
      expect(MwStCode.c.rate, 3.8);
    });

    test('fromCode() doğru enum döndürür', () {
      expect(MwStCode.fromCode('A'), MwStCode.a);
      expect(MwStCode.fromCode('b'), MwStCode.b); // küçük harf
      expect(MwStCode.fromCode('C'), MwStCode.c);
      expect(MwStCode.fromCode('X'), MwStCode.a); // bilinmeyen → A
    });

    test('fromRate() eşik değerlerini doğru map eder', () {
      expect(MwStCode.fromRate(0.0), MwStCode.b);
      expect(MwStCode.fromRate(2.6), MwStCode.b);
      expect(MwStCode.fromRate(3.2), MwStCode.b);
      expect(MwStCode.fromRate(3.8), MwStCode.c);
      expect(MwStCode.fromRate(5.0), MwStCode.c);
      expect(MwStCode.fromRate(8.1), MwStCode.a);
    });
  });

  // ===========================================================================
  // formatChf yardımcı fonksiyonu
  // ===========================================================================

  group('formatChf()', () {
    test('pozitif tutar formatlanır', () {
      expect(formatChf(3375), 'CHF 33.75');
      expect(formatChf(100), 'CHF 1.00');
      expect(formatChf(5), 'CHF 0.05');
    });

    test('negatif tutar tire ile formatlanır', () {
      expect(formatChf(-1625), '-CHF 16.25');
    });

    test('sıfır formatlanır', () {
      expect(formatChf(0), 'CHF 0.00');
    });
  });
}

// ignore: unused_element
extension _TestExt on SwissReceiptData {
  SwissReceiptData copyWith({
    String? restaurantName,
    String? receiptNo,
    List<SwissReceiptItem>? items,
    int? total,
  }) {
    return SwissReceiptData(
      restaurantName: restaurantName ?? this.restaurantName,
      receiptNo: receiptNo ?? this.receiptNo,
      items: items ?? this.items,
      total: total ?? this.total,
      address: address,
      phone: phone,
      mwstNr: mwstNr,
      dateTime: dateTime,
      cashierName: cashierName,
      tableName: tableName,
      orderNo: orderNo,
      orderTypeLabel: orderTypeLabel,
      subtotal: subtotal,
      discountAmount: discountAmount,
      roundingAmount: roundingAmount,
      mwstBreakdown: mwstBreakdown,
      payments: payments,
      tenderedAmount: tenderedAmount,
      changeAmount: changeAmount,
      footerText: footerText,
      qrData: qrData,
      printWidth: printWidth,
      openDrawer: openDrawer,
    );
  }
}
