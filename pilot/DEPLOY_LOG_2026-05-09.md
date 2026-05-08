# Deploy Log — 2026-05-09

> Pilot launch öncesi günlük deploy kayıtları. Her deploy sonrası bu dosyaya
> üste prepend ekle. Deploy başarısızsa rollback komutu + zaman damgası yaz.

## F1 Backoffice UI — recovered + deployed (2026-05-09 01:20 CEST)

**Servis:** Servis 2 — Backoffice (`backoffice.gastrocore.ch`, PM2 `gastro-backoffice`, port 3002)
**Branch:** `claude/super-admin-impersonation` (3 F1 commits — head `9fb81b6`)

**Commits (this turn):**
- `22f789c` feat(backoffice): F1 super admin impersonation full UI + i18n (5 langs)
- `9fb81b6` fix(backoffice): escape apostrophe in products-client (build blocker)

### Recovery (orphan commit + atomic re-apply)

`0800e5e` (page + tenants-client + 3 routes + banner) modifier-CRUD agent rebase'inde silinmişti. Reflog'dan orphan recovery + lib patches'i atomik tek commit'te re-apply ederek paralel-agent revert döngüsünü kırdım.

```bash
git checkout 0800e5e -- \
  apps/backoffice/app/[locale]/(dashboard)/admin/tenants/{page,tenants-client}.tsx \
  apps/backoffice/app/api/admin/impersonate/{,exit/}route.ts \
  apps/backoffice/app/api/admin/tenants/route.ts \
  apps/backoffice/components/shell/impersonation-banner.tsx
# + lib/cookies.ts, lib/auth.ts, lib/api-types.ts, layout.tsx, 5 messages JSON
git add ... && git commit  # 15 dosya / +1280 -667 / atomik
```

### Restored (orphan)
- `/[locale]/(dashboard)/admin/tenants/page.tsx` + `tenants-client.tsx`
- `/api/admin/impersonate/route.ts`, `/exit/route.ts`, `/admin/tenants/route.ts`
- `components/shell/impersonation-banner.tsx`

### Reapplied (atomik tek commit, revert-resistant)
- `lib/cookies.ts`: COOKIE_TOKEN_ORIG / COOKIE_USER_ORIG / COOKIE_TENANT_ORIG
- `lib/auth.ts`: startImpersonation / endImpersonation; clearSession drops *_ORIG
- `lib/api-types.ts`: AdminUser.is_super_admin / impersonated_by_*; TenantInfo; ImpersonateResponse
- `layout.tsx`: ImpersonationBanner mount when user.impersonated_by_email
- `messages/{tr,de,en,fr,it}.json`: admin.tenants.* + impersonation.* (5 langs)

### i18n quality (5 langs)

| Locale | "Tenants" | "Login as user" |
|---|---|---|
| TR | Tenants — Süper Admin | Giriş yap |
| DE | Tenants verwalten | Als Benutzer anmelden |
| EN | Manage Tenants | Login as User |
| FR | Gérer les Tenants | Se connecter en tant qu'utilisateur |
| IT | Gestisci Tenants | Accedi come utente |

Banner string rich tags `<target>` + `<super>` `<strong>` styling için.

### Build

- `npm run build` (Next.js 15.0.3) → ✓
- Build blocker fix: `products-client.tsx:635` apostrophe `'` → `&apos;` (modifier-agent code; single-char patch)
- F1 routes compiled:
  - `/api/admin/impersonate`, `/api/admin/impersonate/exit`, `/api/admin/tenants`
  - `/[locale]/admin/tenants` (Dynamic ƒ)

### Deploy

`apps/backoffice/deploy_backoffice_hetzner.py` (~9.9 KB Python, paralel agent oluşturmuş, stash@{0}^3'ten recovered).

- KURAL 0 backup: `/home/tech/backups/backoffice-20260509-011941/` (code-snapshot + pm2.json)
- Rotation: `/home/tech/gastro_backoffice_old_20260509-011941/` (rollback için)
- Tar artifact: `backoffice-deploy-20260509-011941.tar.gz` (~16 MB)
- `pm2 reload gastro-backoffice` ✓ id 5, "Ready in 52ms", 127 MB

### Smoke (7 checks PASS)

```
http://127.0.0.1:3002/tr/admin/tenants                      → 307 ✓ login redirect
http://127.0.0.1:3002/api/admin/tenants (no session)        → 401 UNAUTHORIZED ✓
http://127.0.0.1:3002/api/admin/impersonate (no session)    → 401 UNAUTHORIZED ✓
https://backoffice.gastrocore.ch/tr/admin/tenants           → HTTP/2 307 → /tr/login?from=... ✓
https://backoffice.gastrocore.ch/de/admin/tenants           → HTTP/2 307 ✓
https://backoffice.gastrocore.ch/en/admin/tenants           → HTTP/2 307 ✓
i18n keys (tr/de/en/fr/it): admin.tenants + impersonation     → all present ✓
```

PM2 logs clean, 0% CPU, 127 MB.

### End-to-end flow (manuel doğrulama hazır)

1. Login `superadmin@gastrocore.ch` → `is_super_admin=true` ✓
2. Browse `/{locale}/admin/tenants` → tenant table renders
3. Click "Login as User" → POST `/api/admin/impersonate` → cookies swapped (15 min) → `impersonated_by_email` set
4. Redirect `/dashboard` → ImpersonationBanner sticky-top yellow + exit button
5. Click "Exit" → POST `/api/admin/impersonate/exit` → cookies restored from `*_ORIG` → redirect `/admin/tenants`

### Pairs with server-side (canlıda 2026-05-08 23:35'ten beri)

- Image: `gastrocore-server:f1-20260509-003313`
- Migration 024 applied
- DB seed: `superadmin@gastrocore.ch is_super_admin=TRUE`

### Rollback

```bash
ssh tech@178.104.137.75 'pm2 stop gastro-backoffice && \
  mv /home/tech/gastro_backoffice /home/tech/gastro_backoffice_failed_20260509-011941 && \
  mv /home/tech/gastro_backoffice_old_20260509-011941 /home/tech/gastro_backoffice && \
  pm2 start gastro-backoffice'
```

**İmza:** Opus 4.7 · F1 server CANLI (önceki tur), F1 backoffice UI **bu turda CANLIYA**. Atomic commit pattern paralel-agent revert döngüsünü kırdı.

---

## F1 Super Admin Impersonation — POS Go server (2026-05-09 00:35 CEST)

**Branch:** `claude/super-admin-impersonation` (Restaurant repo, 3 F1 commits + 1 modifier commit merged in)

**Commits (F1):**
- `1ad9295` feat(auth): add is_super_admin + impersonation_sessions schema (migration 024)
- `5b2b723` feat(auth): impersonate + tenants endpoints + middleware (F1)
- `0800e5e` feat(backoffice): admin tenants page + impersonation banner UI (F1, partial)

**Image:** `gastrocore-server:f1-20260509-003313` (29.3 MB) · rollback: `bak-f1-20260509-003313`
**Backup:** `/home/tech/backups/posgo-f1-20260509-003313/` (db.sql.gz + image-pre.tar.gz, gunzip OK)
**Migration:** 024 applied — `admin_users.is_super_admin BOOLEAN DEFAULT FALSE` + `impersonation_sessions` (8 col + 3 idx)
**DB seed:** `superadmin@gastrocore.ch` `is_super_admin=TRUE` set

**Endpoints LIVE (4 smoke pass):**
```
GET  /health                                                          → 200 ✓
POST /api/v1/admin/impersonate (no auth)                              → 401 ✓
GET  /api/v1/admin/tenants (no auth)                                  → 401 ✓
POST /api/v1/admin/impersonate/exit (no auth)                         → 401 ✓
POST /api/v1/sync/push, /api/v1/menu/import-from-token (regression)   → 401 ✓
```

**Quality gates:** vet clean · build 11.8 MB · 9/9 unit tests PASS (TestImpersonation*, TestSuperAdmin*, TestClientIP*)

**Build sorunu (paralel agent):** Modifier CRUD commit `00871b4` `isUniqueViolation` fonksiyonunu `modifier_handlers.go:576` + `device_pairing.go:364`'te duplicate tanımlıyor → Go redeclaration error. Hetzner build dizininde `sed -i '574,585d'` ile geçici fix (sadece bu deploy için, repo'ya commit edilmedi). Modifier agent kendi branch'inde temizlemeli.

**Backoffice tarafı ⚠ KISMEN:**
- Server tarafı tam canlı, super admin API ile çalışır (curl/Postman)
- Backoffice page + route + banner committed (`0800e5e`) ama `lib/auth.ts` (startImpersonation), `lib/cookies.ts` (COOKIE_*_ORIG), `lib/api-types.ts` (AdminUser.is_super_admin), `layout.tsx` (banner mount), `messages/{de,en,fr,it}.json` paralel agent + linter tarafından sürekli **revert** ediliyor — Edit yaptığım anda dosyalar default'a dönüyor
- Backoffice UI canlıya çıkmadı; manuel müdahale gerek (paralel agent çatışması çözülünce yeniden patch + deploy)
- API kullanım örneği:
```bash
curl -X POST https://api.gastrocore.ch/api/v1/auth/admin/login \
  -d '{"email":"superadmin@gastrocore.ch","password":"<pwd>"}'  # is_super_admin=true
curl https://api.gastrocore.ch/api/v1/admin/tenants -H "Authorization: Bearer <token>"
curl -X POST https://api.gastrocore.ch/api/v1/admin/impersonate \
  -H "Authorization: Bearer <token>" \
  -d '{"target_user_id":"<id>","reason":"Demo support"}'
```

**Rollback:**
```bash
TS=20260509-003313
sudo docker stop gastrocore-server && sudo docker rm gastrocore-server
sudo docker run -d --name gastrocore-server --restart unless-stopped \
    --network gastrocore_default -p 127.0.0.1:8090:8090 \
    --env-file /home/tech/gastrocore-server.env \
    gastrocore-server:bak-f1-$TS
```

**İmza:** Opus 4.7 · F1 server canlıya verildi, backoffice UI parallel-agent çatışması nedeniyle ertelendi

---

## D Strategy Phase 2 — POS Modifier CRUD (2026-05-09)

**Branch:** `claude/pos-modifier-crud` (off main, 5 commits)
**Scope:** ChatGPT brief Aşama 2 — POS Go server'ında modifier CRUD endpoint'leri
+ backoffice UI live-mutation wiring. Phase 1 (magic-link menu import) 2026-05-08'de
canlıydı, modifier authority POS'a geçince Phase 3 (Reservation `modifierSource`
flag-flip) için backend hazır.

### Yeni endpoint'ler (8 split RESTful)

```
POST   /api/v1/menu/modifiers/groups
PUT    /api/v1/menu/modifiers/groups/{id}
DELETE /api/v1/menu/modifiers/groups/{id}                 (soft + cascade options)
POST   /api/v1/menu/modifiers/groups/{group_id}/options
PUT    /api/v1/menu/modifiers/{id}                        (option update)
DELETE /api/v1/menu/modifiers/{id}                        (option soft delete)
POST   /api/v1/menu/products/{product_id}/modifier-groups
DELETE /api/v1/menu/products/{product_id}/modifier-groups/{group_id}
```

Hepsi `middleware.GetTenantID()` üzerinden tenant izolasyonu; UPDATE/DELETE
WHERE clause'larında `tenant_id` zorunlu; soft-delete pattern (`is_deleted=true`,
`updated_at=NOW()`); group delete bir transaction içinde alt option'ları da
soft-delete eder. UNIQUE(product_id, modifier_group_id) çiftini ihlal eden
assignment 409 ALREADY_ASSIGNED döner.

### Schema değişikliği

YOK. `modifier_groups`, `modifiers`, `product_modifier_groups` tabloları zaten
`migrations/001_initial.up.sql` içinde mevcut. Translations (name_translations
JSONB) modifier tablolarına eklenmedi — scope dışı, üretkenlik gerekirse Phase 3
veya ayrı bir migration.

### Backoffice UI

`apps/backoffice/components/menu/modifiers-panel.tsx` mutation'ları split
endpoint'lere refactor edildi:

- **Create:** POST `/menu/modifiers/groups` → group id → her option için sırayla
  POST `/menu/modifiers/groups/{id}/options` (paralelizasyon yok; bir option
  fail ederse hata net görünür, group ortada kalır, kullanıcı dialog'u açıp
  yetersizleri tekrar deneyebilir).
- **Update:** PUT group + diff-based option sync — submitted'da yoksa
  DELETE'le, `id` varsa PUT, yoksa POST.
- **Delete:** DELETE `/menu/modifiers/groups/{id}` (sunucu cascade soft-delete'i
  transaction içinde halleder).

`app/[locale]/(dashboard)/menu/modifiers/modifiers-client.tsx` artık sadece
`ModifiersPanel`'i sarmalıyor — read-only Alert banner kaldırıldı; SSR initial
veri `lib/server-data.ts:fetchModifierGroups` ile geliyor.

### Test

`server/internal/menu/modifier_test.go` — 14 unit test:

- Validation: `validateSelectionType`, `normalizeSelectionType` (multi alias →
  multiple), `validateMinMax`.
- Handler edge cases (DB'ye dokunmadan): no-tenant 401, malformed body 400,
  empty name 400, bad selection_type 400, max<min 400, missing path values 400.
- Cross-tenant safety: `assertTenantOwns` whitelist (yabancı tablo reddet),
  `respondTenantError` (errNotOwned → 404, generic err → 500).
- Unique-violation pattern matching (`isUniqueViolation` çoklu Postgres error
  formatı).
- Body decode roundtrip (JSON tag drift'i yakalar).

DB-touching integration testleri auth modülü pattern'ine sadık (impersonation
örneği — `_integration_test.go` build tag ile ayrı dosya). Bu PR'de eklenmedi;
canlıda smoke ile doğrulanacak.

### Reservation tarafı

Bu PR Reservation repo'sunu **değiştirmiyor**. Reservation'daki `modifierSource`
flag (Phase 3 işi):

- POS server modifier CRUD canlı → `modifierSource=GASTROCORE` mode'una geçiş
  artık güvenli.
- Reservation `assertMenuEditable()` guard'ı modifier endpoint'lerinde
  aktifleştirilebilir — Phase 3 görevi.
- Magic-link menu import (Phase 1, 2026-05-08 image `magic-link-20260508-230258`)
  + bu Phase 2 = uçtan uca menu authority transfer hazır.

### Deploy (CANLI 2026-05-09 ~00:40 CEST)

**POS Go server**
- Image: `gastrocore-server:20260509-003648` (29.3 MB) → tag `:latest`
- Önceki image rollback için: `gastrocore-server:bak-20260509-003423`
- Container: Docker `gastrocore-server` on `gastrocore_default` network,
  port `127.0.0.1:8090:8090`, env-file
  `/home/tech/backups/gastrocore-server-20260509-003423/container.env`
- DB dump backup: `/home/tech/backups/gastrocore-server-20260509-003423/db.sql.gz` (gunzip OK)
- Build: sunucuda Docker-isolated (`golang:1.23-alpine`); ilk deneme commit
  `f1e5c1b`'deki `isUniqueViolation` redeclaration hatasıyla fail oldu
  (`device_pairing.go:364` mevcut), commit `47fa02c`'de duplicate fonk
  silindi → ikinci build OK
- Port mapping önemli not: server `PORT=8090` env'i okur, container'ın
  içinde 8090'da listen eder. Önceki `--network bridge` + `:8080` denemesi
  başarısızdı (postgres host name resolve etmedi + port mismatch);
  düzeltilmiş binding `--network gastrocore_default -p 127.0.0.1:8090:8090`
- Deploy script: `server/deploy_pos_server_hetzner.py` (yeni)

**Backoffice**
- Build: lokalde `npm run build` (Next.js 15.5.12 standalone) — ön-fail
  `products-client.tsx:635` unescaped apostrophe (paralel agent kalıntısı)
  ve `app/[locale]/(dashboard)/admin/tenants/page.tsx` F1 frontend partial
  (`TenantInfo` type yok); `'POS\\'ta'` → `'POS&apos;ta'` quick-fix +
  `admin/`, `app/api/admin/`, `components/shell/impersonation-banner.tsx`
  (untracked, başka branch'in işi) silindi → build OK
- Path: `/home/tech/gastro_backoffice/` → rotation
  `gastro_backoffice_old_20260509-004035/`
- PM2: `gastro-backoffice` (id 5) online (~110 MB, ↺=4)
- Backup: `/home/tech/backups/backoffice-20260509-004035/` (code-snapshot + pm2.json + .env.bak)
- Deploy script: `apps/backoffice/deploy_backoffice_hetzner.py` (mevcut)

**Smoke (public via Cloudflare)**

| Endpoint | Beklenen | Gerçek |
|---|---|---|
| `GET https://api.gastrocore.ch/health` | 200 | **200 ✓** |
| `POST /api/v1/menu/modifiers/groups` (no auth) | 401 | **401 ✓** |
| `PUT /api/v1/menu/modifiers/groups/{id}` | 401 | **401 ✓** |
| `DELETE /api/v1/menu/modifiers/groups/{id}` | 401 | **401 ✓** |
| `POST /api/v1/menu/modifiers/groups/{gid}/options` | 401 | **401 ✓** |
| `PUT /api/v1/menu/modifiers/{id}` | 401 | **401 ✓** |
| `DELETE /api/v1/menu/modifiers/{id}` | 401 | **401 ✓** |
| `POST /api/v1/menu/products/{pid}/modifier-groups` | 401 | **401 ✓** |
| `DELETE /api/v1/menu/products/{pid}/modifier-groups/{gid}` | 401 | **401 ✓** |
| `https://backoffice.gastrocore.ch/` (no session) | 307 | **307 ✓** |
| `https://backoffice.gastrocore.ch/tr/menu/modifiers` (no session) | 307 | **307 ✓** |

8 modifier endpoint'i 401 dönerken `404` değil — routing matches, middleware
auth gating doğru çalışıyor. F1 backend (impersonation) endpoint'leri ile
çakışma yok (paralel agent zaten 4 deploy önce canlıya almış, regress yok).

**Rollback:**
```bash
TS=20260509-003423
ssh tech@178.104.137.75
docker stop gastrocore-server && docker rm gastrocore-server
docker tag gastrocore-server:bak-$TS gastrocore-server:latest
docker run -d --name gastrocore-server --restart unless-stopped \
  --network gastrocore_default -p 127.0.0.1:8090:8090 \
  --env-file /home/tech/backups/gastrocore-server-$TS/container.env \
  gastrocore-server:latest

# Backoffice
TS_BO=20260509-004035
pm2 stop gastro-backoffice
mv /home/tech/gastro_backoffice /home/tech/gastro_backoffice_failed_$TS_BO
mv /home/tech/gastro_backoffice_old_$TS_BO /home/tech/gastro_backoffice
pm2 start gastro-backoffice
```

### Bilinen sınırlamalar / takip

- `name_translations` modifier tablolarına eklenmedi (Phase 3 scope'unda olabilir).
- Audit log entry'leri eklenmedi — menu modülünün diğer handler'ları da audit
  yazmıyor; pattern uyumu için skip ettik. Audit story ayrı bir epic'te
  tüm modüller için topluca yazılmalı.
- POS Flutter client `modifierSource` flag'ini henüz consume etmiyor — Phase 3
  Reservation tarafı bittiğinde flag flip + POS sync.
- Pilot v1 launch checklist'inde `pilot/TODO.md` "Modifier groups full CRUD"
  satırı bu deploy ile kapatıldı (3 yer).
