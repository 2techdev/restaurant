# Overnight Sprint — Reporting Automation + Users Consolidation

**Date:** 2026-05-17 → 2026-05-18 (Switzerland)
**Worktree:** `E:\Project\Restaurant\.claude\worktrees\clever-feynman-7812fd`

## What shipped

### 1. Users consolidation (PR #2)

Branch: `claude/clever-feynman-7812fd` · commit `dfce9c5`
PR: https://github.com/2techdev/restaurant/pull/2

Per operator feedback ("kanka zaten kullancilar ksiminda var ya bu"), the
short-lived stand-alone **Ekip / Team** page has been collapsed into the
existing **Kullanıcılar** page as two tabs:

- **Yönetim Kullanıcıları** → `admin_users` via `/api/v1/admin/users`
  (HQ admin, brand manager, store manager, viewer — unchanged)
- **POS Personeli** → `app_users` via `/api/v1/users`
  (manager / cashier / waiter / kitchen / kiosk — carries over everything
  Ekip provided: auto-generated 12-char password, optional 4–6 digit PIN,
  one-shot credential reveal dialog, search + role/status filter)

This branch never had the Ekip page; deploying it cleanly removes the
duplicate row from the sidebar. 5 locales updated (tr/de/en/fr/it).
Files: `apps/backoffice/app/[locale]/(dashboard)/users/page.tsx`,
`components/users/users-client.tsx`, `lib/server-data.ts`,
`messages/*.json`.

### 2. Reporting automation (PR #1)

Branch: `claude/reporting-automation-night-20260517` · commit `c6dae26`
PR: https://github.com/2techdev/restaurant/pull/1

End-to-end system for **scheduled email reports** and **business-metric
threshold alerts**.

**Migration 041 — `server/migrations/041_reporting_automation.up.sql`**
- `scheduled_reports` (id, tenant_id, name, report_type, schedule_cron,
  recipients_emails text[], format, filters_jsonb, locale, is_active,
  last_sent_at, last_status, next_run_at)
- `report_logs` (one row per send attempt — success/failed/skipped,
  duration_ms, trigger_source)
- `threshold_alerts` (id, tenant_id, name, alert_type, threshold_jsonb,
  recipients_emails, cooldown_minutes, locale, last_triggered_at,
  last_value)
- `alert_logs` (one row per firing — fired / suppressed_cooldown /
  send_failed)

**`server/internal/email/`**
Thin stdlib `net/smtp` wrapper. Multipart/alternative (HTML + auto-derived
text), MIME B-encoded subject for non-ASCII (Turkish, German umlauts,
French accents survive MTAs that mangle 8-bit headers). Port 465 implicit
TLS path + port 587 STARTTLS path. **Empty `SMTP_HOST` = dry-run** — the
rendered body is logged at info level, no actual delivery, no error — so
dev environments stay quiet without nil checks scattered through the
scheduler.

**`server/internal/reporting/`**
- `data.go` — daily-digest aggregations (revenue gross/net, by payment
  method, by order type, top 5 products, staff perf, voids/refunds,
  discount total, online order count, current stockouts). Each
  aggregate swallows its own error so a single bad query never voids
  the whole email.
- `templates.go` — `html/template` responsive email body with inline
  CSS (Gmail/Outlook strip `<style>` blocks). Swiss CHF formatting
  (`CHF 1'234.50` — apostrophe thousands separator). 5-locale L10n
  table (`tr`/`de`/`en`/`fr`/`it`).
- `cron.go` — minimal 5-field parser (exact / list / range / step /
  wildcard). Bit-set match + `Next(after)` scan with one-year horizon.
- `scheduler.go` — in-process goroutine, ticks every minute. Picks
  up `scheduled_reports` where `next_run_at <= now()`, dispatches via
  the email sender, recomputes `next_run_at` from cron, persists
  `report_logs`. Alerts re-evaluated every 5th minute.
- `alerts.go` — six alert types (`sales_drop` / `stockout_count` /
  `online_ack_delay` / `revenue_target` / `refund_spike` /
  `failed_payments`). Cooldown gate via `last_triggered_at` —
  suppressed evaluations still log so the operator sees they were
  considered.
- `handlers_scheduled.go` / `handlers_alerts.go` — tenant-scoped CRUD,
  `POST /send-now`, `POST /test`, `GET /digest/preview` (renders the
  HTML inline so the backoffice iframe can show "what would this
  look like" before subscribing).

**Wired in `cmd/server/main.go`** — module registered, scheduler started
after listen, ctx cancellation on shutdown.

**Config additions** (`internal/shared/config/config.go` + `.env.example`):
`SMTP_HOST`, `SMTP_PORT` (default 587), `SMTP_USER`, `SMTP_PASSWORD`,
`SMTP_FROM` (default `GastroCore Reports <reports@gastrocore.ch>`),
`BACKOFFICE_URL_BASE` (default `https://backoffice.gastrocore.ch` — used
in the email CTA link).

**Backoffice**
Two new sub-pages under **Raporlar** in the sidebar:

- `/[locale]/reports/automation` → list + CRUD dialog (name, report type,
  schedule preset buttons + raw cron input, recipients, format, locale),
  per-row Send-now / Preview / Edit / Delete actions, active toggle,
  Logs tab with 30 s auto-refresh.
- `/[locale]/reports/alerts` → list + CRUD dialog (type picker, threshold
  input with per-type hint, cooldown, recipients, locale), Test button
  that bypasses cooldown, Logs tab.

5-locale i18n added to `messages/{tr,de,en,fr,it}.json` (~110 new keys
per locale split between `automation` and `alerts` namespaces).

## What's verified locally

- ✅ Backoffice: `npm run build` (after `npm install --legacy-peer-deps`)
  → "Compiled successfully", 271 static pages, both new routes appear
  under `/[locale]/reports/automation` and `/[locale]/reports/alerts`.
- ✅ JSON validity: `node -e require()` on all 5 locale files; every
  expected key present.
- ✅ Go imports audited by hand — every imported symbol used; no leftover
  scaffolding. `pq.Array` for `TEXT[]` (already in `go.mod`); `html/template`
  for safe HTML; `crypto/tls` for port-465 path.

## What's NOT verified

- ❌ Server `go build ./...` could not be run locally — Go isn't
  installed on this Windows machine and `winget` install ran but didn't
  complete in time.
- ❌ **GitHub Actions runner allocation failed** for PR #1 on both the
  initial run and the rerun (both runs ended in 3–30 s with empty
  `steps[]` and a 404 on the log artifact — runner never started its
  setup phase, not a code-level failure). Logs in
  `/tmp/go-vet-logs/Go Vet & Test/system.txt` show `Job is waiting for
  a hosted runner to come online` as the last line. Closing/reopening
  the PR or pushing an empty commit should re-queue against fresh
  runners.

## What's blocked (cannot complete from this machine)

- ❌ **SSH deploy to `tech@88.99.190.108`** — port 22 outbound is blocked
  from this network (verified: `ping` works, `ssh -v` shows `Connection
  timed out` after the TCP connect). Migration 041 + binary swap +
  systemctl restart still need to happen on the host.

## How to finish the deploy in the morning

```powershell
# 1. Server binary
cd E:\Project\Restaurant\.claude\worktrees\clever-feynman-7812fd
git checkout claude/reporting-automation-night-20260517
cd server
go build -trimpath -ldflags="-s -w" -o bin\server-linux-amd64 .\cmd\server
scp -i $HOME\.ssh\id_ed25519 bin\server-linux-amd64 `
    tech@88.99.190.108:/home/tech/gastrocore/server.new

# 2. Migration + binary swap + restart
ssh -i $HOME\.ssh\id_ed25519 tech@88.99.190.108 @"
sudo -u postgres psql gastrocore < /home/tech/gastrocore/migrations/041_reporting_automation.up.sql && \
chmod +x /home/tech/gastrocore/server.new && \
mv /home/tech/gastrocore/server.new /home/tech/gastrocore/server && \
sudo systemctl restart gastrocore && \
sleep 2 && sudo systemctl is-active gastrocore && \
journalctl -u gastrocore -n 30 --no-pager | grep -i 'reporting: scheduler'
"@
# Expect: "reporting: scheduler started" in the journal tail.

# 3. SMTP creds — pick provider, then on the host:
ssh tech@88.99.190.108 'sudo systemctl edit gastrocore'
# Add:
#   [Service]
#   Environment="SMTP_HOST=smtp.gmail.com"
#   Environment="SMTP_PORT=587"
#   Environment="SMTP_USER=reports@..."
#   Environment="SMTP_PASSWORD=..."
#   Environment="SMTP_FROM=GastroCore Reports <reports@gastrocore.ch>"
# Save, then: sudo systemctl restart gastrocore

# 4. Backoffice
cd ..\apps\backoffice
npm install --legacy-peer-deps   # if not already
npm run build
tar czf C:\temp\backoffice.tar.gz -C .. backoffice
scp C:\temp\backoffice.tar.gz tech@88.99.190.108:/tmp/
ssh tech@88.99.190.108 "tar xzf /tmp/backoffice.tar.gz -C /home/tech/ && sudo systemctl restart backoffice"
```

## Smoke test (after deploy)

Open `https://backoffice.gastrocore.ch/tr/reports/automation`:

1. Click **Yeni Rapor** → fill name, leave defaults (daily_digest, daily
   23:59, your email, html, tr) → Save → row appears with status "—"
   and Next run showing tonight 23:59.
2. Click the ▶ **Şimdi gönder** button → toast "Rapor sıraya alındı"
   → flip to **Gönderim Geçmişi** tab → see new row with status
   `success` (or `failed` if SMTP isn't wired — in which case
   `journalctl -u gastrocore | grep 'email: dry-run'` should show
   the rendered subject + recipient).
3. Click the 👁 **Önizleme** button → iframe shows the HTML digest
   for yesterday with your tenant's actual numbers.

Open `https://backoffice.gastrocore.ch/tr/reports/alerts`:

4. **Yeni Uyarı** → type `sales_drop`, threshold `20`, your email →
   Save → Test (🧪) → see `alert_logs` row in the Tetiklenme tab
   (status will be `fired` if today's revenue is actually ≥20% below
   the 7-day avg, or no row will appear if the threshold isn't met
   — that's the correct behavior).

Also verify the **Ekip** sidebar row is **gone** and **Kullanıcılar**
shows two tabs after the PR-#2 deploy.

## Known limitations / next steps

- **PDF / CSV formats** are accepted by the form but the renderer
  dispatches to digest for now. Columns exist in the schema; wiring
  is a follow-up.
- **Per-tenant timezone**: scheduler uses server-local. For a Swiss
  pilot that's CET — fine. Need a `tenants.timezone` column for
  multi-region.
- **`online_ack_delay` alert** approximates "ack delay" by looking
  at `tickets.status = 'open'` older than N minutes for delivery /
  online / takeaway orders. If a real outbox table lands later,
  swap the SQL.
- **Email-CTA link** points to `/tr/reports` (the existing revenue
  page). If a per-report deep-link is desired, embed the
  `scheduled_report_id` in the email and add a backoffice route to
  re-render the report inline.
