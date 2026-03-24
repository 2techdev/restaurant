# 24 — Execution Plan

> **Document Status:** Authoritative | **Last Updated:** 2026-03-24
>
> Ordered delivery plan from current state to market-ready product.
> Based on actual codebase state (doc 21), gap analysis (doc 22), and architecture freeze (doc 23).
> **Updated 2026-03-24:** Removed LAN sync phase. Cloud sync is the multi-device path.
> **Team context:** 1–5 person team, AI-assisted development.

---

## 1. Executive Diagnosis

GastroCore has a **strong single-device POS core** that already surpasses many commercial POS products in domain logic quality, test coverage, and hardware integration depth.

The product is **blocked from piloting** by three specific gaps:
1. KDS shows demo data — not connected to real orders
2. No production build / release signing verified
3. No pilot license mode (all features unlocked without a token)

These three gaps can be closed in **2–3 weeks** with focused AI-assisted effort.

Everything else is sequenced after the pilot delivers validated feedback.

---

## 2. What Is Already Strong

- PIN auth, role-based access — complete, tested
- Full POS order flow with modifiers — complete, tested
- Payment terminal integration (myPOS WiFi + Wallee LTI) — production-grade bridges
- Table/floor plan with drag-drop, merge, transfer — complete, 22/22 tests
- Shift open/close with Z-report printing — complete, 27/27 tests
- Swiss MWST receipt builder with 5-Rappen rounding — 36 tests
- Multi-printer support (Bluetooth/USB/WiFi) — solid
- 29-table SQLite schema with UUID v7 and immutable log — well-designed
- Go modular monolith with auth, sync, menu, stores, devices, licenses, kds — MVP-complete modules
- 9 integration test suites, 44 unit test files

---

## 3. What Is Blocking Progress

| Risk Level | Missing Item |
|-----------|-------------|
| **BLOCKS PILOT** | KDS wired to real `kitchen_tickets` data |
| **BLOCKS PILOT** | Production build + keystore + APK distribution |
| **BLOCKS PILOT** | Pilot license mode (all-features JWT hardcoded) |
| **BLOCKS PILOT** | Swiss VAT dine-in/takeaway toggle in POS flow |
| **BLOCKS PILOT** | Settings save incomplete (restaurant name, UID, MWST) |
| BLOCKS REVENUE | License enforcement (tier gating in UI) |
| BLOCKS REVENUE | CI/CD for reliable release process |
| BLOCKS GROWTH | Cloud sync engine (outbox → Go backend → WebSocket push) |
| BLOCKS GROWTH | Cloud dashboard for restaurant owners |
| COMPLIANCE | Germany Fiskaly/TSE (deferred to post-Swiss-pilot) |

---

## 4. Architecture Freeze Summary

See doc 23 for full details. Key frozen decisions relevant to this plan:

| Decision | Outcome |
|----------|---------|
| ERPNext | **Removed permanently.** Custom backoffice via export API. |
| Redis | **Removed from v1.** PostgreSQL outbox only. |
| LAN sync | **Removed.** Cloud sync is the multi-device path. |
| KDS | **Mode within POS app**, not separate binary in v1 |
| Multi-device | **Cloud-based.** Each device connects to Go Cloud Hub over HTTPS. |
| Country order | **Switzerland first**, Germany after Swiss pilot |
| Go server | **Modular monolith**, no microservices |
| Payments | **myPOS primary**, Wallee secondary |

---

## 5. Recommended Delivery Order

```
Phase 0 (DONE):    Core POS + payments + tables + shifts + printing
                   ↓
Phase 1 (NOW):     KDS wired + production build + Swiss VAT + pilot license
                   ↓
Phase 2 (NEXT):    Cloud sync + multi-device (KDS tablet + waiter phone)
                   ↓
Phase 3:           Swiss pilot hardening + QR-bill + operations polish
                   ↓
Phase 4:           Cloud dashboard + license service + CI/CD
                   ↓
Phase 5:           Germany fiscal pack (post-Swiss-pilot)
                   ↓
Phase 6:           Online channels (ordering, QR, kiosk standalone)
                   ↓
Phase 7:           Retail mode + custom backoffice export API
```

---

## 6. Phase 1: Pilot Unblock (Weeks 1–5)

**Goal:** A single restaurant can run a full service day with GastroCore. KDS shows real orders. Receipts are legally Swiss-compliant.

### Sprint 1.1 — KDS Wired (Week 1–2)

| Task | Detail | File |
|------|--------|------|
| Create `KitchenRepositoryImpl` | `watchActiveTickets()` Drift Stream | `lib/features/kitchen/data/` |
| Create `KitchenTicketWithItems` entity | Aggregate: ticket + items | `lib/features/kitchen/domain/` |
| Add `activeKitchenTicketsProvider` | Riverpod StreamProvider | `lib/features/kitchen/` |
| Wire KDS screen to provider | Replace `_buildDemoTickets()` | `KitchenDisplayScreen` |
| Order submit → `createTicketFromOrder()` | POS "Send to Kitchen" writes rows | `OrderRepository` |
| Bump button → `completeTicket()` | DB write; stream auto-removes | KDS screen |
| Wire stats bar to real counts | Pending from stream; completed from query | KDS screen |
| Add audible alert | `audioplayers` package already in pubspec | KDS screen |
| Unit tests | KitchenRepository, ticket creation, bump | `test/unit/` |

**Exit:** Kitchen ticket appears on KDS within 2s of order submit (same device).

### Sprint 1.2 — Production Build + Settings Fix (Week 2–3)

| Task | Detail |
|------|--------|
| Verify / create release keystore | `gastrocore-release.jks` + `key.properties` |
| Test `flutter build appbundle --release` | Clean signed AAB output |
| Set `targetSdk 35`, `minSdk 26` | `android/app/build.gradle.kts` |
| Version `1.0.0+1000` | Update `pubspec.yaml` + `build.gradle.kts` |
| Fix settings save (restaurant name, UID, MWST) | `RestaurantSettings` save path |
| Add UID and MWST number fields to Settings UI | Onboarding wizard + settings screen |

**Exit:** Release AAB builds cleanly; pilot APK installable from signed file.

### Sprint 1.3 — Swiss VAT Toggle (Week 3–4)

| Task | Detail |
|------|--------|
| Dine-in / Takeaway toggle in POS order screen | Prominent toggle, top bar area |
| Wire toggle to `OrderType` in ticket entity | `dineIn` vs `takeaway` |
| FareEngine resolves tax rate from toggle | 8.1% dine-in, 2.6% takeaway for food |
| Verify `effective_from` date on tax profiles | FareEngine reads it |
| 5-Rappen enforcement at cash payment | Cash: rounded; card: exact |
| Rounding delta as payment line item | `type = 'rounding'` in `payments` table |
| Receipt shows rounding line (cash only) | SwissReceiptBuilder |
| SwissReceiptBuilder uses UID + MWST from settings | Settings values |
| Unit tests: all dine-in/takeaway tax scenarios | `test/unit/` |
| Unit tests: 5-Rappen rounding edge cases | `test/unit/` |

**Exit:** Receipt shows correct MWST breakdown. Cash rounding on receipt.

### Sprint 1.4 — Manager Override + Day Close + Backup (Week 4–5)

| Task | Detail |
|------|--------|
| Manager PIN for void above threshold | Cashier cannot void; manager can |
| Discount dialog wired | FareEngine applies discount; receipt shows line |
| Audit log records void/discount with manager ID | `audit_log` write |
| Day close workflow | All shifts verified closed + daily summary print |
| Daily CSV export to Downloads | Shift summary in Swiss accounting format |
| Backup trigger UI verified | Export button + auto on shift close |

**Phase 1 Exit Criteria:**
- [ ] Kitchen ticket appears on KDS within 2s of order submit (same device)
- [ ] Coffee dine-in: receipt shows 8.1% MWST
- [ ] Coffee takeaway: receipt shows 2.6% MWST
- [ ] Cash CHF 17.23 rounds to CHF 17.25 on receipt
- [ ] Restaurant UID and MWST number on receipt
- [ ] Day close produces printed daily summary
- [ ] Full order cycle works in airplane mode
- [ ] Release AAB builds cleanly and installs on physical tablet

---

## 7. Phase 2: Cloud Sync + Multi-Device (Weeks 6–16)

**Goal:** POS tablet and KDS tablet see each other's data via cloud. Waiter phone can submit orders. All over HTTPS through the Go Cloud Hub.

### Sprint 2.1 — Flutter Outbox (Week 6–8)

| Task | Detail |
|------|--------|
| Outbox writer in Drift DAO | Write to `sync_queue` on every DB mutation |
| Idempotency: entity_id + updated_at | Prevents double-upload |
| `SyncRunner` background task | Drain `sync_queue` → POST `/api/v1/sync/upload` |
| Exponential backoff retry | 30s, 1m, 2m … max 10 retries |
| `DownloadRunner` background task | Poll GET `/api/v1/sync/download?cursor=` |
| Apply downloads to local SQLite | Idempotent upserts |
| Wire `pos_sync_indicator.dart` to real state | Online/offline/pending/error |

### Sprint 2.2 — Go Cloud Sync Real Implementation (Week 8–12)

| Task | Detail |
|------|--------|
| Auth: JWT generation + refresh tokens | Device tokens |
| Sync upload handler — real PostgreSQL writes | Conflict resolution: last-writer-wins |
| Sync download handler — cursor-based delta | Returns changes since cursor |
| Sync seed handler | Full state for new device registration |
| Devices: registration + heartbeat | Store device last-seen |
| Reports: aggregate queries | Revenue, shift summaries |
| Deploy to staging VPS with SSL | pos.2tech.ch or staging subdomain |
| PostgreSQL automated daily backup | Critical — set up on first cloud deployment |

### Sprint 2.3 — KDS Multi-Device via Cloud (Week 12–14)

| Task | Detail |
|------|--------|
| KDS tablet subscribes to cloud WebSocket | Go `kds` module WebSocket hub |
| Go KDS hub: push `new_kitchen_ticket` event on order submit | Server-side |
| KDS tablet receives event → re-query or apply payload | Flutter WebSocket client |
| Bump on KDS tablet → POST to cloud → syncs to POS | Cloud-mediated bump |
| KDS "Cloud Disconnected" banner | Falls back to print-only mode |
| Print fallback: if KDS unreachable → auto-print kitchen ticket | `print_kitchen_ticket_use_case` already exists |

### Sprint 2.4 — Waiter Phone via Cloud (Week 14–16)

| Task | Detail |
|------|--------|
| Waiter phone connects to cloud for table status | REST polling or WebSocket |
| Order submission from waiter phone → cloud → POS local sync | Cloud-mediated |
| "My tables" filter | Waiter sees only assigned tables |
| Degraded mode: submit disabled if cloud unreachable | Clear error shown |

### Sprint 2.5 — License Service Basics (Week 15–16)

| Task | Detail |
|------|--------|
| Go license handler — real implementation | Validate key → return signed JWT |
| JWT with Ed25519 signing | Issue signed license tokens |
| Flutter: validate JWT at startup | Parse flags, enforce device limits |
| Grace period: 7-day offline window | Check last validated date |
| Tier enforcement in UI | Hide/show features based on plan flags |

**Phase 2 Exit Criteria:**
- [ ] POS and KDS on separate tablets, same cloud account, tickets sync within 10s
- [ ] Waiter phone can submit orders via cloud
- [ ] When cloud is unreachable, device shows clear banner (not silent failure)
- [ ] License enforcement: Starter plan cannot access KDS or multi-device
- [ ] Cloud backup of transactions verified on staging

---

## 8. Phase 3: Swiss Pilot Hardening (Weeks 17–22)

**Goal:** First paying Swiss restaurant is live. Revenue begins.

### Sprint 3.1 — Swiss Compliance Hardening (Week 17–19)

| Task | Detail |
|------|--------|
| Swiss QR-bill generation (on-demand) | ISO 20022 format for B2B invoices |
| Tax rate effective dates | Admin sets future rate changes |
| UID format validation in settings | Warn if CHE-XXX.XXX.XXX format invalid |
| Reprint receipt by order number | Any past receipt |
| Invoice mode | Formal invoice template for business customers |
| Cash drawer open on cash payment | `open_drawer_use_case` |

### Sprint 3.2 — Operations Polish (Week 19–21)

| Task | Detail |
|------|--------|
| Allergen flags on items | Display on kitchen ticket |
| Table note / cover count | Table-level notes for kitchen |
| Void rate report per staff per shift | |
| In-app help tooltips | Context help on each screen |
| Error recovery guide | Top 10 issues + resolutions |

### Sprint 3.3 — Onboarding Wizard (Week 21–22)

| Task | Detail |
|------|--------|
| First-run wizard | Restaurant name, UID, MWST, tax profile, printers |
| Demo data mode | Pre-populated menu for training/demo |
| Device setup guide | < 15 minutes to onboard a new device |

**Phase 3 Exit Criteria:**
- [ ] First Swiss restaurant processes real transactions
- [ ] 5 business days of operation without data loss
- [ ] QR-bill generates correctly for B2B customer
- [ ] Support response time < 4 hours

---

## 9. Phase 4: Cloud Dashboard + CI/CD (Weeks 23–32)

**Goal:** Restaurant owner sees data in web dashboard. CI/CD in place.

| Sprint | Focus | Deliverable |
|--------|-------|-------------|
| 4.1 | Cloud dashboard MVP | Owner login, revenue charts, device status, menu management |
| 4.2 | License service production | Key activation, renewal, tier enforcement |
| 4.3 | CI/CD pipeline | GitHub Actions: lint → test → build AAB on main |
| 4.4 | Play Store internal track | App listing, privacy policy, data safety form |

**Phase 4 Exit Criteria:**
- [ ] Owner sees sales on web within 5 minutes of sync
- [ ] New device can be seeded from cloud in < 5 minutes
- [ ] CI/CD: AAB builds on every PR merge automatically
- [ ] App visible on Play internal test track

---

## 10. Phase 5: Germany Fiscal Pack (Weeks 33–42)

**Dependency:** Cloud sync must be stable in production. Swiss pilot must have 30+ days of stable operation and 5+ customers.

See doc 30 for full spec. Summary:
- Fiskaly SIGN DE v2 integration in Go backend
- TSE transaction lifecycle: start → update → finish
- DSFinV-K export from cloud dashboard
- German receipt format with TSE QR code
- Offline signing queue: transactions signed when connectivity resumes

**Phase 5 Exit Criteria:**
- [ ] Every German transaction signed by Fiskaly within 5s
- [ ] DSFinV-K export passes BSI validation tool
- [ ] Zero fiscal signing failures in 500-transaction test

---

## 11. Phase 6: Online Channels (Weeks 43–54)

Sequenced after Germany fiscal to avoid channel complexity infecting compliance work.

| Channel | Sequence | Dependency |
|---------|----------|------------|
| Web ordering app | 6a | Cloud sync + Go backend |
| QR table ordering | 6b | After web ordering |
| Kiosk standalone APK | 6c | After QR ordering |
| Waiter standalone APK | 6c | After cloud sync stable |
| Retail mode | 7 | After kiosk; separate UI mode |

---

## 12. What to Cut / Postpone

**Cut entirely from v1:**

| Item | Reason |
|------|--------|
| ERPNext bridge | Removed — custom backoffice is separate project |
| LAN sync / mDNS | Architecture freeze: cloud sync only |
| Redis | Not needed at v1 scale |
| Microservices | Architecture freeze prohibits |
| iOS / web POS | Android only for v1 |
| Customer loyalty / CRM | Not restaurant core |
| Inventory management | Custom backoffice handles it |
| Delivery management | Post-channel work |

---

## 13. Biggest Technical Risks

| # | Risk | Mitigation |
|---|------|------------|
| 1 | Cloud sync latency for KDS | WebSocket push; dedicated connection per KDS device |
| 2 | Sync conflict data corruption | Append-only transactions; last-writer-wins master data; conflict log |
| 3 | Fiskaly API changes (Germany) | Adapter pattern; version-pin API |
| 4 | Bluetooth printer instability | Auto-reconnect; print queue; prefer WiFi printers |
| 5 | Android tablet fragmentation | Recommend 2–3 certified models; set minSdk 26 |
| 6 | Flutter SDK upgrade breaking plugins | Pin Flutter stable; upgrade only after plugin confirmation |
| 7 | Cloud unavailability during multi-device service | Clear banner; single-device fallback mode; KDS print fallback |
| 8 | Release keystore loss | 3 secure backup locations; document recovery procedure |

---

## 14. Biggest Product Risks

| # | Risk | Mitigation |
|---|------|------------|
| 1 | Scope creep before pilot | Strict phase gates; "not yet" list maintained |
| 2 | UX complexity | 30-second rule for all core flows; test with real waiters |
| 3 | Support overload | Limit pilot to 2 restaurants; build self-service help |
| 4 | Void / cash theft | Manager PIN for voids; audit reports |
| 5 | Cloud downtime affecting multi-device restaurants | Each device works standalone; clear degraded mode |
| 6 | Pilot customer churns | Weekly check-ins; fix blockers within 24h during pilot |

---

## 15. Top 10 Things NOT to Build Yet

1. ERPNext bridge — removed permanently
2. LAN sync / embedded HTTP server in Flutter
3. Online ordering web app
4. QR table ordering
5. Standalone kiosk APK
6. Customer loyalty / points system
7. Inventory management
8. Advanced analytics / BI dashboard
9. iOS or web POS app
10. Redis or message broker infrastructure

---

## 16. Top 10 Architectural Mistakes to Avoid

1. **Building LAN sync** — cloud sync covers all multi-device use cases
2. **Splitting Go monolith** into microservices before scale evidence
3. **Blocking transactions on cloud** — everything must work offline
4. **Putting ERPNext back** in any form
5. **Storing money as floats** — integer cents only (Money class)
6. **Mutating completed transactions** — void/refund creates new records always
7. **Hardcoding tax rates** — configurable with effective dates
8. **Adding Redis** before demonstrating PostgreSQL is the bottleneck
9. **Skipping the outbox pattern** — sync must be eventual and retryable
10. **Deploying cloud backend without HTTPS + daily backups**

---

## 17. Top 10 Rollout Mistakes to Avoid

1. **Onboarding > 2 pilot restaurants simultaneously** — support will break
2. **Going to Germany before Swiss pilot is stable** — fiscal on unstable core = disaster
3. **Publishing to Play Store before closed beta** — public reviews before maturity
4. **Setting pricing before pilot feedback** — validate willingness to pay first
5. **Promising custom features to pilot customers** — scope creep vector
6. **Deploying Go backend without SSL and backups** — never HTTP in production
7. **Running without daily PostgreSQL backups** — set up on day 1 of cloud
8. **Skipping smoke test after APK update** — test on physical tablet first
9. **Not documenting device setup procedure** — onboarding must be < 15 minutes
10. **Losing the pilot restaurant relationship** — weekly check-ins mandatory
