# Merge Plan — v1.0.0-beta.1 Pilot Release

**Tarih:** 2026-04-18
**Hazırlayan:** `naughty-morse-c91a7b` (release infra agent)
**Durum:** PLAN ONLY — hiçbir merge henüz yapılmadı.

Paralel çalışan agent session'ları pilot P0 işlerini tamamlamak üzere:

- Backoffice Sprint 2 full push (`tender-hopper-fe0dc2`)
- Boss Sprint 1 (`ecstatic-almeida-9b7ccf`)
- POS Sprint 4 (`jolly-hodgkin-1ca89c`)
- i18n Next.js (`quizzical-fermat-2c58ed` — uncommitted)
- Printer package (`epic-shannon-0b42cb` — uncommitted)
- Waiter docs fix (`pedantic-feistel-12c0be`)
- Shared packages (`compassionate-spence-94e9b6`)
- Payment terminals (`flamboyant-hertz-6624fa`)
- KDS sprint (`practical-raman-06ba29`)
- Release infra (`naughty-morse-c91a7b` — bu agent)

Hepsi bitip haber verildikten sonra merge **bu dokümandaki sıra ile** yürütülecek.

---

## 1. Worktree envanteri (2026-04-18 itibarıyla)

`main` = `ad9c175` (merge: admiring-einstein — adisyon, Z-report, receipt, modifiers, images, freemium fix).

| # | Branch | Commits ahead | Last SHA | Scope | Dosya sayısı |
|---|---|---|---|---|---|
| 1 | `claude/ecstatic-almeida-9b7ccf` | 1 | `60d6835` | **Boss rename** — patron→boss docs rename, apps/boss/ placeholder, ROADMAP/TODO updates | 6 |
| 2 | `claude/naughty-morse-c91a7b` | 8 | `9746399` | **Release infra** — v1.0.0-beta.1 version alignment, nginx port fix, docker secrets, Sentry Flutter, Android keystore, Go 1.23, melos.yaml, 3 new CI workflows | 25 |
| 3 | `claude/compassionate-spence-94e9b6` | 4 | `5733ce9` | **Shared packages** — gastrocore_models (Role/Gang/Discount/Tax/Restaurant/Store/Settings entities), gastrocore_api (payments/staff/settings/reports/dashboard endpoints), gastrocore_ui (Gc* widgets + tokens), melos workspace + test scaffolds | 45 |
| 4 | `claude/tender-hopper-fe0dc2` | 2 | `4b8d7b1` | **Backoffice server** — tables CRUD, reports, orgs list, middleware refactor, inventory guard, parametric Gang settings. Server-only (Go). Migrations 008_product_default_gang, 009_store_settings, 010_tables_zone | 21 |
| 5 | `claude/flamboyant-hertz-6624fa` | 4 | `46690d4` | **Payment terminals** — PaymentEngine with 30s timeout, terminal configs from paymentSettingsProvider, persist terminal response (schema v9), docs | 7 |
| 6 | `claude/practical-raman-06ba29` | 17 | `602a96d` | **KDS** — WS client, station management, per-Gang states, timers, allergy banner, kitchen printer settings, e2e bump/recall tests | 29 |
| 7 | `claude/pedantic-feistel-12c0be` | 8 | `9ccf6f9` | **Waiter** — seat assignment, KDS→waiter Drift sync, service-call bell+inbox, guest-count edit, connectivity banner, Sunmi smoke-test docs | 31 |
| 8 | `claude/jolly-hodgkin-1ca89c` | 13 | `103588c` | **POS** — SambaPOS-style fine-dining shell (1↔2 col), PosMode SharedPrefs, AppTokens, service charge, Hold&Fire per-Gang, seat-first split billing, SambaPOS calc pipeline, orthogonal table flags, Order Tag richness, gang l10n route, drop legacy order-center | 55 |
| 9 | `claude/epic-shannon-0b42cb` | **UNCOMMITTED** | — | **Printer package** — new `packages/gastrocore_printers/`, `server/internal/printers/`, migration `008_printer_configs` (⚠️ **numara çakışması** — hopper 008'i aldı) | 5 staged |
| 10 | `claude/quizzical-fermat-2c58ed` | **UNCOMMITTED** | — | **i18n** — all 3 apps (pos/online/dashboard) + tr ARB, gastrocore_models date_format util, dashboard pubspec değişikliği, docs/40-i18n-localization.md | 30 staged |

Kalan 40 worktree `main` (`ad9c175`) hizasında — boş veya commit'lenmemiş WIP. Bu merge planında **dokunulmuyor**.

---

## 2. Conflict matrisi

`git merge-tree --write-tree` ile pairwise test edildi. "—" = clean (auto-merge başarılı).

| Source ↓ / Target → | almeida | naughty | spence | hopper | hertz | raman | feistel | hodgkin |
|---|---|---|---|---|---|---|---|---|
| almeida | — | — | — | — | — | — | — | — |
| naughty | — | — | **M** | — | — | — | — | — |
| spence | — | **M** | — | — | — | — | — | — |
| hopper | — | — | — | — | — | — | — | — |
| hertz | — | — | — | — | — | **DB** | **DB** | **DB** |
| raman | — | — | — | — | **DB** | — | **5** | **2** |
| feistel | — | — | — | — | **DB** | **5** | — | **4** |
| hodgkin | — | — | — | — | **DB** | **2** | **4** | — |

**Legend:**
- **M** — `melos.yaml` add/add (mine ve spence ikisi de yarattı)
- **DB** — `apps/pos/lib/core/database/app_database.dart` schema version çakışması
- **N** — N adet dosya çakışması

### 2.1 Hot files (aynı dosyayı birden fazla branch değiştiriyor)

| Dosya | Branch'ler | Conflict |
|---|---|---|
| `apps/pos/lib/core/database/app_database.dart` | hertz (payment v9), hodgkin (POS), feistel (waiter service_calls), raman (KDS stations) | **Her pair'de çakışıyor** — schema version int'i |
| `apps/pos/lib/features/settings/domain/entities/restaurant_settings.dart` | hodgkin, feistel, raman | hodgkin+feistel, hodgkin+raman, feistel+raman |
| `apps/pos/lib/features/orders/domain/entities/order_item_entity.dart` | hodgkin, feistel | hodgkin+feistel |
| `apps/pos/lib/features/waiter/services/waiter_order_service.dart` | hodgkin, feistel | hodgkin+feistel |
| `apps/pos/lib/core/data/seed_data.dart` | feistel, raman | feistel+raman |
| `apps/pos/lib/features/gang/data/gang_repository.dart` | feistel, raman | feistel+raman |
| `apps/pos/lib/features/kds_app/presentation/screens/kds_main_screen.dart` | feistel, raman | feistel+raman |
| `melos.yaml` | naughty (mine), spence | add/add |
| `server/cmd/server/main.go` | naughty (version string), hopper (endpoint routing), shannon (printer routing — uncommitted) | Auto-merges cleanly for naughty+hopper. Shannon risk. |
| `packages/gastrocore_sync/pubspec.yaml` | naughty (version), spence (deps) | Auto-merged clean |

### 2.2 Migration numara çakışması

- **`hopper` committed:** `008_product_default_gang`, `009_store_settings`, `010_tables_zone`.
- **`shannon` uncommitted:** `008_printer_configs` → **hopper 008'i aldı. Shannon commit'ten önce `011_printer_configs`'a renumber etmeli.**
- Her schema bump'ından sonra `server/migrations/`'ı gözden geçir.

---

## 3. Önerilen merge sırası

Temel prensip: **bağımlılık sırası → conflict minimizasyonu → schema versiyonu sequential bump**.

### Faz A — Izole değişiklikler (hiçbir conflict yok, en önce)

**1. `claude/ecstatic-almeida-9b7ccf` (Boss rename)**
- Risk: sıfır. Sadece docs + placeholder.
- Gerekçe: warmup merge, conflict matrisinde tüm hücreler temiz.

**2. `claude/naughty-morse-c91a7b` (release infra, BU BRANCH)**
- Risk: düşük. Sadece spence ile `melos.yaml` add/add çakışıyor → Faz B'de çözülecek.
- Gerekçe: v1.0.0-beta.1 semver baseline'ı, Go 1.23 backend CVE closure, nginx/docker-compose prod hijyen. Diğer tüm branch'ler bu yeni workflow'larda (pr-check, deploy-server) test edilecek. **Feature merge'lerden önce lock edilmeli** ki CI yeni gate'lerle koşsun.

### Faz B — Paket altyapısı (feature branch'lerinin consumer'ı)

**3. `claude/compassionate-spence-94e9b6` (shared packages)**
- Risk: orta. `melos.yaml` add/add → manuel resolve.
- **Resolve stratejisi:** Faz A sonrası naughty'nin `melos.yaml`'ı main'de. Spence'inki daha zengin (workspace sections, bootstrap scripts, pubspec test scaffolds). **Spence'in versiyonunu taban al, naughty'nin `command:` / `scripts:` bölümlerini birleştir.** Test: `melos bootstrap && melos run analyze`.
- Gerekçe: gastrocore_api / gastrocore_models / gastrocore_sync / gastrocore_ui paketleri. POS/Waiter/KDS/Backoffice bu paketlere dart dependency ekleyecek (fermat i18n dahil). **Paket mezarı önce atılmalı.**

### Faz C — Server-only (Flutter çakışması yok)

**4. `claude/tender-hopper-fe0dc2` (backoffice server)**
- Risk: sıfır. Go-only, Flutter tarafında değişiklik yok. Tüm branch'lerle clean merge.
- Gerekçe: migration 008/009/010'u sisteme tanıt → sonraki Flutter branch'lerinin backend API'sı bekleniyor. Shannon (uncommitted) bunu görüp 008'i 011'e kaydıracak.
- Post-merge: `cd server && go mod tidy && go build ./... && go test ./...`.

### Faz D — POS şema evrimi (sequential app_database.dart bump'ları)

Her merge şu pattern'i izler: `git checkout main && git merge --no-ff <branch>` → `app_database.dart` conflict açılır → schema version değerlerini sıralı artır (mevcut main vN → vN+1, vN+2, vN+3), migration ordering list'e her iki tarafın ekleyeceğini koru.

**5. `claude/flamboyant-hertz-6624fa` (payments, schema v9)**
- Risk: düşük. Sadece hodgkin/feistel/raman ile `app_database.dart` çakışıyor — bunlar daha sonra sıralanacak.
- Gerekçe: payment terminal schema bump en küçük kapsam (4 commit, 7 dosya). Raman/feistel/hodgkin'den önce land et ki onlar `hertz`'in v9'unun üstüne kendi bump'larını yazsın.
- Post-merge: `cd apps/pos && flutter pub get && flutter test test/features/payments/`.

**6. `claude/practical-raman-06ba29` (KDS, stations + WS)**
- Risk: orta. hertz ile `app_database.dart` çakışıyor (schema version).
- **Resolve stratejisi:** Hertz v9 → raman v10 (stations table + seed). Migration list'e append. Raman'ın KDS-only alanları (kds_app, stations) izole.
- Post-merge: `flutter test test/features/kds/ test/features/stations/ test/features/kitchen/`.

**7. `claude/pedantic-feistel-12c0be` (Waiter, service_calls)**
- Risk: yüksek. hertz + raman ile çakışıyor:
  - `app_database.dart` (schema bump) — feistel v11 = raman v10 + service_calls table.
  - `seed_data.dart` — gangs/station seed + service call demo data. **Her iki tarafın eklemelerini koru.**
  - `gang_repository.dart` — raman parametrik gang sistemini getirdi, feistel gangsEnabled/maxGangs/gangLabels toggle ekledi. **Feistel'in domain kullanımını raman'ın repo yüzeyine map et.**
  - `kds_main_screen.dart` — feistel sadece import/navigation, raman tüm ekranı yeniden yazdı. **Raman'ın versiyonunu al, feistel'in ufak değişikliklerini üstüne uygula.**
  - `restaurant_settings.dart` — 3-way merge (hodgkin de değiştirecek). **Field-by-field birleştir.**
- Gerekçe: Waiter, raman'ın KDS shape'i üstünde çalışıyor. Raman'dan sonra gelmeli.
- Post-merge: `flutter test test/features/waiter/`.

**8. `claude/jolly-hodgkin-1ca89c` (POS, SambaPOS shell)**
- Risk: **en yüksek**. 55 dosya, 13 commit. hertz + raman + feistel üçü ile çakışıyor:
  - `app_database.dart` — hodgkin v12 = feistel v11 + orthogonal table flags + modifier groups + order tag richness. Son schema bump.
  - `order_item_entity.dart` — hodgkin gang/hold/fire ekledi, feistel service-call metadata'sı ekledi. **Entity'nin her iki tarafını da koru.**
  - `restaurant_settings.dart` — 3-way merge final (hodgkin gangs param + posMode + serviceCharge + appTokens).
  - `waiter_order_service.dart` — feistel seat/service-call logic'i, hodgkin gang fire-to-kitchen. **Method'lar ayrı (çakışma muhtemelen ortak imports)**, birleştir.
- Gerekçe: Hodgkin en geniş dokunuşlu → en son gelsin ki önceki tüm şema/entity/settings değişikliklerini absorbe etsin.
- Post-merge: **regresyon suite'i komple** — `flutter analyze --fatal-infos && flutter test` hepsini koştur.

### Faz E — Pending (henüz commit olmayan)

**9. `claude/epic-shannon-0b42cb` (Printer package)** — agent commit etmeli. Commit öncesi:
- Migration `008_printer_configs.{up,down}.sql` → `011_printer_configs.{up,down}.sql` olarak **rename** (hopper 008/009/010 aldı).
- `server/cmd/server/main.go` değişikliğini hopper sonrasına rebase et.
- Commit'lendikten sonra Faz C sonrası (hopper'ın ardından) merge edilir. Flutter tarafı değiştirmiyor → diğer POS branch'leriyle çakışmaz.

**10. `claude/quizzical-fermat-2c58ed` (i18n)** — agent commit etmeli. Commit öncesi:
- 22 modifiye + 8 yeni dosya. `apps/pos/lib/l10n/app_*.arb` hodgkin ile aynı dosyaları değiştiriyor → **hodgkin merge'den sonra rebase** gerekecek.
- `packages/gastrocore_models/lib/gastrocore_models.dart` spence'in barrel'ını patch'liyor → **spence merge'den sonra rebase**.
- Commit'lendikten sonra Faz D sonrası (hodgkin'in ardından) merge. 3-way ARB birleştirmesi muhtemel.

---

## 4. Merge komutları (sıralı, main branch'inde execute)

```bash
cd E:/Project/Restaurant
git checkout main
git pull --ff-only origin main   # diğer session'lar main'e push etmiş olabilir

# Faz A ——————————————————————————————————————————————————
# 1) almeida (Boss rename)
git merge --no-ff claude/ecstatic-almeida-9b7ccf \
  -m "merge: ecstatic-almeida — rename patron → boss (post-pilot owner mobile app)"

# 2) naughty-morse (release infra, v1.0.0-beta.1 baseline)
git merge --no-ff claude/naughty-morse-c91a7b \
  -m "merge: naughty-morse — v1.0.0-beta.1 alignment + Sentry + Go 1.23 + CI/CD"

# Faz B ——————————————————————————————————————————————————
# 3) spence (shared packages) — MANUAL CONFLICT: melos.yaml
git merge --no-ff claude/compassionate-spence-94e9b6 \
  -m "merge: compassionate-spence — shared packages (models/api/ui) + melos scaffold"
# ❗ CONFLICT: melos.yaml (add/add). Resolve:
#   - Spence'in workspace + bootstrap sections'ını al
#   - Naughty'nin scripts: analyze/test/format/clean bölümlerini üstüne ekle
#   - Commit: git add melos.yaml && git commit --no-edit

# Post Faz A+B verification:
cd apps/pos && flutter pub get && cd ../..
cd packages/gastrocore_models && flutter pub get && cd ../..
melos bootstrap
melos run analyze

# Faz C ——————————————————————————————————————————————————
# 4) hopper (backoffice server, migrations 008/009/010)
git merge --no-ff claude/tender-hopper-fe0dc2 \
  -m "merge: tender-hopper — backoffice tables/reports/orgs + migrations 008-010"

# Post Faz C:
cd server && go mod tidy && go build ./... && go test ./...
cd ..

# Faz D ——————————————————————————————————————————————————
# 5) hertz (payments, schema v9)
git merge --no-ff claude/flamboyant-hertz-6624fa \
  -m "merge: flamboyant-hertz — payment engine + terminal configs + schema v9"
cd apps/pos && flutter test test/features/payments/ && cd ../..

# 6) raman (KDS, schema v10) — MANUAL CONFLICT: app_database.dart
git merge --no-ff claude/practical-raman-06ba29 \
  -m "merge: practical-raman — KDS WS + stations + per-Gang states (schema v10)"
# ❗ CONFLICT: app_database.dart — merge hertz v9 + raman stations = v10
cd apps/pos && flutter test test/features/kds/ test/features/stations/ && cd ../..

# 7) feistel (Waiter, schema v11) — MANUAL CONFLICT: 5 files
git merge --no-ff claude/pedantic-feistel-12c0be \
  -m "merge: pedantic-feistel — waiter sprint 2 (seat, service-call, sync) schema v11"
# ❗ CONFLICTS (5):
#   - app_database.dart → raman v10 + service_calls = v11
#   - seed_data.dart → preserve both demo data sets
#   - gang_repository.dart → feistel domain on raman's repo surface
#   - kds_main_screen.dart → keep raman's version, layer feistel's minor changes
#   - restaurant_settings.dart → field-by-field merge
cd apps/pos && flutter test test/features/waiter/ && cd ../..

# 8) hodgkin (POS, schema v12) — MANUAL CONFLICT: 4 files, biggest merge
git merge --no-ff claude/jolly-hodgkin-1ca89c \
  -m "merge: jolly-hodgkin — SambaPOS fine-dining shell + calc pipeline (schema v12)"
# ❗ CONFLICTS (4):
#   - app_database.dart → feistel v11 + orthogonal flags/modifier groups = v12
#   - order_item_entity.dart → preserve gang + service-call fields
#   - restaurant_settings.dart → final 3-way merge
#   - waiter_order_service.dart → merge methods (likely imports only)
cd apps/pos && flutter analyze --fatal-infos && flutter test && cd ../..

# Faz E ——————————————————————————————————————————————————
# 9) shannon (Printer) — user commits first with renumbered migration
# git merge --no-ff claude/epic-shannon-0b42cb -m "merge: epic-shannon — printer package + migration 011"

# 10) fermat (i18n) — user commits first, rebased onto main post-hodgkin
# git merge --no-ff claude/quizzical-fermat-2c58ed -m "merge: quizzical-fermat — tr locale + date_format util"
```

---

## 5. Post-merge verification (tek sefer, Faz E sonunda)

```bash
cd E:/Project/Restaurant

# 1. Monorepo bootstrap
dart pub global activate melos  # ilk kez ise
melos bootstrap

# 2. Flutter lint + test
melos run analyze      # apps/pos, apps/dashboard, apps/online, packages/*
melos run analyze-dart # gastrocore_models (pure Dart)
melos run test
melos run test-dart
melos run format-check

# 3. Go server
cd server
go mod tidy
go vet ./...
go test -race ./...
go build ./cmd/server
cd ..

# 4. Docker smoke
cd infra/deploy
cp .env.example .env  # geçici lokal test için
# (gerçek secret'lar CI'da)
docker compose -f docker-compose.prod.yml config   # sadece parse doğrulaması
cd ../..

# 5. Migration sıra doğrulaması
ls -1 server/migrations/ | grep -E '^0[0-9]{2}_' | sort
# Beklenen sıra: 001...007 (existing), 008_product_default_gang, 009_store_settings,
# 010_tables_zone, 011_printer_configs (shannon commit edince)
```

Her komut **0 exit code** dönmeli. Fail eden olursa ilgili branch'in merge commit'ine dön, fix commit'i ekle (o branch'e cherry-pick etme — main'de direct fix).

---

## 6. Bilinen riskler + mitigation

| Risk | Olasılık | Impact | Mitigation |
|---|---|---|---|
| `app_database.dart` schema version çakışması | **Kesin** | Orta | Sıralı merge (hertz→raman→feistel→hodgkin). Her merge'de schema version'ı +1. Migration list'e her iki tarafın eklemesini append et. |
| Shannon migration 008 collision | **Kesin** (hopper merge edilirse) | Düşük | User session commit öncesi migration'ı 011'e renumber etmeli. |
| Fermat ARB'leri hodgkin ile çakışır | Yüksek | Düşük | Fermat hodgkin sonrası rebase; ARB 3-way merge Dart tooling kolay çözer. |
| Fermat `gastrocore_models.dart` barrel'ı spence ile çakışır | Orta | Düşük | Fermat spence sonrası rebase; barrel export satırlarını birleştir. |
| POS flutter test yeni schema ile kırılırsa | Orta | Yüksek | Her Faz D merge'ünde tests'i koş; fail'de branch'i reverse et, schema migration logic'i sprint agent'ına bildir. |
| Melos bootstrap Windows'ta başarısız | Düşük | Düşük | Shell scriptler `.cmd` yedek olarak spence'te mevcut (`scripts/bootstrap.cmd`). |
| Go 1.23 bump server test'leri kırarsa | Düşük | Yüksek | Go 1.22 → 1.23 minor bump, backwards compatible. `go test -race` merge öncesi bu branch'te passed. |
| Hopper migration 010_tables_zone POS tables.dart ile şema tutarsız | Düşük | Orta | Server-side zone alanı DB'de, POS client-side tables.dart sync pipeline'dan okur. Tests hodgkin merge sonrası regression'da yakalar. |
| Paralel session'lar bu merge planını beklerken main'e push | Düşük | Orta | Merge execute öncesi `git fetch origin main && git log main..origin/main` kontrolü. |

---

## 7. Rollback prosedürü

Her merge `--no-ff` ile yapıldığı için her biri **tek commit ile reversible**:

```bash
# Son merge'ü geri al (çalışan tree'yi bozmadan)
git revert -m 1 HEAD

# Veya: çalışmanı kaybetmeden önceki state'e git (force push gerekir)
git reset --hard HEAD~1
```

Bir merge fail ederse:
1. `git reset --hard ORIG_HEAD` → merge öncesi state'e dön.
2. Branch owner'ına rapor → onlar rebase edip push eder.
3. Plan güncellenmiş SHA ile tekrar çalıştırılır.

**HİÇBİR destructive push henüz yok** — tüm branch'ler `claude/*` namespace'inde duruyor, safety tag'leri (`safety/agent-*-20260417`) mevcut.

---

## 8. P0 readiness matrisi (Release Plan 2026-04-17 → branch mapping)

Release Plan'daki 12 pilot bloker'ın hangisi hangi branch'te ship ediliyor:

| # | P0 Item | Durum | Branch | Notlar |
|---|---|---|---|---|
| 1 | Worktree konsolidasyonu | ✅ | `naughty-morse` | Safety tag'ler + audit doc. 37 WIP worktree'ye dokunulmadı. |
| 2 | Sentry init (Flutter) | ✅ | `naughty-morse` | `sentry_flutter ^8.9.0` + `runGuarded` wrapper. DSN `--dart-define`. |
| 3 | Android keystore + signing | ✅ | `naughty-morse` | `key.properties.template` + generate script. CI secret adları mevcut `ci.yml`/`release.yml` ile uyumlu. |
| 4 | Docker/Compose secret rotation | ✅ | `naughty-morse` | `${VAR:?error}` zorunlu syntax + `.env.example`. |
| 5 | Nginx → Go port mismatch | ✅ | `naughty-morse` | `8080 → 8090` (ws + root). |
| 6 | Go 1.22 → 1.23 bump | ✅ | `naughty-morse` | go.mod + Dockerfile + 4 CI workflow. |
| 7 | Ödeme terminali entegrasyon | 🟨 | `flamboyant-hertz-6624fa` | PaymentEngine 30s timeout + terminal configs + schema v9 + docs. **Gerçek Wallee/myPOS credential test user action.** |
| 8 | Settings → DB kayıt | 🟨 | `tender-hopper-fe0dc2` | `server/internal/stores/settings.go` (GET/PUT `/api/v1/stores/{id}/settings`) + migration `009_store_settings`. **POS/dashboard client wire-up sprint sonunda.** |
| 9 | Raporlar (DB sorgusu) | 🟨 | `tender-hopper-fe0dc2` | `server/internal/reports/handlers.go` + module. **Günlük satış / MWST breakdown / Z-rapor endpoint mevcut; UI wire-up kalanı backoffice sprint 2.** |
| 10 | Ürün görseli | ✅ | `main` (`ad9c175`) | "admiring-einstein" merge'ünde image upload geldi. Commit log'da "images" var. |
| 11 | Version tutarlılığı | ✅ | `naughty-morse` | `v1.0.0-beta.1` (pilot). Tüm pubspec/packages/server/CHANGELOG. |
| 12 | Waiter App (pilot blocker) | 🟨 | `pedantic-feistel-12c0be` | Sprint 2: seat assignment, service-call bell, real-time sync, guest-count, offline queue, Sunmi smoke-test. **Fiziksel tablet regression kalanı user-executed.** |

### 8.1 Bonus P0'ya eklenen infra (Release Plan'da yazmıyordu, ama bu turda tamamlandı)

| Item | Branch | Not |
|---|---|---|
| Shared monorepo packages | `compassionate-spence` | Role/Gang/Tax/Discount entities + API endpoints + Gc* design system. P2 "Melos monorepo"nun P0'a çekilen kısmı. |
| Melos workspace config | `naughty-morse` + `compassionate-spence` | Root `melos.yaml` (merge'de birleşecek). |
| CI/CD workflows | `naughty-morse` | `pr-check`, `deploy-backoffice` (Cloudflare Pages), `deploy-server` (Docker + GHCR + SSH rolling restart). P1 listesindeki "CI/CD APK automation"u kapsıyor. |
| POS SambaPOS fine-dining shell | `jolly-hodgkin-1ca89c` | PosMode, AppTokens, 1↔2 column toggle, calc pipeline, Order Tag richness. Release Plan'da ayrı P0 yoktu, ama fine-dining pilot için kritik. |
| KDS real-time + stations | `practical-raman-06ba29` | WS client + station management + per-Gang timers. Pilot için fine-dining expo station kritik. |
| Boss app rename (patron → boss) | `ecstatic-almeida-9b7ccf` | P2 scope, sadece rename + placeholder. Pilota engel değil. |
| i18n tr locale + date_format | `quizzical-fermat-2c58ed` (uncommitted) | Fine-dining pilotu Türk restoranı — **tr olmadan pilot bazına çıkmaz**. **Commit user action.** |
| Printer package + server | `epic-shannon-0b42cb` (uncommitted) | Thermal printer abstraction, kitchen/receipt birleşik. **Commit + migration renumber user action.** |

### 8.2 Eksik P0 / Risk (pilot kalkışı için hâlâ gerekli)

| Risk | Durum | Owner |
|---|---|---|
| **Gerçek Wallee/myPOS kart işlemi test** | Hertz kod tarafı bitti; sertifika + terminal donanımı yok | **User (tedarikçi engagement)** |
| **Fiziksel Sunmi tablet regression** | Smoke-test dokümanı var (feistel); gerçek tablet testi yapılmadı | **User (hardware)** |
| **i18n tr commit** | Fermat uncommitted | **Pending user session** |
| **Printer package commit + migration rename** | Shannon uncommitted, 008 conflict | **Pending user session** |
| **Gerçek Sentry DSN + CF_PAGES_PROJECT + GHCR secret** | Workflow'lar hazır; secret'lar repo'da yok | **User (GitHub Settings)** |
| **VPS .env dosyası** | Şablon var; prod credential yok | **User (server manuel setup)** |
| **Keystore .jks (CI secret olarak)** | Template + generate script var; `KEYSTORE_BASE64` secret'ı yok | **User (generate + upload)** |

**Değerlendirme:** Pilot kalkışı için **code tarafı %90 hazır**. Bloker'lar hep **external** (tedarikçi sertifika, donanım test, repo secret setup, 2 pending commit). Merge plan doğru sırada yürütülürse, tek bir `v1.0.0-beta.1` tag'i ile release.yml APK + server binary üretecek.

---

## 9. İlgili belgeler

- [../../CHANGELOG.md](../../CHANGELOG.md) — `1.0.0-beta.1` changelog girişi (naughty-morse tarafından eklendi)
- [../../infra/deploy/.env.example](../../infra/deploy/.env.example) — prod secret şablonu
- [../../melos.yaml](../../melos.yaml) — monorepo orchestration
- Obsidian: `Restaurant - Release Plan 2026-04-17.md`, `Restaurant - Infra Cleanup 2026-04-17.md`, `Restaurant - Worktree Audit 2026-04-17.md`

---

## 10. Ready to execute?

**HAYIR — henüz değil.**

Blocker'lar:

| # | Blocker | Durum | Çözüm |
|---|---|---|---|
| B1 | Shannon (Printer) commit'lenmedi | **Pending user** | Agent commit etsin + migration 011 rename |
| B2 | Fermat (i18n) commit'lenmedi | **Pending user** | Agent commit etsin |
| B3 | Hodgkin POS Sprint 4 "full push" iddiası — user bitti haber vermeli | **Pending user** | User confirmation |
| B4 | Feistel Waiter docs fix — user bitti haber vermeli | **Pending user** | User confirmation |
| B5 | Hopper Backoffice Sprint 2 "full push" — user bitti haber vermeli | **Pending user** | User confirmation |
| B6 | Raman KDS sprint — user bitti haber vermeli | **Pending user** | User confirmation |
| B7 | Almeida Boss Sprint 1 — user bitti haber vermeli | **Pending user** | User confirmation |
| B8 | Hertz Payment terminals — user bitti haber vermeli | **Pending user** | User confirmation |
| B9 | Spence shared packages — user bitti haber vermeli | **Pending user** | User confirmation |

**Infra tarafı (naughty-morse) hazır ve commit'li.** Diğer 8 session'ın tümü "bitti" haber verildiğinde:

1. Bu dokümandaki komutları sırayla yürüt.
2. Her Faz sonunda verification koş.
3. Faz E sonunda full verification.
4. `git tag v1.0.0-beta.1 && git push origin main v1.0.0-beta.1` (manuel confirmation ile).
5. Release workflow (`release.yml`) tag'i görüp APK + server binary üretir.
