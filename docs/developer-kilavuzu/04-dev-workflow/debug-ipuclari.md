# Debug İpuçları

POS'ta sık karşılaşılan sıkıntılar ve nasıl çözüleceği.

## Layout Boşa Çıkıyor (Items Grid Boş)

**Belirti**: Schnell bar görünüyor ama products grid hiç render değil. Ekran orta-alt kısmı bomboş.

**Kök sebep**: POS v2 shell geçmişinde yaşandı. `Column` içindeki `Expanded`'a parent 0 height veriyordu.

### Teşhis stratejisi: LayoutBuilder ile width/height ölç

Geçici debug widget'ı ile Expanded'ın gerçekten ne kadar alan aldığını yazdır:
```dart
Expanded(
  child: LayoutBuilder(builder: (ctx, constraints) {
    print('inner=${constraints.maxWidth}x${constraints.maxHeight}');
    return child;
  }),
);
```

Eğer `inner=1160x0` gibi bir çıktı görüyorsan o Expanded yüksek kazanamıyor demektir.

### Çözüm A: MainAxisSize.min
İç Column'larda:
```dart
Column(
  mainAxisSize: MainAxisSize.min,   // *** kritik
  children: [...]
)
```

Default `.max` olduğunda parent'tan infinite height ister, bu da outer constraint'i bozar.

### Çözüm B: Explicit SizedBox height
Fixed height'la wrap et:
```dart
SizedBox(height: 108, child: _SchnellBar(products: allProducts))
```

Grid'in parent'ı bu sayede net bir height biliyor, Expanded kalan alanı doğru alıyor.

Detaylı hikaye: [05-kararlar-ve-bilinmesi-gerekenler/mainaxis-size-leak.md](../05-kararlar-ve-bilinmesi-gerekenler/mainaxis-size-leak.md).

## Riverpod Provider `late` Hatası

**Belirti**:
```
LateInitializationError: Field '_x@...' has not been initialized.
```

**Kök sebep**: `StateNotifier` içinde `late final` alan, constructor'da set edilmeden read edildi.

**Çözüm**: Alanı `late` yerine nullable yap veya constructor'da init et. `late` değil `late final` daha kritik - sadece bir kere set edilebilir, try-catch'e alınamaz.

## "Menü konnte nicht geladen werden" Hatası

**Belirti**: Products grid yerine Almanca hata mesajı.

**Teşhis**: `productsAsync.when(error: (err, _) => ...)` branch'i tetiklendi.

**Olası sebepler**:
1. **DB schema mismatch** - APK farklı schemaVersion. `adb uninstall ch.twotech.gastrocore.pos` sonra reinstall.
2. **Drift migration eksik** - schema bumped ama onUpgrade case yok. `app_database.dart:109`'da ekle.
3. **Menu seeding yok** - DB boş. `AppDatabase.onCreate` veya first-run seeder check.
4. **Cloud down, local cache boş** - ilk açılışta cloud sync gerekiyor.

DevTools'tan stack trace al: `flutter run` çıkışında exception satırı.

## Hot Reload Widget'ı Güncellemiyor

**Belirti**: Kod değiştiriyorum ama ekran aynı kalıyor.

**Sebepler**:
- Widget `const` constructor - yeni value alamıyor. Hot restart gerekir: `R`.
- Provider state'i değişmiş değil, sadece build fonksiyonu değişmiş. Hot restart.
- Build runner çıktısı (`.g.dart`) stale. `dart run build_runner build --delete-conflicting-outputs` sonra hot restart.

## Provider Sonsuz Rebuild

**Belirti**: UI atıyor, CPU yanıyor.

**Sebep**: `ref.watch` içinde değişkeni provider'a geri yazıyor.

Örnek bad code:
```dart
final counter = ref.watch(counterProvider);
ref.read(counterProvider.notifier).state = counter + 1;   // loop!
```

**Çözüm**: `watch` sadece okur, yazmak için `read` ve sadece event handler içinde.

## Drift "Unknown column" Runtime Hatası

**Belirti**:
```
DriftRemoteException: no such column: products.image_path
```

**Sebep**: Schema değişti, migration yok veya build_runner çalışmadı.

**Çözüm**:
```bash
dart run build_runner build --delete-conflicting-outputs
```

Sonra `app_database.g.dart`'un commit'e dahil olduğundan emin ol.

Cihazda eski APK varsa migration case eklemen gerek:
```dart
onUpgrade: (m, from, to) async {
  if (from < 12) {
    await m.addColumn(products, products.imagePath);
  }
},
```

## TWINT/Wallee Terminal Yanıt Vermiyor

**Belirti**: Payment ekranı spinner'da takılı kalıyor.

**Teşhis**:
1. Wallee web dashboard'da transaction status'u kontrol.
2. Terminal ekranını gör (fiziksel).
3. POS log'unda HTTP exception var mı?

**Sebepler**:
- Terminal offline (WiFi/4G yok).
- Wallee API key expired.
- Merchant ID yanlış config.

**Çözüm**: 3 dakika timeout sonrası otomatik void. Kasiyer nakit ödeme alabilir.

Debug mode: `WalleeConfig.sandbox()` ile test ortamında yeniden dene.

## Touch Target Tıklanmıyor

**Belirti**: Kart'a dokunuyorum, hiçbir şey olmuyor.

**Sebepler**:
- Parent `IgnorePointer` veya `AbsorbPointer` içinde.
- Stack'de üste başka widget binip bloke ediyor (z-order).
- `InkWell` constructor'da `onTap: null` (disabled).

**Teşhis**: DevTools Flutter Inspector -> Select Widget mode. Tıklayınca hangi widget selecte oluyor?

## Hot Reload + Global Provider Reset

Hot reload sonrası bazen `currentTicketProvider` reset oluyor. Çünkü provider `StateNotifier`'ı yeniden yaratılıyor.

**Çözüm**: Hot restart kullan (`R`) veya `autoDispose` ekleme ki reload'da state düşmesin.

## APK Yüklenmiyor - "Uyumsuz"

**Belirti**: `adb install` -> `INSTALL_FAILED_UPDATE_INCOMPATIBLE`.

**Sebepler**:
- Schema version düştü (v12 -> v11). Downgrade yasak.
- Signing key değişti.
- Package name çakışması.

**Çözüm**:
```bash
adb uninstall ch.twotech.gastrocore.pos
adb install build/app/outputs/flutter-apk/app-release.apk
```

Uninstall cihazdaki tüm lokal veriyi siler. Cloud sync'ten geri gelecek.

## Release Build Başarısız

**Belirti**: `flutter build apk --release` fail, assembleRelease gradle error.

**Sık sebepler**:
- R8 minify hatası (obfuscate + reflection uyumsuz).
- ProGuard rule eksik.
- NDK version uyumsuz.

**Çözüm**:
```bash
flutter clean
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter build apk --release --verbose
```

`--verbose` çıktısında hangi gradle task fail olduğunu gör.

## Flutter Analyze Uyarıları

```bash
flutter analyze
```

Kabul edilebilir uyarı yok, hepsi temiz olmalı. Sık uyarılar:
- `unused_import` - elle temizle.
- `prefer_const_constructors` - `const` ekle.
- `deprecated_member_use` - yeni API'ye geç.

`analysis_options.yaml` ile kurallar configured.

## Performans: Frame Drop

**Belirti**: Scroll tırtıklı, UI donma.

**Araç**: Flutter DevTools -> Performance tab.

**Sık sebepler**:
- `GridView`'in `itemCount` çok büyük + her item build'de expensive iş.
- `Image.asset` + cache yok.
- `StreamProvider` sürekli emit ediyor + tüm widget rebuild oluyor.

**Çözüm**: `const` constructor, image cache, provider `select` ile precise watch.

## Logging

Production log için `core/monitoring/`:
```dart
AppMonitoring.logError('payment failed', error: e, stackTrace: st);
```

Dev için:
```dart
debugPrint('...');
```

Crash'ler crash analytics'e otomatik gider (Sentry/Crashlytics config'li).

## adb Komutları (Android)

```bash
adb devices                           # bağlı cihaz listesi
adb logcat | grep gastrocore          # uygulama logları
adb shell pm clear ch.twotech.gastrocore.pos   # cihaz datasını sil
adb install -r app-release.apk        # reinstall (data korunur)
adb shell am start -n ch.twotech.gastrocore.pos/.MainActivity
adb pull /sdcard/receipts/abc.pdf     # cihazdan dosya çek
```

## Web Build Debug

Web build CORS sıkıntıları çıkarır. Backend CORS header'larını kontrol et. LAN sync web'de çalışmaz (browser TCP socket veya mDNS yok).
