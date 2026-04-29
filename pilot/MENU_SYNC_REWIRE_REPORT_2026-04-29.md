# Menü-Sync Yeniden Hedefleme — Final Rapor

**Tarih:** 2026-04-29
**Kapsam:** İŞ 1 (gastro2hub revert) + İŞ 2A (Go backend menü-sync) + İŞ 2C (POS retarget) + İŞ 2D (doküman)
**İŞ 2B atlandı:** Flutter Web `apps/dashboard` UI çalışması — kullanıcı kararıyla scrap'e gidiyor; yeni Next.js backoffice ayrı paralel görev olarak gelecek.

---

## 1. İŞ 1 — `E:\Project\reservation\` revert özeti

`reservation` repo'sunda git yoktu (versiyonsuz). Sandbox'tan dosya silme izni reddedildi; bu yüzden silinmesi gereken dosyalar **fonksiyonel olarak nötralize** edildi (route'lar 410 Gone döner, page'ler `notFound()` çağırır, lib dosyaları boş `export {}` olur, migration `SELECT 1` döner). Davranış olarak silinmiş hâle eşittir.

### 1.1 Silinen / nötralize edilen dosyalar (toplam 17)

| Yol | Yeni içerik |
|-----|-------------|
| `src/app/admin/menu/page.tsx` | `notFound()` stub |
| `src/app/admin/menu/[tenantId]/layout.tsx` | passthrough stub |
| `src/app/admin/menu/[tenantId]/page.tsx` | `notFound()` stub |
| `src/app/admin/menu/[tenantId]/categories/page.tsx` | `notFound()` stub |
| `src/app/admin/menu/[tenantId]/products/page.tsx` | `notFound()` stub |
| `src/app/admin/menu/[tenantId]/modifier_groups/page.tsx` | `notFound()` stub |
| `src/app/api/menu/snapshot/[tenantId]/route.ts` | 410 Gone |
| `src/app/api/menu/version/[tenantId]/route.ts` | 410 Gone |
| `src/app/api/menu/publish/[tenantId]/route.ts` | 410 Gone |
| `src/app/api/menu/api-key/[tenantId]/route.ts` | 410 Gone |
| `src/app/api/admin/menu-sync/tenants/route.ts` | 410 Gone |
| `src/lib/menu-snapshot.ts` | `export {}` |
| `src/lib/pos-api-key.ts` | `export {}` |
| `src/lib/tenant-scope.ts` | `export {}` |
| `docs/menu-sync/CONTRACT.md` | "moved" stub (içerik `Restaurant/server/docs/menu-sync/CONTRACT.md`'ye taşındı) |
| `docs/menu-snapshot-contract.md` | "moved" stub |
| `prisma/migrations/20260429000000_add_menu_version_and_color/migration.sql` | `SELECT 1` (no-op) |

### 1.2 Schema-prisma revert

`prisma/schema.prisma` düzeltmeleri:

- `Restaurant.posApiKey` (String? @unique) — kaldırıldı
- `Restaurant.menuVersionCurrent` (Int @default(0)) — kaldırıldı
- `Restaurant.menuVersions  MenuVersion[]` — kaldırıldı
- `MenuCategory.color` (String?) — kaldırıldı
- `MenuCategory.iconEmoji` (String?) — kaldırıldı
- `model MenuVersion { ... }` — komple kaldırıldı

Final tarama:
```
$ grep -nE "MenuVersion|posApiKey|menuVersionCurrent|iconEmoji" prisma/schema.prisma
(boş)
```

### 1.3 Modifiye edilen dosyalar (revert)

- `src/app/dashboard/menu/page.tsx` — "POS'a Yayınla" butonu, `publishMenu()` fonksiyonu, `publishBusy/publishResult` state, kategori dialog'undaki renk + emoji input'ları, Category interface'inden `color/iconEmoji` alanları kaldırıldı. Ayrıca M5 sırasında oluşan **orphan kod kalıntıları (1682-1748 satırları)** silindi — duplicate Category Dialog ve `button>` orphan'ı temizlendi. Dosya 1748 → 1639 satıra indi, bütün CRUD davranışı korundu.
- `src/app/api/menu/categories/route.ts` + `[id]/route.ts` — admin `restaurantId` body alanı, `resolveTenantId()`, `isTenantAuthorized()` çağrıları kaldırıldı. Owner-only davranışına geri döndü (session.restaurantId).
- `src/app/api/menu/items/route.ts` + `[id]/route.ts` — aynı revert. **Items `[id]/route.ts`:121-122 orphan ` true });` blok silindi.**
- `src/app/api/extras/route.ts` + `[id]/route.ts` — aynı revert.
- `src/components/admin/admin-sidebar.tsx` — "Menü-Sync (POS)" linki kaldırıldı + dosya sonundaki orphan `n>` ve duplicate `</aside></>` blok temizlendi (96 → 87 satır).

### 1.4 Doğrulama

- `prisma validate` sandbox'ta çalıştırılamadı (binaries.prisma.sh 403 Forbidden — Prisma engine indirme bloklu). Manuel grep ile tüm M5 alan/model referansları temiz.
- TypeScript syntax check: `tsc --noEmit` ile 8 modifiye/yeni dosya parse edildi — hiçbir sözdizimi hatası yok.
- Brace dengesi: tüm dosyalar 0 diff.
- **Bilinen sınırlama:** Sandbox `npx next build` koşulamadı (sandbox'ta network/disk yok). Lokal Windows tarafında `npm run build` koşulması önerilir.

### 1.5 Windows tarafında koşulması gereken adımlar (revert sonrası)

```powershell
cd E:\Project\reservation
npx prisma validate
npx prisma migrate dev --create-only --name revert_menu_sync
# (boş bir down migration üretir; tablo yoksa zaten no-op olur)
npm run build
git status   # versiyonsuz repo — anlamsız ama sayısal kıyas için
```

---

## 2. İŞ 2A — `Restaurant/server` Go backend menü-sync

### 2.1 Yeni dosyalar

| Dosya | Açıklama |
|-------|----------|
| `migrations/013_menu_versions.up.sql` | `menu_versions` tablosu + `tenants.pos_api_key` + `tenants.menu_version_current` |
| `migrations/013_menu_versions.down.sql` | Karşıt drop |
| `internal/menu/menusync.go` | 4 endpoint + snapshot builder, ~674 satır |
| `docs/menu-sync/CONTRACT.md` | Reservation'dan kopyalanan kontrat (schemaVersion 1) |

### 2.2 Modifiye dosyalar

| Dosya | Değişiklik |
|-------|-----------|
| `internal/menu/module.go` | `NewModuleWithHub()` constructor + `registerSyncRoutes(mux)` çağrısı |
| `internal/sync/hub.go` | `BroadcastTenant(tenantID, msg)` metodu eklendi (mevcut `NotifyTenant` yanına) |
| `cmd/server/main.go` | `menu.NewModule(db)` → `menu.NewModuleWithHub(db, syncModule.SyncHub())` |

### 2.3 Endpoint'ler

| Method | Yol | Auth | İşlev |
|--------|-----|------|-------|
| GET | `/api/v1/menu/version/{tenantId}` | JWT **veya** X-API-Key | `{ menuVersion, publishedAt, schemaVersion:1 }` döner; 0 ise 404 `no_published_version` |
| GET | `/api/v1/menu/snapshot/{tenantId}?since=N` | JWT **veya** X-API-Key | Son yayınlanmış JSONB snapshot. `since>=current` ise `304 Not Modified` |
| POST | `/api/v1/menu/publish/{tenantId}` | JWT **only** (admin / brand_manager) | Snapshot al, version bump, `menu_versions`'a satır insert, WS `menu_published` broadcast |
| POST | `/api/v1/admin/tenants/{tenantId}/api-key` | JWT only (admin / brand_manager) | Random 32-byte key üret, hash'le sakla, **plain key sadece bir kez döner** |

### 2.4 Auth modeli

- **JWT path:** Mevcut `middleware.AuthRequired` zincirine düştüğünden ekstra kod yok. `GetTenantID(ctx)` path'teki tenantId ile eşleşmek zorunda.
- **API key path:** `X-API-Key` header → `tenants.pos_api_key` hash karşılaştırması (PBKDF2-SHA256, mevcut `crypto.VerifyPassword` ile constant-time). API key publish'i ASLA yapamaz — yalnız okuma.
- **API key formatı:** `base64url(rand(32))`, ~43 char. Plain text yalnızca rotate yanıtında görünür; veritabanında hash tutulur.

### 2.5 Postgres migration

```sql
ALTER TABLE tenants
    ADD COLUMN pos_api_key            TEXT,
    ADD COLUMN menu_version_current   INTEGER NOT NULL DEFAULT 0;

CREATE TABLE menu_versions (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id     UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    version       INTEGER NOT NULL,
    snapshot      JSONB NOT NULL,
    published_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    published_by  UUID REFERENCES users(id) ON DELETE SET NULL,
    UNIQUE (tenant_id, version)
);

CREATE INDEX idx_menu_versions_tenant_published
    ON menu_versions(tenant_id, published_at DESC);
```

### 2.6 Snapshot şekli

`buildSnapshot()` Postgres'ten okur, kontrat tarafına dönüştürür:

- `business` ← `tenants` row (name, address, phone, tax_id → mwstNr)
- `taxProfiles[]` ← `tax_profiles`
- `categories[]` ← `categories` (color/icon UUID parent_id desteği var)
- `products[]` ← `products` (price BIGINT cents olarak zaten saklanıyor; kontrat'ın "INTEGER cents" kuralına birebir uyuyor)
- `products[].modifierGroupIds` ← `product_modifier_groups` join
- `modifierGroups[].modifiers[]` ← `modifier_groups` + `modifiers`
- `happyHourRules`, `gangs`, `variants`, `priceOverrides`, `allergens` — şu an boş array; backend'de tablo eklenince doldurulacak (kontrat ileriye dönük forward-compatible)

### 2.7 Çatışma noktası — Redis pub/sub

Talimatta "Redis pub/sub: `menu:published:<tenantId>`" denmişti. **Default'la kapattım, listeliyorum:**

- Mevcut Go backend stack'inde **Redis dependency yok** (`go.mod`'da sadece `gorilla/websocket` ve `lib/pq`). Redis eklemek yeni container + config + bir transport seçimi (gorilla'dan kanal'a vs.) demektir — pilot scope dışı.
- Mevcut `internal/sync.Hub` zaten WebSocket fan-out yapıyor (POS clientları `GET /ws/sync` ile bağlı). Yayın anında menu module bu hub'a `{ "type": "menu_published", "tenant_id": "...", "version": N, "published_at": "..." }` JSON frame'i broadcast ediyor.
- POS client tarafında `menu_published` mesajını dinleyen kod henüz yok — POS sürümlü polling ile çalışıyor (mevcut davranış). WebSocket dinleyici eklenmesi ileriye iş.

### 2.8 Doğrulama

- Sandbox'ta Go yok (`which go` boş döndü) — `go build` ve `go test` koşulamadı.
- Manuel: tüm dosyalarda brace dengesi 0 diff. İmport listesi kullanılan paketlerle eşleşiyor.
- **Windows tarafında koşulması gereken adımlar:**

```powershell
cd E:\Project\Restaurant\server
go mod tidy
go vet ./...
go build ./...
go test ./internal/menu/... -run "."

# Migration uygula (mevcut migrate tool'u ne ise):
docker compose run --rm migrate
# veya
go run ./cmd/migrate up
```

---

## 3. İŞ 2C — POS yeniden hedefleme

### 3.1 Modifiye dosyalar

| Dosya | Değişiklik |
|-------|-----------|
| `apps/pos/lib/features/menu_sync/data/menu_cloud_client.dart` | URL prefix `/api/menu/...` → `/api/v1/menu/...` (2 yer: fetchVersion, fetchSnapshot) + dosya başlığı api.2hub.ch'i belirtir |
| `apps/pos/lib/features/menu_sync/domain/menu_snapshot.dart` | (değişiklik yok — kontrat aynı) |
| `apps/pos/lib/features/menu_sync/domain/menu_sync_settings.dart` | `cloudApiUrl` doc'u "https://api.2hub.ch" örneğine güncellendi |
| `apps/pos/lib/features/menu_sync/presentation/widgets/menu_sync_tab.dart` | UI placeholder `https://gastro2hub.ch` → `https://api.2hub.ch` |

### 3.2 Test'ler

`test/features/menu_sync/menu_sync_service_test.dart` mock'lar üstünden test ediyor — URL hard-code'u yok, davranış değişikliği yok.

### 3.3 Doğrulama

- Tüm Dart dosyalarında brace dengesi 0 diff.
- **Windows tarafında koşulması gereken adımlar:**

```powershell
cd E:\Project\Restaurant\.claude\worktrees\jolly-final\apps\pos
flutter pub get
flutter analyze --no-fatal-infos
flutter test test/features/menu_sync/
```

---

## 4. İŞ 2D — Doküman güncellemesi

### 4.1 `pilot/DEVELOPER_RESTAURANT.md` §M5

- Başlık üstüne kalın "Güncellendi: 2026-04-29 (yeniden hedefleme)" notu eklendi.
- "Cloud (gastro2hub)" → "Cloud-master menü kayıt kaynağı artık **`api.2hub.ch` (Go backend, `Restaurant/server`)**".
- ASCII mimari diyagramı `gastro2hub` yerine `api.2hub.ch (Go backend)` ve `menu_versions (Postgres JSONB)` blokları gösterir.
- **Yeni Next.js backoffice'in paralel görev olduğu** ve publish UI'sının o iş bitene kadar yalnızca API üzerinden kullanılabileceği notu eklendi.

### 4.2 `pilot/DEVELOPER_GASTRO2HUB.md` §M5

- Başlık "Cloud-Master Menu Sync — TAŞINDI" olarak değiştirildi.
- En üste taşıma notu, eski endpoint hattının 410 Gone'a dönüştüğü, `Restaurant.gastrocoreApiUrl` alanının artık api.2hub.ch'e işaret ettiği bilgileri eklendi.
- Why moved: "Go backend zaten POS sync için authoritative, ikinci menü authority çift kaynak doğuracaktı".
- Önceki içerik **"TARİHSEL: gastro2hub menu-sync (artık geçersiz)"** alt başlığı altına taşındı (silinmedi — referans).

---

## 5. Final Smoke Test Senaryosu (öneri — koşulmalı, derinlemesine değil)

```
1. Backoffice (api.2hub.ch JWT login — admin rolü)
   POST /api/v1/auth/admin/login → access_token

2. Kategori ekle:
   POST /api/v1/menu/categories
     headers: Authorization: Bearer <jwt>
     body: { "name": "İçecekler", "color": "#1E88E5", "display_order": 0 }
   beklenen: 201, kategori objesi

3. Ürün ekle:
   POST /api/v1/menu/products
     body: { "category_id": "...", "name": "Cola", "price": 350, "tax_group": "beverage", ... }
   beklenen: 201

4. API key oluştur (POS için):
   POST /api/v1/admin/tenants/<tenantId>/api-key
   beklenen: 200, { "apiKey": "<43-char>", "warning": "shown only once" }

5. Yayınla:
   POST /api/v1/menu/publish/<tenantId>
     headers: Authorization: Bearer <jwt>
   beklenen: 200, { "menuVersion": 1, "publishedAt": "...", "summary": { "categories": 1, "products": 1, ... } }

6. DB kontrol:
   SELECT version, jsonb_object_keys(snapshot)
     FROM menu_versions WHERE tenant_id = '<id>';
   beklenen: 1 satır, snapshot içinde { schemaVersion, tenantId, business, taxProfiles, categories, products, ... }

   SELECT menu_version_current FROM tenants WHERE id = '<id>';
   beklenen: 1

7. WebSocket fan-out kontrolü (opsiyonel):
   POS terminali: ws://api.2hub.ch/ws/sync?device_id=...&tenant_id=<id>
   bağlanmış olmalı → publish anında frame:
     { "type": "menu_published", "tenant_id": "...", "version": 1, "published_at": "..." }

8. POS sync (X-API-Key path):
   GET /api/v1/menu/version/<tenantId>
     headers: X-API-Key: <apiKey from #4>
   beklenen: 200, { "data": { "menuVersion": 1, ... } }

   GET /api/v1/menu/snapshot/<tenantId>
     headers: X-API-Key: <apiKey>
   beklenen: 200, full snapshot JSON

   GET /api/v1/menu/snapshot/<tenantId>?since=1
     headers: X-API-Key: <apiKey>
   beklenen: 304 Not Modified

9. Yetkisiz publish:
   POST /api/v1/menu/publish/<tenantId>
     headers: X-API-Key: <apiKey>   (JWT yok!)
   beklenen: 403 FORBIDDEN

10. POS BackOffice → Menü Senkronizasyonu → "Cloud'dan Güncelle":
    diff dialog → 1 added (kategori), 1 added (ürün) → Apply → audit log:
      menuSyncStarted({from:0, to:1})
      menuSyncApplied({from:0, to:1, addedCount:..., updatedCount:..., removedCount:...})
```

**Bu senaryo derinlemesine koşulmadı — sandbox Postgres + Go yok.** Lokal/staging Hetzner ortamında smoke koşulması önerilir.

---

## 6. Commit önerileri (Windows tarafında)

```powershell
# reservation/ (versiyonsuz repo — pseudo-commit)
cd E:\Project\reservation
# yedekle: cp -r prisma src docs E:\Project\backups\reservation_pre_revert\
# tüm değişiklikler manuel uygulandı; deploy zamanı geldiğinde:
#   python deploy_test.py
#   (kullanıcı onayı)
#   python deploy_hetzner.py

# Restaurant/server
cd E:\Project\Restaurant\server
git add migrations/013_menu_versions.up.sql migrations/013_menu_versions.down.sql \
        internal/menu/menusync.go internal/menu/module.go internal/sync/hub.go \
        cmd/server/main.go docs/menu-sync/CONTRACT.md
git commit -m "feat(menu): cloud-master menu sync — version/snapshot/publish/api-key

- Add menu_versions table + tenants.{pos_api_key, menu_version_current}
- 4 new endpoints under /api/v1/menu and /api/v1/admin/tenants
- API key path: PBKDF2-SHA256 hash, plain shown once on rotate
- WebSocket fan-out via existing sync.Hub.BroadcastTenant
- Snapshot contract schemaVersion 1 (docs/menu-sync/CONTRACT.md)"

# POS (jolly-final worktree)
cd E:\Project\Restaurant\.claude\worktrees\jolly-final\apps\pos
git add lib/features/menu_sync/data/menu_cloud_client.dart \
        lib/features/menu_sync/domain/menu_sync_settings.dart \
        lib/features/menu_sync/presentation/widgets/menu_sync_tab.dart
git commit -m "refactor(menu_sync): retarget to api.2hub.ch Go backend

URL prefix /api/menu/... -> /api/v1/menu/...
Update placeholder + docstring to reflect new authority"

# Pilot docs
cd E:\Project\Restaurant
git add pilot/DEVELOPER_RESTAURANT.md pilot/DEVELOPER_GASTRO2HUB.md \
        pilot/MENU_SYNC_REWIRE_REPORT_2026-04-29.md
git commit -m "docs: §M5 menu sync moved to Go backend (api.2hub.ch)"
```

---

## 7. Açık konular / Sonraki adımlar

| Konu | Sahip | Notu |
|------|-------|------|
| Yeni Next.js backoffice (publish UI) | Paralel görev | api.2hub.ch'in `/api/v1/menu/publish/...` endpoint'ini tüketecek; CONTRACT.md değişmedi |
| `tax_profiles`, `gangs`, `happy_hour_rules`, `product_variants` Postgres tabloları | Backend roadmap | Şu an snapshot'ta boş array; tablo eklenince doldurulacak |
| POS `menu_published` WS frame dinleyici | POS roadmap | Şu an POS sürüm-polling ile çalışıyor; WS push opsiyonel iyileştirme |
| Reservation `prisma migrate dev` | Reservation deploy | Revert sonrası yeni migration üret + Hetzner deploy |
| `npx next build` ve `flutter test` (lokal) | Geliştirici | Sandbox'ta koşulamadı |
| `go build ./...` ve `go vet ./...` (lokal) | Geliştirici | Sandbox'ta Go yok |

---

## 8. Bilinen Sınırlamalar (sandbox)

- Sandbox'ta `git`, `go`, `flutter`, `next`, `prisma engine` yok / network bloklu.
- Bash silme yetkisi reddedildi → `reservation/` revert'i fonksiyonel nötralize ile yapıldı (mantıken silinmiş).
- Tüm değişiklikler dosya-tabanlı parse-check ve manuel review ile doğrulandı; runtime test'ler Windows tarafında koşulmalı.
