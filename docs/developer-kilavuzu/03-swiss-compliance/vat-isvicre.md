# Swiss KDV (MWST) Kuralları

Mehrwertsteuer (MWST) İsviçre KDV'sidir. POS'un bu kurallari dogru hesaplamasi yasal zorunluluk.

**Ana referans dosya**: `apps/pos/lib/features/orders/presentation/providers/order_provider.dart:30-70`

## Oranlar (2024-01-01 Itibari Ile)

| Kategori | Oran | Ne zaman |
|---|---|---|
| Standard (dine-in yemek/icecek/alkol) | 8.1% | Masada tüketim |
| Reduced (takeaway yemek) | 2.6% | Paketleme, evde yeme |
| Special (konaklama) | 3.8% | Otel, pansiyon |

**Kaynak**: ESTV (Eidgenössische Steuerverwaltung, federal vergi dairesi).

**Önemli**: Bu oranlar **2024-01-01**'den geçerli. Eskiden (2023'e kadar) standard %7.7 idi. Code'da da yeni oran.

## Dine-In vs Takeaway - En Kritik Fark

**Aynı ürün, farklı oran:**

- Pizza Margherita dine-in (masada yersiniz): **%8.1 KDV**
- Pizza Margherita takeaway (paket alırsınız): **%2.6 KDV**

Bu kural sadece **yemek** için geçerli. İçecekler (su, kahve) her zaman %8.1, alkol her zaman %8.1.

**Code referansı** (`order_provider.dart:38-70`):
```dart
const _swissFareConfig = FareConfig(
  isTaxInclusive: true,
  currency: 'CHF',
  roundingRule: RoundingRule(rule: 'round', unit: 'five_percent'),
  taxRates: [
    // Food: 8.1% dine-in, 2.6% takeaway
    TaxRateConfig(
      name: 'food',
      rate: 8.1,
      dineInRate: '8.1',
      takeawayRate: '2.6',
    ),
    // Beverages (non-alcoholic): 8.1% always
    TaxRateConfig(
      name: 'beverage',
      rate: 8.1,
      dineInRate: '8.1',
      takeawayRate: '8.1',
    ),
    // Alcohol: 8.1% always (never reduced)
    TaxRateConfig(
      name: 'alcohol',
      rate: 8.1,
      dineInRate: '8.1',
      takeawayRate: '8.1',
    ),
    // Standard fallback
    TaxRateConfig(
      name: 'standard',
      rate: 8.1,
      dineInRate: '8.1',
      takeawayRate: '8.1',
    ),
    // Accommodation
    TaxRateConfig(name: 'accommodation', rate: 3.8),
  ],
);
```

## Mode Switch Mekaniği

POS v2 shell üst barında `_ModeSwitch` widget'ı (`pos_v2_shell.dart:467`):
- **Dine-In** (default) - kullanıcı oturacak
- **Takeaway** - kullanıcı gidecek
- **Delivery** - teslimat (takeaway gibi davranır)
- **Online** - web siparişi (dine-in gibi davranır - hazirlanip paketleniyor)

Mode değişince `_orderTypeKey` yardımcısı hangi rate'in kullanılacağını belirler:
```dart
String _orderTypeKey(OrderType type) {
  switch (type) {
    case OrderType.takeaway:
    case OrderType.delivery:
      return 'takeaway';
    case OrderType.dineIn:
    case OrderType.online:
      return 'dine_in';
  }
}
```

Mode değiştiğinde `FareEngine.recalculate(ticket)` çağrılır, tüm ticket item'larının KDV satırları yeniden hesaplanır. Total anlık güncellenir.

## Tax-Inclusive (Brutto) vs Tax-Exclusive (Netto)

İsviçre'de restoranlar **Brutto** (tax-inclusive) fiyat gösterir. Müşterinin gördüğü fiyata KDV dahildir.

```dart
FareConfig(isTaxInclusive: true, ...)
```

Ters hesaplama:
```
bruttoPrice = 10.00 CHF
taxRate = 8.1%
netto  = 10.00 / 1.081 = 9.25 CHF
tax    = 10.00 - 9.25  = 0.75 CHF
```

Makbuzda her iki bilgi de yazdırılır (Swiss zorunluluk: "inkl. MWST 8.1%").

## Rappen Yuvarlama (5-Rappen)

Nakit ödemede **sadece** aktif:

```dart
int roundToFiveRappen(int cents) {
  return ((cents + 2) ~/ 5) * 5;
}
```

Örnekler:
| Raw | Nakit | Kart |
|---|---|---|
| CHF 12.37 | CHF 12.35 | CHF 12.37 |
| CHF 12.38 | CHF 12.40 | CHF 12.38 |
| CHF 12.40 | CHF 12.40 | CHF 12.40 |

`CountryConfig.ch.taxSettings.rappenRounding == true`.

## FareEngine (Hesaplama Motoru)

`apps/pos/lib/core/services/fare_engine.dart`

Ticket aggregate için:
```dart
class FareEngine {
  FareResult calculate({
    required FareConfig config,
    required OrderType orderType,
    required List<CartLine> lines,
  }) {
    // Her line için:
    // - product taxRateCode'una göre TaxRateConfig bul
    // - dineInRate / takeawayRate seç
    // - netto, tax, brutto hesapla
    // Aggregate:
    // - lineTotals, taxBreakdown, grandTotal, rounding
  }
}
```

Output:
```dart
class FareResult {
  final List<LineResult> lines;
  final Map<String, int> taxBreakdown;   // "8.1" -> 342 cents, "2.6" -> 95 cents
  final int subtotalCents;
  final int roundingAdjustmentCents;      // Rappen rounding delta
  final int grandTotalCents;
}
```

## Happy Hour / Pricing Overrides

`apps/pos/lib/features/pricing/`:
```dart
final happyHour = ref.watch(happyHourProvider);
if (happyHour != null) {
  price = happyHour.apply(price);
}
```

Happy hour sadece **fiyatı** değiştirir, KDV oranını değiştirmez (oran yine dine-in/takeaway kuralı). İndirim brutto fiyat üzerinden, sonra netto ve tax yeniden hesaplanır.

## KDV Beyannamesi (Quarterly Filing)

İsviçre firmalari çeyreklik KDV beyanı verir. Gerekli kolonlar:
- Toplam dine-in satış (8.1% oran)
- Toplam takeaway yemek (2.6% oran)
- Toplam konaklama (3.8% oran)
- Her oran için hesaplanan KDV

POS'tan export: `apps/pos/lib/features/reports/services/mwst_csv_export_service.dart`. Tipik olarak Treuhänder haftalık indirir, beyan zamanı toplam.

Backend'de zaten aggregate endpoint var: `/api/v1/reports/vat?from=...&to=...` -> tüm cihazlardan gelen veriyi birleştirir.

## Test

Unit test: `test/core/services/fare_engine_test.dart` (varsa):
```dart
test('dine-in food at 8.1%', () {
  final result = FareEngine().calculate(
    config: _swissFareConfig,
    orderType: OrderType.dineIn,
    lines: [CartLine(taxRateCode: 'food', brutto: 1000)],   // 10.00 CHF
  );
  expect(result.taxBreakdown['8.1'], equals(75));             // 0.75 CHF
  expect(result.grandTotalCents, equals(1000));
});

test('takeaway food drops to 2.6%', () {
  final result = FareEngine().calculate(
    config: _swissFareConfig,
    orderType: OrderType.takeaway,
    lines: [CartLine(taxRateCode: 'food', brutto: 1000)],
  );
  expect(result.taxBreakdown['2.6'], equals(25));             // 0.25 CHF
});
```

## Gotcha'lar

- Alkollü içecek takeaway'de bile %8.1 (indirimli oran alamazsiniz).
- Menuda bir combo (yemek + içecek) varsa her component kendi oranını kullanır, aggregate toplam basılır.
- Mix mode yok: bir ticket'ın tüm kalemleri aynı mode'da (dine-in veya takeaway).
- Kart ödemesinde rounding yapılmaz. Nakit + kart karışık ödemede (`split payment`) kart kısmı raw, nakit kısmı yuvarlanır.
