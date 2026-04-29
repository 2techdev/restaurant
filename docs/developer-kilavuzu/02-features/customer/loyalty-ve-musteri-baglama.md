# Loyalty ve Müşteri Bağlama

Ticket'a müşteri bağlama, topbar chip, puan görünümü ve ödeme sırasında puan kullanımı.

**Dizin**: `apps/pos/lib/features/customers/` + `apps/pos/lib/features/payments/`

## Veri tarafı

Migration **v16** ile `tickets.customer_id` kolonu (nullable FK → `customers.id`).

```sql
ALTER TABLE tickets ADD COLUMN customer_id TEXT REFERENCES customers(id);
```

Backfill: tüm mevcut ticket'larda `NULL`. Downgrade: kolon drop, veri kaybı yok (customer-bağı sadece UI şortcut).

`CustomerEntity` zaten mevcut (ad, telefon, e-posta, puan, doğum tarihi). Puan alanı (`loyaltyPoints`) integer; bu oturumda repository üzerine redeem API'si eklendi.

## Customer chip (topbar)

`apps/pos/lib/features/orders/presentation/widgets/customer_chip.dart`:

- Aktif ticket'ın `customer_id` null ise "Müşteri Ekle" chip'i.
- Doluysa müşteri adı + puan rozeti.
- Tap → `CustomerLinkDialog` açılır:
  - Arama alanı (ad / telefon).
  - Sonuç listesi — satır tap edilince ticket'a bağlanır.
  - "Yeni Müşteri" butonu → yeni kayıt formu.
  - Chip üzerinde "x" → unlink.

Unlink konfirmasyon dialog'u yok; audit satırı yeterli ("customer removed from ticket X").

## Loyalty redeem akışı

`features/payments/presentation/dialogs/loyalty_redeem_sheet.dart`:

1. Payment dialog açıldığında müşteri bağlı + puan > 0 ise "Puan Kullan" butonu görünür.
2. Bottom sheet: kullanıcı sliderla puan seçer (0..min(customer.points, maxRedeemable)).
3. Redemption oranı: `settings.loyaltyPointValue` — her puan kaç rappen?
4. Onay → payment dialog `discountCents` olarak uygular.

Redemption ticket kapandığında kesinleşir:

- `CustomerRepository.applyRedemption(customerId, pointsUsed)` atomik decrement (negatif puan önlenir).
- `AuditService.logLoyaltyRedemption(...)` satır yazar: customerId, pointsBefore, pointsUsed, ticketId.

İptal edilen ticket → redemption `CustomerRepository.refundRedemption()` ile geri alınır (aynı transaction içinde).

## Puan kazanımı

Ticket kapanışında `payment_repository_impl.dart` içinde:

```dart
if (ticket.customerId != null && payment.isSettled) {
  final points = (ticket.total / pointValueCents).floor();
  await customerRepo.addPoints(ticket.customerId!, points, ticketId: ticket.id);
}
```

Kural: her tam rappen birimi 1 puan değil; `settings.loyaltyPointValue` üzerinden hesaplanır. Pilot için default 100 rappen = 1 puan.

## Audit aksiyonları

- `customerLinkedToTicket` / `customerUnlinkedFromTicket`
- `loyaltyPointsRedeemed`
- `loyaltyPointsEarned`

Hepsi `AuditLogScreen` içinde müşteri ikonuyla render edilir.

## Hatırlatma

- Puan gerçek zamanlı güncellenmez (ticket kapanana kadar müşteri kaydında düşmez). Aynı müşteri birden fazla aktif ticket'a bağlıysa ikinci ticket'ta "eski" puanı görebilirsiniz. Beklenen — ticket kapanışında senkronize olur.
- Transfer/split ticket'ta customer linki korunur (split edilen her ticket kopyalanır).
- Refund (storno) → puan geri verme **henüz yok**. Eklendiğinde `refund_repository_impl.dart` içine yerleştirilmeli.
