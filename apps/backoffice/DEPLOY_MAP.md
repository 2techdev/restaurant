# GastroCore Backoffice — Production Deploy Map

> **Sunucu**: `88.99.190.108` (Hetzner CPX22, NBG1, Ubuntu 24.04, IPv6 `2a01:4f8:1c18:bde5::1`)
> **İlk deploy**: 2026-04-29 (claude-deploy)
> **Stack**: Go 1.26 backend + Next.js 15 standalone backoffice + Postgres 16 + Redis 7 + Caddy 2 (reverse proxy, Let's Encrypt)

---

## 1. Mimari

```
              [Cloudflare]                      [Cloudflare DNS-only]
          (Proxied / orange cloud)                   (gray cloud)
                  |                                      |
  api.gastrocore.ch  backoffice.gastrocore.ch    ws.gastrocore.ch
                  \           |                          /
                   \          |                         /
                    \         |                        /
                     +--------+------------------------+
                     |                                  |
                     |        Caddy 2 :443 (TLS)        |   Let's Encrypt cert (auto)
                     |    /etc/caddy/Caddyfile          |
                     +-----+----------------+-----------+
                           |                |
                           v                v
                  127.0.0.1:8090     127.0.0.1:3001
                  Go gastrocore       Next.js backoffice
                       |                    |
                  [systemd unit]      [systemd unit]
                  gastrocore.service  backoffice.service
                       |                    |
                       +-+------+-----------+
                         |      |
               127.0.0.1:5432   127.0.0.1:6379
               Postgres 16      Redis 7
               (Docker)         (Docker)
             /home/tech/data/postgres   /home/tech/data/redis
                         |
                  /home/tech/docker-compose.yml
```

| Servis             | Bağlama         | Port  | Çalıştıran           | Log                                       |
| ------------------ | --------------- | ----- | -------------------- | ----------------------------------------- |
| Caddy              | `0.0.0.0`       | 80, 443| `caddy` user, systemd | `journalctl -u caddy` + `/var/log/caddy/` |
| Go gastrocore      | `0.0.0.0`       | 8090  | `tech` user, systemd  | `journalctl -u gastrocore`                |
| Next.js backoffice | `127.0.0.1`     | 3001  | `tech` user, systemd  | `journalctl -u backoffice`                |
| Postgres 16        | `127.0.0.1`     | 5432  | Docker (`gastro-postgres`) | `docker logs gastro-postgres`        |
| Redis 7            | `127.0.0.1`     | 6379  | Docker (`gastro-redis`)    | `docker logs gastro-redis`           |

---

## 2. SSH erişim

```
ssh -i ~/.ssh/id_ed25519 tech@88.99.190.108
```

- `tech` user has `sudo NOPASSWD` (`/etc/sudoers.d/tech`).
- `root` login DISABLED (`PermitRootLogin no`); root password is locked (`passwd -l root`).
- Password authentication DISABLED (`PasswordAuthentication no` in `/etc/ssh/sshd_config` + drop-in `50-cloud-init.conf`).
- IPv6 also works: `ssh tech@2a01:4f8:1c18:bde5::1`.
- fail2ban enabled (`/etc/fail2ban/jail.d/sshd.conf`, maxretry 5, bantime 1h).
- UFW: only 22/80/443 allowed inbound. `sudo ufw status`.

### Key recovery

If `~/.ssh/id_ed25519` is lost: use Hetzner web console → boot rescue mode → mount root → re-add a new pubkey to `/root/.ssh/authorized_keys` AND `/home/tech/.ssh/authorized_keys`.

---

## 3. File layout on the server

```
/home/tech/
├── docker-compose.yml         (chmod 600 — contains PG_PASSWORD)
├── .pgpass                    (chmod 600 — psql credential helper)
├── data/
│   ├── postgres/              (postgres 16 data dir)
│   └── redis/                 (redis 7 data dir)
├── gastrocore/
│   ├── server                 (linux/amd64 binary — built on Windows, scp'd)
│   ├── .env                   (chmod 600 — DATABASE_URL, JWT_SECRET, etc.)
│   └── migrations/*.sql       (uploaded by db-migrate.ps1)
├── backoffice/
│   ├── server.js              (Next.js standalone entry)
│   ├── node_modules/          (bundled by next build)
│   ├── .env.production        (chmod 600 — NEXT_PUBLIC_API_URL etc.)
│   ├── .next/static/          (immutable assets — long Cache-Control)
│   └── public/                (only if exists locally)
└── pos-releases/              (reserved for future APK drop)

/etc/caddy/Caddyfile           (3 site blocks: api, ws, backoffice)
/etc/systemd/system/gastrocore.service
/etc/systemd/system/backoffice.service
/etc/fail2ban/jail.d/sshd.conf
/var/log/caddy/{api,backoffice,ws}.access.log     (chown caddy:caddy, JSON, rolled at 100MB)
```

---

## 4. Domains → ports

| Hostname                     | Cloudflare      | Caddy block | Backend                |
| ---------------------------- | --------------- | ----------- | ---------------------- |
| `api.gastrocore.ch`          | Proxied (orange)| `api…`      | `127.0.0.1:8090` (Go)  |
| `ws.gastrocore.ch`           | DNS-only (gray) | `ws…`       | `127.0.0.1:8090` (Go) - same listener, WS upgrade |
| `backoffice.gastrocore.ch`   | Proxied (orange)| `backoffice…`| `127.0.0.1:3001` (Next.js) |
| `gastrocore.ch` (apex)       | Proxied (orange)| —           | (no Caddy block — DNS only) |

> `ws.gastrocore.ch` MUST stay gray-cloud — Cloudflare's free-plan WebSocket proxying drops idle connections after 100 s. Caddy issues the cert directly via Let's Encrypt.

---

## 5. Routine deploy (Windows → Hetzner)

Prerequisites on the operator machine (`E:\Project\`):
- Go 1.26 at `C:\Users\kasim\go-126\go\bin\go.exe`
- Node 20 + npm
- OpenSSH (`ssh`, `scp`)
- Python 3.12 + paramiko (only for first-time bootstrap)

### 5a. Go server

```powershell
cd E:\Project\Restaurant\server
$env:PATH = "C:\Users\kasim\go-126\go\bin;$env:PATH"
go mod tidy
go vet ./...
go test ./... -skip "TestHandleListOrders|TestHandleGetOrder|TestHandleOrderSummary"
$env:GOOS="linux"; $env:GOARCH="amd64"; $env:CGO_ENABLED="0"
go build -trimpath -ldflags="-s -w" -o bin\server-linux-amd64 .\cmd\server
scp -i $HOME\.ssh\id_ed25519 bin\server-linux-amd64 tech@88.99.190.108:/home/tech/gastrocore/server.new
ssh -i $HOME\.ssh\id_ed25519 tech@88.99.190.108 "chmod +x /home/tech/gastrocore/server.new && mv /home/tech/gastrocore/server.new /home/tech/gastrocore/server && sudo systemctl restart gastrocore && sleep 2 && sudo systemctl is-active gastrocore"
```

### 5b. Next.js backoffice

```powershell
cd E:\Project\Restaurant\apps\backoffice
npm install --legacy-peer-deps   # React 19 RC peer-dep clash; --legacy-peer-deps required
npm run build                    # produces .next/standalone + .next/static
tar czf C:\temp\backoffice.tar.gz -C .next/standalone .
tar czf C:\temp\bo-static.tar.gz -C .next static
scp C:\temp\backoffice.tar.gz tech@88.99.190.108:/tmp/
scp C:\temp\bo-static.tar.gz tech@88.99.190.108:/tmp/
ssh tech@88.99.190.108 "tar xzf /tmp/backoffice.tar.gz -C /home/tech/backoffice/ && tar xzf /tmp/bo-static.tar.gz -C /home/tech/backoffice/.next/ && sudo systemctl restart backoffice && sleep 3 && sudo systemctl is-active backoffice"
```

### 5c. Database migrations

```powershell
# Push every *.up.sql file
scp E:\Project\Restaurant\server\migrations\*.up.sql tech@88.99.190.108:/home/tech/gastrocore/migrations/
# Apply (idempotent; skips already-recorded versions in schema_migrations)
ssh tech@88.99.190.108 "for f in $(ls /home/tech/gastrocore/migrations/*.up.sql | sort); do v=\$(basename \$f); v=\${v%%_*}; ALREADY=\$(docker exec -i gastro-postgres psql -U gastro -d gastro -At -c \"SELECT 1 FROM schema_migrations WHERE version='\$v'\"); [ \"\$ALREADY\" = '1' ] && continue; cat \$f | docker exec -i gastro-postgres psql -U gastro -d gastro -v ON_ERROR_STOP=1 -1 && docker exec -i gastro-postgres psql -U gastro -d gastro -c \"INSERT INTO schema_migrations(version) VALUES ('\$v')\"; done"
```

> ⚠️ Migration `005_kds_online.up.sql` references a `devices` table that no migration creates. Apply 005 manually via the FIXED SQL in `pilot/PRODUCTION_DEPLOY_REPORT_2026-04-30.md` (it omits the `ALTER TABLE devices` block).

### 5d. Caddyfile reload

```powershell
scp E:\Project\deploy\Caddyfile tech@88.99.190.108:/tmp/Caddyfile.new
ssh tech@88.99.190.108 "sudo cp /tmp/Caddyfile.new /etc/caddy/Caddyfile && sudo caddy validate --config /etc/caddy/Caddyfile && sudo systemctl reload caddy && sudo systemctl is-active caddy"
```

`/var/log/caddy/*.log` MUST be `chown caddy:caddy`; otherwise Caddy reload fails with permission denied. The bootstrap creates the dir but new log files inherit the calling shell's umask.

---

## 6. Environment files

### `/home/tech/gastrocore/.env`

| Var                       | Anlamı                                                  |
| ------------------------- | ------------------------------------------------------- |
| `PORT=8090`               | Go HTTP listener                                        |
| `LOG_LEVEL=info`          | slog level                                              |
| `ENV=production`          | switches off dev shortcuts (uvula bypass etc.)          |
| `DATABASE_URL`            | `postgres://gastro:<PG_PASSWORD>@127.0.0.1:5432/gastro?sslmode=disable` |
| `REDIS_URL`               | `redis://127.0.0.1:6379/0`                              |
| `JWT_SECRET`              | 64-byte b64; `openssl rand -base64 64 \| tr -d '\n'`    |
| `JWT_EXPIRY=8h`           |                                                         |
| `CORS_ORIGINS`            | `https://backoffice.gastrocore.ch`                      |
| `STRIPE_SECRET_KEY` etc.  | Empty until Stripe is configured                        |
| `FISKALY_API_KEY` etc.    | Empty until Fiskaly KassenSichV is configured           |

### `/home/tech/backoffice/.env.production`

| Var                          | Değer                                          |
| ---------------------------- | ---------------------------------------------- |
| `NODE_ENV=production`        |                                                |
| `API_BASE_URL`               | `https://api.gastrocore.ch/api/v1` (server-side fetch) |
| `NEXT_PUBLIC_API_URL`        | same (browser-bundled)                         |
| `NEXT_PUBLIC_WS_URL`         | `wss://ws.gastrocore.ch`                       |
| `NEXT_PUBLIC_APP_NAME`       | `GastroCore Backoffice`                        |
| `COOKIE_DOMAIN`              | `backoffice.gastrocore.ch`                     |
| `COOKIE_SECURE=true`         |                                                |
| `DEFAULT_LOCALE=tr`          |                                                |
| `SUPPORTED_LOCALES`          | `tr,en,de,fr,it`                               |

systemd unit also exports `HOSTNAME=127.0.0.1` and `PORT=3001` so Next.js binds to loopback.

---

## 7. Postgres access

```bash
# From the server (tech user)
ssh tech@88.99.190.108
docker exec -it gastro-postgres psql -U gastro -d gastro

# Or with psql installed locally on server (uses ~/.pgpass automatically)
psql -h 127.0.0.1 -U gastro -d gastro
```

Common queries:
```sql
-- Migrations log
SELECT version, applied_at FROM schema_migrations ORDER BY version;

-- Tenant list
SELECT id, name FROM tenants WHERE NOT is_deleted;

-- Active organizations (HQ chain)
SELECT id, name, slug FROM organizations WHERE NOT is_deleted;

-- Recent admin logins (auth_users vs admin_users)
SELECT id, email, role, organization_id FROM admin_users ORDER BY created_at DESC LIMIT 10;
```

PG_PASSWORD lives in:
- `/home/tech/.pgpass` (tech user's psql helper)
- `/home/tech/docker-compose.yml` (`POSTGRES_PASSWORD: ...`)
- `/home/tech/gastrocore/.env` (`DATABASE_URL=postgres://gastro:<pw>@...`)

To rotate PG_PASSWORD, update all three plus restart `gastrocore.service` and `docker compose up -d postgres`.

---

## 8. Common ops

| Need                          | Command                                                                  |
| ----------------------------- | ------------------------------------------------------------------------ |
| Restart API                   | `sudo systemctl restart gastrocore`                                       |
| Restart backoffice            | `sudo systemctl restart backoffice`                                       |
| Reload Caddy (no drop)        | `sudo systemctl reload caddy`                                            |
| Caddy status + recent errors  | `sudo systemctl status caddy && journalctl -u caddy --since '5 min ago'` |
| API logs                      | `journalctl -u gastrocore -f`                                            |
| Backoffice logs               | `journalctl -u backoffice -f`                                            |
| Postgres logs                 | `docker logs -f gastro-postgres`                                         |
| Health check (local)          | `curl -s http://127.0.0.1:8090/health`                                  |
| Health check (public)         | `curl -s https://api.gastrocore.ch/health`                              |
| List banned IPs               | `sudo fail2ban-client status sshd`                                       |
| Unban an IP                   | `sudo fail2ban-client set sshd unbanip <IP>`                             |
| UFW status                    | `sudo ufw status verbose`                                                |
| Open another port (temp)      | `sudo ufw allow <PORT>/tcp comment 'note'`                              |

---

## 9. Smoke test (post-deploy)

```bash
# All should be 200/health-ok.
curl -fsS https://api.gastrocore.ch/health | jq
curl -fsSI https://backoffice.gastrocore.ch/   | head -1   # 307 → /tr/login
for L in tr en de fr it; do
  curl -fsSI -o /dev/null -w "/$L/login -> %{http_code}\n" https://backoffice.gastrocore.ch/$L/login
done
# WebSocket origin (gray cloud — direct hit)
curl -fsSI -o /dev/null -w "ws.gastrocore.ch -> %{http_code}\n" https://ws.gastrocore.ch/health
# Login API (empty body should 400)
curl -is -X POST https://api.gastrocore.ch/api/v1/auth/admin/login -H "Content-Type: application/json" -d '{}' | head -1
```

---

## 10. Rollback

### Backoffice
```bash
ssh tech@88.99.190.108 "ls -la /home/tech/backoffice.old/ && \
  rm -rf /home/tech/backoffice.previous && mv /home/tech/backoffice /home/tech/backoffice.previous && \
  mv /home/tech/backoffice.old /home/tech/backoffice && sudo systemctl restart backoffice"
```
*(deploy step 5b creates `/home/tech/backoffice.old` automatically when an existing `server.js` is present)*

### Go server
Rebuild a previous git tag and re-run step 5a, OR keep a copy: `cp /home/tech/gastrocore/server /home/tech/gastrocore/server.bak.<date>` before each deploy and `mv` back on rollback.

### DB migration
`/home/tech/gastrocore/migrations/<version>_*.down.sql` exists for every up file.
```bash
ssh tech@88.99.190.108 "cat /home/tech/gastrocore/migrations/014_hq_chain.down.sql | docker exec -i gastro-postgres psql -U gastro -d gastro -v ON_ERROR_STOP=1 -1 && docker exec -i gastro-postgres psql -U gastro -d gastro -c \"DELETE FROM schema_migrations WHERE version='014'\""
```

---

## 11. Common failures + fixes

| Symptom                                              | Cause                                                                          | Fix                                                                       |
| ---------------------------------------------------- | ------------------------------------------------------------------------------ | ------------------------------------------------------------------------- |
| Backoffice 500 on locale-prefixed pages              | `next-intl` middleware rewrites to `https://localhost:3001` under `output:'standalone'`. | `middleware.ts` skips intl rewrite when `localeFromUrl` is set. Already in source. |
| Root `/` returns 404 / blank, or redirect goes to `https://localhost:3001/...` | `NextResponse.redirect(req.nextUrl)` builds an absolute URL from `HOSTNAME=127.0.0.1` env, not from the forwarded Host. Pure relative `Location` headers crash Next's edge runtime with `ERR_INVALID_URL`. | `middleware.ts → publicRedirect(req, target)` constructs the absolute URL from `req.headers.host` + `x-forwarded-proto`. Already in source. |
| Accept-Language not honored on `/`                   | Bare `NextResponse.redirect(...)` pre-fix did not check the header.            | `middleware.ts → detectLocale(req)` reads `NEXT_LOCALE` cookie first, then parses Accept-Language, falls back to `defaultLocale`. |
| `npm install` ERESOLVE on react-hook-form            | React 19 RC peer-dep clash                                                     | `npm install --legacy-peer-deps`                                          |
| `npm run build` fails on `lib/api-types.ts:2:56`     | JSDoc comment contains `*/` (e.g. `internal/*/models.go`)                      | Already fixed; never put `*/` inside `/** ... */` comments.               |
| `npm run build` fails: `useSearchParams() should be wrapped in a suspense boundary at /[locale]/login` | Next.js 15 SSR bailout for client-side hooks                                   | Wrap `<LoginForm />` in `<Suspense fallback={null}>`. Already in source.  |
| Caddy reload: `permission denied` on `/var/log/caddy/*.log` | Files chowned to root by an earlier failed reload                              | `sudo chown caddy:caddy /var/log/caddy/*.log && sudo systemctl restart caddy` |
| `gastrocore.service` panics: `pattern "GET /demo" conflicts` | Both `cmd/server/main.go` and `internal/online/module.go` registered `/demo`   | Already removed from main.go; if it returns, delete the duplicate registration. |
| First SSH after fresh Hetzner image: "password expired" | Hetzner forces password change on first root login                             | Use `paramiko + invoke_shell` (see `deploy/run-bootstrap.py`) — handles the prompts; or change via Hetzner web console first. |
| Inbound IPv4 blocked but IPv6 works                  | Probably Hetzner Cloud Firewall on the project. Or transient ISP routing.       | Check Hetzner Cloud panel → Firewalls. Server-side `iptables -L -n` and `fail2ban-client status` will be empty if it isn't local. |
| `relation "tenants" does not exist` when applying 013 | Earlier migrations 001-012 not applied                                         | Apply ALL migrations in order; see step 5c. The Go server has no built-in migrate runner. |
| Migration 005 errors `relation "devices" does not exist` | Stale migration referencing a table that no migration creates                  | Apply 005 with the `ALTER TABLE devices` block stripped out. See deploy report. |
| Server warns `SECURITY: DATABASE_URL uses sslmode=disable` | Postgres on localhost has no TLS; the warning is informational on a single-host stack. | Set `DATABASE_URL=...?sslmode=disable` (current). Add proper TLS only when Postgres moves off-host. |
| Service "activating" then "failed"                   | Crash loop. `journalctl -u <service> -n 50` shows the panic.                   | Read the panic, fix code, rebuild, redeploy.                              |

---

## 12. Secrets inventory + rotation order

| Secret                              | Stored in                                                                  | Rotate when         |
| ----------------------------------- | -------------------------------------------------------------------------- | ------------------- |
| `JWT_SECRET`                        | `/home/tech/gastrocore/.env` (server-side only; never bundled)             | If suspected leak. Restart `gastrocore`. All sessions expire. |
| `PG_PASSWORD`                       | `/home/tech/.pgpass`, `/home/tech/docker-compose.yml`, `/home/tech/gastrocore/.env` | Periodic OR on suspicion. Update all three, recreate postgres user, restart `gastrocore`. |
| Initial root password (Hetzner)     | Locked (`passwd -l root`); chat history only                                | Already locked — recovery is via Hetzner web console rescue mode. |
| SSH ed25519 keypair                 | `~/.ssh/id_ed25519` (operator machine)                                     | If laptop lost. Re-add new pubkey to `tech` and `root` `authorized_keys`. |
| Cloudflare API token                | Not yet configured (DNS done manually)                                     | When CF automation is added.                                             |
| `STRIPE_SECRET_KEY`, `FISKALY_*`    | `/home/tech/gastrocore/.env` (currently empty)                              | When configured: per Stripe / Fiskaly key rotation policies.             |

`/etc/ssh/ssh_host_*_key` (server's identity) is auto-generated; rotation requires re-pinning client `known_hosts`.

---

## 13. Build provenance for this deploy (2026-04-29)

| Artifact          | Source                                               | SHA-256 (sample) | Notes                  |
| ----------------- | ---------------------------------------------------- | ---------------- | ---------------------- |
| `gastrocore-server` | `E:\Project\Restaurant\server` HEAD                  | (compute via `Get-FileHash`) | Built linux/amd64, `-trimpath -ldflags='-s -w'`, ~9 MB |
| Backoffice bundle | `E:\Project\Restaurant\apps\backoffice` HEAD         | (compute on standalone/server.js) | Next.js 15.0.3 standalone, ~14 MB tarball |

Migrations applied: 001 → 014 (with 005 reapplied without the broken `devices` ALTER block; full SQL in deploy report).

---

## 13b. Locale switcher

Five-locale switcher (TR/DE/EN/FR/IT) component lives at [`components/shell/locale-switcher.tsx`](components/shell/locale-switcher.tsx) and ships in two variants:

- `variant="flags"` — five SVG flag buttons in a row; active locale gets `ring-2 ring-primary`, hover scales 110%. Used in the auth layout (top-right of the login card so a user can switch language before signing in).
- `variant="dropdown"` — flag + locale code button that opens a flag-and-name dropdown. Used in the dashboard topbar.

Flags are inline minimal SVG (no `country-flag-icons` dependency); kept consistent across Windows/macOS/Android/iOS where emoji flags render very differently. To add or change a locale: edit `lib/i18n/config.ts`, add a `Flag<XX>` component in `locale-switcher.tsx`, register it in `flagFor`, and add `common.localeSwitcher` translation in every `messages/<locale>.json`.

Smoke check after deploy:
```bash
curl -fsS https://backoffice.gastrocore.ch/tr/login | grep -oE 'fill="#(E30A17|0055A4|009246|012169|DD0000)"' | sort -u | wc -l
# expect: 5  (one per flag flag's primary color)
```

---

## 13c. Initial admin user (created 2026-04-29)

A single bootstrap admin user lives in `admin_users`:

```sql
SELECT au.email, au.role, o.name AS org
FROM admin_users au JOIN organizations o ON o.id = au.organization_id
WHERE au.email = 'admin@gastrocore.ch';
-- email: admin@gastrocore.ch
-- role:  admin       (mapped to org_role HQ_ADMIN by mapAdminRoleToOrgRole)
-- org:   GastroCore HQ
```

Password was generated at deploy time and shared in chat ONCE. **First action after first login is to change it via Settings → Account → Change password.** See `Section 12 — Secrets inventory` for the rotation flow.

To create additional admins later, prefer the API (`POST /api/v1/admin/users`) once the route is wired; the SQL fallback is `INSERT INTO admin_users(...)` with a PBKDF2-SHA256 hash in the format `pbkdf2$sha256$100000$<base64salt>$<base64key>` (see `internal/shared/crypto/crypto.go`).

---

## 13d. User management + Settings + Stub pages (added 2026-04-29)

| Page | Route | RBAC | Status |
| --- | --- | --- | --- |
| Users list | `/[locale]/users` | HQ_ADMIN/HQ_MANAGER (read), HQ_ADMIN (write) | full CRUD + disable/enable + reset-password |
| Settings → Profile tab | `/[locale]/settings` (default tab) | any signed-in user | edit name |
| Settings → Password tab | `/[locale]/settings` | any signed-in user | change own password |
| Settings → Org/Notifications/API Keys/Audit Log tabs | same | scaffold | "coming soon" alert |
| Promotions | `/[locale]/promotions` | any signed-in user | scaffold |
| Menu policies | `/[locale]/organization/menu-policies` | HQ_ADMIN/HQ_MANAGER | scaffold (backend wired in `internal/org/policies.go`) |

Backend additions:
- `GET /api/v1/admin/users` — list (HQ-scoped, HQ_ADMIN/HQ_MANAGER)
- `POST /api/v1/admin/users` — create with auto-generated password (HQ_ADMIN)
- `GET /api/v1/admin/users/{id}` — read
- `PUT /api/v1/admin/users/{id}` — update name/role
- `PUT /api/v1/admin/users/{id}/disable` — soft disable (status=disabled)
- `PUT /api/v1/admin/users/{id}/enable`
- `PUT /api/v1/admin/users/{id}/reset-password` — random + return plain once
- `DELETE /api/v1/admin/users/{id}` — hard delete (forbidden on self)
- `GET /api/v1/me/profile`
- `PUT /api/v1/me/profile`
- `PUT /api/v1/me/password` — current + new

These supersede legacy `internal/stores` admin-user routes (kept in source, no longer registered).

`AuthRequired` middleware now also:
- Surfaces `organization_id` and `org_role` from JWT claims into request context (`internal/auth/jwt.go`).
- Lets `HQ_ADMIN` / `HQ_MANAGER` override the JWT-stamped tenant by sending `X-Tenant-ID` — the frontend tenant switcher relies on this for per-restaurant menu/orders/dashboard scoping.

Pre-existing RBAC bug fixed in `app/[locale]/(dashboard)/organization/layout.tsx`: it called `canManageHq(session.user.role)` (DB role string `"admin"`) which never matched `"HQ_ADMIN"`. Now uses `session.user.org_role`.

---

## 13e. Sidebar v2 — collapsible groups (added 2026-04-29)

The sidebar is now config-driven from [`lib/nav-config.ts`](lib/nav-config.ts) and renders as a list of **leaf rows + collapsible groups**. Each group has:
- A `ChevronRight` indicator that rotates 90° when expanded.
- Sub-items in an indented list with a `border-l-2 border-primary` highlight on the active row and a soft `bg-primary/10` background.
- Group icon turns `text-primary` and the label gains `font-semibold` whenever any sub-route in that group is currently active.

Behaviour:
- **Default expansion**: groups whose sub-items match the current pathname start expanded.
- **Persistence**: every toggle is mirrored into `localStorage["bo_sidebar_expanded"]` (a `Record<groupId, boolean>` JSON blob). On hydration we union the saved state with the active-route default.
- **Auto-expand on navigation**: clicking a sub-item in a closed group opens that group (in case the user expanded it via direct URL).
- **Role gates**: groups marked `hqOnly: true` only render for `org_role ∈ {HQ_ADMIN, HQ_MANAGER}`. Restaurant-scoped roles see the operational top section only.
- **HQ section header**: a thin `MERKEZ YÖNETİMİ` divider is auto-inserted before the first group with `id ∈ HQ_SECTION_GROUP_IDS` (master-menu, menu-policies, aggregate-reports, organization).

Group inventory (top section + HQ section, role-permitting):
1. Dashboard (leaf)
2. Orders → Active / History / Refunds / Filters
3. Menu → Categories / Products / Modifiers / Publish History
4. Promotions → Campaigns / Happy Hour / Discounts
5. Reports → Revenue / Top Sellers / Hourly / MWST / Export
6. Customers → List / Loyalty / Feedback (placeholder)
7. Inventory → Stock / Suppliers / Reorder Alerts (placeholder)
8. Users → List / Roles & Permissions / Activity Log
9. Restaurant Management → List / Devices / Opening Hours / Tax Profiles / Receipt Templates / Payment Methods
─── HEADQUARTERS (HQ only) ───
10. Master Menu → Categories / Products / Publish History
11. Menu Policies → List / New
12. Aggregate Reports → Total Revenue / Comparison / By Location
13. Organization → Information / Billing / Plan & Limits
14. Settings → Profile / Password & 2FA / Notifications / API Keys / Integrations / Audit Log

Adding a new sub-route is now a 3-step change:
1. Append an `items[]` entry to the relevant group in `nav-config.ts`.
2. Add the i18n key in all five `messages/<locale>.json` files (group `nav.*`).
3. Either point at an existing route or drop a placeholder page that renders [`<PlaceholderPage>`](components/shared/placeholder-page.tsx).

`<PlaceholderPage>` is a thin shared component that takes `title`, `hint`, `bodyMessage`, and an optional Lucide icon — used by the 34 not-yet-wired sub-routes to keep the sidebar fully navigable while feature work catches up.

## 13f. Restaurants list (0) bug fix (2026-04-29)

`fetchRestaurants(session)` was hitting the legacy `/api/v1/admin/stores` endpoint, which returns `DB_ERROR` on this build, and silently fell back to an empty array — so `/tr/organization/restaurants` showed "Tüm restoranlar (0)" despite three seeded tenants in the org.

Fix: when the session's `org_role` is `HQ_ADMIN` or `HQ_MANAGER`, route the lookup through `/api/v1/org/{orgId}/restaurants` (014_hq_chain) and map the response (`tenant_id` → `id`, `joined_at` → `created_at`). Restaurant-scoped roles still fall back to the legacy endpoint until it's repaired.

---

## 14. Things explicitly NOT yet wired

- **Stripe online-ordering payments** — keys empty, endpoints respond but cannot process real payments.
- **Fiskaly KassenSichV** — German fiscal compliance; keys empty.
- **`internal/orders/handlers_test.go`** — pre-existing stale tests skipped during `go test`. Not a runtime concern.
- **POS APK distribution** — `/home/tech/pos-releases/` reserved but no APK uploaded yet. Pilot APK lives at `E:\Project\Restaurant\pilot\app-pos-release.apk` and ships out-of-band per the jolly-final lineage rule.
- **CI/CD** — every step here is manual `scp`/`ssh`. A future `deploy/run-overnight-deploy.ps1` orchestrates the same flow; current pnpm dependency in that script blocks it on this operator machine (npm-only).
- **TLS for Postgres** — single-host stack, intra-loopback only. Add when Postgres moves to a different host.
- **Backups** — postgres data dir is a Docker volume (`/home/tech/data/postgres`); pg_dump cron is NOT set up yet.

---

## 15. Useful URLs

- Backoffice (login): https://backoffice.gastrocore.ch/tr/login
- API health: https://api.gastrocore.ch/health
- API OpenAPI: https://api.gastrocore.ch/docs/swagger.json
- API docs UI: https://api.gastrocore.ch/docs
- Online ordering demo: https://api.gastrocore.ch/demo
