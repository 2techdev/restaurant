# Payment Flow

Ödeme akışı. Kasiyer BEZAHLEN'e bastıktan sonra açılan `OrderPaymentScreen`'den başlar.

**Dizinler**:
- `apps/pos/lib/features/payments/` - Donanım sağlayıcı entegrasyonu
- `apps/pos/lib/features/orders/presentation/screens/payment_screen.dart` - UI
- `apps/pos/lib/core/payment/` - Ödeme provider soyutlamasının temeli

## Klasör Yapısı

```
features/payments/
├── data/
│   ├── hardware/
│   │   ├── mypos/          # myPOS terminal entegrasyonu
│   │   ├── wallee/         # Wallee / TWINT
│   │   └── payment_engine.dart
│   └── repositories/
├── domain/
│   ├── entities/
│   └── services/
│       └── seat_split_calculator.dart
├── presentation/
└── providers/
    └── hardware_payment_providers.dart
```

## Ödeme Türleri

| Yöntem | Provider | Tipik kullanım |
|---|---|---|
| Nakit | In-app (cash_movements tablosu) | Default, her yerde |
| Kart | Wallee / myPOS | Genel İsviçre pazarı |
| TWINT | Wallee | İsviçre ana mobil ödeme |
| Hediye kartı | In-app | Opsiyonel |
| Bon / voucher | In-app | Opsiyonel |

## OrderPaymentScreen

`apps/pos/lib/features/orders/presentation/screens/payment_screen.dart`

Tipik akış:
1. Ticket toplam CHF 42.50.
2. Kasiyer ödeme yöntemi seçer (Cash / Card / TWINT).
3. Cash: alınan miktar input -> para üstü hesaplanır.
4. Card/TWINT: terminal tetiklenir -> uygulama sonucu bekler.
5. Başarılı -> `PaymentEntity` kayıt, `Receipts` tablosuna makbuz.
6. Ticket `isPaid = true`, `currentTicketProvider` reset.

## Wallee (TWINT + Kart)

`apps/pos/lib/features/payments/data/hardware/wallee/`

Wallee, İsviçre'nin en yaygın payment gateway'lerinden. TWINT, Visa, Mastercard, Apple Pay hepsi Wallee üzerinden gider.

**Config**: `shared_preferences`'ta `wallee_trx_sync_number` (hardcoded key `trxSyncNumber`).

Flow:
1. `WalleePaymentProvider.charge(amount, currency)` çağrılır.
2. Gateway'e HTTP POST ile transaction create.
3. Kullanıcı terminalde TWINT QR tarar veya kart geçirir.
4. Long-poll ile status kontrol edilir (pending -> completed / failed).
5. Success sonrası `PaymentEntity` lokalde saved.

Error handling: 3 dakika timeout. Timeout durumunda transaction iptal edilir (void).

## myPOS

`apps/pos/lib/features/payments/data/hardware/mypos/`

Alternatif terminal sağlayıcı. Belirli merchant'lar için aktif. myPOS Android terminal üstünde POS app'i ile entegre çalışır.

## Payment Engine

`apps/pos/lib/features/payments/data/hardware/payment_engine.dart`

Tüm ödeme sağlayıcıları için ortak interface:
```dart
abstract class PaymentEngine {
  Future<PaymentResult> charge({required int amountCents, required String currency});
  Future<void> cancel(String transactionId);
  Future<PaymentResult> refund(String transactionId, int amountCents);
}
```

Her sağlayıcı (`WalleePaymentProvider`, `MyPosPaymentProvider`, `CashPaymentProvider`) bu interface'i implemente eder.

Provider wiring: `hardware_payment_providers.dart`:
```dart
final walleePaymentProvider = Provider<WalleePaymentProvider>(...);
final myPosPaymentProvider = Provider<MyPosPaymentProvider>(...);
```

Aktif provider tenant config'ine göre seçilir.

## Split Bill

`apps/pos/lib/features/payments/domain/services/seat_split_calculator.dart`

Bir ticket birden fazla müşteri arasında bölündüğünde:
- Eşit bölüşüm (N kişiye eşit)
- Koltuğa göre (kimin hangi item'ı aldığı)
- Manuel miktar

`AppRoutes.splitBillFor(ticketId)` bu ekrana götürür. Bottom action bar'daki TEILEN butonu tetikler.

## Rappen Rounding (5-Rappen Yuvarlama)

İsviçre kuralı: nakit ödemede 0.05 CHF'ye yuvarla. Bu **sadece nakit** için, kartta centler exactsa.

```dart
int roundToFiveRappen(int cents) {
  return ((cents + 2) ~/ 5) * 5;
}
```

Örnekler:
- CHF 12.37 cash -> CHF 12.35
- CHF 12.38 cash -> CHF 12.40
- CHF 12.40 card -> CHF 12.40 (yuvarlama yok)

Bu `CountryConfig.ch.taxSettings.rappenRounding == true` iken aktif.

## Receipt Generation

Ödeme başarılı olduğunda:
1. `Receipts` tablosuna satır eklenir.
2. PDF üretilir (`pdf` paketi ile).
3. Yazıcı bağlıysa anında basılır (`printing` paketi).
4. Müşteri Swiss QR-Bill isterse ayrı bir PDF üretilir.
5. `share_plus` ile email/WhatsApp üzerinden paylaşım seçeneği.

Detaylar: [03-swiss-compliance/receipt.md](../../03-swiss-compliance/receipt.md).

## Audit Log

Her ödeme `AuditLog` tablosuna kayıt bırakır:
- `kim` (cashier user ID)
- `ne` (payment_created)
- `detay` (amount, currency, method, ticket_id)
- `zaman` (UTC timestamp)

Void/refund'ler özel olarak işaretlenir. Manager override varsa override_id de eklenir.

## Hata Senaryoları

- **Timeout**: Terminal 3 dakika yanıt vermezse transaction void edilir, ticket paid olmaz.
- **Partial success**: Kart çekildi ama ağ kesildi -> `SyncQueue`'a push pending. Cloud zaten bildiğinde deduplicate.
- **User cancel**: Terminal ekranında kullanıcı cancel -> `PaymentResult.cancelled`, UI'da cancel mesajı.
- **Insufficient funds**: Terminal döner `failed` -> kasiyer farklı yöntem dener.

## Test

Mock provider mevcut: `MockPaymentEngine` (test dosyaları altinda). Unit testlerde:
```dart
final mock = MockPaymentEngine();
when(() => mock.charge(any())).thenAnswer((_) async => PaymentResult.success(...));
container.read(walleePaymentProvider.notifier).override = mock;
```

Integration test: Wallee sandbox ortamı kullanılabilir.
