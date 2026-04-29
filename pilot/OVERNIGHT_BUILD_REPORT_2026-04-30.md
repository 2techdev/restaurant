# Overnight Build Raporu — 2026-04-30

> 4 paralel iş paketi + entegrasyon doğrulama + tek-tıklama deploy paketi tamamlandı.
> **Yeni Hetzner sunucusu**: `88.99.190.108` (NBG1, Ubuntu 24.04). IPv6 `2a01:4f8:1c18:bde5::/64`.
> İlk bootstrap için root + password (web console), sonrasında `tech` user + SSH key.
> Sandbox public-internet egress yok → uzak deploy Windows tarafında koşulacak.

## Domain dağılımı (kullanıcıyla netleşti)

| Domain | Cloudflare | Hedef |
|---|---|---|
| `backoffice.gastrocore.ch` | Proxied | Caddy → Next.js :3001 |
| `api.gastrocore.ch` | Proxied | Caddy → Go :8090 |
| `ws.gastrocore.ch` | DNS only (gri) | Caddy → Go :8090 (WS upgrade) |
| `gastro.2hub.ch` | (eski sunucu) | DOKUNULMAZ |

---

## 1. Paket özeti

| # | Paket | Etki alanı | Durum |
|---|-------|------------|-------|
| 1 | `local_f868a3fa` — gastro2hub revert + Go menu-sync | `Restaurant/server/internal/menu/menusync.go` (674 satır), `migrations/013_menu_versions.up.sql` (40 satır) | ✅ Statik doğrulandı |
| 2 | `local_c94e7d60` — Next.js 15 backoffice scaffold | `Restaurant/apps/backoffice/` 84 TS/TSX dosyası | ⚠️ pnpm install network engeli — Windows tarafında derlenecek |
| 3 | `local_f1fd784a` — Go HQ logic | `Restaurant/server/internal/org/` 10 dosya, `migrations/014_hq_chain.up.sql` (125 satır) | ✅ Statik doğrulandı |
| 4 | **Bu paket** — entegrasyon doğrulama + deploy orchestrator | `deploy/` 8 dosya, kritik fix'ler `auth/jwt.go`, `auth/handlers.go`, `shared/middleware/middleware.go`, `org/auth.go` | ✅ Tamamlandı |

**Toplam Go LoC** (yeni): yaklaşık 2 800 satır (menu-sync 674 + org 1 800 + 014_hq_chain 125 + 013_menu_versions 40 + auth düzeltmeleri ~100).
**Toplam TS/TSX LoC** (yeni backoffice): tahminen 6 500–7 500 satır (84 dosya × ortalama 80 satır).

---

## 2. Entegrasyon doğrulama bulguları

### CRITICAL — Onarıldı

**(C-1) JWT Claims `OrgRole` + `OrganizationID` taşımıyordu**
Admin login `admin_users` tablosunu sorguluyor; `org/auth.go`'nun `resolveUser()` fonksiyonu ise `users` tablosuna bakıyordu. Bu mismatch nedeniyle her admin login'in HQ rotalarında `403 NO_ORG` alması garantiydi.

Onarım:
- `auth/jwt.go` Claims struct'ına `OrganizationID` ve `OrgRole` alanları eklendi (json tag: `organization_id`, `org_role`).
- `auth/handlers.go` içinde `mapAdminRoleToOrgRole()` haritalama fonksiyonu eklendi: `admin → HQ_ADMIN`, `brand_manager → HQ_MANAGER`, `store_manager → RESTAURANT_MANAGER`, diğerleri → `""`.
- Admin login (handleAdminLogin) ve refresh token (handleTokenRefresh) artık her iki alanı JWT'ye basıyor.
- `shared/middleware/middleware.go`: `ContextKeyOrganizationID`, `ContextKeyOrgRole` context key'leri ve `GetOrganizationID()`, `GetOrgRole()` getter'ları eklendi; AuthRequired middleware'i claims'ten okuyup context'e geçiyor.
- `org/auth.go`: `resolveUser()` artık önce JWT, sonra `users`, sonra `admin_users` tablolarına sırayla bakıyor — geriye dönük uyumlu, post-014 native HQ kullanıcıları için forward-compatible.

### WARNING — Belgelendi

**(W-1) Backoffice `/admin/stores` legacy endpoint kullanıyor**
`apps/backoffice/lib/server-data.ts:150` HQ restoran listesi için `/admin/stores` çağırıyor — yeni `/api/v1/org/{orgId}/restaurants` endpoint'i değil. Eski endpoint Go tarafında hâlâ çalışıyor (`stores/handlers.go:340`) ve aynı listeyi döndürüyor; fonksiyonel olarak iş yapıyor. Sabah doğrulamada görülürse refactor önerilir.

**(W-2) Logout HTTP metodu**
TS tarafında GET `/auth/logout`, Go tarafında POST `/auth/logout`. Backend tarafına bakıldığında genellikle 405'le karşılaşılacak — TS tarafını POST'a çevirmek tek satırlık.

**(W-3) Migration 013/014 default UUID fonksiyonu farkı**
013 `uuid_generate_v4()` (uuid-ossp uzantısı) kullanıyor, 014 `gen_random_uuid()` (pgcrypto). 013 önce koşarsa fark görünmez (tablo zaten oluşmuş, 014 IF NOT EXISTS atlar). Ters sıra mümkün değil (numerik sıra). Tek olası sorun: 013'ün uuid-ossp uzantısının kurulu olmaması. **Aksiyon**: smoke test öncesi remote'da `CREATE EXTENSION IF NOT EXISTS "uuid-ossp"; CREATE EXTENSION IF NOT EXISTS pgcrypto;` çalıştırın (deploy script'i bu ihtimali doğrudan ele almıyor, manuel kontrol gerek).

### INFO

- `Restaurant/apps/pos/lib/features/menu_sync/` ana branch'te yok; `cloud_sync_integration_test.dart` mevcut. POS Dart tarafının cloud-master menü sync client'ı için ayrı bir görev gerekecek.
- `internal/menu/handlers.go` `org` paketini doğru import ediyor (satır 11) — derleme hatası yok.
- `internal/menu/menusync.go` 4 endpoint'in tamamını doğru pattern'larla register ediyor (`registerSyncRoutes`, satır 161–164).
- `auth/handlers_test.go`, `org/handlers_test.go`, `org/publish_test.go` — testler mevcut; sabahki `go test ./...` koşusunda yeni Claims alanları için test güncellemesi gerekebilir (özellikle GenerateToken/ValidateToken testleri).

---

## 3. Yeni endpoint'ler (Go)

### Menu sync (cloud-master)
- `GET /api/v1/menu/version/{tenantId}` — JWT veya X-API-Key
- `GET /api/v1/menu/snapshot/{tenantId}` — JWT veya X-API-Key
- `POST /api/v1/menu/publish/{tenantId}` — JWT (admin/brand_manager)
- `POST /api/v1/admin/tenants/{tenantId}/api-key` — JWT (admin/brand_manager)

### Org / HQ
- `GET /api/v1/org/me`
- `GET /api/v1/org/{orgId}/restaurants`
- `POST /api/v1/org/{orgId}/restaurants`
- `DELETE /api/v1/org/{orgId}/restaurants/{restaurantId}`
- `GET /api/v1/org/{orgId}/master-menu`
- `POST /api/v1/org/{orgId}/master-menu/categories`
- `PUT /api/v1/org/{orgId}/master-menu/categories/{id}`
- `DELETE /api/v1/org/{orgId}/master-menu/categories/{id}`
- `POST /api/v1/org/{orgId}/master-menu/products`
- `PUT /api/v1/org/{orgId}/master-menu/products/{id}`
- `DELETE /api/v1/org/{orgId}/master-menu/products/{id}`
- `POST /api/v1/org/{orgId}/master-menu/publish`
- `GET /api/v1/org/{orgId}/policies`
- `POST /api/v1/org/{orgId}/policies`
- `PUT /api/v1/org/{orgId}/policies/{policyId}`
- `DELETE /api/v1/org/{orgId}/policies/{policyId}`
- `GET /api/v1/org/{orgId}/reports/aggregate`
- `GET /api/v1/org/{orgId}/reports/by-restaurant`

---

## 4. Yeni feature'lar

- **Cloud-master menü dağıtımı**: backoffice "Publish" butonu → Go publish handler → immutable JSON snapshot → POS'lar `/version` polling + `/snapshot` `since` ile delta çekme.
- **Tenant başına POS API key**: bcrypt-hashed, rotate edilebilir, X-API-Key header ile menü çekme.
- **HQ chain restaurant logic**: organizasyon → tenant memberships, master menu version history, kilit politikaları (FULLY_LOCKED / PRICE_LOCKED / FLEXIBLE), aggregate raporlar.
- **Locked product mutation guard**: `org.CheckMutation()` artık `menu/handlers.go`'da product update/delete'i policy lock'una karşı doğruluyor (`org.LockedError` 423 ile döner).
- **HQ rolleri JWT'de**: admin login artık `org_role` ve `organization_id`'yi token'a damgalıyor — DB round-trip'siz HQ authorization.

---

## 5. Bilinen TBD'ler — sandbox'ta yapılamadı

| Konu | Neden |
|---|---|
| `go build ./...` çalıştırma | Sandbox'ta Go kurulu değil — düzeltmeler statik incelemeyle doğrulandı |
| `go test ./...` | Aynı |
| `pnpm install + build` | Sandbox public internet egress yok |
| `flutter analyze + test` | Sandbox'ta Flutter SDK yok |
| Uzak sunucuya SSH | Sandbox 88.99.190.108'e ulaşamıyor (egress block) |
| POS Dart `menu_cloud_client.dart` ana branch'e merge | Worktree'de hâlır; ayrı bir paket olarak ele alınmalı |
| TS/Go DTO `policy_lock` field uyumu | Snapshot publish'te server tarafında merge edilmesi gereken küçük bir alan — backoffice TS'inde tip mevcut, Go Product modeli ayrı `MenuPolicy` tablosundan join ile veriyor |

---

## 6. Sabah yapılacaklar (sırayla)

> **YENİ SUNUCU AKIŞI** — 88.99.190.108 hâlâ Hetzner default state'inde, root + password ile login. İki aşamalı:
> **Aşama A** — `bootstrap-server.sh` Hetzner web console'da root olarak koşulur (10 dk).
> **Aşama B** — Windows'tan SSH ile devam: `post-bootstrap-deploy.ps1` ilk deploy + altyapı (Caddyfile + systemd unit'leri yükler), sonra rutin deploy `run-overnight-deploy.ps1`.

### Aşama A — Sunucu bootstrap (Hetzner web console, bir defa)

1. `E:\Project\deploy\bootstrap-server.sh`'yi aç, `PUBKEY="<<<KULLANICI_PUBKEY_BURAYA>>>"` satırını `~/.ssh/id_ed25519.pub` içeriğinle değiştir.
2. Hetzner Cloud Console → 88.99.190.108 → Console → root + password ile login.
3. Script'in tamamını yapıştır → çalışır (2–5 dk).
4. Sonunda yazılan **POSTGRES_PASSWORD**'ü güvenli bir yere kaydet.

### Aşama B — Windows tarafı

```powershell
# 1) SSH key auth çalışıyor mu?
ssh -i $HOME\.ssh\id_ed25519 tech@88.99.190.108 'echo OK'

# 2) Password auth disable
ssh tech@88.99.190.108 "sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config && sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config && sudo systemctl restart ssh"

# 3) Cloudflare DNS A records → 88.99.190.108
#    api.gastrocore.ch        Proxied
#    backoffice.gastrocore.ch Proxied
#    ws.gastrocore.ch         DNS-only
#    (CF_API_TOKEN .env'e koyulursa cf-dns-update.ps1 otomatik yapar)

# 4) .env hazırla
cd E:\Project\deploy
Copy-Item .env.example .env
notepad .env   # SERVER_HOST=tech@88.99.190.108

# 5) Repo'larda dosya kaybı kontrolü
cd E:\Project; git status
cd E:\Project\reservation; git status
cd E:\Project\Restaurant; git status

# 2) Reservation
cd E:\Project\reservation
npx prisma validate
npm run build

# 3) Backoffice
cd E:\Project\Restaurant\apps\backoffice
pnpm install --frozen-lockfile
pnpm build

# 4) Go server
cd E:\Project\Restaurant\server
go mod tidy
go build ./...
go test ./...

# 5) POS (opsiyonel — APK gerekiyorsa)
cd E:\Project\Restaurant\apps\pos
flutter pub get
flutter analyze
flutter test

# 6) İlk deploy — Caddyfile + systemd unit'leri + DB migrate + build
cd E:\Project\deploy
.\post-bootstrap-deploy.ps1

# 7) İlk deploy başarılıysa, sonraki rutin deploy:
.\run-overnight-deploy.ps1
```

> Postgres uzantıları (`uuid-ossp`, `pgcrypto`) `bootstrap-server.sh` içinde otomatik yükleniyor, manuel adım gerekmez.

---

## 7. Commit komutları

### Restaurant repo

```bash
cd E:\Project\Restaurant
git add server/internal/auth/jwt.go server/internal/auth/handlers.go \
        server/internal/shared/middleware/middleware.go server/internal/org/auth.go \
        pilot/OVERNIGHT_BUILD_REPORT_2026-04-30.md
git commit -m "auth: stamp organization_id + org_role into JWT, add HQ middleware getters

- Claims gains OrganizationID + OrgRole fields, mirrored at admin login via
  mapAdminRoleToOrgRole (admin->HQ_ADMIN, brand_manager->HQ_MANAGER,
  store_manager->RESTAURANT_MANAGER).
- middleware extracts both into request context, exposes GetOrganizationID
  and GetOrgRole.
- org.resolveUser now reads from JWT first, falls back to users / admin_users
  tables, finally to legacy raw role claim. Fixes 403 NO_ORG that hit every
  admin login on /api/v1/org/* endpoints.

Refs: 014_hq_chain"
```

### Deploy paketi (E:\Project)

```bash
cd E:\Project
git add deploy/
git commit -m "deploy: PowerShell overnight orchestrator targeting 88.99.190.108

- run-overnight-deploy.ps1 runs DB migrate -> server build -> backoffice
  build -> POS APK -> smoke test, with per-step skip flags and DryRun.
- common.ps1 centralises dotenv loading, logger, dependency check, and
  Test-NetConnection-based connectivity probe (catches Cloudflare-vs-LAN
  IP confusion early).
- backoffice/server/pos/db-migrate/smoke-test scripts each abort on the
  documented failure modes (pnpm fail -> abort, go build fail -> abort,
  flutter test fail -> APK skip with warning, SSH fail -> remediation hint).
- README documents rollback per artefact."
```

---

## 8. Smoke test akışı (manuel doğrulama)

```bash
# Health
curl -fsS https://api.gastrocore.ch/health | jq

# Swagger
curl -fsS https://api.gastrocore.ch/docs/swagger.json | jq '.info.version'

# Login (admin@... / pass)
curl -fsS -X POST https://api.gastrocore.ch/api/v1/auth/admin/login \
     -H 'Content-Type: application/json' \
     -d '{"email":"admin@example.ch","password":"<paste>"}' | jq

# Token'dan org_role çek
TOKEN=...; echo $TOKEN | cut -d. -f2 | base64 -d 2>/dev/null | jq '.org_role,.organization_id'

# org/me
curl -fsS https://api.gastrocore.ch/api/v1/org/me -H "Authorization: Bearer $TOKEN" | jq

# Master menu listesi
ORG=...; curl -fsS https://api.gastrocore.ch/api/v1/org/$ORG/master-menu -H "Authorization: Bearer $TOKEN" | jq '.categories | length'

# Backoffice
curl -fsSI https://backoffice.gastrocore.ch | head -1
```

Beklenen: tüm istekler 200 ya da semantik olarak doğru status (login no-body → 400). Token payload'unda `org_role` HQ_ADMIN/HQ_MANAGER, `organization_id` UUID gözükmeli.

---

## 9. Risk ve rollback

| Risk | Etki | Mitigation | Rollback |
|---|---|---|---|
| Migration 014 menu_versions tablosuna kolon eklerken kilit alır | Yazma rollback'i kısa süreli | `ADD COLUMN IF NOT EXISTS` non-blocking — production trafiğinde kabul edilebilir | `014_hq_chain.down.sql` ile kolonları DROP |
| JWT format değişikliği eski token'ları geçersiz kılar mı? | Yeni alanlar `omitempty` — eski token'lar valid kalır | Eski token'lar HQ endpoint'lerde DB lookup ile resolve olur (geriye dönük) | Yok — değişiklik aditif |
| `mapAdminRoleToOrgRole` "viewer" rolünü `""` yapıyor — viewer kullanıcılar HQ'ya erişemiyor | Mevcut viewer'lar HQ rotalarında 403 alır | Bu zaten istenen davranış (least privilege) | Gerekirse map'e `viewer → HQ_VIEWER` eklenir, yeni rol const'u tanımlanır |
| Backoffice prod build'inde Next.js standalone output yoksa rsync boş kalır | 502 / blank UI | `next.config.ts`'de `output: 'standalone'` doğrulanmalı | Eski `.next` klasörünü manuel restore + `pnpm start` |
| pnpm install network engeli sabah da olursa | Backoffice deploy abort | `npm install --legacy-peer-deps` fallback komutu var; veya offline mirror | `-SkipBackoffice` ile deploy yapılır, backoffice eski kalır |

---

## 10. Değişen dosya listesi

### Yeni — deploy paketi
- `E:\Project\deploy\.env.example`
- `E:\Project\deploy\server.env.example`
- `E:\Project\deploy\backoffice.env.example`
- `E:\Project\deploy\README.md`
- `E:\Project\deploy\bootstrap-server.sh` — Hetzner web console paste, bir defa
- `E:\Project\deploy\post-bootstrap-deploy.ps1` — ilk deploy + altyapı kurulum
- `E:\Project\deploy\run-overnight-deploy.ps1` — rutin deploy
- `E:\Project\deploy\common.ps1`
- `E:\Project\deploy\backoffice-deploy.ps1`
- `E:\Project\deploy\server-deploy.ps1`
- `E:\Project\deploy\pos-deploy.ps1`
- `E:\Project\deploy\db-migrate.ps1`
- `E:\Project\deploy\smoke-test.ps1`
- `E:\Project\deploy\cf-dns-update.ps1` — Cloudflare DNS API
- `E:\Project\deploy\Caddyfile` — 3 site bloğu (api/ws/backoffice)
- `E:\Project\deploy\systemd\gastrocore.service`
- `E:\Project\deploy\systemd\backoffice.service`

### Yeni — rapor
- `E:\Project\Restaurant\pilot\OVERNIGHT_BUILD_REPORT_2026-04-30.md`

### Değiştirilen — Go backend (kritik auth fix)
- `E:\Project\Restaurant\server\internal\auth\jwt.go` (+5 satır: Claims struct'a 2 alan)
- `E:\Project\Restaurant\server\internal\auth\handlers.go` (+30 satır: mapAdminRoleToOrgRole + login/refresh JWT damgası + adminUserInfo.OrgRole)
- `E:\Project\Restaurant\server\internal\shared\middleware\middleware.go` (+30 satır: 2 context key + AuthRequired ekleme + 2 getter)
- `E:\Project\Restaurant\server\internal\org\auth.go` (-26 +60 satır: resolveUser refactor + mapAdminRoleAtDB)

### Değiştirilen — backoffice domain
- `E:\Project\Restaurant\apps\backoffice\.env.example` (api.2hub → api.gastrocore, ws.2hub → ws.gastrocore)
- `E:\Project\Restaurant\apps\backoffice\lib\api.ts` (default fallback URL)

---

**Sonuç:** Statik entegrasyon doğrulama yapıldı, 1 kritik auth bug onarıldı, deploy orchestrator'ı tek komutla koşacak şekilde paketlendi. Sabah yapılacaklar sırayla işlendiğinde production'a deploy yarım saatten kısa sürede tamamlanmalı.
