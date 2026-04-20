# Flavors ve Country Config

POS repo'sunda iki ayrı "flavor" kavramı var. Karıştırmamak lazım.

## 1. Platform Flavor'ları (Uygulama Kimliği)

Aynı codebase'den beş farklı Android paketi üretir.

| Flavor | Entry dosyası | Android AppId |
|---|---|---|
| **pos** | `apps/pos/lib/main.dart` | `ch.twotech.gastrocore.pos` |
| **kiosk** | `apps/pos/lib/main_kiosk.dart` | `ch.twotech.gastrocore.kiosk` |
| **kds** | `apps/pos/lib/main_kds.dart` | `ch.twotech.gastrocore.kds` |
| **ods** | `apps/pos/lib/main_ods.dart` | `ch.twotech.gastrocore.ods` |
| **waiter** | `apps/pos/lib/main_waiter.dart` | `ch.twotech.gastrocore.waiter` |

### Build komutları
```bash
cd apps/pos
flutter build apk --release                                        # POS default
flutter build apk --release -t lib/main_kiosk.dart --flavor kiosk
flutter build apk --release -t lib/main_kds.dart --flavor kds
flutter build apk --release -t lib/main_ods.dart --flavor ods
flutter build apk --release -t lib/main_waiter.dart --flavor waiter
```

Gradle konfigürasyonu: `apps/pos/android/app/build.gradle.kts`.

### Kiosk özellikleri
- Forced landscape.
- Immersive full-screen (sistem barları gizli).
- Device ID prefix `K-`.
- 60 saniye inaktivite auto-reset.
- Auth yok, müşteriye açık.

### Her flavor'ın feature alt kümesi
POS flavor'ı çoğu feature'ı içerir. Kiosk, KDS, ODS sadece gereken feature'ları kullanır. Aktivasyon `app.dart`'lardaki GoRouter tanımlarında yapılır:
- `app.dart` - POS route'ları
- `kiosk_app.dart` - Sadece menu browse + order submit
- `kds_app.dart` - Sadece kitchen_tickets stream
- `ods_app.dart` - Sadece ticket state display
- `waiter_app.dart` - Tables + orders

## 2. Country Config (Fiscal Ülke Ayarı)

Farklı bir boyut. Bir POS cihazı ya **İsviçre** ya **Almanya** moduna göre çalışır.

**Dosya**: `apps/pos/lib/core/country_config.dart`

```dart
enum CountryCode { ch, de }

class CountryConfig {
  final CountryCode code;
  final String name;
  final String currency;           // CHF | EUR
  final TaxSettings taxSettings;
  final bool requiresTse;           // CH: false, DE: true
  final bool requiresQrBill;        // CH: true, DE: false
  final String taxLabel;            // 'MWST' | 'MwSt'
}
```

### İsviçre (CH)
```dart
CountryConfig.ch:
  currency: 'CHF'
  taxSettings:
    standardRate: 8.1                 // dine-in food + beverage
    reducedRate: 2.6                  // takeaway food
    accommodationRate: 3.8
    taxIncludedInPrice: true          // Bruttopreise
    rappenRounding: true              // 5-Rappen yuvarlama
  requiresTse: false
  requiresQrBill: true                // ISO 20022 QR zorunlu
  taxLabel: 'MWST'
```

### Almanya (DE)
```dart
CountryConfig.de:
  currency: 'EUR'
  taxSettings:
    standardRate: 19.0
    reducedRate: 7.0
    taxIncludedInPrice: true
    rappenRounding: false
  requiresTse: true                   // Fiskaly TSE zorunlu (KassenSichV)
  requiresQrBill: false
  taxLabel: 'MwSt'
```

### Lookup
```dart
final cfg = CountryConfig.forCode('CH');   // veya 'DE'
```
Tanımlanmayan kod için default `CountryConfig.ch` döner.

### Kim kullanır
- **Order provider** - `_swissFareConfig` içinde KDV rate'leri dönüştürür (`features/orders/presentation/providers/order_provider.dart:34`).
- **Payment screen** - Yuvarlama.
- **Receipt builder** - Basılacak KDV satırları, QR-Bill.
- **Report provider** - Rapor para birimi.
- **fiscal_de feature** - Sadece `requiresTse=true` ise aktif.

### Nerede bağlanıyor
Genellikle tenant setup'ında seçilir, `SyncMetadata` veya `Tenants` tablosunda saklanır. Runtime'da bir `Provider<CountryConfig>` exposes (core/providers altında aramak gerekir).

## Flavor + Country Matrisi

Pilot senaryoda:

| Deployment | Flavor | Country |
|---|---|---|
| Swiss restoran | pos + kiosk + kds + ods + waiter | CH |
| Alman restoran | pos + kiosk + kds + ods + waiter | DE |

**Her restoranda çalışan tüm cihazlar aynı country'i kullanır.** Tek bir cihaz iki ülke değildir.

## Kiosk için ayrı CountryConfig yok

Kiosk her iki ülkede de çalışır; country_config yine tenant-level ayar. Kiosk kodu sadece POS mode + ekran davranışını değiştirir.

## Feature Flags

**Dosya**: `apps/pos/lib/core/feature_flags.dart`

`CountryConfig`'ten bağımsız runtime toggle'ları:
```dart
class FeatureFlags {
  static bool get lanSyncEnabled => ...;
  static bool get happyHourEnabled => ...;
}
```

Bir feature'i geçici olarak kapatmak istediğinizde flag ekleyip GoRouter / widget tarafında bakarsınız. Pilot testlerinde yanınizda bulundurun.
