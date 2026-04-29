# Wallee / TWINT Entegrasyonu

TWINT İsviçre'nin en yaygın mobil ödeme uygulaması. Wallee ise POS'un kullandığı payment gateway; TWINT + Visa + Mastercard + Apple Pay + Google Pay her biri Wallee üzerinden akıyor.

**Dizin**: `apps/pos/lib/features/payments/data/hardware/wallee/`

## Neden Wallee

Swiss merchant'lar için:
- TWINT native entegrasyon (tek SDK ile).
- Yerel bank acquirer'lar ile doğrudan sözleşme.
- Wallee Boss + POS terminal donanımı hazır (SumUp benzeri).
- Swiss DPA (data processing agreement) ile GDPR/FADP uyumlu.

Alternatif olarak myPOS da entegre ama Wallee Swiss pazarında dominant.

## Akış (Kart + TWINT)

### 1. Charge Tetikleme
```dart
final provider = ref.read(walleePaymentProvider);
final result = await provider.charge(
  amountCents: ticket.totalCents,
  currency: 'CHF',
);
```

### 2. Gateway'e İstek
`WalleePaymentProvider.charge` Wallee REST API'ye POST:
```http
POST /api/transaction/create
Authorization: Bearer <wallee-token>
Content-Type: application/json

{
  "amount": 42.50,
  "currency": "CHF",
  "lineItems": [...],
  "language": "de-CH",
  "customerId": "...",
  "metaData": {"ticket_id": "abc-123"}
}
```

Gateway transaction ID döner.

### 3. Terminal'e İlet
Terminal Wallee SDK üzerinden transaction ID'yi alır, ekranda müşteriye "Kartınızı uzatın veya TWINT QR tarayın" gösterir.

### 4. Long Poll
POS her 2 saniyede status sorgular:
```http
GET /api/transaction/{id}/status
```

Status değerleri:
- `PENDING` - bekliyor
- `AUTHORIZED` - onaylandı, tahsilat edilecek
- `COMPLETED` - tamamlandı
- `FAILED` - reddedildi
- `CANCELLED` - iptal

### 5. Sonuç
- COMPLETED -> `PaymentEntity` DB'ye kayıt, ticket paid.
- FAILED / CANCELLED -> kullanıcıya hata mesajı, başka method dene.
- Timeout (3 dk) -> void.

## Configuration

`shared_preferences` üzerinden saklanan anahtar:
```dart
const _kTrxSyncNumber = 'wallee_trx_sync_number';
```

`trxSyncNumber` - Wallee'den aldığın unique transaction numarası, device-level. POS ilk kurulumda set edilir.

Diğer config (API key, merchant ID) tenant settings'te saklanır (`features/settings/`).

## TWINT Özel Durumu

TWINT için Wallee üç mode destekler:

### Mode 1: POS-Initiated QR
Terminal ekranında QR çıkar, müşteri telefonuyla tarar. Masada otur, fiziksel terminal gerekiyor.

### Mode 2: Customer-Initiated (QR at Table)
Müşteri kendi TWINT app'inde "ödeme yap" der, POS'un gösterdiği QR'ı tarar.

### Mode 3: Push (For E-Commerce)
Online ordering flavor'ında kullanılır. POS flavor'ında aktif değil.

POS tarafında default Mode 1. QR ekranda 60 saniye expired olur, yenisi üretilir.

## Hata Senaryoları

### Müşteri reddetti / TWINT bakiyesi yetmiyor
Wallee `FAILED` döner:
```dart
if (result.status == WalleeStatus.failed) {
  showError('Ödeme reddedildi. Başka yöntem deneyin.');
}
```

Ticket paid olmaz, cashier başka method (nakit, kart) seçebilir.

### Network koptu ama terminal onayladı
En tehlikeli senaryo. Wallee webhook (varsa) kullanılır. POS periyodik olarak pending trx'leri polllar, resolve eder.

`SyncQueue` içine `payment_reconcile_<trxId>` event eklenir, bağlantı gelince cloud'a sorulur.

### Terminal offline
Wallee zaten internet gerektiriyor. Terminal offline iken TWINT/kart kullanılamaz. Kasiyer nakit alır, "no-payment-device" audit log.

## myPOS Alternatifi

`apps/pos/lib/features/payments/data/hardware/mypos/` - farklı merchant tercih senaryosu. API benzer ama provider ayrı:
```dart
final myPosPaymentProvider = Provider<MyPosPaymentProvider>(...);
```

Tenant setup'ta `payment_provider_id` field'ı ile hangisi aktif olduğu belirlenir.

## Sandbox Test

Wallee sandbox ortam:
- `api-sandbox.wallee.com`
- Test kart numaraları: `4000 0000 0000 0002` (success), `4000 0000 0000 0028` (3DS), `4000 0000 0000 0010` (decline).
- Test TWINT: `+41 79 000 0000` sandbox test numarası.

Integration test'lerde:
```dart
WalleeConfig.sandbox()
  .charge(amount: 100)
  .expect(status: Status.completed);
```

## DPA + Compliance

- Wallee Switzerland AG, Winterthur.
- DSG (Swiss Data Protection Act) uyumlu.
- PCI-DSS Level 1 (kart verisi Wallee'de, POS'ta değil).
- POS sadece `transactionId` ve sonuç status'u saklar. Kart numarası, CVV vb hiçbir zaman POS DB'sinde değildir.

## Refund

```dart
await walleeProvider.refund(transactionId: 'abc-123', amountCents: 4250);
```

- Full refund - tüm amount.
- Partial refund - parça parça.
- Tax refund - ilgili KDV de geri döner, `PaymentEntity` refund olarak işaretlenir.
- Audit log: `payment_refunded` + manager override ID (refund manager yetkisi ister).

Wallee refund'i aynı kartın/TWINT hesabının kaynağına gönderir. Ortalama 3-5 iş günü.

## Tips ve Service

İsviçre'de tip kültürü var ama kartta eklemek opsiyonel. TWINT'de "tip eklemek?" ekranı Wallee tarafından gösterilir. POS tip amount'u ayrı kalem olarak `PaymentEntity`'ye yazar, ticket'a eklemez (KDV yok).

## Test Notları

- Wallee sandbox environment setup: `docs/DEVELOPMENT.md` (varsa) veya `.env.example`.
- TWINT test app'i developer mode'unda gerçek para ile değil, test account ile çalışır.
- Terminal emülatörü: Wallee'nin sandbox web UI'da emülatör var, gerçek donanım olmadan akış test edilebilir.
