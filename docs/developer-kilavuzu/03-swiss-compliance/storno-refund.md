# Storno / İade (Swiss Compliance)

İsviçre'de bir fişin iptali ("Storno") audit edilebilir olmalı: orijinal fiş numarasına referans verir, hangi personel talep etti + hangi manager onayladı bilgisi iki ayrı kimlik olarak tutulur, sebep zorunludur.

**Dizin**: `apps/pos/lib/features/payments/`

## Giriş noktaları

1. **Tam storno**: Payment dialog'da ödeme tamamlandıktan sonra "İade" butonu — tüm ticket iade edilir.
2. **Kısmi storno**: Closed ticket detayında satır seçip "Seçilenleri iade et".

Her iki yol `RefundNotifier.processRefund(...)` çağrısıyla sonlanır; domain tarafı aynıdır.

## Zorunlu alanlar

`refund_repository_impl.dart` işlemi başlatmadan (transaction'dan bile önce) kontrol eder:

```dart
if (reason.trim().isEmpty) throw const RefundReasonRequiredException();
```

Bu deliberate — UI validation yeterli değil, storno backend'de de reddedilmeli. İsviçre denetçisi audit log'dan "boş sebep ile iade var mı?" diye sorar.

## Dual-identity audit

`processRefund` imzası:

```dart
Future<RefundResult> processRefund({
  required String ticketId,
  required String tenantId,
  required String deviceId,
  required List<String> orderItemIds,    // boş = tam storno
  required String reason,
  required String refundMethodStr,
  required UserEntity approver,           // onay veren manager
  required UserEntity requester,          // talep eden kasiyer/garson
  String? notes,
})
```

Audit satırı:

- `userId` / `userName` = requester (işlemi yapan).
- `managerId` / `managerName` = approver (ek alanlar).
- `action` = `paymentRefunded` (tam) veya `itemRefunded` (kısmi).
- `newValueJson` = `{originalReceiptId, originalReceiptNumber, stornoReceiptId, stornoReceiptNumber, refundTotal, refundSubtotal, refundTax, method, notes}`.

Iki ayrı kimlik = hem manager override'ı gösterir hem de kim fiziksel olarak kasada olduğunu belgeler.

## Orijinal fiş referansı

Repository transaction içinde:

```sql
SELECT * FROM receipts
WHERE bill_id = :ticketId AND receipt_type = 'sale'
ORDER BY created_at ASC
LIMIT 1
```

Bulunan `sale` receipt'inin `receiptNumber`'ı storno payload'ına yazılır. Eğer ticket için henüz fiş basılmamışsa (edge case: ticket ödenmiş ama fiş crash ile basılamamış) → `originalReceiptNumber = null`, audit satırı yine düşer ama manager'ın bunu tespit etmesi için log'a `notes` alanında "missing original receipt" uyarısı eklenmelidir (TODO: otomatikleştir).

## Storno fişi (KOPIE/STORNO)

Tüm iadelerden sonra yeni bir `receipt` satırı yazılır:

- `receiptType = 'storno'`.
- `receiptNumber` = kendi serisinden (tenant scope'lu counter).
- `payloadJson` = `RefundRepositoryImpl.buildStornoReceiptJson(...)` saf fonksiyonu üretir.

Payload şekli:

```json
{
  "type": "storno",
  "originalReceiptNumber": "2026-0142",
  "stornoReceiptNumber": "2026-S-0007",
  "refundedAt": "2026-04-22T14:32:00+02:00",
  "requester": {"id": "...", "name": "Ali"},
  "approver": {"id": "...", "name": "Manager Zeki"},
  "reason": "Yanlış masaya gönderildi",
  "notes": null,
  "method": "cash",
  "lines": [
    {"productName": "Pizza", "quantity": 1, "subtotal": 1800, "taxAmount": 139}
  ],
  "refundTotal": 1939,
  "refundSubtotal": 1800,
  "refundTax": 139
}
```

Saf builder `buildStornoReceiptJson` DB'ye dokunmaz — JSON test edilebilir. `null notes` / `null receipt` gibi alanlar payload'dan **atlanır** (clean serialization).

## Payment referansı

Transaction içinde `payments` tablosuna **negatif tutarlı** bir satır yazılır:

- `amountCents = -refundTotalCents`
- `reference = 'STORNO-<uuid>'` — sale payment'larının `reference` alanı genelde `TICKET-...` olur, prefix'i görerek hızlıca ayırt edilir.
- `method` = iade edilen method (cash / card / twint).

## Envanter / puan etkisi

- Inventory sistemi yok (kaldırıldı), stock restore gerekmiyor.
- Loyalty puanı geri verme bu oturumda eklenmedi — TODO.

## Testler

`apps/pos/test/features/payments/refund_repository_impl_test.dart` — 12 test:

- Partial refund → doğru toplam.
- Payment satırı negatif + `STORNO-` prefix.
- Audit satırı `itemRefunded` (kısmi) veya `paymentRefunded` (tam).
- Audit manager + requester alanları dolu.
- Audit payload `originalReceiptNumber` taşır.
- Storno receipt JSON roundtrip — Swiss alanları (refundTax, refundSubtotal) korunur.
- Boş sebep → `RefundReasonRequiredException` + transaction side-effect'i yok.
- Bilinmeyen ticketId → exception.
- Pure builder `null notes`/`null receipt` payload'dan düşürür.

## Hatırlatma

- Storno fişinin basımı ayrı — repository sadece satırı DB'ye yazıyor. Yazıcı entegrasyonu `ReceiptPrintService` üzerinden tetikleniyor; hata olursa retry sırası `receipts.print_status = 'failed'` ile işaretleniyor.
- Counter collision: iki cihazda paralel storno olursa aynı numarayı üretebilir. Pilot tek cihaz; multi-device senaryoda `receipt_counters` tablosu tenant-level lock gerektirir.
- Refund method = orijinal ödeme method. Farklı method'ta iade vermek istenirse (nakit ödedi, kart iadesi) UI katmanında dönüşüm yapılmalı, domain zorlamıyor.
