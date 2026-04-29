# Tasarım Kararları

Proje boyunca alınan, koddan direkt görünmeyen ama "niye böyle yapılmış?" sorusuna cevap veren kararlar.

## Mimari

### Clean Architecture kullanımı
**Neden**: Feature'ların test edilebilir + birbirinden bağımsız olması için. Swiss compliance gibi feature'lar saf domain sayesinde Flutter ortamı olmadan test edilebilir.

**Alternatif**: MVC veya sadece feature-by-layer. Daha hızlı ama feature yalıtımı zayıf, DB'ye bağlılık UI'dan kaçmaz.

### Monorepo (path dependency ile)
**Neden**: Dört farklı app + dört paket birbirini çok kullanıyor. Tek repo = tek senkron değişiklik.

**Alternatif**: Her paket ayrı repo + pub.dev'de publish. Açık kaynak değil, overhead gereksiz.

### Riverpod seçimi
**Neden**: Compile-time safety + test overridability + provider composability. Provider hiyerarşisi `watch` zincirlerini otomatik yönetiyor.

**Alternatif**: BLoC (daha verbose, boilerplate), Provider eski nesli (null-safety zayıf), GetX (service locator anti-pattern).

### Drift (SQLite)
**Neden**: Type-safe query builder + code generation + migrations. SQLite native Android destekli, offline-first için vazgeçilmez.

**Alternatif**: Hive (NoSQL, queryability zayıf), Isar (hızlı ama Flutter ekosistemi az), raw SQLite (type-safety yok).

### GoRouter
**Neden**: Declarative routing + deep link desteği + Flutter resmi önerisi.

**Alternatif**: Navigator 2.0 raw API (çok verbose), auto_route (code gen overhead), beamer (niche).

## UI/UX

### POS v2 reference design
**Neden**: `.design/pos-v2/POS.html` + `parts.jsx` üzerinden pixel-perfect port. Tasarımcının çıkardığı HTML/JSX referansı "source of truth".

**Alternatif**: Flutter'da scratch'ten yapmak. Hızlı değişiklik gerekirse tasarımcıyla roundtrip sürer, tutarsızlık yaratır.

### Category rengi = Kartın tamamı
**Neden**: Hızlı görsel tarama. Kasiyer 5-6 kategori rengini tanıdıktan sonra isim okumadan bulabilir.

**Alternatif**: Küçük renk chip + beyaz kart. Daha sade ama okuma süresi yüksek.

### Ivory / Midnight palette switch
**Neden**: Farklı saatler / farklı ortamlar. Gün ışığında Ivory, akşam servis Midnight.

**Alternatif**: Tek tema. Kullanıcı tercihi yok, esneklik kaybı.

### Produktbilder on/off toggle
**Neden**: Küçük işletmeler ürün fotoğrafı yüklemek istemiyor (vakit yok). Default off. Full fotoğraflı menu olanlar için "on" seçeneği.

**Alternatif**: Hep kapalı veya hep açık. Bir merchant grubu mutsuz.

### Gear'ı top bar'a taşımak (header strip kaldırma)
**Neden**: Ekran yer az, her pixel değerli. 40px items header stripi tek bir gear ikonu için harcamak gereksiz.

**Alternatif**: Sağ alt FAB. Tablet'te kasiyerin aksiyon alanını bloke eder.

### 6 Schnell tile (8 değil)
**Neden**: Tablet'te 6 tile rahat parmak erişimi. 8 tile sıkışık oluyor.

**Alternatif**: Horizontal scroll ile 20+ tile. Kasiyerin iki elini kullanması gerekir, hız düşer.

### BEZAHLEN gradient + inset highlight
**Neden**: Primary CTA'nın hemen göze çarpmasi. Kasiyer hızlı flow için.

**Alternatif**: Düz yeşil. Daha sade ama "fiziksel tuş" hissi kaybolur.

## Swiss Compliance

### Tax-inclusive pricing (brutto)
**Neden**: İsviçre standardı. Müşteriye gösterilen fiyat KDV dahildir.

**Alternatif**: Netto pricing. Almanya'da da yaygın değil, sadece B2B.

### 5-Rappen rounding sadece nakit
**Neden**: Kağıt para 5-Rappen step'ler halinde. Kart işleminde centler tam.

**Alternatif**: Hep yuvarlama. Kart ödemesinde müşteri fark eder, yanlış bulur.

### Country-per-tenant (per-device değil)
**Neden**: Bir restoran tek ülkeye ait. Swiss restoranda Almanya rate'leri karışmamalı.

**Alternatif**: Per-device country. Aynı restoranda iki cihaz farklı KDV? Fatura tutarsız.

### TSE sadece DE (İsviçre opsiyonel değil - yasak)
**Neden**: Swiss fiscal kuralları TSE zorunluluğu getirmez. Almanya'da zorunlu (KassenSichV).

**Alternatif**: Hep TSE. Swiss için gereksiz Fiskaly ücreti.

### Wallee ana provider
**Neden**: Swiss merchant eşleşmesi en iyi, TWINT native. Local acquirer ilişkisi kolay.

**Alternatif**: Stripe (Swiss pazarı küçük), SumUp (bazı merchant'lar), myPOS (alternatif tutuluyor).

## State Management

### UI provider'lari feature-local, iş mantığı core/feature-global
**Neden**: `v2SelectedLineIdProvider` sadece POS v2 shell'de anlamlı, global yer almamalı. `currentTicketProvider` ise her yerde okunur.

**Alternatif**: Hepsi global. Provider'ların bulunduğu dosya büyür, anlaşılmaz.

### `StateNotifier` > `ChangeNotifier`
**Neden**: Immutability + copy-on-write. State mutation'ları trace edilebilir.

**Alternatif**: `ChangeNotifier` + `notifyListeners()`. Mutable state, debug zor.

### `AsyncValue.when` pattern
**Neden**: Loading + error UI baştan düşünülmüş olur. Default olarak asla "blank screen" problemi yok.

**Alternatif**: `FutureBuilder` veya manuel null check. Error state unutulursa kullanıcıya boş ekran.

## Database

### Schema version 12
**Neden**: Proje boyunca 11 kere schema değişti (yeni feature + yeni tablo). Her değişimde bump.

**Alternatif**: Schema snapshot'ları. Drift zaten migration pattern bekliyor, fork sürdürmek overhead.

### last-write-wins (`updated_at` karşılaştırma)
**Neden**: Çok cihazlı restoran için basit + performant. Kazanan güncel kayıt.

**Alternatif**: CRDT, operational transform. Restoran ticket'larının semantiği buna gerek duymaz (aynı ticket'ta iki cihazdan eş zamanlı edit nadir + audit log ile konstruct).

### SyncQueue outbox pattern
**Neden**: Atomic write (yazma + outbox aynı transaction). Cloud'a push başarısız olsa bile data lokalde sağlam.

**Alternatif**: Dual write (önce local sonra cloud). Cloud başarılı, local fail olursa tutarsızlık.

## Security

### PIN hash (cleartext değil)
**Neden**: Cihaz çalınsa bile kullanıcı PIN'leri rawdb'den okunmasın.

**Alternatif**: Cleartext (yasak). Hash + salt standart.

### JWT in flutter_secure_storage (SharedPreferences değil)
**Neden**: Android Keystore / iOS Keychain hardware-backed. Root'lu cihazda bile token kolay çıkarılmaz.

**Alternatif**: `shared_preferences`. Plain storage, kolay extract.

### Ed25519 lisans imzası
**Neden**: Offline lisans doğrulama. Server'a ulaşamasak bile imza local pub key ile verify.

**Alternatif**: JWT + backend çağrısı. Offline-first için uygunsuz.

## Performance

### `const` constructor kullanımı (maksimum)
**Neden**: Widget rebuild atlamak. Çağırılmayan subtree flag'li.

**Alternatif**: Hepsi mutable. Rebuild cascade ekran atmaya sebep olur.

### `GridView.builder` (GridView değil)
**Neden**: Lazy rendering, sadece görünür kartlar build.

**Alternatif**: `GridView(children: List.generate(...))`. 100 ürünlü menuda frame drop.

### `Image.asset` (cached)
**Neden**: Flutter asset cache tek referansta diskten okur, sonra memory'de tutar.

**Alternatif**: `Image.file` / `Image.network`. Cache manuel yönetim gerekir.

## Developer Experience

### Worktree-based pilot work
**Neden**: Main branch stabil kalsın, pilot deneysel çalışma ayrı dizinde.

**Alternatif**: Feature branch'te commit basıp switch. Merge conflict'te elindeki build gider.

### Belt-and-suspenders fix policy
**Neden**: Pilot deadline'da "bu yeterlidir" diye tek çözüm vermek yerine iki çözümü üst üste koymak. Bkz [mainaxis-size-leak.md](mainaxis-size-leak.md).

**Alternatif**: Minimal fix. Başka edge case'de tekrar break olur.

### `.design/pos-v2/` referansı commit
**Neden**: Tasarım dosyaları repo'da. "Bu ekran niye böyle?" cevabı git'te.

**Alternatif**: Figma/Zeplin'de. Link'ler ölür, erişim izni değişir.

### Türkçe / Almanca karışık
**Neden**: Developer'lar TR, UI DE (Swiss pilot). Kod İngilizce, UI Almanca, docs TR.

**Alternatif**: Hepsi İngilizce. Swiss müşteri kullanıcıya İngilizce UI göstermek demek.

## Gelecek İçin Not

Bu kararlar 2026-Nisan itibariyle geçerli. Pilot sonrası retrospective yapılacak:
- Hangi tercih geri tepti?
- Hangisi doğruydu?
- Neye pişman olmayı düşünüyoruz?

`CHANGELOG.md` + `RELEASE_NOTES.md` pilot retrospective'i yakalayacak.
