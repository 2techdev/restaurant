# Receipt Reprint ve KOPIE Banner

Fişin ikinci (ve sonraki) baskıları Swiss compliance için açıkça "KOPIE" olarak işaretlenir ve audit'e düşer.

**Dizin**: `apps/pos/lib/features/orders/` + `apps/pos/lib/core/services/`

## Neden

İsviçre'de orijinal fişle kopyası görsel olarak ayırt edilebilir olmalı. İki baskı arasındaki fark görsel bir banner'dan ibaret değil — audit log'da "reprint" olayı ayrı bir satır olmalı ki denetçi "kaç kez basıldı?" sorusuna cevap bulabilsin.

## Akış

`ReceiptPrintService.printReceipt(receipt, {isReprint})`:

- `isReprint = false` (ilk baskı) → payload'a `KOPIE` banner eklenmez, audit satırı `receiptPrinted`.
- `isReprint = true` → header'a `**KOPIE / COPY / COPIE**` banner'ı eklenir, audit satırı `receiptReprinted`.

Reprint tetikleme yolları:

1. Closed ticket detayında "Tekrar Yazdır" butonu.
2. Payment ekranında "Fiş Tekrar Yazdır".
3. Printer failure retry — `print_status = 'failed'` olan receipt'leri tekrar yazdır.

Otomatik retry `isReprint = false` olarak devam eder (ilk baskı başarısızdı, kopya sayılmaz). Kullanıcı manuel tıkladığında `isReprint = true`.

## Audit

`AuditAction` enum'una eklendi:

```dart
receiptReprinted('Receipt Reprinted'),
```

`AuditLogScreen` ikonu: `(AppColors.orange, Icons.print_rounded)` — normal print'ten renkle ayrılır.

Audit satırı payload'ı:

```json
{
  "receiptId": "...",
  "receiptNumber": "2026-0142",
  "reprintCount": 2,
  "reason": "customer request"
}
```

`reprintCount` sayacı `receipts.reprint_count` kolonundan gelir, her manuel reprint'te +1.

## KOPIE banner formatı

Fiş payload'ı ESC/POS thermal printer uyumlu. Banner:

```
================================
         K O P I E
       COPY / COPIE
================================
```

Üç dilli — Swiss multi-lingual bölgeleri için (DE/FR/IT). Genişlik 32 karakter (80mm thermal).

## Test

`apps/pos/test/features/orders/receipt_reprint_test.dart`:

- İlk print → audit `receiptPrinted`, payload banner yok.
- İkinci print `isReprint=true` → audit `receiptReprinted`, payload `KOPIE` içeriyor.
- `reprint_count` kolonu her reprint'te artıyor.
- Failure retry ilk sefer için banner eklemez.

## Hatırlatma

- Banner'ı sadece görsel için değil, **iz için** de eklenmiş sayın. Printer banner'ı yazdırmasa bile audit satırı kanıt olarak kalır.
- Email / PDF ihracı farklı kod yolu — aynı flag'i `email_receipt_service` paralelde takip etmeli (TODO: email service'in PDF başlığına KOPIE eklenmeli).
