# Dizin Yapısı

Repo kökü: `E:\Project\Restaurant\` (prod) veya bir worktree (örn `E:\Project\Restaurant\.claude\worktrees\jolly-final`).

## Üst Seviye

```
.
├── apps/              # Flutter uygulamaları
│   ├── pos/           # Ana POS + KDS/ODS/Kiosk/Waiter flavor entry'leri
│   ├── dashboard/     # Yönetim paneli (web + masaüstü)
│   └── online/        # Müşteri online ordering (Flutter Web)
├── packages/          # Paylaşılan Dart paketleri (monorepo)
│   ├── gastrocore_models/
│   ├── gastrocore_api/
│   ├── gastrocore_sync/
│   └── gastrocore_ui/
├── server/            # Go backend
├── docs/              # Tüm doküman (bu kılavuz da burada)
├── infra/             # Docker, nginx, CI config
├── scripts/           # Yardımcı scriptler
├── design/            # Design referansları (pos-v2 HTML/JSX)
├── store-listing/     # Google Play / App Store metinleri
└── docker-compose.yml
```

## apps/pos (ana konu)

POS uygulamasının iç yapısı. Bu kılavuzun ana odağı.

```
apps/pos/
├── pubspec.yaml
├── android/, ios/, linux/, macos/, web/, windows/    # platform klasörleri
├── assets/
│   ├── audio/                         # KDS beep
│   └── images/
│       ├── products/                  # starter, main_course, pizza, dessert, beverage SVG
│       └── staff/                     # max_mueller, sarah_weber, ... SVG
├── test/                              # unit + widget testleri
└── lib/
    ├── main.dart                      # POS default entry
    ├── main_kiosk.dart                # Kiosk entry
    ├── main_kds.dart                  # KDS entry
    ├── main_ods.dart                  # ODS entry
    ├── main_waiter.dart               # Waiter entry
    ├── app.dart                       # POS app root widget
    ├── kiosk_app.dart                 # Kiosk app root
    ├── kds_app.dart                   # KDS app root
    ├── ods_app.dart                   # ODS app root
    ├── waiter_app.dart                # Waiter app root
    ├── l10n/                          # ARB dosyaları (de, fr, it, en, tr)
    ├── shared/                        # Feature'lar arası paylaşılan UI
    ├── core/                          # Altyapı (bkz aşağı)
    └── features/                      # Feature klasörleri (bkz aşağı)
```

## apps/pos/lib/core/

Uygulamanın altyapı kemeri. Feature'lar bunu kullanır, kendisi feature'lara bağlı değildir.

| Klasör | Ne yapıyor |
|---|---|
| `config/` | Runtime konfigürasyonları |
| `constants/` | Sabitler (route adları, key'ler vb) |
| `country_config.dart` | Ülke bazlı KDV, para birimi, dil ayarı |
| `data/` | Core data helper'ları |
| `database/` | Drift `AppDatabase`, tablo tanımları, migration'lar |
| `di/` | `get_it` Dependency Injection setup |
| `error/` | Failure / Exception sınıfları (Clean Arch) |
| `feature_flags.dart` | Feature on/off toggle'lari |
| `monitoring/` | Crash + analytics hook'ları |
| `payment/` | Ödeme sağlayıcı interface'leri (Wallee, Cash vb) |
| `pos_mode/` | POS mode provider (dine-in / takeaway vb) |
| `printing/` | Fiş yazdırma altyapısı |
| `providers/` | Global providerlar (currentUser, connectivity...) |
| `router/` | GoRouter tanımları (`app_router.dart`) |
| `services/` | Platform servisleri (share, secure storage) |
| `theme/` | Uygulama teması, tokenlar (`app_tokens.dart`, `kinetic_theme.dart`) |
| `utils/` | Yardımcı fonksiyonlar |

## apps/pos/lib/features/ - 32 Feature

Her feature kendi içinde Clean Architecture katmanlarına sahip: `data/`, `domain/`, `presentation/` (kimisi ek `providers/`).

### Satış Çekirdeği
- **orders/** - POS v2 shell, sipariş akışı, bu kılavuzun en büyük bölümü
- **menu/** - Kategori + ürün yönetimi
- **payments/** - Ödeme sağlayıcı entegrasyonu (Wallee, cash, kart)
- **pricing/** - Happy hour, indirim, promosyon

### Mutfak / Servis
- **kitchen/** - KDS içindeki iş mantığı (POS flavor'ının tüketeceği)
- **gang/** - Kurs / gang sistem (stater -> main -> dessert sıralaması)
- **tables/** - Masa düzeni + transfer
- **waiter/** - Waiter handheld iş mantığı

### Müşteri
- **customers/** - Müşteri kayıtları, sadakat
- **reservations/** - Rezervasyon yönetimi
- **online_orders/** - Online ordering entry'lerinin yerel aynası

### Yönetim
- **auth/** - PIN girişi, JWT token, role
- **brand_auth/** - Merchant/brand seviyesi kimlik doğrulama
- **home/** - Uygulama home ekranı (POS flavor'ında)
- **dashboard/** - Dashboard feature (kullanım POS içinde)
- **backoffice/** - Yönetim menüleri
- **settings/** - Ayarlar
- **shifts/** - Vardiya açma/kapama
- **overrides/** - Cashier override akışları (indirim yetkisi vb)

### Compliance + Legal
- **fiscal_de/** - Almanya TSE entegrasyonu (KassenSichV)
- **audit_log/** - Denetim günlüğü
- **license/**, **licensing/** - Uygulama lisans doğrulama (Ed25519)

### Raporlama
- **reports/** - Satış, ürün, vardiya raporları

### Operasyon
- **inventory/** - Stok
- **sync/** - Sync engine UI ve provider sarmalamaları
- **lan_sync/** - LAN içi mDNS keşif + shelf server
- **onboarding/** - İlk kurulum wizard
- **splash/** - Splash screen

### Alternatif Flavor'lar (Kendi Entry'leri Var)
- **kds_app/** - KDS flavor'ının feature kümesi
- **kiosk/** - Kiosk flavor'ının feature kümesi
- **ods/** - ODS flavor'ının feature kümesi

## Feature İçi Şablon

Tipik bir feature:

```
features/orders/
├── data/              # Repository implementasyonları, DataSource'lar
├── domain/            # Entity'ler, repository interface'leri, use case'ler
└── presentation/
    ├── screens/       # Tam ekran widget'lar (routing hedefi)
    ├── shells/        # Birden fazla widget'ı bir araya getiren UI shell'leri
    ├── providers/     # Sadece UI state provider'ları
    ├── theme/         # Feature-özel tema (örn pos_v2_theme.dart)
    └── widgets/       # Reusable widget'lar (shell alt parçaları)
```

`features/orders/presentation/` içinde tipik örnekler:
- `screens/pos_screen.dart` - Ana POS ekranı
- `screens/payment_screen.dart` - Ödeme akışı
- `shells/pos_v2_shell.dart` - POS v2 design
- `shells/pos_shell_router.dart` - Aktif shell'i seçen router
- `providers/order_provider.dart` - `currentTicketProvider`

## packages/

`pubspec.yaml`'ta `path: ../../packages/...` ile bağlı.

```
packages/
├── gastrocore_models/     # Entity'ler + Freezed data class'lar
├── gastrocore_api/        # REST client + DTO'lar
├── gastrocore_sync/       # Outbox + pull + WS senkron
└── gastrocore_ui/         # Shared widget'lar, tema token'ları
```

## server/

```
server/
├── cmd/
│   ├── server/            # Ana HTTP server
│   ├── migrate/           # DB migration runner
│   └── seed/              # Demo data seed
├── internal/              # İç paketler
├── migrations/            # SQL migration dosyaları
└── Dockerfile
```

## docs/

Sayısal prefix'li mimari / karar dokümanlari (`00-executive-summary.md` -> `33-...`). Bizim kılavuz ise:

```
docs/developer-kilavuzu/
├── README.md                      # Bu kılavuzun index'i
├── 00-genel-bakis/
├── 01-mimari/
├── 02-features/
├── 03-swiss-compliance/
├── 04-dev-workflow/
└── 05-kararlar-ve-bilinmesi-gerekenler/
```
