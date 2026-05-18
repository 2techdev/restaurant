# Deploy Log — 2026-05-18 — Order Profiles + time-based pricing

> Standalone deploy log for this branch (`claude/order-profiles-night-20260517`).
> Will get rolled into pilot/DEPLOY_LOG_*.md when the branch merges.

## 2026-05-18 ~10:54 CEST — Order Profiles + time-based pricing modülü canlıda

**Kapsam:** Backoffice (Hetzner 88, `backoffice.service` :3001) + POS Go sunucusu (`gastrocore.service` :8090) + Postgres (migration 037). Worktree: `claude/order-profiles-night-20260517`. Cash Collector / Loyalty session'larıyla namespace çakışması yok (yeni `internal/orderprofiles/` modülü, yeni `/menu/order-profiles` sayfası, yeni migration numarası).

### Ne eklendi

**Concept:** Order Profile = sipariş tipini augment eden zaman-bazlı preset. Profil her tenant'a ait, schedule + pricing override + service charge + print routing + visibility taşıyor. Sunucu her dakika hangi profilin "kazandığını" yeniden hesaplayıp WS üzerinden `profile_changed` event'i broadcast ediyor; POS bu event'le carttaki fiyatları re-calc edebilir.

**Backend (Go):**

- `server/migrations/037_order_profiles.up.sql` — 2 tablo:
  - `order_profiles` (tenant_id, code, name, is_active, is_default, priority, settings JSONB, UNIQUE(tenant_id, code))
  - `order_profile_pricing_rules` (profile_id, category_id veya product_id, override_price_cents veya discount_percent — CHECK constraint'lerle XOR)
  - Partial unique index `WHERE is_default = TRUE` ile tenant başına tek default
  - Seed: her tenant için "Normal" default profili (`{schedule: [], printRules: {kitchen,bar,copies:1}}`)
- `server/internal/orderprofiles/` (yeni modül):
  - `models.go` — DTO'lar (Profile, ProfileSettings, ScheduleSlot, ServiceCharge, PrintRules, Visibility, PricingRule, ActiveProfileSummary)
  - `schedule.go` — `slotMatchesAt` (gece yarısını aşan slot mantığı dahil: `endsAt < startsAt` ise `[startsAt, 24:00)` ∪ `[00:00, endsAt)` ertesi gün), `chooseWinner` (highest priority + CreatedAt tiebreaker, scheduled match yoksa default'a düş)
  - `store.go` — `listProfiles` (pricing rules iki sorguyla stitch — cartesian explosion'dan kaçınmak için), `upsertProfile` (default flip için tx içinde önce eski default'u kapat, sonra yenisini set et — partial unique index'i memnun etmek için), `deleteProfile` (default silinmez)
  - `handlers.go` — `GET /order-profiles`, `GET /order-profiles/{id}`, `POST /order-profiles`, `PUT /order-profiles/{id}`, `DELETE /order-profiles/{id}`, `GET /order-profiles/active?at=<RFC3339>` (test modu için `at` query parametresi)
  - `scheduler.go` — 60s ticker; her tenant için active set'i yeniden hesaplar; winner ID değişirse `BroadcastTenant` ile `profile_changed` event yollar; ilk tick suppress edilir (boot anında spam olmasın). CRUD handler'lar `notifyChanged()` çağırıp anlık broadcast da yapıyor (operatör test modunda fiyatın değiştiğini hemen görsün)
  - `module.go` — `NewModule(db, hub)` + `RegisterRoutes` + `Start(ctx)`
- `server/cmd/server/main.go` — modül import + register + `Start(context.WithCancel(...))` ticker başlatma

**Backoffice (Next.js):**

- `apps/backoffice/app/[locale]/(dashboard)/menu/order-profiles/page.tsx` — SSR sayfa, categories + products önceden çekiliyor
- `apps/backoffice/app/[locale]/(dashboard)/menu/order-profiles/order-profiles-client.tsx`:
  - "Şu anda aktif" header card (60s'de bir auto-refresh)
  - **Test modu** card: datetime-local picker → `/order-profiles/active?at=<ISO>` query, kazanan profil rozet olarak
  - Profil listesi tablosu — schedule özeti (Mon,Tue,Wed 16:00-18:00 formatı), pricing rule sayısı, service charge özeti, priority, isActive, "Şu an aktif" rozeti
  - Edit Sheet (sağdan açılır panel):
    - Code (lowercase + URL-safe slug filtresi), priority, name + 5 dil translations (DE primary, diğerleri collapsible)
    - Schedule editor: weekday toggle chip group + 2 time input (HH:MM); "ekle" / "sil" butonları; gece yarısını aşan slot için açıklama hint'i
    - Pricing rules tablo: target = category | product (Select), value = % discount | fixed CHF (Select + input)
    - Service charge: kind (CHF | %) + value + label
    - Print routing: kitchen / bar toggle + customer copies
    - isActive + isDefault toggle
    - Validation: code + name zorunlu
- `apps/backoffice/lib/nav-config.ts` — Menu group altına `menuOrderProfiles` sub-item eklendi (Kategoriler / Ürünler / Modifier / **Sipariş Profilleri** / Yayın Geçmişi)
- `apps/backoffice/lib/api-client.ts` üzerinden tüm CRUD `/api/proxy/order-profiles` route handler'ından geçiyor (JWT + X-Tenant-ID otomatik)

**i18n (5 dil — DE primary):**

- TR / DE / EN / FR / IT'de:
  - `nav.menuOrderProfiles` ("Sipariş Profilleri" / "Bestellprofile" / "Order Profiles" / "Profils de commande" / "Profili ordine")
  - `menu.orderProfilesPage.*` namespace — başlık + alt başlık + active badge + test modu + listeleme + edit field'lar + weekday kısaltmaları + schedule + pricing + serviceCharge + print
- JSON valid check tüm dosyalar için PASS

### Build / Deploy

- **POS Go server:** `python deploy_gastrocore_binary_88.py` (worktree-aware). 218 dosya / ~290KB tar → Hetzner'da `golang:1.23-alpine` cross-compile (CGO_ENABLED=0). Binary 8.3MB, swap, `sudo systemctl restart gastrocore.service`. Backup: `/home/tech/gastrocore/server.bak.20260518-104929`.
- **Migration 037:** Backoffice deploy'unun ÖNCESİNDE upload + apply edildi — `scp 037_order_profiles.up.sql tech@88:/tmp/` + `psql $DATABASE_URL -v ON_ERROR_STOP=1 -f /tmp/037_order_profiles.up.sql` + `INSERT INTO schema_migrations VALUES ('037_order_profiles') ON CONFLICT DO NOTHING`. `\d order_profiles` ile tablo + indexler + FK + seed verisi (3 tenant × 1 default = 3 row) doğrulandı.
- **Backoffice:** `npm install --legacy-peer-deps` (570 paket) + `npm run build`. İlk build bir pre-existing ESLint hatasıyla patladı (`products-client.tsx:635` türünde `POS'ta` apostrofu) — `&apos;` ile encode edildi, ikinci build temiz. `python deploy_backoffice_hetzner.py` (worktree-aware), 51MB standalone tar → `systemctl restart backoffice.service`. Backup: `/home/tech/backups/backoffice-20260518-105406/code-snapshot`.
- Go server bir kez daha restart edildi — modül scheduler boot anında "table does not exist" WARN'ı vermişti (migration henüz yokmuş), restart sonrası temiz.

### Post-deploy smoke (origin)

| Endpoint / sayfa | Beklenen | Gözlenen |
|---|---|---|
| `gastrocore.service` | active | ✅ active |
| `backoffice.service` | active | ✅ active |
| `GET /health` (8090) | 200 | ✅ 200 `{"status":"ok","components":{"database":"ok"}}` |
| `GET /api/v1/order-profiles` no-auth | 401 (route mounted, JWT zorunlu) | ✅ 401 |
| `GET /api/v1/order-profiles/active` no-auth | 401 | ✅ 401 |
| `GET /api/v1/order-profiles/active?at=…` no-auth | 401 (query param parse hatası vermesin) | ✅ 401 |
| `strings server | grep handleActive` | hit | ✅ `handleActive`, `*orderprofiles.Module`, `*orderprofiles.Profile`, `*orderprofiles.scheduler`, `*orderprofiles.PrintRules` |
| `GET /tr/login` + `/de/login` (3001) | 200 | ✅ 200 |
| `GET /tr/menu/order-profiles` + `/de/...` no-auth | 307 → /login (Next.js page exists + auth gate) | ✅ 307 → `/tr/login?from=%2Ftr%2Fmenu%2Forder-profiles` |
| `.next/server/app/[locale]/(dashboard)/menu/` | `order-profiles/` klasörü | ✅ present |
| `orderProfilesPage` keys in 5 messages files | mevcut | ✅ all 5 |
| DB: `SELECT id, code, is_default FROM order_profiles` | 3 default (her tenant 1) | ✅ 3 row, all `code=normal is_default=t` |
| DB: Happy Hour test profili insert | UPSERT OK, schedule JSONB doğru | ✅ `[{"endsAt":"18:00","startsAt":"16:00","weekdays":[1,2,3,4,5]}]` |

### Kullanıcı tarafından gözlenecek

1. **Sidebar > Menü altında yeni alt-item:** "Sipariş Profilleri" (DE: Bestellprofile / EN: Order Profiles / FR: Profils de commande / IT: Profili ordine).
2. **Sayfa açıldığında üst card:** "Şu anda aktif: Normal" (default profil, çünkü hiç schedule yok). Her tenant'ın seed'lediği `Normal` profili otomatik olarak default winner.
3. **Test modu card:** Bir datetime seç → kazanan profil rozet olarak gösteriliyor. Sunucu schedule eval'i çağırıyor, frontend sadece render.
4. **"Yeni profil" butonu:** Sheet açılır, schedule slot eklenir (örn. `Happy Hour` profili için weekdays=Pzt-Cum, 16:00-18:00), pricing rule eklenir (kategori bazında %20 indirim), kaydet.
5. **Kaydedildikten sonra:** CRUD handler `notifyChanged` çağırıp `profile_changed` WS event'i broadcast eder; POS'un cart kodu (faz 2 — ayrı session) bu event'i yakalayıp fiyatları re-calc edebilir.

### Test akışı (DB seed + endpoint)

```bash
# 1. Seed bir Happy Hour profile (Mon-Fri 16:00-18:00, priority 50)
psql $DATABASE_URL -c "INSERT INTO order_profiles (tenant_id, code, name, settings, priority)
  SELECT id, 'happy-hour-test', 'Happy Hour (Test)',
         '{\"schedule\":[{\"weekdays\":[1,2,3,4,5],\"startsAt\":\"16:00\",\"endsAt\":\"18:00\"}]}',
         50
  FROM tenants LIMIT 1"

# 2. JWT alıp /active endpoint'i 16:30 Mon (UTC 14:30) için test et:
TOKEN=$(curl -s -X POST http://localhost:8090/api/v1/auth/admin/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"admin@…","password":"…"}' | jq -r .token)

curl -s -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8090/api/v1/order-profiles/active?at=2026-05-18T14:30:00Z" | jq .
# beklenen: winnerProfile.code == "happy-hour-test"

curl -s -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8090/api/v1/order-profiles/active?at=2026-05-18T17:30:00Z" | jq .
# beklenen: winnerProfile.code == "normal" (saat 19:30 lokal, Happy Hour bitti)
```

### Rollback

```bash
# Backoffice
ssh tech@88.99.190.108 'sudo systemctl stop backoffice.service && \
  sudo mv /home/tech/backoffice /home/tech/backoffice_failed_20260518-105406 && \
  sudo mv /home/tech/backoffice_old_20260518-105406 /home/tech/backoffice && \
  sudo chown tech:tech /home/tech/backoffice/.env.production && \
  sudo systemctl start backoffice.service'

# Go server
ssh tech@88.99.190.108 'sudo systemctl stop gastrocore.service && \
  cp /home/tech/gastrocore/server.bak.20260518-104929 /home/tech/gastrocore/server && \
  sudo systemctl start gastrocore.service'

# Migration (varsa DB rollback)
psql $DATABASE_URL -f server/migrations/037_order_profiles.down.sql && \
  psql $DATABASE_URL -c "DELETE FROM schema_migrations WHERE version='037_order_profiles'"
```

### Notlar

- ✅ POS integration (faz 2 — POS cart'ında active profile çekme + fiyat re-calc + WS listener) ayrı session'da. Bu session sadece backend + backoffice editor.
- ✅ Migration runner (`cmd/migrate/main.go`) manuel — server binary auto-migrate etmiyor. 037 elle uygulandı; schema_migrations row'u da elle insert edildi ki gelecek `migrate up` çağrısı atlayabilsin.
- ⚠️ `schema_migrations` tablosunda `038_customer_analytics` zaten varmış (başka session) — 037'den önce uygulanmış olmuş. Migrate runner sadece version isimlerini izliyor, sıralama monoton olmak zorunda değil. Sorun yok.
- ⚠️ Timezone: schedule eval `Europe/Zurich` hardcoded (Swiss pilot). Tenants tablosunda timezone kolonu yok; ileride eklenirse `ProfileMatchesNow(p, now, tenantLoc)` overload'ı eklenir.
- ⚠️ `modified` (pricing rules için body diff) bu sürümde yok — sadece add/remove sayım. Body diff Agent A roadmap'inde.
- ⚠️ Sidebar nav-config.ts'te `team` referansı temiz (önceki Ekip merge fix branch'inde halledilmişti, bu worktree fresh main'den çıktı — main zaten temiz).
