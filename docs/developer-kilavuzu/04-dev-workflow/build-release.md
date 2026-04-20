# Build ve Release

POS uygulamasini geliştirme ve production için build etmek.

## Prerequisites

| Tool | Version |
|---|---|
| Flutter | 3.35.0 |
| Dart SDK | ^3.9.2 (Flutter ile birlikte) |
| Java | 17 (Temurin) |
| Gradle | 8.x (Android wrapper içinde) |
| Android SDK | API 34 (Android 14) |

`flutter doctor` green olmalı. Özellikle:
- Flutter (Channel stable)
- Android toolchain
- Chrome (web için, opsiyonel)

## Dependencies

```bash
cd apps/pos
flutter pub get
```

Monorepo path dependencies (`gastrocore_models`, `gastrocore_api`, `gastrocore_sync`, `gastrocore_ui`) otomatik çözülür.

## Code Generation

Drift ve Freezed kod üretimi:
```bash
cd apps/pos
dart run build_runner build --delete-conflicting-outputs
```

Değişen `.g.dart` + `.freezed.dart` dosyalari commit'e dahil edilmeli.

**Watch mode** (dev sırasında sürekli):
```bash
dart run build_runner watch --delete-conflicting-outputs
```

## Development (Hot Reload)

```bash
cd apps/pos
flutter run                           # default POS flavor
flutter run -t lib/main_kiosk.dart
flutter run -t lib/main_kds.dart
flutter run -t lib/main_ods.dart
flutter run -t lib/main_waiter.dart
```

Cihaz seçimi:
```bash
flutter devices              # listele
flutter run -d chrome        # web
flutter run -d emulator-5554 # Android emulator
```

Hot reload: `r` (widget tree yeniden build, state korunur).
Hot restart: `R` (uygulama yeniden başlar, state kaybolur).

## Release Build (Android APK)

```bash
cd apps/pos

# Standard release APK
flutter build apk --release

# Verbose (debug için)
flutter build apk --release --verbose

# Split-per-ABI (küçük APK'lar)
flutter build apk --release --split-per-abi

# Specific flavor
flutter build apk --release -t lib/main_kiosk.dart --flavor kiosk
```

Çıktı:
```
apps/pos/build/app/outputs/flutter-apk/app-release.apk
```

## Release Build (App Bundle - Play Store)

```bash
cd apps/pos
flutter build appbundle --release
```

Çıktı: `build/app/outputs/bundle/release/app-release.aab`.

## Web Build

```bash
cd apps/pos
flutter build web --release
```

Çıktı: `build/web/`. Nginx/CDN'e deploy edilebilir.

## Signing

Release APK için keystore gerekli. `android/key.properties` (gitignore'da):
```properties
storePassword=...
keyPassword=...
keyAlias=upload
storeFile=/path/to/upload-keystore.jks
```

`android/app/build.gradle.kts` içinde referans.

**GÜVENLİK**: `key.properties` ve `upload-keystore.jks` asla repo'ya commit edilmez. Keystore kaybolursa Play Store'a yeni APK yüklenemez (hayati belge).

## Release Checklist

Pilot için commit öncesi:
1. `flutter analyze` - uyarı yok.
2. `flutter test` - tüm test pass.
3. `flutter build apk --release` - başarılı.
4. APK sha256 hesaplanır, release notes'a eklenir.
5. Version bump: `pubspec.yaml` `version: 1.3.0+130` -> `1.3.1+131` (hem name hem build number).
6. `CHANGELOG.md` güncelle.
7. Commit + tag (`v1.3.1`).
8. Keystore ile imzalı APK üretilir.
9. Hedef cihaza yüklemeden önce eski versiyon uninstall (schema uyumsuzluğu varsa `adb uninstall` kullan).

`RELEASE_CHECKLIST.md` root'ta daha detaylı bir checklist var.

## AOT Compilation (Dartaotruntime)

Dart AOT ile Flutter Android:
```bash
flutter build apk --release    # zaten AOT
```

Release modda `dartaotruntime` native kod üretir. Startup hızı + performans için debug'dan çok daha iyi.

## Performans Build Flagleri

```bash
# Tree-shake icons (unused icon'lar atılır)
flutter build apk --release --tree-shake-icons

# Obfuscation (Dart sembolleri karıştırılır, reverse-engineering zorlaştırılır)
flutter build apk --release --obfuscate --split-debug-info=build/symbols
```

Obfuscate'le build edersen `build/symbols/` içindeki dosyaları saklamak zorundasın (stack trace decode için).

## APK Boyutu

Hedef: < 50 MB (tek ABI).

Şişiren nedenler:
- Unused locale ARB'leri (`flutter_localizations` tümünü içerir, kırpılabilir).
- SVG yerine PNG asset (SVG çok daha küçük).
- Embedded font'lar (Work Sans 6 variant = ~1 MB, gerekmeyen atılabilir).

`flutter build apk --analyze-size` size breakdown verir.

## Deploy Hedef'leri

### Direct APK install (manual pilot)
```bash
adb install build/app/outputs/flutter-apk/app-release.apk
```

Merchant'a e-mail / WhatsApp üzerinden APK göndermek legal ama Play Store update'i yok. Manuel update.

### Play Store Internal Testing
Play Console'a `.aab` upload. Closed testing track. Merchant email ile invite.

### Play Store Production
Closed testing'den promote. Review süreci 1-3 gün.

## LAN Sync / mDNS Port

APK yüklendikten sonra cihazın LAN içinde mDNS broadcast yapabilmesi için:
- WiFi Multicast permission (Android otomatik verir).
- Port 8787 TCP/UDP boş olmalı (başka app bloke ediyorsa failsafe var).

## Server Build (Go Backend)

Bu kılavuzun kapsamı dışı ama ekip için:
```bash
cd server
go build -o gastrocore-server ./cmd/server
```

Docker:
```bash
docker build -t gastrocore-server:latest ./server
docker-compose up -d
```

## CI (GitHub Actions)

`.github/workflows/`:
- `deploy-online.yml` - online ordering flavor'ını GitHub Pages'e push.
- (POS için CI pipeline tipik: `flutter test`, lint, analyze. Build release el ile tetiklenir.)

Detay için `.github/workflows/` dosyalarına bak.
