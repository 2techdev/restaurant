# Teknoloji Stack

Kaynak: `apps/pos/pubspec.yaml`.

## Dil ve SDK

- **Dart SDK**: `^3.9.2`
- **Flutter**: 3.35.0 (README'de sabitlendi)
- **Go**: 1.22+ (backend için)
- **Java**: 17 (Temurin, Android build için)

## Flutter Katmanı

### State Management

| Paket | Versiyon | Ne için |
|---|---|---|
| `flutter_riverpod` | ^2.6.1 | Ana state kütüphanesi |
| `riverpod_annotation` | ^2.6.1 | Code generation için notation |
| `riverpod_generator` | ^2.6.3 | Dev dependency, build_runner ile çalışır |

`StateProvider`, `FutureProvider`, `StateNotifierProvider`, `AsyncValue.when` ile okunabilir async state. Detay: [01-mimari/state-management.md](../01-mimari/state-management.md).

### Database

| Paket | Versiyon | Ne için |
|---|---|---|
| `drift` | ^2.22.1 | SQLite ORM |
| `sqlite3_flutter_libs` | ^0.5.28 | Native SQLite binary |
| `path_provider` | ^2.1.5 | Cihaz storage path'i |
| `drift_dev` | ^2.22.1 | Dev dependency, tablo sınıfları üretir |

Detay: [01-mimari/database.md](../01-mimari/database.md).

### Navigasyon

| Paket | Versiyon | Ne için |
|---|---|---|
| `go_router` | ^14.8.1 | Declarative routing |

Route tanımları: `apps/pos/lib/core/router/app_router.dart`.

### Networking & Sync

| Paket | Versiyon | Ne için |
|---|---|---|
| `http` | ^1.3.0 | REST çağrıları |
| `web_socket_channel` | ^3.0.2 | Sync fan-out için WS |
| `connectivity_plus` | ^6.1.4 | Offline/online detect |
| `shelf` | ^1.4.2 | LAN içi gömülü HTTP sunucusu |
| `shelf_router` | ^1.1.4 | LAN server router |
| `multicast_dns` | ^0.3.2+1 | mDNS cihaz keşfi |

LAN sync: `apps/pos/lib/features/lan_sync/`.

### Güvenlik

| Paket | Versiyon | Ne için |
|---|---|---|
| `crypto` | ^3.0.6 | PIN hash, checksum |
| `pointycastle` | ^3.9.1 | Ed25519 lisans doğrulama |
| `flutter_secure_storage` | ^9.2.2 | JWT + device token, Android Keystore / iOS Keychain |
| `shared_preferences` | ^2.3.2 | Güvensiz yerel key-value (örn. Wallee trxSyncNumber) |

Lisanslama: `apps/pos/lib/features/licensing/` ve `apps/pos/lib/features/license/`.

### UI + Format

| Paket | Versiyon | Ne için |
|---|---|---|
| `cupertino_icons` | ^1.0.8 | iOS tarzı ikonlar (fallback) |
| `intl` | ^0.20.2 | Tarih / para formatı, i18n |
| `fl_chart` | ^0.69.0 | Rapor grafikleri |
| `qr_flutter` | ^4.1.0 | Swiss QR-Bill rendering |
| `pdf` | ^3.10.8 | PDF oluşturma |
| `printing` | ^5.13.2 | Yazıcıya basma |
| `excel` | ^4.0.6 | Rapor Excel export |
| `image_picker` | ^1.2.1 | Ürün/personel fotoğrafı |
| `share_plus` | ^10.0.0 | Makbuz paylaşımı |
| `audioplayers` | ^6.1.0 | KDS yeni-sipariş beep sesi |

### Code Generation

| Paket | Versiyon | Ne için |
|---|---|---|
| `build_runner` | ^2.4.14 | Gen pipeline |
| `freezed` | ^3.0.2 | Immutable data class'lar |
| `freezed_annotation` | ^3.0.0 | Freezed için notation |
| `json_serializable` | ^6.9.4 | JSON <-> Dart |
| `json_annotation` | ^4.9.0 | JSON için notation |

Kod üretmek:
```bash
cd apps/pos
dart run build_runner build --delete-conflicting-outputs
```

## Paylaşılan Paketler (Monorepo)

`packages/` altında. POS tüm dördünü de kullanır.

| Paket | Amacı |
|---|---|
| `gastrocore_models` | Entity'ler, DTO'lar (tüm app'lerde ortak) |
| `gastrocore_api` | HTTP client (POS, dashboard, online için) |
| `gastrocore_sync` | Sync engine (outbox, pull, WS) |
| `gastrocore_ui` | Shared widget'lar, tema |

## Backend (Go)

- `net/http` (stdlib) - framework yok.
- `gorilla/websocket` - WS hub.
- `pgx` - PostgreSQL driver.
- JWT (`golang-jwt/jwt`).

Server kodu: `server/cmd/server/`. Dış kapsam: bu kılavuz POS odaklı, backend detayı için root `README.md`.

## Dev Toolchain

```bash
flutter doctor           # temel sağlık
flutter pub get          # bağımlılık yükle
flutter analyze          # lint + type check
flutter test             # unit + widget testleri
flutter run              # debug cihazda
flutter build apk --release    # Android release
```

Detaylar: [04-dev-workflow/build-release.md](../04-dev-workflow/build-release.md).
