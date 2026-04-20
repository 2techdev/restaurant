# Katmanlar (Clean Architecture)

POS projesi Clean Architecture düzeniyle organize edildi. Her feature kendi içinde üç katmana ayrılır: `domain`, `data`, `presentation`. Bu kural monorepo'daki paketlerde de geçerli (örn `packages/gastrocore_sync`).

## Üç Ana Katman

### 1. Domain (İş Kuralları)

**Nerede**: `features/<feature>/domain/`

**Ne var**:
- `entities/` - Saf Dart veri sınıfları. UI'a veya DB'ye bağımlı değil. Örnek: `TicketEntity`, `ProductEntity`, `CustomerEntity`.
- `repositories/` - Abstract sınıflar (interface gibi). Domain bilmez, data katmanı bu sözleşmeyi implemente eder.
- `usecases/` - Opsiyonel. Tek fonksiyonluk "iş adımı" sarmalayıcıları.

**Kural**: Domain import'ları sadece Dart SDK ve `equatable` / `freezed_annotation` gibi veri anotasyonları olabilir. Flutter, Drift, http yok.

### 2. Data (Dış Dünyayla Köprü)

**Nerede**: `features/<feature>/data/`

**Ne var**:
- `datasources/` - `LocalDataSource` (Drift/SQLite), `RemoteDataSource` (HTTP), `CacheDataSource`. Sadece CRUD operasyonları.
- `repositories/` - Domain'deki abstract'ın concrete implementasyonu. Örneğin offline-first senaryoda önce local'e yazar, sonra outbox'a sync kaydı düşer.
- `models/` - DTO'lar. Genelde entity'den ayrı tutulur; JSON serialize/deserialize buraya düşer.

**Kural**: Data katmanı domain'e bağımlı olabilir, domain data'ya bağımlı olmaz.

### 3. Presentation (UI)

**Nerede**: `features/<feature>/presentation/`

**Ne var**:
- `screens/` - Tam ekran widget'lar. Genelde `ConsumerWidget` veya `ConsumerStatefulWidget`.
- `shells/` - Birden fazla widget'ı bir araya getiren kompozit UI (örn `pos_v2_shell.dart`).
- `widgets/` - Shell / screen altında kullanılan alt parçalar.
- `providers/` - UI state provider'ları. Sadece presentation'a özel state.
- `theme/` - Feature özel tema (örn `pos_v2_theme.dart`).

**Kural**: Presentation, domain + data'ya bağımlı olabilir; tersi yasak.

## Gerçek Örnek: Orders Feature

```
features/orders/
├── domain/
│   ├── entities/
│   │   ├── ticket_entity.dart          # Ticket (sepet) modeli
│   │   ├── order_item_entity.dart      # Sepet kalemi
│   │   └── payment_entity.dart         # Ödeme kayıt modeli
│   └── repositories/
│       └── order_repository.dart       # Abstract, domain sözleşmesi
├── data/
│   ├── datasources/
│   │   ├── order_local_datasource.dart # Drift üzerinden SQLite
│   │   └── order_remote_datasource.dart
│   ├── repositories/
│   │   └── order_repository_impl.dart  # Concrete
│   └── models/                         # DTO'lar
└── presentation/
    ├── screens/
    │   ├── pos_screen.dart
    │   ├── payment_screen.dart
    │   └── order_history_screen.dart
    ├── shells/
    │   ├── pos_v2_shell.dart           # En büyük UI parçası
    │   ├── pos_shell_router.dart
    │   ├── fine_dining_shell.dart
    │   └── fast_food_shell.dart
    ├── providers/
    │   ├── order_provider.dart         # currentTicketProvider
    │   ├── storno_log_provider.dart
    │   └── void_provider.dart
    ├── theme/
    │   └── pos_v2_theme.dart
    └── widgets/
        └── shell/
            └── bottom_action_bar.dart
```

## Bağımlılık Yönü

```
presentation/   depends on   domain + data
data/           depends on   domain
domain/         depends on   hiçbir şeye (temiz)
```

Bu kural zincirleme tersine çevirilemez. Eğer `entity` bir `IconData` import ediyorsa, domain kirlenmiştir, refactor gerekir. Aynı sebepten entity'ler `ChangeNotifier` değildir, Riverpod'u bilmezler.

## Core (Feature'lar Arası Kemer)

`apps/pos/lib/core/` feature'ların üstünde, onları taşıyan altyapıdır:

- `database/` - Drift `AppDatabase` (tüm feature'ların yerel tablolari).
- `router/` - GoRouter (feature'lar burada register edilir).
- `di/` - `get_it` service locator.
- `theme/` - Uygulama tema token'ları (`app_tokens.dart`, `kinetic_theme.dart`).
- `country_config.dart` - `CountryCode.ch` / `.de` + KDV oranları.
- `feature_flags.dart` - Feature on/off.

**Core feature'lara bağımlı olmaz.** Eğer `core/` içinde bir `features/orders/...` import görürseniz yanlış katmanda durmaktadır, mimari kırıldı demektir.

## Paketler (Monorepo Katmanı)

Packages katmanı feature'ların üstündedir. Birden fazla app paylaşır:

- `gastrocore_models` - Cross-app entity'ler (tenant, user, device, sync envelope).
- `gastrocore_api` - REST client abstraksiyonu.
- `gastrocore_sync` - Outbox + pull + WS.
- `gastrocore_ui` - Shared widget + tema.

POS bu paketleri `pubspec.yaml` içinde `path:` ile lokal olarak bağlar.

## Neden Bu Düzen

- **Test edilebilirlik**: Domain saf olduğu için Flutter ortamı gerektirmez, `dart test` ile hızlıca çalıştırılır.
- **Offline-first kolay**: Repository pattern sayesinde online/offline fark etmeksizin data'ya erişim tek yerde yönetilir.
- **Feature taşınabilir**: Bir feature'ı (örn `reservations`) başka bir app'e almak kolaydır çünkü bağımlılıklar ismi belli.
- **Fiscal izolasyon**: `features/fiscal_de/` (TSE) ve Swiss compliance birbirinden ayrı tutulur, country_config switch'i olmadan karışmaz.
