# Swiss QR-Bill

İsviçre'nin 2020'de zorunlu kıldığı QR kodlu fatura formatı. Eski turuncu/kırmızı ödeme slipleri yerine geçti. Her restoran faturasında bu QR olmak zorunda.

**Dosya**: [apps/pos/lib/features/orders/presentation/screens/qr_bill_screen.dart](../../apps/pos/lib/features/orders/presentation/screens/qr_bill_screen.dart)

## Nedir

Swiss QR-Bill = ISO 20022 standardında QR kod + fatura slibi. Müşteri bu QR'ı banka app'iyle tarar, tüm ödeme bilgisi otomatik doldurulur, onayla gönderir.

## Spec

İki ana bölüm:
- **Left section** (payment information): IBAN, amount, creditor, reference
- **Right section** (receipt strip): QR code + amount

Boyut: A6 yatay (bir A4 sayfasının alt şeridi).

## Country Config

```dart
CountryConfig.ch.requiresQrBill == true
```

Her Swiss tenant için QR-Bill ekranı otomatik aktif. Almanya için `requiresQrBill == false`, ekran hiç render edilmez.

## QR İçindeki Veri

Swift payload format:
```
SPC
0200
1
<iban-or-qr-iban>
S
<creditor-name>
<creditor-street>
<creditor-building>
<creditor-zip>
<creditor-city>
<creditor-country>
<amount>
<currency>
...
```

POS bu payload'u compose eder. `qr_flutter: ^4.1.0` ile render edilir.

## State ve Provider

```dart
class _QRBillData {
  final String qrData;             // yukardaki SPC payload
  final String iban;
  final String amountFormatted;
  final String creditorName;
  final String creditorAddress;
  final String? debtorName;        // müşteri ismi
  final String? debtorAddress;
  final String referenceType;      // 'QRR' | 'SCOR' | 'NON'
  final String? reference;
  final String? message;
}
```

### Creditor Info
Restoran ayarlarından gelir: `restaurant_settings.dart`.
- IBAN / QR-IBAN
- Ticari unvan
- Adres
- Ülke

Settings genelde onboarding sırasında girilir, backend'e sync edilir.

### Debtor Info (Opsiyonel)
Müşteri ismi/adresi biliniyorsa (kayıtlı müşteri veya faturada bilgi eklendiyse) doldurulur. Yoksa boş, müşteri manuel yazar.

### Reference
- `QRR` - QR-Reference, numeric, QR-IBAN gerektirir.
- `SCOR` - Structured Creditor Reference (ISO 11649).
- `NON` - Reference yok.

POS ticket ID'yi reference olarak kullanır (QRR format): `00000000000000000000012345` (27 hane, son 1 check digit).

## IBAN vs QR-IBAN

- **Normal IBAN**: CH93 0076 2011 6238 5295 7
- **QR-IBAN**: CH21 3080 8001 2345 6789 0 (institution ID 30000-31999)

QR-IBAN sadece QR-Bill için kullanılır, banka sisteminde otomatik reference eşleştirmesi yapar. Muhasebe için kritik (gelen ödemeyi hangi faturaya saymak otomatik).

Restoranın bankada QR-IBAN yoksa normal IBAN + `SCOR` veya `NON` reference kullanılır.

## UI Render

`qr_bill_screen.dart`:
```dart
QrImageView(
  data: _qrBillData.qrData,
  version: QrVersions.auto,
  size: 200,
  backgroundColor: Colors.white,
  embeddedImage: AssetImage('assets/images/swiss_cross.png'),  // merkezdeki haç
  embeddedImageStyle: QrEmbeddedImageStyle(size: Size(40, 40)),
);
```

İsviçre bayrağı haçı QR'ın merkezine gömülür (spec zorunluluğu).

Layout HTML/PDF versiyonunda spec'te verilen kesin ölçüler (`Helvetica 10pt` başlıklar, `Helvetica Bold 8pt` alan isimleri) kullanılır.

## Makbuz Üretimi

Ödeme başarılı olduktan sonra:
1. `payment_screen.dart` `OrderPaymentScreen` ödeme akışını tamamlar.
2. Müşteri "QR-Bill istiyorum" seçerse `qr_bill_screen.dart`'a navigate eder.
3. `_QRBillData` compose edilir (restoran + ticket verisi).
4. Ekranda QR görüntülenir.
5. `printing` paketi ile yazıcıya basılır.
6. Opsiyonel: `share_plus` ile PDF email/WhatsApp.

## Server-Side QR Fetch

```dart
final response = await http.post(
  AppEndpoints.qrBill,
  body: jsonEncode({'ticket_id': ticketId}),
);
```

Server bazı durumlarda QR payload'ı merkezi olarak üretir (tenant ayarı ile). Client-side fallback her zaman var.

## Validation

- IBAN checksum (mod-97) - girildikçe kontrol.
- Amount format: `1234.56` (12 hane max, 2 decimal).
- Reference: QRR ise 27 hane, SCOR ise max 25 hane + RF prefix.
- Creditor name: max 70 char.
- Messages: max 140 char.

Validation helper'ları `features/settings/data/` altında (varsa) veya inline.

## Test

Integration test: Swiss banka app'i ile gerçek tarama (sandbox QR spec'i var).
Unit test: payload string format expectation'ları:
```dart
expect(qrData, startsWith('SPC\n0200\n1\n'));
expect(qrData.split('\n').length, equals(30));    // spec'te 30 satır
```

## Gotcha'lar

- Yuvarlama: QR-Bill amount alanı 2 decimal. Nakit yuvarlaması (5-Rappen) **sonra** uygulanır. Önce raw ticket total, sonra yuvarla, sonra QR'e yaz.
- Unicode: creditor ismi Alman umlaut (ä, ö, ü) içerir, payload UTF-8.
- Boş alanlar: spec'e göre boş kalacak field'lar bile satır olarak payload'da olmalı (\n).
- Swiss Cross: QR'a gömülü haç `error correction level M` (medium) ile yapılmalı, başka level QR'u okumaz.

## Gelecek

Sadakat puan kullanımı + QR-Bill karışık ödeme senaryosu henüz yok. Şu an müşteri ya full QR öder ya da nakit+kart.
