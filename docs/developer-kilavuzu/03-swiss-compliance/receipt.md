# Makbuz (Receipt)

Ödeme tamamlandığında üretilen kağıt fiş veya PDF. Swiss restoranda müşteriye vermek zorunluluk, denetim için kayıt tutulması zorunluluk.

**Dosya**: [apps/pos/lib/features/orders/presentation/screens/receipt_preview_screen.dart](../../apps/pos/lib/features/orders/presentation/screens/receipt_preview_screen.dart)

DB tablosu: `Receipts`.

## Swiss Zorunlu Alanlar

İsviçre'de bir fişte bulunmak zorunda:

1. **Restoran unvanı + adresi** (UID - firma kimlik numarası dahil)
2. **Tarih + saat** (UTC+1 lokal saat)
3. **Ticket/makbuz numarası** (sıralı, tekil)
4. **Item listesi** (isim, quantity, fiyat)
5. **Alt toplam (subtotal)**
6. **KDV dökümü** (her oran ayrı satır, örn "MWST 8.1%: 3.42 CHF")
7. **Yuvarlama (varsa)** (örn "Rappen-Rundung: -0.02 CHF")
8. **Toplam**
9. **Ödeme yöntemi** (Cash / Card / TWINT)
10. **Nakit alındı / para üstü** (nakitse)

Opsiyonel ama yaygın:
- Cashier adı/PIN
- Table / guest count
- Happy hour notu
- Loyalty puan bakiyesi
- QR-Bill (sonraki sayfada)
- "Vielen Dank für Ihren Besuch!" mesajı

## Receipt Template Örneği

```
═══════════════════════════════════════
     RESTAURANT GASTROCORE
     Bahnhofstrasse 10
     8001 Zürich
     UID: CHE-123.456.789
═══════════════════════════════════════
Bon Nr: 230-00042
Datum: 20.04.2026  18:37
Tisch: 5  Gäste: 4
Kassierer: Max

───────────────────────────────────────
2x Pizza Margherita      @14.50   29.00
1x Bier Gross            @ 6.00    6.00
1x Kaffee                @ 4.00    4.00
───────────────────────────────────────
Zwischensumme                     39.00
MWST 8.1% (inkl.)                  2.92
───────────────────────────────────────
TOTAL                    CHF     39.00

Zahlung: TWINT
Transaktion: TRX-abc-123

───────────────────────────────────────
       Vielen Dank fur Ihren
        Besuch!

      [QR-Bill zweite Seite]
═══════════════════════════════════════
```

## PDF Üretimi

`pdf: ^3.10.8` paketi ile:

```dart
final pdf = pw.Document();
pdf.addPage(pw.Page(
  pageFormat: PdfPageFormat.roll80,     // 80mm termal yazıcı rulo
  build: (ctx) => pw.Column(
    children: [
      pw.Text(restaurant.name, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
      pw.Text(restaurant.address),
      pw.Divider(),
      for (final item in ticket.items) _itemRow(item),
      pw.Divider(),
      _subtotalRow(ticket.subtotalCents),
      _taxBreakdown(ticket.taxBreakdown),
      _grandTotalRow(ticket.grandTotalCents),
      pw.SizedBox(height: 20),
      pw.Text('Zahlung: ${payment.method}'),
    ],
  ),
));
final bytes = await pdf.save();
```

## Yazdırma

`printing: ^5.13.2` paketi:
```dart
await Printing.layoutPdf(onLayout: (format) async => bytes);
```

İki mod:
- **Direct print** - Bluetooth thermal yazıcıya direk (Star Micronics, Epson TM-T88 vb).
- **System dialog** - kullanıcı yazıcı seçer (test / dev).

Yazıcı eşlemesi `features/settings/` + Bluetooth permission (`permission_handler`).

## Paylaşım (Email / WhatsApp)

```dart
await Share.shareFiles(
  [receiptPdfPath],
  text: 'Ihre Rechnung von ${restaurant.name}',
);
```

`share_plus: ^10.0.0` üzerinden Android/iOS share sheet açılır.

## Receipts Tablosu

```dart
class Receipts extends Table {
  TextColumn  get id => text()();
  TextColumn  get ticketId => text().references(Tickets, #id)();
  TextColumn  get receiptNumber => text()();        // 230-00042
  TextColumn  get pdfBlob => text()();              // base64 veya file path
  IntColumn   get totalCents => integer()();
  TextColumn  get paymentMethod => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}
```

## Tekrar Yazdırma

Müşteri fişini kaybederse:
1. Order history ekranından ticket bulunur.
2. "Receipt" butonu -> `receipt_preview_screen.dart` eski PDF'i render eder.
3. Yeniden yazdır / paylaş.

Re-print yaptığında audit log: `receipt_reprint`.

## Void/Refund Makbuzu

Refund başarılıysa yeni bir fiş (kırmızı "STORNO" watermark ile) basılır:
```
═══════════════════════════════════════
         *** STORNO ***
═══════════════════════════════════════
Bon Nr: 230-00042
Refund: TRX-xyz-789
...
-2x Pizza Margherita     @14.50  -29.00
...
TOTAL RÜCKERSTATTUNG:    CHF    -29.00
```

## E-Receipt (Digital)

Müşteri mail veya telefon verirse digital makbuz:
```dart
final receiptUrl = 'https://your-server.com/receipt/${receipt.id}?token=...';
await mail.send(to: customer.email, body: receiptUrl);
```

Müşteri tarayıcıda açar, hash-based access token ile 30 gün geçerli.

## Audit Log

Her receipt print'te:
```dart
auditLog.insert(
  action: 'receipt_printed',
  details: {
    'receipt_id': receipt.id,
    'ticket_id': ticket.id,
    'payment_id': payment.id,
  },
);
```

Denetim sırasında "bu fiş basıldı mı?" sorusuna cevap olur.

## Kayıt Süresi

İsviçre ticari defterler yasası (OR Art. 957): **10 yıl** saklama zorunluluğu.

POS cihazda her fiş `Receipts` tablosunda. Cloud sync üzerinden merchant'ın arşivine de kopyalanır. 10 yıl retention merkezi olarak cloud'da uygulanır.

## Test

- Cash ödemede Rappen rounding satırı basılır mı?
- Card ödemede rounding satırı **basılmaz**.
- Multi-tax ticket (food + alcohol karışık) -> iki ayrı MWST satırı.
- QR-Bill istendiğinde ikinci sayfa eklenir mi?
- 80mm roll genişliğinde satırlar taşmıyor mu?
