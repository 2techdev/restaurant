# GastroCore POS — Developer Handoff (Restaurant / POS Tarafı)

> **Hedef okuyucu:** Projeye yeni giren bir Claude oturumu veya developer.
> Bu dosya **self-contained**'dir; başka bir dosya okumadan pilot branch'te üretken olabilmeniz için yeterli bağlam verir.
>
> **Tarih:** 2026-04-29
> **Pilot APK SHA-256 (son build):** `715bf72b70ad19538a1132bd0c6c0557b6aab3ae6f0f2f5e3867801bd5605946`
> **Not:** APK yeniden build edilmedi — son build `8913cc4` baz alıyor; M1–M5 grubu (aşağıda) sonrası APK üretmek için §3'teki komut dizisini koşun.

---

## 0. TL;DR — İlk 60 Saniye

```bash
# 1. Worktree'ye gir
cd E:/Project/Restaurant/.claude/worktrees/jolly-final

# 2. Branch doğrula
git branch --show-current   # → claude/pilot-final olmalı
git log --oneline -3

# 3. Bağımlılıklar + codegen
cd apps/pos
flutter pub get
dart run build_runner build --delete-conflicting-outputs

# 4. Sanity: analyze + touched test'ler
flutter analyze --no-fatal-infos
flutter test test/features/

# 5. Pilot APK build
flutter build apk --release --flavor pos
cp build/app/outputs/flutter-apk/app-pos-release.apk E:/Project/Restaurant/pilot/app-pos-release.apk
sha256sum E:/Project/Restaurant/pilot/app-pos-release.apk
```

**Üç altın kural:**
1. **Pilot APK her zaman `jolly-final` worktree'sinden üretilir.** `sweet-feistel-4e5dfc` TERKEDİLMİŞ — üzerine rebase yapmayın, merge etmeyin, APK üretmeyin.
2. **`claude/pilot-final` push edilmez, main'e merge edilmez.** Pilot branch — sadece APK üretir, sahaya gider.
3. **Klavye kısayolu EKLEMEYİN.** POS donanımı tablet-only; `LogicalKeyboardKey` kullanımı yoktur ve olmamalıdır.

### M1–M7 — Pilot Operatör Revizyon Paketi (2026-04-29)

| Madde | Tema | Ana dosya |
|-------|------|-----------|
| **M1** | Modifier dialog v2 shell'de wire-up; BackOffice → Modifier yönet entry | `pos_v2_shell.addProductToCurrentTicket`, `menu_management_tab.dart` |
| **M2** | Settings → POS Back butonu `/pos`'a gidiyor; 5 dilde `settingsBackToPos` | `settings_screen._navigateBack` |
| **M3** | Çoklu gast için seat tab'ları (Tümü / Person N) + orphan seat sweep | `_SeatTabs`, `activeSeatProvider` |
| **M4** | Geçici masa: schema v19 + numpad + audit lifecycle + payment cleanup | `_TempTableDialog`, `restaurant_tables.is_temporary`, `AuditAction.temporaryTable*` |
| **M5** | Tek "Senden" — per-gang fire chip toggle (default OFF) | `RestaurantSettings.enablePerGangFire` |
| **M6** | Ürün tile'ında açıklama satırı kaldırıldı; sadece ad + fiyat | `_PCard` (pos_v2_shell.dart) |
| **M7** | Operatör seçilebilir tile boyutu — Klein / Mittel / Gross (S 0.85x / M 1.0x / L 1.2x) | `RestaurantSettings.posTileScale`, `_PosTileSizeSegmented` |

Bu paket içerikleri §3.1 Build, §4.3 Schema (v19), §5 Feature Matrisi, §7 Commit Geçmişi ve §8 AuditAction tablosunda detaylı. APK henüz rebuild edilmedi — §3 komut dizisini koş ve §10'daki SHA'yı güncelle.

---

## 1. Proje Kimliği

- **Proje:** GastroCore POS — İsviçre pazarına yönelik restoran POS sistemi
- **Pilot müşteri:** Zurich kafe (tenant: `pilot-zurich-001`)
- **Teknoloji:** Flutter monorepo, **multi-flavor** (`pos`, `kds`, `kiosk`, `ods`, `waiter`)
- **Toolchain:**
  - Flutter **3.41.6** (channel stable, 2026-03-25 db50e20168)
  - Dart **3.11.4**
  - Android build: Gradle + AGP (flavor tabanlı `assemblePosRelease`)
- **Dil:** Flutter tarafı Dart. Developer kılavuzu Türkçe, kod kommentleri Almanca/İngilizce karışık, UI i18n = DE/EN/FR/IT/**TR**
- **Kurulum platformu (pilot):** Android tablet (landscape 1920×1200)

### 1.1 Monorepo Yapısı

```
E:\Project\Restaurant\.claude\worktrees\jolly-final\
├── apps/
│   ├── pos/           ← PILOT — ana flavor, bu handoff bunu anlatıyor
│   ├── kds/           ← Kitchen Display (ikincil)
│   ├── kiosk/         ← Self-service kiosk (MVP)
│   ├── ods/           ← Order Display (ekran)
│   └── waiter/        ← Waiter handheld (MVP)
├── packages/          ← Paylaşılan (minimal şu an)
├── docs/
│   └── developer-kilavuzu/   ← Türkçe iç doküman — bkz. §9
└── pilot/             ← Aslında repo DIŞI: E:\Project\Restaurant\pilot\
```

**Pilot flavor:** `pos` (ana hedef). Diğer flavorlar pilot için ikinci planda, aynı codebase'den build edilir.

---

## 2. Branch Stratejisi — ÖNEMLİ

```
main
 └─ claude/jolly-hodgkin-1ca89c        ← base (jolly lineage başlangıcı)
     └─ claude/pilot-final              ← ÜRETİM BRANCH'İ (burada çalışıyoruz)
                                          APK buradan üretilir

[TERKEDİLDİ] claude/sweet-feistel-4e5dfc  ← DOKUNMA
```

### Kurallar

- **Pilot branch'i sadece `claude/pilot-final`.** Her commit buraya gider.
- **Sweet-feistel terkedildi** (memory kuralı: "pilot APK always builds from jolly-final; never rebase onto sweet-feistel"). Dosyaları orada kalabilir; o worktree'de **kod yazmayın**, **APK üretmeyin**.
- **Push yok.** Uzak repoya push edilmez. APK = deliverable, branch = sadece yerel tarih.
- **Main'e merge yok.** Pilot branch'i main'e dönmeyecek; pilot bittiğinde ayrı bir cherry-pick / temizlik planı yapılacak.
- **Rebase:** Sadece `claude/jolly-hodgkin-1ca89c` üzerine ihtiyaç halinde fast-forward. Sweet-feistel üzerine **asla**.
- **Commit stili:** Conventional Commits (`feat(pos):`, `fix(orders):`, `test(reports):`, `docs:`, `chore(lint):`, `refactor(pos):`, `refine(pos):`).

### Worktree bilgisi

`jolly-final` worktree yolu: `E:\Project\Restaurant\.claude\worktrees\jolly-final\`
Ana repo: `E:\Project\Restaurant\` (main branch'i orada)

---

## 3. Build & Test Komutları

```bash
# Deps
flutter pub get

# Codegen (drift, freezed, riverpod_generator — gerekli!)
dart run build_runner build --delete-conflicting-outputs

# Analyzer
flutter analyze --no-pub
flutter analyze --no-fatal-infos      # pilot-gate: info çıksa bile geçer

# Test (flavor gerekmez)
flutter test                                          # tüm suit
flutter test test/features/                           # sadece feature testleri
flutter test test/features/orders/widgets/pos_v2_footer_test.dart  # nokta atışı

# Golden test baseline (1920x1200)
flutter test test/goldens/

# Pilot APK (release, pos flavor)
flutter build apk --release --flavor pos
# Çıktı: build/app/outputs/flutter-apk/app-pos-release.apk

# Pilot klasörüne kopya
cp build/app/outputs/flutter-apk/app-pos-release.apk \
   E:/Project/Restaurant/pilot/app-pos-release.apk

# SHA-256 imza (release notes için)
sha256sum E:/Project/Restaurant/pilot/app-pos-release.apk
```

### Test durumu (2026-04-23)

- **1810 passed / 41 failed** — 41 failure **eski seed / schemaVersion / module_order key** kaynaklı, pilot-değişiklikleri ile ilgisi yok, post-pilot temizlik backlog'ta (bkz. §12).
- **Touched-module green:** footer (5), audit (27+5 kendi + extended), sync, goldens → tümü geçiyor.

---

## 4. Mimari Özet

### 4.1 Katmanlar (Clean Architecture)

Her feature `apps/pos/lib/features/<name>/`:

```
features/orders/
├── domain/
│   ├── entities/       ← immutable POJO (freezed, opsiyonel)
│   └── repositories/   ← abstract contract
├── data/
│   ├── datasources/    ← DAO (drift)
│   ├── models/         ← DB <-> entity mappers
│   └── repositories/   ← concrete impl
└── presentation/
    ├── providers/      ← Riverpod provider'lar
    ├── screens/        ← route-level widget
    ├── shells/         ← layout shell'ler (örn. pos_v2_shell.dart)
    └── widgets/        ← reusable widget
```

### 4.2 State Management — Riverpod 2.6

- **`Provider`** → pure/sabit (repoProvider, serviceProvider)
- **`StateProvider`** → basit mutable (filter flag, selection)
- **`StateNotifierProvider`** → karmaşık mutable flow (ticket düzenleme, oturum)
- **`FutureProvider` / `AsyncValue`** → async fetch + loading/error
- **`ConsumerWidget`** / **`ConsumerStatefulWidget`** → widget'lar
- **Override-heavy test** → `ProviderScope(overrides: [...])` testlerin bel kemiği

**Critical provider örneği:** `currentTicketProvider` — tüm POS akışının ortası. Tüm butonlar onu okur/günceller.

### 4.3 Veritabanı — Drift (SQLite offline-first)

- Path: `apps/pos/lib/core/database/app_database.dart`
- **Current schema version: 19** (`schemaVersion => 19`)
- Migration dosyaları: `lib/core/database/migrations/`

#### Schema history (pilot-relevant)

| Ver | İçerik | Commit SHA |
|-----|--------|------------|
| v15 | `products.is_available` flag (sold-out toggle) | `6937ced` |
| v16 | `tickets.customer_id` (CRM link) | `905d9d7` |
| v17 | Receipt counter unique constraint + atomik `receipt_counter` tablosu | `5b5c5e4` |
| v18 | Combo / set menu tabloları (`combos`, `combo_components`) | `9879731` |
| v19 | `restaurant_tables.is_temporary` (M4 ad-hoc masa lifecycle) | M4 |

### 4.4 Tema — V2Palette / Kinetic

- `ThemeExtension<V2Palette>` — tüm renkler buradan gelir
- `context.v2` getter → `Theme.of(context).extension<V2Palette>()!`
- **Dark mode:** `ThemeMode.dark/light/system` — `settingsProvider`'dan canlı okunur
- **Color customization:** Settings → Theme bölümünden operatör kendi paletini seçer
- **High contrast + text scale:** Accessibility ayarları
- **Vendored tokens:** `apps/pos/lib/core/theme/kinetic_theme.dart` — son commit `cb8a570`'te shift-open redesign için vendor edildi

### 4.5 Flavor sistemi

Flavor `pos` → `FLUTTER_FLAVOR=pos`, `AppConfig.flavor` üzerinden runtime dallanma (router, seed, feature flag override).

---

## 5. Feature Matrisi — Pilot'ta Çalışanlar

Her satır: **özellik — kısa açıklama — ana dosya / commit**.

### 5.1 Masa Yönetimi (Tables)

| Özellik | Açıklama | Nerede |
|--|--|--|
| Masa planı (floor plan) | 2D grid + kat seçimi | `features/tables/presentation/screens/floor_plan_screen.dart` |
| Masa durumu | `free/open/occupied/dirty` otomatik lifecycle | `7c4e500` + `3950f33` |
| Split table | Bir masanın bon'unu böl | existing |
| Transfer | Bonu farklı masaya taşı | existing |
| Merge | İki masayı birleştir, audit'li | `b671bf7` |
| Bill split | Ödeme tarafında kalem/kişi böl | `AppRoutes.splitBillFor(id)` |
| **Geçici masa (yeni — M4)** | Topbar "Tisch +" → numpad → ad-hoc tablo + ticket; ödeme/iptal sonrası otomatik soft-delete + audit | schema v19 + `_TempTableDialog` |

### 5.2 Sipariş Akışı (Orders)

| Özellik | Açıklama | Nerede |
|--|--|--|
| **Modifier (yeni — M1)** | Ürün seçenekleri (`+espresso`, `-laktoz`); v2 shell artık modifier dialog'u tetikliyor | `pos_v2_shell.addProductToCurrentTicket` |
| **Tile içeriği — sadece ad + fiyat (M6)** | Pilot kararı: ürün tile'ından açıklama satırı kaldırıldı, kasiyer gözü doğru butona daha hızlı oturuyor | `_PCard` |
| **Operatör tile zoom (M7)** | Klein/Mittel/Gross 3 preset, persist edilen scale font + tile boyutuna çarpılıyor | `RestaurantSettings.posTileScale` |
| Kalem notu | Kişisel komentar satırı | existing |
| Kombo / Set menü | v18 schema + ComboDao | `9879731` |
| Takeaway / Dine-in | Ticket `orderType` alanı | `TicketEntity.orderType` |
| Gang 1/2/3 | Kuryer çağrı sıraları (lifecycle persisted) | `7a509d9` |
| **Sipariş Ver** (yeni) | Table mode footer primary — sendToKitchen + audit + floor plan | `8913cc4` |
| Zur Kasse (yeni) | Table mode footer secondary — ödemeye git | `8913cc4` |
| Schnell grid | Hızlı ürün grid'i (1-satır bar) | `053318d` |
| Kategori rail | Renk-coded kategori rail'i (sol/sağ handedness) | `2fd9c3c` + `d57968d` |
| **Çoklu kişi seat (yeni — M3)** | Order header "Tümü / Kişi N" tab strip; aktif seat yeni item'a yapışır; orphan seat'ler guest count düşünce snackbar+temizlik | `_SeatTabs` + `activeSeatProvider` |
| **Tek "Senden" (yeni — M5)** | Per-gang fire chip default OFF; tek global Senden ; toggle Settings → Workflow | `RestaurantSettings.enablePerGangFire` |

**Pilot UX bug fix (bu oturum — `8913cc4`):**
Tablet modunda `ticket.tableId != null` ise footer artık iki butonlu: **Sipariş Ver** (ana CTA, sendToKitchen + audit `orderSentToKitchen` + `/tables`'a dön) + **Zur Kasse** (save + `/payment/:id`). Eski `Schliessen / Neuer Bon / Senden` triad'ı sadece takeaway (tableId == null) modunda kalır. Tablo bon'ları kasıtlı olarak ödenmemiş duruyor → "nicht bezahlt" uyarı dialog'u table mode'ta silent-approve.

### 5.3 Ödeme (Payment)

| Özellik | Açıklama | Nerede |
|--|--|--|
| Mixed tender | Birden fazla ödeme aracı (cash + kart + voucher) | `8125785` |
| Bahşiş (tip) | Yüzde / sabit tutar | existing |
| Voucher | Hediye çeki | existing |
| TWINT / Wallee | İsviçre ödeme entegrasyonu | existing |
| Storno / refund | İsviçre fiscal compliance katı kuralları | `0823d48` |
| Loyalty redeem | Puan kırdırma ödeme akışında | `d6cf2d7` |
| Split bill | Kalem/kişi/yüzde | existing |

### 5.4 Raporlar

| Özellik | Açıklama | Nerede |
|--|--|--|
| Z-raporu | Gün-sonu sealed snapshot + monotonicity guard | `64ee0f4` + `07caba1` |
| Monthly / Period | Tarih aralıklı | `a26f158` |
| Hourly heatmap | Saat-bazlı ısı haritası | `01b9cc5` |
| Per-waiter | Garson bazlı performans | `01b9cc5` |
| PDF export | Tüm raporlar PDF'e | `64ee0f4` |

### 5.5 Müşteri / CRM

| Özellik | Açıklama | Nerede |
|--|--|--|
| Customer chip (topbar) | Aktif ticket'a bağlı müşteri rozeti | `6d8d18f` |
| Arama / link / unlink | Topbar dialog | `6d8d18f` |
| `customer_id` on tickets | Schema v16 | `905d9d7` |
| Loyalty | Puan kazanım + kırdırma | `d6cf2d7` |
| Loyalty konfigürasyon | Earn rate / redemption / tier | `e1ed6b0` |
| GDPR export + anonymize | Müşteri verisi dışa aktar + silme | `80f277b` |

### 5.6 Menü

| Özellik | Açıklama | Nerede |
|--|--|--|
| Sold-out / 86'd toggle | Uzun-bas ile kullanım-dışı işareti + audit | `8760312` + `40b22e2` |
| Envanter | **KALDIRILDI** (user kararı) | `9263f71` — revert |
| Availability changed audit | `productAvailabilityChanged` | `7c6c3a8` |
| Kombo editor | v18 ile | `9879731` |

### 5.7 Happy Hour / Pricing

| Özellik | Açıklama | Nerede |
|--|--|--|
| Kural editörü | BackOffice'te kalıcı happy-hour kuralı | `711e93a` |

### 5.8 Vardiya / Mesai (Shifts)

| Özellik | Açıklama | Nerede |
|--|--|--|
| Clock in/out | PIN'den ayrı, Mesai paneli | `d4bf480` |
| Break / pause / overtime | Ara başlat/bitir + fazla mesai | `bb920c7` |
| Cash variance audit | Gün sonu kasa farkı loglanır | `2901503` |
| Shift open redesign | Configurable toggle | `4c757f3` |

### 5.9 Fiş / Receipts

| Özellik | Açıklama | Nerede |
|--|--|--|
| İlk fiş yazdırma | Payment flow'da doğrudan, audit **YOK** | existing |
| Reprint | Sonraki her yazdırma — **KOPIE** banner + audit | `3983358` |
| Dijital fiş (email/QR PDF) | Share sheet ile gönder — audit | `d7abab4` |
| Atomik counter + UNIQUE | Per-tenant benzersiz numara | `5b5c5e4` |

### 5.10 İsviçre Compliance

| Özellik | Açıklama | Nerede |
|--|--|--|
| MWST oranları | 2.6% / 3.8% / 8.1% | entity + seed |
| fiscal_ch export | MWST CSV/JSON dışa aktar | `0385be3` |
| Audit log retention | 10 yıl saklama + purge API | `9b2ffd3` |
| Z-seal | Sealed Z-rapor (değişmez snapshot) | `64ee0f4` |

### 5.11 Ayarlar

| Özellik | Açıklama | Nerede |
|--|--|--|
| Dark mode | Light/Dark/System | `9ce0511` |
| Handedness (sol/sağ el) | Kategori rail mirror | `460f81e` + `d57968d` |
| Renk customization | Palette picker | `e6e8e03` + `7fc4fc7` |
| Action button editor | Samba-tarzı konfigüre edilebilir butonlar | `2e07ea3` + `b760c18` |
| Role-based action visibility | Rol bazlı aksiyon | `8e48395` |
| High contrast + text scale | A11y | `32e73f5` |
| Update channel | Manifest-based self-update checker | `d064e3b` |
| **Per-gang fire toggle (M5)** | Default OFF — bistro/fast-food konsepti tek Senden; ON → fine-dining her gang ayrı fire | Settings → Restaurant → WORKFLOW |
| **Geçici masa toggle (M4)** | Default ON — sales shell'de "Tisch +" pill aktif; OFF → topbar pill gizlenir | Settings → Restaurant → WORKFLOW |
| **POS tile size (M7)** | 3 preset (Klein 0.85x / Mittel 1.0x / Gross 1.2x); v2 shell'in `_SchnellTile` ve `_PCard` font-size'larını + `_ItemsGrid` row height'ını çarpıyor | Settings → Restaurant → WORKFLOW |
| **Settings → POS Back (M2)** | Top bar'daki Back tuşu artık `/home` yerine `AppRoutes.pos`'a gidiyor; etiket 5 dilde i18n'lı (`settingsBackToPos`) | `_navigateBack` |

### 5.12 i18n

| Özellik | Açıklama | Nerede |
|--|--|--|
| DE/EN/FR/IT | Baseline | existing ARB |
| **TR** (yeni) | Türkçe locale, 157 key | `d855d00` |
| ARB parity guard | Test — key set eşit mi? | `a411b7a` |

### 5.13 A11y

| Özellik | Açıklama | Nerede |
|--|--|--|
| Semantics labels | Kritik widget'larda | `cb12432` + `16dcd50` |
| Golden test baseline | 1920×1200 | `4710a62` |
| PIN pad / table tile / payment method | Ekran okuyucu labels | `16dcd50` |

### 5.14 Sync / Offline

| Özellik | Açıklama | Nerede |
|--|--|--|
| Offline-first | Drift local + server eventual sync | core |
| Dead Letter Queue (DLQ) | Poison event parked for inspection | `9875e63` |

### 5.15 Lisans / Aktivasyon

| Özellik | Açıklama | Nerede |
|--|--|--|
| Feature flags | `FeatureFlag` enum | `core/features/` |
| License gate | Aktivasyon önünde yetki | existing |

### 5.16 PIN / Auth

| Özellik | Açıklama | Nerede |
|--|--|--|
| PIN-only login | Kullanıcı seçim ekranı YOK — PIN → staff | `0a9d347` |
| User logged in/out audit | Oturum eventleri | `AuditAction.userLoggedIn/Out` |
| Clock-in/out **ayrı** | Oturum loginden bağımsız | `AuditAction.userClockedIn/Out` |

### 5.17 Son-anda P0 fix'ler (bu pilot)

- `2243044` — **P0 pilot blocker**: empty menu + wrong landing
- `ffa83f0` — diagnostic badge sweet-lineage provider'larla uyumlu hale geldi

---

## 6. Pilot-Specific Kurallar (Memory + Teamwork)

Aşağıdakiler hem memory hem de takım tarihinden: **ihlal = çöpe atılmış pilot**.

1. **jolly-final lineage only.** APK, refactor, yeni feature — hepsi `jolly-final` worktree'sinde. `sweet-feistel-4e5dfc` terk edildi.
2. **Klavye kısayolu ASLA.** POS tablet-only. `LogicalKeyboardKey`, `KeyboardListener`, `Shortcut` widget yoktur, olmayacak.
3. **Envanter KALDIRILDI.** User kararı (`9263f71` revert). Sadece "sold-out / 86'd toggle" var. Envanter girmeye çalışma.
4. **Push YOK.** `git push` / `git push --force` hiçbir branch'te koşulmaz. APK = deliverable.
5. **Main'e merge YOK.** Pilot bittiğinde ayrı temizlik planı yapılacak.
6. **`--no-verify` kullanma.** Hook fail ederse kök neden bul.
7. **Fine dining shell ≠ POS v2 shell.** Pilot `PosV2Shell` kullanıyor — `FineDiningShell` var ama ayrı bir experiment, karıştırma.
8. **Push'sız commit imzası:** `Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>` heredoc ile.
9. **SnackBar testlerinde `pumpAndSettle` KULLANMA.** 2s duration fake clock'ta stall yapar — `pump() + pump(Duration(milliseconds: 50))` ikili kullan. (Bu pilot'ta çok vakit yedi.)
10. **Seed tenant:** `pilot-zurich-001`. Test-fake'lerde `tenant-test`.

---

## 7. commit geçmişi (pilot-final branch, base'den sonra)

Aşağıda `git log --oneline claude/jolly-hodgkin-1ca89c..HEAD` — tersten kronolojik (en yeni üstte):

```
[M1–M7 — 2026-04-29] Pilot operatör revizyon paketi (henüz hash atanmadı):
  feat(pos): hide product description + adjustable tile scale [M6, M7]
  feat(tables): temporary tables — schema v19 + numpad + audit lifecycle [M4]
  feat(orders): per-guest seat tabs in pilot v2 shell [M3]
  feat(orders): wire up modifier dialog in pos_v2_shell [M1]
  feat(orders): single global Senden + per-gang fire toggle [M5]
  fix(settings): Back navigates to /pos with localized "Zurück zum POS" label [M2]

8913cc4 fix(pos): table-mode footer → Sipariş Ver / Zur Kasse, drop bogus unpaid dialog
9875e63 feat(sync): dead-letter queue for poison offline events
f8c0ffa docs: sync pilot Blok 2 / 3 status across top-level docs
4710a62 test(goldens): baseline screens at 1920x1200
16dcd50 feat(a11y): Semantics labels on PIN pad, table tiles, payment methods
d064e3b feat(updates): manifest-based self-update checker with audit trail
d855d00 feat(l10n): add Turkish (tr) locale with 157 keys
e1ed6b0 feat(loyalty): configurable earn rate, redemption ratio, tier thresholds
bb920c7 feat(shifts): break/pause + overtime tracking on Mesai panel
d7abab4 feat(orders): digital receipt with QR PDF share + audit trail
01b9cc5 feat(reports): hourly heatmap + per-waiter performance breakdown
80f277b feat(gdpr): customer data export + anonymisation service
9879731 feat(menu): combo / set menu — ComboDao + schema v18 + entity
b671bf7 feat(tables): audit table merges + E2E integration test
9b2ffd3 feat(audit_log): 10-year retention + purge API
0385be3 feat(fiscal_ch): Swiss MWST export — CSV + JSON from Reports Center
5b5c5e4 feat(receipts): per-tenant atomic counter + UNIQUE constraint (schema v17)
8125785 feat(payments): mixed tender payments — running balance + tender list
7e3ae35 fix(pos): wire topbar search to productSearchProvider
7eea17b fix(pos): make POS v2 shell react to dark-mode theme
d57968d fix(pos): mirror category rail in left-handed mode
1ed8da5 docs(kilavuz): sync developer guide with pilot-final features
0823d48 feat(payments): Swiss storno refund compliance hardening
d4bf480 feat(shifts): per-waiter Mesai clock in/out panel
711e93a feat(pricing): persistent happy-hour editor in Back Office
2901503 feat(shifts): audit cash reconciliation variance on day close
3983358 feat(orders): audit receipt reprints with visible KOPIE banner
d6cf2d7 feat(payments): loyalty redemption in payment flow
6d8d18f feat(pos): customer chip in topbar + link/unlink dialog
905d9d7 feat(orders): customer_id on tickets + migration v16
40b22e2 test(menu): unavailable toggle end-to-end
8760312 feat(pos): unavailable product visual + tap disabled + long-press toggle
7c6c3a8 feat(menu): unavailable toggle in product edit form
6937ced feat(menu): is_available flag on product + migration v15
9263f71 revert(inventory): drop full inventory system per user decision
1805ec6 feat(inventory): low-stock badge on product card
6a74c8a feat(inventory): decrement stock on ticket close
0910f1e feat(inventory): route + rail tile behind FeatureFlag.inventory
8e48395 feat(action-buttons): role-based visibility
cb12432 feat(a11y): semantics labels on critical UI
32e73f5 feat(a11y): high contrast mode + text scale settings
a411b7a test(l10n): ARB parity guard + Swiss-typography rule doc
c4d6c70 fix(providers): actionable error + shared test overrides
6faa748 feat(core): ErrorHandler util for consistent snackbar feedback
4119b16 chore(lint): clear 44 analyzer infos (withOpacity, tearoffs, container lints)
7d60f5a fix(tests): unskip order_panel_test and align with uppercase gang labels
d108743 chore(tests): implement ThemeCustomization in fake SettingsRepository
07caba1 test(reports): Z-seal monotonicity + snapshot round-trip coverage
64ee0f4 feat(reports): reports center screen + PDF export + sidebar entry
a26f158 feat(reports): repository + Z/monthly/period generators
460f81e feat(layout): left-handed mirror mode for POS shell
e6e8e03 feat(theme): color picker section in Settings
7fc4fc7 feat(theme): customization provider + overlay at MaterialApp level
d8ecbb7 feat(action-buttons): seed default buttons + integration test
2e07ea3 feat(settings): action buttons configuration screen
6fad782 feat(action-buttons): POS shell strip + dispatcher
b760c18 feat(action-buttons): schema + repository + provider
9ce0511 feat(theme): dark mode with settings toggle
622fe13 fix(orders): persist items added after first gang fire
3950f33 test(integration): table lifecycle end-to-end regression guard
7a509d9 feat(orders): persist gang lifecycle and expose SERVE action
7c4e500 feat(tables): automatic table occupancy lifecycle
e3d1628 docs: developer kilavuzu for POS project
a20acc3 refine(pos): Schnell tiles fill full allocated height for tablet tap targets
c6ea47a refine(pos): remove items header strip, move Tweaks gear to top bar
efccaab refine(pos): drop category header + 6-wide Schnell + taller cards
053318d redesign(pos): 1-row Schnell bar + text-only category cards
f57970f fix(pos): use MainAxisSize.min + fixed-height header/schnell
7e1eedb debug(pos): inner LayoutBuilder readout for collapsed region
87e10ff debug(pos): expose _ItemsWrap LayoutBuilder constraints in strip
d857cc2 debug(pos): lime/red/purple visibility markers
8b7ab92 debug(pos): release-visible amber strip above items grid
178ad78 fix(pos): wire v2 shell to real providers — products + favorites now render
cc1baf7 feat(pos): POS v2 order-panel footer + 3+GESAMT+3 bottom action bar
6892feb feat(pos): top bar v2 — brand lockup + Im Haus/Takeaway/Theke mode switch
2fd9c3c feat(pos): per-category tile + card colours driven by CategoryEntity.color
edb689c fix(tables): use near-square tiles on floor-plan grid
53a4218 fix(payments): redesign payment screen in kinetic-grid style
0c9cd15 fix(orders): wire İKRAM handler in left nav rail
77a7198 fix(pos): reconcile 96df9c4 cherry-pick with jolly's shell + payment repo
```

### Bu oturumda atılan son commit

**`8913cc4`** — Blok 4 UX fix. 5 dosya / +386 / −30:
- `apps/pos/lib/features/audit_log/domain/entities/audit_action.dart` — `orderSentToKitchen` eklendi
- `apps/pos/lib/features/orders/presentation/shells/pos_v2_shell.dart` — footer split + `buildPosV2FooterForTest()` `@visibleForTesting` factory
- `apps/pos/lib/features/orders/presentation/widgets/shell/bottom_action_bar.dart` — Neuer Bon dialog `tableId != null` ise silent-approve
- `apps/pos/test/features/audit_log/audit_service_extended_test.dart` — enum size 27 → 32
- `apps/pos/test/features/orders/widgets/pos_v2_footer_test.dart` — **yeni**, 5 widget test

---

## 8. AuditAction Enum — Tam Liste (post-M4)

`apps/pos/lib/features/audit_log/domain/entities/audit_action.dart` — şu an **34 action**:

Orders: `orderCreated`, `orderEdited`, `orderCancelled`, `orderVoided`, `itemVoided`, `orderSentToKitchen`, `tableMerged`
Payments: `paymentReceived`, `paymentRefunded`, `itemRefunded`
Discounts: `discountApplied`
Shifts: `shiftOpened`, `shiftClosed`, `dayOpened`, `dayClosed`
Prices: `priceChanged`
Menu: `productAvailabilityChanged`
CRM: `customerLinkedToTicket`
Loyalty: `loyaltyRedeemed`
Receipts: `receiptReprinted`, `receiptSentDigital`
Auth: `userLoggedIn`, `userLoggedOut`
Clock: `userClockedIn`, `userClockedOut`, `userBreakStarted`, `userBreakEnded`
Manager: `managerOverride`
Settings: `settingChanged`
Cash: `cashDrawerOpened`
Backup: `backupCreated`, `backupRestored`
Tables (yeni — M4): **`temporaryTableCreated`**, **`temporaryTableClosed`**

`audit_service_extended_test.dart` enum-size invariant'ı 32 → 34 olarak güncellendi.

---

## 9. Developer Kılavuzu (dahili, Türkçe)

`docs/developer-kilavuzu/` altında 6 kategori. Her özellik için ayrı MD dosyası var — bu handoff o kılavuzun özeti; detay için kılavuza bak:

```
docs/developer-kilavuzu/
├── 00-genel-bakis/       ← Proje nedir, nasıl kurulur
├── 01-mimari/            ← Katmanlar, Riverpod, Drift, flavor
├── 02-features/          ← Feature başına MD
│   ├── customer/
│   ├── kitchen/
│   ├── menu/
│   ├── orders/
│   ├── payment/
│   ├── pricing/
│   ├── reporting/
│   └── shifts/
├── 03-swiss-compliance/  ← MWST, fiscal_ch, audit retention, Z-seal
├── 04-dev-workflow/      ← Branch, commit, test, APK build
├── 05-kararlar-ve-bilinmesi-gerekenler/   ← "Neden böyle?" kararlar
└── README.md             ← Kılavuz girişi
```

**`05-kararlar-ve-bilinmesi-gerekenler/`** özellikle önemli — `tenant-switcher-ertelendi.md` gibi "neden yapılmadı" notları burada.

Son sync commit'i: `1ed8da5 docs(kilavuz): sync developer guide with pilot-final features`.

---

## 10. Pilot APK Son Durum (2026-04-23)

- **Yol:** `E:\Project\Restaurant\pilot\app-pos-release.apk`
- **Boyut:** 87,051,670 bayt (~83.0 MB)
- **SHA-256:** `715bf72b70ad19538a1132bd0c6c0557b6aab3ae6f0f2f5e3867801bd5605946`
- **Flavor:** `pos`
- **Build türü:** `--release`
- **Flutter:** 3.41.6 / Dart 3.11.4
- **Base commit:** `8913cc4`

Önceki interim APK: `E:\Project\Restaurant\pilot\app-pos-release-interim-11f637d.apk` — **eski, silinebilir** (Blok 4 öncesi).

---

## 11. Ortak Editlenen Kritik Dosyalar — İlk Okuma Listesi

Yeni Claude bir feature eklemek istiyorsa şu dosyaları okumalı:

- `apps/pos/lib/core/database/app_database.dart` — schema + DAO kayıtları
- `apps/pos/lib/core/router/app_router.dart` — tüm rotalar + `AppRoutes` const'ları
- `apps/pos/lib/features/orders/presentation/providers/order_provider.dart` — `currentTicketProvider` (POS'un kalbi)
- `apps/pos/lib/features/orders/domain/entities/ticket_entity.dart` — `TicketEntity`, `OrderType`, `TicketStatus`
- `apps/pos/lib/features/orders/presentation/shells/pos_v2_shell.dart` — ana satış shell'i (uzun!)
- `apps/pos/lib/features/orders/presentation/widgets/shell/bottom_action_bar.dart` — takeaway footer
- `apps/pos/lib/features/audit_log/domain/entities/audit_action.dart` — audit enum (32 action)
- `apps/pos/lib/core/services/audit_service.dart` — `audit.log(...)` API
- `apps/pos/lib/core/theme/app_tokens.dart` + `kinetic_theme.dart` — renk/ölçü tokenları
- `apps/pos/pubspec.yaml` — deps ve flavor flags

---

## 12. Bilinen TODO / Açık Bayraklar

### Post-pilot temizlik backlog'u

- **41 eski test failure** — pilot-değişikliklerinin fault'u değil. Kökler:
  - `pin_enter_btn` viewport hit-test (test viewport 800×600, pad 738'de)
  - `module_order` key'i değişmiş eski seed
  - Eski schemaVersion hard-code (v14/v15/v18 beklentisi olan testler — v19 sonrası bazıları taze düşebilir)
  - `table_map_test.dart`'ta tab navigation bozuk
- **Refund sonrası loyalty iadesi eksik.** Puan kırılırsa ve sonra refund yapılırsa, puan **geri verilmiyor**. Bug — yapılacak.
- **Email receipt PDF'e KOPIE banner eksik.** Reprint'te görsel `KOPIE` stripi var ama **dijital** receipt'e yok — GDPR/fiscal için eklenmeli.
- **Multi-tenant runtime switcher ertelendi.** Karar: `docs/developer-kilavuzu/05-kararlar-ve-bilinmesi-gerekenler/tenant-switcher-ertelendi.md`. Şu an sabit `pilot-zurich-001` seed.
- **Sweet-feistel ağacı temizliği** — pilot bittiğinde o worktree silinecek, branch terk edilecek.

### M1–M5 sonrası açık kalan ufak TODO'lar

- **APK rebuild gerekiyor.** Mevcut pilot APK `8913cc4` baz alıyor; M1–M5 değişiklikleri APK'da yok. §3'teki komut dizisini koş + SHA-256'yı bu dosyanın başında güncelle.
- **`flutter analyze` + `flutter test` koşulmadı** — sandbox'ta Flutter yok. M3'te eklenen `seat_tabs_test.dart` ve M4 `temporary_table_test.dart` dahil yeni 25+ test koşulup yeşil görülmeli.
- **Modifier admin entry**: `BackOffice → Menu Management → "Modifier yönet"` butonu `/menu-management` route'una gidiyor — pilot kıdemli operatör buradan grup CRUD yapabilir; sidebar'a ayrı bir Settings sekmesi gerekirse v2'de eklenir.
- **Geçici masa floor-plan rail'i:** `openTemporaryTablesProvider` mevcut; Settings veya sales shell'de "Aktif Geçici Masalar" listesi eklenebilir. Şu an aktif geçici masaya sadece açık ticket panel'inden ulaşılır.
- **Per-guest mutfak ticket:** kullanıcı kararı "mutfak için değil" — receipt-side seat groupings dahil değil. İstenirse split-bill ekranı zaten seat-aware.

### Yeni pilot geri dönüşü geldikten sonra

- i18n TR key audit (d855d00 eklendi ama pilot saha operatörü feedback ile kelime seçimi gözden geçirilecek)
- Golden baseline refresh (görsel değişiklik olursa) — `4710a62`
- Fine dining shell (eksper): `fine_dining_shell.dart` aktif geliştirmede değil, pilot sonrası

---

## 13. Yeni Claude İçin "İlk Adımlar" Kılavuzu

Sıfırdan bir Claude oturumu açıldığında:

1. **Worktree'ye gir:**
   ```bash
   cd E:/Project/Restaurant/.claude/worktrees/jolly-final
   ```
2. **Branch doğrula:**
   ```bash
   git branch --show-current   # → claude/pilot-final
   ```
3. **Son commit'i oku:**
   ```bash
   git log -1 --stat
   ```
4. **Bu handoff'u oku** (`E:\Project\Restaurant\pilot\DEVELOPER_RESTAURANT.md`) + developer kılavuzu README (`docs/developer-kilavuzu/README.md`).
5. **Ortamı hazırla:**
   ```bash
   cd apps/pos
   flutter pub get
   dart run build_runner build --delete-conflicting-outputs
   ```
6. **Sanity check:**
   ```bash
   flutter analyze --no-fatal-infos
   flutter test test/features/orders/widgets/pos_v2_footer_test.dart
   ```
7. **Task bazlı:** user ne istiyorsa feature matrisine (§5) bak → ilgili dosyaları oku → dokun → test yaz → analyzer + test → commit.
8. **APK üretimi:** §3'teki komut dizisi.

### Hata payı — en sık tuzaklar

- **build_runner çalıştırmadan test koşma:** drift generated dosyalar eksik → test patlar.
- **`pumpAndSettle` + SnackBar:** fake clock stall. `pump() + pump(50ms)` kullan.
- **`Future.delayed(Duration.zero)` + DB read:** aynı şekilde fake clock'ta hang.
- **Yanlış worktree:** sweet-feistel'de yazıp jolly-final'e aktarmayı unutma — her zaman jolly-final'de çalış.
- **Schema değişikliği:** `schemaVersion`'ı bump etmeden migration ekleme → runtime crash.

---

## 14. Kaynaklar ve Yollar — Yeni Claude İçin Hızlı Okuma

Aynı bilgisayarda çalışıyorsan aşağıdaki yolları doğrudan `Read` tool ile açabilirsin.

### 14.1 Repo ve Worktree

| Ne | Yol |
|----|-----|
| **Base repo (monorepo kökü)** | `E:\Project\Restaurant\` |
| **Pilot worktree** | `E:\Project\Restaurant\.claude\worktrees\jolly-final\` |
| **Pilot branch** | `claude/pilot-final` on `claude/jolly-hodgkin-1ca89c` |
| **Terk edilmiş worktree (dokunma)** | `E:\Project\Restaurant\.claude\worktrees\sweet-feistel-4e5dfc\` |

### 14.2 Pilot APK

| Ne | Yol |
|----|-----|
| **Pilot APK** | `E:\Project\Restaurant\pilot\app-pos-release.apk` |
| **Eski interim (silinebilir)** | `E:\Project\Restaurant\pilot\app-pos-release-interim-11f637d.apk` |
| **APK çıktı dizini (build)** | `...\jolly-final\apps\pos\build\app\outputs\flutter-apk\app-pos-release.apk` |

### 14.3 Developer Kılavuzu — Canonical Source (repo içi, Türkçe)

**Kök dizin:**
```
E:\Project\Restaurant\.claude\worktrees\jolly-final\docs\developer-kilavuzu\
```

**Alt dizinler (gerçek repo yapısı):**

```
docs/developer-kilavuzu/
├── 00-genel-bakis/
├── 01-mimari/
├── 02-features/
│   ├── customer/
│   ├── kitchen/
│   ├── menu/
│   ├── orders/
│   ├── payment/
│   ├── pricing/
│   ├── reporting/
│   └── shifts/
├── 03-swiss-compliance/
├── 04-dev-workflow/
├── 05-kararlar-ve-bilinmesi-gerekenler/
└── README.md
```

> **Not:** Önceki planlamada `06-glossary/` düşünülmüştü, şu an **yok**. Oluşturulursa "Glossary" için buraya dokümentasyon eklenecek.

**İlk okuma (Read tool):**
```
E:\Project\Restaurant\.claude\worktrees\jolly-final\docs\developer-kilavuzu\README.md
```

### 14.4 Obsidian Vault — Kullanıcının Kişisel Notları (mirror + daha fazlası)

**Yol (DOĞRULANDI, mevcut):**
```
C:\Users\kasim\Documents\2tech\2tech\Projects\POS Developer Kılavuzu\
```

**İçerik (2026-04-23 ls):**
```
00-genel-bakis/
01-mimari/
02-features/
03-swiss-compliance/
04-dev-workflow/
05-kararlar-ve-bilinmesi-gerekenler/
README Restaurant GASTROCORE.md
```

**Vault'un üst dizininde (`C:\Users\kasim\Documents\2tech\2tech\Projects\`)** pilot-ilgili başka kişisel notlar da var — örneğin `Restaurant - Release Plan 2026-04-17.md`, `Restaurant - POS UI Redesign Plan 2026-04-17.md`, `Restaurant - Worktree Audit 2026-04-17.md`, `Reservation - Session Report 2026-04-18_19.md`. Bunlar user'ın planlama notları, kılavuz mirror'ından farklı statüde — gerekirse oku, ancak **canonical olan repo içi `docs/developer-kilavuzu/`**.

### 14.5 Claude Oturum Yolları (otomatik)

| Ne | Yol |
|----|-----|
| **Memory dizini** (auto-memory, pilot lineage kuralları) | `C:\Users\kasim\.claude\projects\E--Project-Restaurant\memory\` |
| **Session transcript'leri** | `C:\Users\kasim\.claude\projects\E--Project-Restaurant--claude-worktrees-*\*.jsonl` |
| **Uploads (screenshot vb.)** | `C:\Users\kasim\AppData\Roaming\Claude\local-agent-mode-sessions\<session-id>\agent\local_ditto_<id>\uploads\` |

Memory dosyaları (zaten her session başında yüklenir):
- `MEMORY.md` — index
- `feedback_jolly_lineage.md` — jolly-final lineage kuralı
- `project_pos_pilot.md` — pilot context

### 14.6 Yeni Claude İçin Read-Order

Bir task açıldığında okuma sırası:

```
1. E:\Project\Restaurant\pilot\DEVELOPER_RESTAURANT.md         (bu dosya — genel harita)
2. E:\Project\Restaurant\.claude\worktrees\jolly-final\docs\developer-kilavuzu\README.md
3. Feature özelindeki MD: docs\developer-kilavuzu\02-features\<area>\
4. İlgili kod dosyası (bkz. §11 "Ortak Editlenen Kritik Dosyalar")
```

---

## 15. Koordinat — 2 Tarafın Buluşması

Bu dosya **restoran tarafı**. İkinci bir dosya var:

**`E:\Project\Restaurant\pilot\DEVELOPER_RESERVATION.md`** — gastro.2hub.ch rezervasyon + online sipariş webi (henüz kod yok, spec).

Rezervasyon web'i POS ile entegre olacak — POS tarafında eklenecekler (yeni `reservations` tablosu, `OnlineOrder` mapping, REST API) orada tanımlı. Restoran tarafı hazırsa oraya bakın.

Rezervasyon dosyasını açmak için:
```
Read tool: E:\Project\Restaurant\pilot\DEVELOPER_RESERVATION.md
```

---

**Son güncelleme:** 2026-04-23, commit `8913cc4`. Bu dosyayı güncel tutmak commit'in parçası değil — pilot aşaması boyunca manuel revize edin.


---

## §M5 Cloud-Master Menu Sync (POS tarafı)

> Eklendi: 2026-04-29. **Güncellendi: 2026-04-29 (yeniden hedefleme).**
> Cloud-master menü kayıt kaynağı artık **`api.2hub.ch` (Go backend,
> `Restaurant/server`)** — eski gastro2hub Next.js sürümü emekliye
> ayrıldı. Yeni Next.js backoffice (`apps/backoffice/`) pilot için ayağa
> kaldırıldı — handoff: [`pilot/DEVELOPER_BACKOFFICE.md`](DEVELOPER_BACKOFFICE.md).
> Publish UI (POS'a Yayınla butonu) backoffice'te `/{locale}/menu` ve
> `/{locale}/organization/menu` (HQ master menu) sayfalarında. POS yalnızca
> yayınlanmış snapshot'ları çeker ve uygular.
> Bileşenler `lib/features/menu_sync/` altında yaşar.

> **Endpoint hedefi:** `https://api.2hub.ch/api/v1/menu/{version|snapshot|publish}/:tenantId`
> (eski path `/api/menu/...` artık 410 Gone — backoffice tarafı taşınana
> kadar 410 dönen Next.js stub'ları bırakıldı).

### Mimari özet

```
+-----------------+   HTTP (X-API-Key)        +-----------------+
| MenuCloudClient | -----------------------> | api.2hub.ch     |
+-----------------+ GET /api/v1/menu/...     | (Go backend)    |
        |                                    +-----------------+
        v                                              |
+-----------------+                          +-----------------+
| MenuSyncService |                          | menu_versions   |
+-----------------+                          | (Postgres JSONB)|
        |                                    +-----------------+
        v
+-----------------+
| MenuSyncService |  diff() + applySnapshot() — Drift transaction
+-----------------+
        |
        v
+-----------------+
|  AppDatabase    |  products, categories, modifier_groups, modifiers,
|  (Drift, v20)   |  product_modifier_groups
+-----------------+
        |
        v
+-----------------+
|   AuditLogDao   |  menuSyncStarted | menuSyncApplied | menuSyncFailed
+-----------------+
```

### Drift schema bumpları (v20)

* `products.cloud_version int? null`
* `categories.cloud_version int? null`

`MenuSyncService.applySnapshot` her commitlenen ürün/kategori satırına
güncel `menuVersion` numarasını yazar; null değer "yerel mod" rölikleri
veya migration öncesi satırlar için bırakılır.

### Audit eylemleri (v34 → v37)

`AuditAction` enum'u üç yeni değer kazandı:

| Eylem               | newValueJson içeriği                     | Reason kullanımı |
|---------------------|------------------------------------------|------------------|
| `menuSyncStarted`   | `{from, to}`                             | —                |
| `menuSyncApplied`   | `{from, to, addedCount, updatedCount, removedCount, …}` | —      |
| `menuSyncFailed`    | `{from, to}`                             | hata metni       |

### Settings (`MenuSyncSettings`)

`SharedPreferences` altında `menu_sync.v1` anahtarında saklanır. `RestaurantSettings`'ten
ayrı tutuldu — bu sözleşmeye yapılacak bump'lar yerel ayarları etkilemesin.

| Alan                   | Tip          | Açıklama                                            |
|------------------------|--------------|-----------------------------------------------------|
| `cloudApiUrl`          | String       | `https://gastro2hub.ch` (trailing slash trimlenir)  |
| `cloudApiKey`          | String       | Plaintext API anahtarı (admin'in bir kez gösterdiği)|
| `cloudTenantId`        | String       | gastro2hub `Restaurant.id`                          |
| `lastSyncedVersion`    | int          | En son uygulanan `menuVersion`                      |
| `menuEditMode`         | enum         | `cloud` (varsayılan) \| `local` \| `hybrid`         |
| `backgroundCheckEnabled` | bool       | Saatte bir versiyon probe'u (varsayılan kapalı)     |

`menuEditMode = cloud` iken `MenuManagementTab` `AbsorbPointer` ile
sarılır + üstte `_CloudReadOnlyBanner` görünür. `local` eski davranışa
geri döner. `hybrid` sadece acil durumlar için: yerel düzenleme açık
kalır ama her apply yerel değişiklikleri ezer.

### BackOffice akışı

`Menü Senkronizasyonu` tab'ı (`MenuSyncTab`) üç bölüm sunar:

1. **Status header** — yerel sürüm vs cloud sürümü, "Cloud'dan Güncelle"
   ve "Versiyonu Kontrol Et" CTA'leri.
2. **Yapılandırma kartı** — URL/Tenant/Key formu, mod chip'leri,
   arka plan poll toggle'ı.
3. **Diff Preview Dialog** — pull sonrası, apply öncesi: kategori/ürün/
   modifier başına `+/~/-` sayıları. "İptal" diff'i atar; "Uygula"
   tek bir Drift transaction'ında commit eder.

### Apply sırası (CONTRACT.md §5)

1. Modifier grupları + modifierler (`insertOnConflictUpdate`)
2. Kategoriler (`cloudVersion` damgası)
3. Ürünler (`cloudVersion` damgası)
4. Product ↔ modifier-group linkleri (replace stratejisi)
5. Snapshot'tan kaybolan satırların **hard-delete**'i

Tüm adımlar `_db.transaction(...)` içindedir; herhangi bir adımda
exception → rollback. Çağ