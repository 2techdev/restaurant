# 24 - Execution Plan

> **Document Status:** Authoritative | **Last Updated:** 2026-03-20
>
> Ordered delivery plan from current state to market-ready product.
> Based on actual codebase state (doc 21) and gap analysis (doc 22).

---

## 1. Executive Diagnosis

GastroCore has a **strong single-device POS core** that is already better than many commercial POS products in its domain logic quality, test coverage, and hardware integration depth.

The product is **blocked from piloting** by three specific gaps:
1. KDS is not connected to real orders
2. There is no multi-device coordination (even on LAN)
3. There is no production build and distribution mechanism

These three gaps can be closed in **4–6 weeks** with focused effort, enabling a real pilot restaurant to operate.

Everything else is sequenced after the pilot delivers validated feedback.

---

## 2. What Is Already Strong

- PIN auth, role-based access — complete, tested
- Full POS order flow with modifiers — complete, tested
- Payment terminal integration (Wallee LTI + MyPOS WiFi) — production-grade implementation
- Table/floor plan with drag-drop, merge, transfer — complete, 22/22 tests
- Shift open/close with Z-report printing — complete, 27/27 tests
- Swiss MWST receipt builder with 5-Rappen rounding — 36 tests
- Multi-printer support (Bluetooth/USB/WiFi) — solid
- 33-table SQLite schema with UUID v7 and immutable log — well-designed
- Go modular monolith skeleton with proper routing and middleware — ready to implement

---

## 3. What Is Dangerously Missing

| Risk Level | Missing Item |
|-----------|-------------|
| BLOCKS PILOT | KDS wired to real kitchen_tickets data |
| BLOCKS PILOT | LAN sync / multi-device coordination |
| BLOCKS PILOT | Production build + keystore + APK distribution |
| BLOCKS PILOT | Swiss VAT dine-in/takeaway toggle in POS flow |
| BLOCKS REVENUE | License enforcement (any tier gating) |
| BLOCKS REVENUE | CI/CD for reliable release process |
| BLOCKS GROWTH | Cloud sync engine (Go backend implementation) |
| BLOCKS GROWTH | Cloud dashboard for restaurant owners |
| COMPLIANCE | Germany Fiskaly/TSE (deferred to post-Swiss-pilot) |

---

## 4. Architecture Freeze Summary

See doc 23 for full details. Key frozen decisions:

| Decision | Outcome |
|----------|---------|
| ERPNext | **Removed permanently.** Custom backoffice via export API. |
| Redis | **Removed from v1.** PostgreSQL outbox only. |
| KDS | **Screen within POS app**, not separate binary |
| Sync order | **LAN first** (Phase 2), **cloud second** (Phase 3) |
| Country order | **Switzerland first**, Germany after Swiss pilot |
| Deployment | **Modular Go monolith**, no microservices |

---

## 5. Recommended Delivery Order

```
Phase 0 (DONE):    Core POS + payments + tables + shifts + printing
                   ↓
Phase 1 (NOW):     KDS wired + production build + Swiss VAT toggle
                   ↓
Phase 2 (NEXT):    LAN sync + multi-device + license basics
                   ↓
Phase 3:           Swiss pilot + Swiss compliance hardening
                   ↓
Phase 4:           Cloud sync + Go backend + cloud dashboard
                   ↓
Phase 5:           Germany fiscal pack (post-Swiss-pilot)
                   ↓
Phase 6:           Online channels (ordering, QR, kiosk)
                   ↓
Phase 7:           Retail mode + custom backoffice export
```

---

## 6. Phase 1: Pilot Unblock (Weeks 1–6)

**Goal:** A single restaurant can run a full service day using GastroCore on one tablet + one KDS tablet.

### Sprint 1.1 — KDS Wired (Week 1–2)

| Task | Detail |
|------|--------|
| Wire KDS to `kitchen_tickets` stream | Replace `_buildDemoTickets()` with Drift StreamProvider |
| Order submit → kitchen ticket | POS submit action writes `KitchenTickets` + `KitchenTicketItems` rows |
| Bump → DB write | `_bumpTicket()` writes `status = completed` to DB |
| Kitchen ticket entity → provider | Add `KitchenTicketProvider` reading live DB stream |
| Station filter UI | KDS screen filter by category/station assignment |

Single-device KDS works immediately (same SQLite). Multi-device requires Phase 2.

### Sprint 1.2 — Production Build + Swiss VAT (Week 2–3)

| Task | Detail |
|------|--------|
| Release keystore verification | Confirm `gastrocore-release.jks` + `key.properties` exist |
| `flutter build appbundle --release` | Verify clean AAB build |
| `targetSdk 35`, `minSdk 26` | Set explicitly in `build.gradle.kts` |
| Version naming strategy | vMAJOR.MINOR.PATCH+BUILD — define policy |
| Dine-in/Takeaway toggle in POS | Order-level toggle, drives tax rate resolution in FareEngine |
| FareEngine wiring | Ensure toggle passes through to receipt tax breakdown |
| 5-Rappen enforcement at payment | Cash: round total; card: exact; rounding difference as line item |

### Sprint 1.3 — Manager Override + Day Close + Backup (Week 3–5)

| Task | Detail |
|------|--------|
| Manager PIN for void | Void above threshold requires manager role PIN |
| Role-based void policy | Cashier cannot void; manager can; threshold configurable |
| Day close workflow | All shifts closed check + daily summary print + audit log entry |
| Local backup export | Export SQLite snapshot to device Downloads + auto-backup on shift close |
| Restore flow | Manager PIN confirmation to restore from backup file |

### Sprint 1.4 — Pilot License + Offline Tests (Week 5–6)

| Task | Detail |
|------|--------|
| Pilot license mode | Hardcoded "pilot mode" enables all Professional features without server |
| Offline scenario tests | Full order cycle in airplane mode, payment terminal reconnect, KDS in LAN-only mode |
| Localization audit | Ensure all POS flow strings are in German ARB file |

**Phase 1 Exit Criteria:**
- [ ] Kitchen ticket appears on KDS within 2s of order submit (same device)
- [ ] Receipt shows correct Swiss MWST breakdown with dine-in/takeaway selection
- [ ] Day close produces printed daily summary
- [ ] Full order cycle works in airplane mode
- [ ] Release APK/AAB builds cleanly

---

## 7. Phase 2: Multi-Device + LAN Sync (Weeks 7–14)

**Goal:** POS tablet and KDS tablet on same WiFi see each other's data in real time.

### LAN Sync Architecture

- Primary device serves a local HTTP + SSE server
- Secondary devices register with primary via mDNS or manual IP
- POS write operations: primary applies immediately; secondary pushes to primary
- KDS: subscribes to SSE stream from primary for `kitchen_tickets` events
- Conflict resolution: append-only for orders (no edit conflicts); last-writer-wins for table status

### Sprint 2.1 — Local HTTP Server on Primary (Week 7–9)

| Task | Detail |
|------|--------|
| Embedded HTTP server in Flutter | `shelf` package or platform channel to serve local API |
| POST /lan/orders — receive order from secondary | Primary writes to SQLite |
| GET /lan/kitchen-tickets — SSE stream | KDS subscribes for live updates |
| GET /lan/tables — sync table status | Secondary refreshes floor plan |
| Device role selection | Settings: this device is "primary" or "secondary" |

### Sprint 2.2 — Discovery + Secondary Client (Week 9–11)

| Task | Detail |
|------|--------|
| mDNS service broadcast on primary | Announce `gastrocore-pos._tcp.local` |
| mDNS discovery on secondary | Scan and show found primaries |
| Secondary order flow | Routes order mutations through primary HTTP API |
| Reconnect handling | Secondary shows "Primary disconnected" banner; continues in degraded mode |
| Heartbeat | Secondary polls primary every 5s; alerts at 15s silence |

### Sprint 2.3 — Waiter Handheld Mode (Week 11–13)

| Task | Detail |
|------|--------|
| Compact order UI for phone | Simplified product list + order builder for small screen |
| Connect as secondary | Same LAN sync, phone registers as secondary |
| Table assignment | Waiter selects table from floor plan, sends order to primary |
| "My tables" filter | Waiter sees only their assigned tables |

### Sprint 2.4 — License Service Basics (Week 13–14)

| Task | Detail |
|------|--------|
| Go license handler — real implementation | Look up license key, return feature flags JSON |
| JWT with Ed25519 signing | Issue signed license tokens |
| Flutter: validate JWT at startup | Parse flags, enforce device limits |
| Grace period: 7-day offline window | App checks last validated date; grace if offline |
| Tier enforcement in UI | Hide/show features based on plan flags |

**Phase 2 Exit Criteria:**
- [ ] POS and KDS on separate tablets, same WiFi, tickets sync within 3s
- [ ] Waiter phone app can send orders to POS primary
- [ ] When primary is unreachable, secondary shows clear warning (not silent failure)
- [ ] License enforcement: Starter plan cannot access KDS or multi-device

---

## 8. Phase 3: Swiss Pilot (Weeks 15–20)

**Goal:** First paying Swiss restaurant is live. Revenue begins.

### Sprint 3.1 — Swiss Compliance Hardening (Week 15–17)

| Task | Detail |
|------|--------|
| Swiss QR-bill generation | ISO 20022 format, on-demand invoice for B2B |
| Restaurant UID in receipts | Unternehmens-Identifikationsnummer field in settings + receipts |
| MWST number display | Receipt shows MWST registration number |
| Tax rate effective dates | Admin can set future rate changes with activation date |
| Invoice mode | Formal invoice template for business customers |

### Sprint 3.2 — Operations Polish (Week 17–19)

| Task | Detail |
|------|--------|
| Void audit report | Show voids per staff member per shift |
| Reprint receipt | Reprint any past receipt by receipt number |
| Cash drawer support | Open drawer on payment confirmation |
| Table note / cover count | Table-level notes for kitchen, guest count adjustment during service |
| Allergen flags on items | Display allergen codes on kitchen ticket |

### Sprint 3.3 — Pilot Onboarding (Week 19–20)

| Task | Detail |
|------|--------|
| Onboarding wizard | First-run: set restaurant name, MWST number, printers, tax profile |
| Demo data mode | Pre-populated menu for demo/training |
| In-app help | Context help on each screen (brief tooltips) |
| Error recovery guide | Document top 10 issues + resolutions for support |

**Phase 3 Exit Criteria:**
- [ ] First Swiss restaurant processes real transactions
- [ ] 5 business days of operation without data loss or critical bug
- [ ] Owner can view sales data locally
- [ ] Support response time < 4 hours

---

## 9. Phase 4: Cloud Sync + Backend (Weeks 21–32)

**Goal:** Restaurant owner sees data in web dashboard. Second device can restore from cloud.

### Sprint 4.1 — Go Backend Core (Week 21–25)

| Task | Detail |
|------|--------|
| Auth: JWT generation + refresh | Device tokens, user tokens |
| Sync: upload/download/seed/status | Real implementation (see doc 27) |
| Devices: registration + heartbeat | Register device ID, store last-seen |
| Stores: tenant + branch CRUD | Create tenant on first use |
| PostgreSQL migrations: run on startup | Use existing `001_initial.up.sql` |

### Sprint 4.2 — Flutter Cloud Sync Client (Week 25–28)

| Task | Detail |
|------|--------|
| Outbox writer | Write to `sync_queue` on every DB mutation |
| Sync runner | Background isolate: drain `sync_queue` → POST /api/v1/sync/upload |
| Download runner | Poll GET /api/v1/sync/download with cursor |
| Apply changes to local DB | Idempotent upserts |
| Sync status UI | `pos_sync_indicator.dart` already exists — wire to real sync state |
| Conflict resolution | Last-writer-wins (server wins on conflict) |

### Sprint 4.3 — Cloud Dashboard MVP (Week 28–32)

| Task | Detail |
|------|--------|
| Owner login (email + password) | |
| Daily/weekly/monthly revenue charts | |
| Top products report | |
| Device status (online/offline, last sync) | |
| Menu management (CRUD) with sync push | |
| Staff management (create/edit PINs) | |

**Phase 4 Exit Criteria:**
- [ ] Device syncs to cloud within 60s of connectivity
- [ ] 8 hours offline then sync completes without data loss
- [ ] Owner sees sales on web within 5 minutes of sync
- [ ] New device can be seeded from cloud in < 5 minutes

---

## 10. Phase 5: Germany Fiscal Pack (Weeks 33–40)

**Dependency:** Cloud sync must be stable. Germany requires cloud for Fiskaly TSE calls.

See doc 30 for full spec. Summary:
- Fiskaly SIGN DE v2 integration
- TSE transaction lifecycle: start → update → finish
- DSFinV-K export from cloud dashboard
- Receipt with TSE QR code and all required fields
- Offline queue: transactions signed when connectivity resumes

**Phase 5 Exit Criteria:**
- [ ] Every transaction signed by Fiskaly within 5s (online)
- [ ] DSFinV-K export passes validation tool
- [ ] Zero fiscal signing failures in 500-transaction test

---

## 11. Phase 6: Online Channels (Weeks 41–52)

Sequenced after Germany fiscal to avoid channel complexity infecting compliance work.

| Channel | Sequence | Dependency |
|---------|----------|------------|
| Website ordering | 6a | Cloud sync + Go backend |
| QR table ordering | 6b | After website ordering |
| Kiosk mode | 6c | After QR ordering |
| Retail mode | 7 | After kiosk; separate UI mode |

---

## 12. What to Cut / Postpone

**Cut entirely from v1 scope:**

| Item | Reason |
|------|--------|
| ERPNext bridge | Removed — custom backoffice is team's own project |
| Redis | Not needed at v1 scale |
| Microservices | Architecture freeze prohibits |
| iOS / web POS | Android only for v1 |
| Customer loyalty / CRM | Not restaurant core |
| Inventory management | Not in scope — custom backoffice handles it |
| Delivery management | Post-channel work |
| Customer accounts | Post-channel work |
| Room charge integration | Hotel F&B — future |
| Multi-language kiosk | After kiosk exists |
| Advanced BI / analytics | Post-50 customers |

**Defer until 100+ tenants:**

| Item | Trigger |
|------|---------|
| Redis pub/sub | Sync throughput degrades |
| PostgreSQL read replicas | Report query contention |
| Multi-region deployment | Cross-timezone customer requests |
| SLA / uptime guarantee | Enterprise tier customers |

---

## 13. Biggest Technical Risks

| # | Risk | Mitigation |
|---|------|------------|
| 1 | KDS LAN latency | SSE direct socket; dedicated WiFi AP for POS network |
| 2 | Sync conflict corruption | Append-only transactions; last-writer-wins master data; conflict log |
| 3 | Fiskaly API changes | Adapter pattern; version-pin API; maintain Fiskaly relationship |
| 4 | Bluetooth printer instability | Auto-reconnect; print queue; prefer WiFi printers |
| 5 | Android tablet fragmentation | Recommend 2–3 certified models; set minSdk 26 |
| 6 | Flutter SDK major upgrade breaking plugins | Pin Flutter stable; upgrade only after plugin confirmation |
| 7 | Germany fiscal edge cases | Tax advisor; test all transaction types; DSFinV-K validator |
| 8 | Sync data loss during device failure | Aggressive sync cadence; WAL mode; shift-close backup |

---

## 14. Biggest Product Risks

| # | Risk | Mitigation |
|---|------|------------|
| 1 | Scope creep before pilot | Strict phase gates; "not yet" list maintained |
| 2 | UX complexity | 30-second rule for all core flows; user test with real waiters |
| 3 | Support overload | Limit pilot to 2 restaurants; build self-service help |
| 4 | Void / cash theft | Manager PIN for voids; audit reports; void rate alerts |
| 5 | License circumvention | Server-side feature flags; cloud value deters piracy |
| 6 | Competing product at lower price | Compete on offline reliability + Swiss compliance; not price |
| 7 | Pilot customer churns before feedback | Weekly check-ins; fix blockers within 24h during pilot |

---

## 15. Top 10 Things NOT to Build Yet

1. ERPNext bridge — removed permanently
2. Online ordering web app
3. QR table ordering
4. Kiosk mode
5. Retail / barcode scanning mode
6. Customer loyalty / points system
7. Inventory management
8. Advanced analytics / BI dashboard
9. iOS or web POS app
10. Redis or message broker infrastructure

---

## 16. Top 10 Architectural Mistakes to Avoid

1. **Splitting Go monolith** into microservices before scale evidence
2. **Blocking transactions on cloud** — everything must work offline
3. **Putting ERPNext back** in any form — custom backoffice is separate
4. **Storing money as floats** — integer cents only (Money class)
5. **Mutating completed transactions** — void/refund creates new records always
6. **Hardcoding tax rates** — they must be configurable with effective dates
7. **Making KDS a separate Flutter app** in v1 — unnecessary complexity
8. **Skipping LAN sync** and going straight to cloud-only multi-device
9. **Adding Redis** before demonstrating PostgreSQL is the bottleneck
10. **Skipping the outbox pattern** — sync must be eventual and retryable

---

## 17. Top 10 Rollout Mistakes to Avoid

1. **Onboarding > 2 pilot restaurants simultaneously** — support will break
2. **Going to Germany before Swiss pilot is stable** — fiscal on unstable core = disaster
3. **Publishing to Play Store before closed beta** — public reviews before maturity damage reputation
4. **Setting pricing before pilot feedback** — pilot restaurants should validate willingness to pay
5. **Promising custom features to pilot customers** — scope creep vector
6. **Deploying Go backend without SSL** — never HTTP in production
7. **Running without daily PostgreSQL backups** — set this up on day 1 of cloud
8. **Skipping smoke test after APK update** — release = test on physical tablet first
9. **Not documenting device setup procedure** — new device onboarding must be < 15 minutes
10. **Not having a rollback plan** — every release needs tested downgrade path
