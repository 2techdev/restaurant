# POS Go server — perf + bug audit (2026-05-17 gece sprint)

Branch: `claude/server-perf-night-20260517`
Scope: `E:\Project\Restaurant\server\` (go binary, port 8090).

This audit was performed as a static review (Go toolchain not installed in
the sprint environment — `go vet` / `go build` need to be re-run on the
deploy host).

## Top 10 perf observations

| # | Area | Finding | Status |
|---|------|---------|--------|
| 1 | Observability | No `/metrics` endpoint; latency only in slog | **FIXED** — `server/internal/shared/metrics/metrics.go` exposes Prometheus exposition (`gastrocore_http_requests_total`, `gastrocore_http_request_duration_seconds`, DB pool gauges, goroutine count, heap bytes) via `middleware.SetRequestRecorder(metrics.RecordRequest)`. |
| 2 | Indexes | Composite indexes missing for hot list/paginate patterns (tickets, bills, order_items, products by category, menu_sync_events idempotency, notifications unread, shifts.open). Existing single-column indexes force bitmap-heap-scan back to the table. | **FIXED** — migration 024 adds 10 composite/partial indexes. Idempotent (`CREATE INDEX IF NOT EXISTS`). |
| 3 | Query bounds | Handler DB queries used the raw request context — a slow query could outlast the response and pile up. | **FIXED** — `middleware.RequestTimeout(25s)` caps request context; WS / `/realtime` / `/stream` paths excluded. 25s < HTTP server WriteTimeout (30s) so handlers see `ctx.Done()` before forced close. |
| 4 | Connection pool | DB pool already sized at MaxOpen=25 / MaxIdle=10 in `database.Connect`. **No action**, but exposed via `gastrocore_db_pool_*` so capacity is observable now. | OK |
| 5 | Cache layer | Dashboard aggregates + menu tree have no Redis-style cache. With current pilot tenant size this isn't blocking; revisit when tenant count crosses ~50. | DEFER |
| 6 | Menu modifiers | `fetchModifiers(groupID)` loops per group → N+1 query pattern in `handleListModifiers` when no `product_id` filter. Pilot tenant has <30 groups so impact is small. | NOTED — fix when modifier CRUD lands (Aşama 2). |
| 7 | Pagination | `/api/v1/menu/products` lacks `limit/offset` cursor; full list per tenant. Pilot ~150 items, ok for now but degrades after 1k. | NOTED |
| 8 | Outbound HTTP | Only `gastrohub_client.go` sets a per-request timeout (30s). Other outbound clients (Fiskaly, Stripe, ERPNext) should be audited next sprint. | NOTED |
| 9 | WS broadcast | `online.OnlineHub` and `kds.NewHub` use unbuffered fan-out under a lock; slow subscriber stalls the entire room. Pilot has ≤4 subscribers so it never hits — but adding per-client buffer queue is the standard fix. | NOTED |
| 10 | Logger | slog writes JSON on every request including `/metrics` polls. Filter `/metrics` and `/health` from access log (or sample) once Prometheus scrape is wired (every 15s = 5760 events/day). | NOTED |

## Top 10 bug observations

| # | Severity | Finding | Status |
|---|----------|---------|--------|
| 1 | Low | `loadExistingMapping` in `menu/import_apply.go` returned early on Scan failure without closing `rows`. Already had `rows.Close()` after the loop. | Fine — early-return only happens on Scan error after which the conn is recycled by `tx.Rollback()` in the outer defer. |
| 2 | Low | `metrics.counterMap.inc` does a double-checked write under lock for new keys — correct, no race. | OK |
| 3 | Med | No request-context deadline on long-running endpoints (reports, sync snapshot). | **FIXED** via `RequestTimeout(25s)` middleware (#3 above). |
| 4 | Low | `requestRecorder` global in `middleware` is unguarded — fine because `SetRequestRecorder` is called once at startup before traffic. Documented in code. | OK |
| 5 | Low | i18n catalog: missing translation falls back to English, then to the code. Code text leaks via the wire if a key is added without a catalog entry. Acceptable; logged as DEBUG by the catalog. | OK |
| 6 | High | `/admin/*` routes had **no JWT enforcement** in the gate (only `/api/v1/*` was authenticated). Any unauthenticated client could hit admin endpoints. | **FIXED** — `authGate` now matches `/admin/*` too, with a public carve-out only for the Bexio OAuth callback. |
| 7 | Med | OSD endpoints `/api/v1/osd/{slug}/*` are intended to be public (kiosk display) but were caught by the JWT gate. | **FIXED** — explicit prefix carve-out in `authGate`. |
| 8 | Low | `nullableString` returns `interface{}` to satisfy lib/pq driver — works but fragile against type assertions. | Acceptable. |
| 9 | Med | `online.OnlineHub.Run()` goroutine has no shutdown channel; on `srv.Shutdown` it leaks until process exit. Negligible (process is exiting). | NOTED |
| 10 | Low | CORS allow-list hard-codes `192.168.1.134:*` for test box. Env override (`CORS_ORIGINS`) already supported; document deployment. | NOTED |

## Endpoint stubs delivered (unblock parallel sessions)

All return `501 NOT_IMPLEMENTED` with `{module, op}` details and enforce JWT
+ role checks where applicable. Parallel sessions can replace handler bodies
one-by-one without touching routing.

- **Loyalty** (`server/internal/loyalty/`): `/api/v1/loyalty/accounts/{customer_id}` (get/history/earn/redeem/adjust) + `/api/v1/loyalty/tiers` + admin tier + rules CRUD.
- **Order Profiles** (`server/internal/order_profiles/`): `/api/v1/order-profiles` CRUD + `/apply`.
- **Tasks / HACCP** (`server/internal/tasks/`): staff `/api/v1/tasks` list/complete/skip + admin `/admin/tasks/templates` CRUD + `/admin/tasks/haccp/report`.
- **OSD** (`server/internal/osd/`): public `/api/v1/osd/{slug}/{active-tickets,now-serving,realtime}`.
- **Manager mobile** (`server/internal/manager_mobile/`): `/api/v1/manager/{dashboard,notifications,notifications/{id}/ack,alerts,realtime}` (manager role+).
- **Customer analytics** (`server/internal/customer_analytics/`): `/admin/segments` + `/admin/campaigns` CRUD + run + members + send + results.

## Files touched

```
A  pilot/PERF_AUDIT_2026-05-17.md                             (this report)
A  server/internal/customer_analytics/module.go
A  server/internal/loyalty/module.go
A  server/internal/manager_mobile/module.go
A  server/internal/order_profiles/module.go
A  server/internal/osd/module.go
A  server/internal/tasks/module.go
A  server/internal/shared/i18n/i18n.go
A  server/internal/shared/metrics/metrics.go
A  server/migrations/024_perf_indexes.up.sql
A  server/migrations/024_perf_indexes.down.sql
M  server/cmd/server/main.go        (imports, module init, route registration, authGate /admin/* + OSD, i18n + RequestTimeout in chain, metrics.Register + SetRequestRecorder)
M  server/internal/shared/middleware/middleware.go   (RequestRecorder hook in Logger + RequestTimeout)
M  server/internal/shared/response/response.go       (LocalizedError + LocalizedErrorWithDetails)
```

> Note: an earlier draft included a `server/internal/bexio/` stub for
> third-party accounting OAuth. Removed at user request — the business
> uses its own accounting workflow, no external integration needed.

## What was NOT done

- `go vet` / `go build` / `go test ./...` — Go toolchain not in this
  sprint environment. Must be re-run on a host with Go installed.
- Hetzner deploy — postponed until vet/build is clean.
- Detailed audit of WS hubs / inventory / reports — pattern-match scan
  only; deep review needs runtime tracing.

## Suggested deploy sequence

1. `cd server && go vet ./... && go test ./... && go build ./cmd/server`
2. Apply migration: `DATABASE_URL=... go run ./cmd/migrate up`
   (idempotent — only 023 and 024 are new since last deploy)
3. Restart `gastrocore-server` systemd unit on 88.99.190.108.
4. Smoke: `curl https://api.gastrocore.ch/health` → 200, `curl https://api.gastrocore.ch/metrics | head -30` → Prometheus output, `curl -H "Accept-Language: tr" https://api.gastrocore.ch/api/v1/loyalty/tiers` (no auth) → 401 with Turkish message.
