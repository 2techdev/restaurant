# GastroCore Platform — Remaining Work
**Generated:** 2026-03-21
**Sources:** TODO.md, docs/32-implementation-backlog.md, docs/33-90-180-365-plan.md, docs/17-roadmap.md, CHANGELOG.md, memory files

---

## COMPLETED SINCE SPRINT 1 (as of 2026-03-21)

| Area | Status |
|------|--------|
| Swiss VAT Phase 1 (toggle, FareEngine wiring, receipt, tests) | ✅ DONE |
| Kiosk flavor (7 screens, KioskOrderService, KioskSessionNotifier, 2 test files) | ✅ DONE |
| UI/UX Polish (splash screen, onboarding wizard, page transitions, pull-to-refresh, light theme, responsive layout, animated lists, accessibility) | ✅ DONE |
| Waiter handheld mode (6 screens, waiter flavor, standalone entry point) | ✅ DONE |
| KDS App mode (3 screens scaffolded in POS app) | ✅ SCAFFOLDED |
| ODS module scaffolded | ✅ SCAFFOLDED |
| Online ordering web app scaffolded | ✅ SCAFFOLDED |

---

## P0 — PILOT BLOCKERS (Target: 2026-05-01 Pilot APK)

### Epic 0: Build Infrastructure
| ID | Task | Effort |
|----|------|--------|
| B-01 | Verify/create release keystore + key.properties | 2h |
| B-02 | Test `flutter build appbundle --release` succeeds | 1h |
| B-03 | Set explicit `targetSdk 35`, `minSdk 26` in build.gradle.kts | 30m |
| B-04 | Set version policy: `1.0.0+1000` for first release | 30m |
| B-05 | Add obfuscation flags to release build | 30m |
| B-06 | Document manual release procedure | 2h |

### Epic 1: KDS Wiring (screens exist but use demo data)
| ID | Task | Effort |
|----|------|--------|
| K-01 | `KitchenRepositoryImpl.watchActiveTickets()` Drift stream | 1d |
| K-02 | `KitchenTicketWithItems` aggregate entity | 2h |
| K-03 | `activeKitchenTicketsProvider` Riverpod StreamProvider | 2h |
| K-04 | Wire KDS screen to real provider (remove `_buildDemoTickets()`) | 3h |
| K-05 | Implement `createTicketFromOrder()` in order submit flow | 1d |
| K-06 | Wire bump button to `completeTicket()` DB write | 2h |
| K-07 | Wire stats bar to real counts (pending from stream, completed from query) | 3h |
| K-08 | Audible alert on new ticket arrival | 3h |
| K-09 | Station filter UI (single station default, multi-station prep) | 4h |
| K-10 | Print fallback: if no KDS registered, auto-print kitchen ticket | 2h |
| K-11 | Timer thresholds in Settings (green/orange/red minutes, configurable) | 2h |
| K-12 | Unit tests: KitchenRepository, ticket creation, bump logic | 1d |

### Swiss VAT Remaining (Phase 2–3)
| ID | Task | Effort | Source |
|----|------|--------|--------|
| V-04 | FareEngine: verify `effective_from` date on tax profiles | 2h | doc-32 Epic 2 |
| V-08b | UID/MWST-Nr format validation (CHE-XXX.XXX.XXX) | 2h | memory |
| D-04b | Daily shift CSV export with MWST breakdown by rate | 4h | CHANGELOG pending |

---

## P1 — PRE-COMMERCIAL (Target: 2026-06-01 Swiss Pilot Live)

### Epic 3: Manager Override and Operations
| ID | Task | Effort |
|----|------|--------|
| M-01 | Manager PIN dialog component | 3h |
| M-02 | Void: require manager PIN above configurable threshold | 4h |
| M-03 | Discount: require manager PIN above configurable percentage | 3h |
| M-04 | Role-based access: cashier cannot void/discount without manager auth | 2h |
| M-05 | Audit log: record void/discount with authorizing manager ID | 2h |
| M-06 | Void rate report per staff member per shift | 3h |
| M-07 | Reprint receipt by receipt number | 3h |

### Epic 4: Day Close and Backup
| ID | Task | Effort |
|----|------|--------|
| D-01 | Day close workflow screen (verify all shifts closed) | 4h |
| D-02 | Daily summary print: totals, taxes, payment methods, voids | 4h |
| D-03 | Day close entry in audit log | 1h |
| D-04 | Daily CSV export to device Downloads | 4h |
| D-05 | Local backup: export SQLite snapshot to device Downloads | 3h |
| D-06 | Auto-backup trigger on shift close | 2h |
| D-07 | Restore from backup: manager PIN + file picker | 4h |

### Epic 5: License Basics
| ID | Task | Effort |
|----|------|--------|
| L-01 | License token structure (JWT, Ed25519, feature flags JSON) | 1d |
| L-02 | Pilot mode: hardcoded "all Professional features" token | 2h |
| L-03 | Flutter: parse and validate license JWT at startup | 1d |
| L-04 | Flutter: LicenseProvider with feature flag accessors | 3h |
| L-05 | Flutter: `FlagGate` widget (upgrade prompt if feature not licensed) | 4h |
| L-06 | Gate KDS behind Professional flag | 1h |
| L-07 | Gate LAN sync behind Professional flag | 1h |
| L-08 | Gate Cloud sync behind Enterprise flag | 1h |
| L-09 | Grace period: 7-day offline window before gating | 3h |
| L-10 | Receipt-only mode: <90 days expired warn; >90 days gate reports/KDS | 4h |

### Onboarding (from 33-day plan, not in backlog as separate tasks)
| Task | Effort |
|------|--------|
| First-run onboarding wizard: restaurant name, UID, MWST, printers | 4h (built, needs settings save wiring) |
| Demo mode: 5 orders/shift cap, receipt watermark | 3h |

---

## PHASE 2 — MULTI-DEVICE (Target: Day 90 = 2026-06-20)

### Epic 6: LAN Sync
| ID | Task | Effort |
|----|------|--------|
| S-01 | Embedded HTTP server on primary device (shelf package) | 3d |
| S-02 | LAN health / info endpoints | 1d |
| S-03 | LAN order submission endpoint | 2d |
| S-04 | LAN kitchen ticket SSE stream | 2d |
| S-05 | LAN table status endpoint | 1d |
| S-06 | LAN menu sync endpoint | 1d |
| S-07 | mDNS service broadcast on primary | 2d |
| S-08 | mDNS device discovery on secondary | 2d |
| S-09 | Secondary device: connect to primary flow in Settings | 1d |
| S-10 | Secondary: heartbeat + disconnection detection | 1d |
| S-11 | Secondary: degraded mode banner | 1d |
| S-12 | HMAC shared secret auth for LAN connections | 1d |
| S-13 | Waiter compact UI for phone | 3d |
| S-14 | Integration test: two-device order + KDS scenario | 2d |

### Epic 12: CI/CD
| ID | Task | Effort |
|----|------|--------|
| CI-01 | GitHub Actions: Flutter lint + test on PR | 1d |
| CI-02 | GitHub Actions: release AAB build on main merge | 1d |
| CI-03 | Go: go vet + go test in CI | 1d |
| CI-04 | Auto version-code increment in CI | 1d |
| CI-05 | Keystore stored as GitHub Secret (base64) | 1d |
| CI-06 | Upload AAB to Play Internal track automatically | 1d |

---

## PHASE 3 — CLOUD + DASHBOARD (Target: Day 180 = 2026-09-20)

### Epic 7: Cloud Sync — Go Backend
| ID | Task | Effort |
|----|------|--------|
| G-01 | Auth: JWT generation + device token + refresh | 3d |
| G-02 | Devices: register, heartbeat, status | 2d |
| G-03 | Stores: tenant + branch CRUD | 2d |
| G-04 | Sync: upload handler (batch conflict resolution) | 5d |
| G-05 | Sync: download handler (cursor-based delta) | 3d |
| G-06 | Sync: seed handler (full state for new device) | 2d |
| G-07 | Sync: status handler | 1d |
| G-08 | Licenses: key validation, feature flags, grace period | 3d |
| G-09 | Reports: aggregate queries from synced data | 3d |
| G-10 | Go unit tests for all handlers | 3d |
| G-11 | PostgreSQL deployment: VPS, SSL, automated backups | 2d |
| G-12 | CI/CD: GitHub Actions for Go build + test | 1d |

### Epic 8: Cloud Sync — Flutter Client
| ID | Task | Effort |
|----|------|--------|
| C-01 | Outbox writer: write to sync_queue on every mutation | 3d |
| C-02 | Sync runner background isolate: drain sync_queue → POST upload | 3d |
| C-03 | Download runner: poll + apply changes to local DB | 2d |
| C-04 | Cursor management in sync_metadata | 1d |
| C-05 | Conflict resolution: apply server version on conflict | 2d |
| C-06 | Wire pos_sync_indicator to real sync state | 1d |
| C-07 | Device registration flow: on first cloud connect | 1d |
| C-08 | Cloud license token fetch + replace local pilot token | 1d |

### Epic 9: Cloud Dashboard
| ID | Task | Effort |
|----|------|--------|
| W-01 | Owner login (email + password) | 2d |
| W-02 | Daily/weekly/monthly revenue charts | 3d |
| W-03 | Top products report | 2d |
| W-04 | Device status dashboard | 2d |
| W-05 | Menu management CRUD | 3d |
| W-06 | Staff management (PINs, roles) | 2d |
| W-07 | CSV export for accounting | 2d |

### Epic 11: Swiss QR-Bill
| ID | Task | Effort |
|----|------|--------|
| Q-01 | Evaluate Swiss QR-bill Dart library | 1d |
| Q-02 | QR-bill generator: creditor + debtor + amount + reference | 3d |
| Q-03 | Invoice print template (A4 with QR-bill section) | 2d |
| Q-04 | "Print Invoice" action from order screen | 1d |

---

## PHASE 5 — GERMANY FISCAL (Target: Day 365 = 2027-03-20)

### Epic 10: Germany Fiscal (Fiskaly)
| ID | Task | Effort |
|----|------|--------|
| F-01 | Fiskaly account + SIGN DE v2 sandbox setup | 1d |
| F-02 | Fiskaly HTTP client in Go (internal/fiscal) | 3d |
| F-03 | TSE initialization API call | 1d |
| F-04 | Start/finish transaction lifecycle | 3d |
| F-05 | TSE response storage in receipts table | 1d |
| F-06 | Retry logic + offline queue for fiscal signing | 3d |
| F-07 | German receipt format with TSE QR code | 2d |
| F-08 | Flutter: async fiscal signing after payment | 2d |
| F-09 | Flutter: "Signatur ausstehend" receipt state | 1d |
| F-10 | DSFinV-K export via Fiskaly SUBMIT DE | 3d |
| F-11 | Cloud dashboard: fiscal signing status + export button | 2d |
| F-12 | German VAT rates (19%, 7%) in tax profiles | 1d |
| F-13 | 1000-transaction compliance test | 2d |

---

## ONGOING — TEST COVERAGE

### Epic 13: Test Coverage
| ID | Task | Effort |
|----|------|--------|
| T-01 | Integration test: full order cycle offline | 2d |
| T-02 | Integration test: payment terminal (mock) | 2d |
| T-03 | Integration test: Swiss VAT all scenarios | 1d |
| T-04 | Integration test: shift open/close cycle | 1d |
| T-05 | Go unit tests: all handler logic | 3d |
| T-06 | Multi-device sync simulation (automated) | 3d |
| T-07 | Stress test: 200 orders in sequence | 1d |

---

## TODO.md PHASES — ADDITIONAL ITEMS NOT IN BACKLOG

### Phase 1.1: Shared Package Extraction (not yet started)
- [ ] `packages/core_models/` — entity, enum, value objects
- [ ] `packages/core_database/` — Drift tables, AppDatabase
- [ ] `packages/core_theme/` — AppColors, AppTheme, shared widgets
- [ ] `packages/core_auth/` — PIN auth, user entity
- [ ] `packages/core_sync/` — sync engine, connectivity
- [ ] `packages/core_printing/` — printer service abstraction
- [ ] Melos workspace (melos.yaml)
- [ ] POS app imports updated to shared packages

### Phase 1.2: Database Updates (fare_engine gap)
- [ ] tickets table: 16 new fare fields
- [ ] order_items table: 6 new fields (weight, openPrice, taxFree)
- [ ] payments table: 6 new fields (subChannel, paymentForm, external)
- [ ] products table: 4 new fields (stockStatus, openPrice, weightBased)
- [ ] Migration v1→v2
- [ ] build_runner re-run, generated files updated

### Phase 1.3: Fare Engine UI Wiring
- [ ] POS screen uses FareEngine for real tax calculation (not manual)
- [ ] Payment screen shows full FareBreakdown
- [ ] Receipt shows detailed fare breakdown
- [ ] Settings: FareConfig (tax rate, service fee, rounding rule)

### Phase 1.4: Missing UI/UX
- [ ] Online Order Acceptance screen (incoming order popup)
- [ ] Device Pairing screen (QR-based device pairing)
- [ ] Discount dialog (percentage/fixed, named discounts)
- [ ] Customer selection dialog (select/create customer)
- [ ] Quick notes dialog (order notes)
- [ ] Table merge/split/move dialogs
- [ ] Stitch designs S12–S20 (Back Office details, Settings, etc.)

### Phase 1.5: Hardware Integration
- [ ] Bluetooth thermal printer — discovery + ESC/POS commands
- [ ] Network printer (Star Micronics, Epson)
- [ ] Cash drawer trigger
- [ ] Barcode scanner
- [ ] Scale integration (retail mode)
- [ ] Payment terminal abstraction (Telpo, SumUp, etc.)

### Phase 4: Web Dashboard (full app)
- [ ] `web/dashboard/` app (Flutter Web or React — decide first)
- [ ] Login (email + password)
- [ ] Dashboard homepage (daily sales, order count, revenue)
- [ ] Menu management (category/product/modifier CRUD + image upload)
- [ ] Staff management
- [ ] Reports (daily, weekly, monthly, product performance)
- [ ] Device management (connected tablets, health)
- [ ] Settings (tax, currency, printer, service fee)
- [ ] Go backend API integration

### Phase 5: Patron App
- [ ] `apps/patron/` Flutter project
- [ ] Dashboard (today's sales, order count)
- [ ] Multi-branch view (enterprise)
- [ ] Staff performance
- [ ] Push notifications (shift opened/closed, high void rate)
- [ ] Read-only — no order taking
- [ ] Cloud API connection

### Phase 6: Online Ordering
- [ ] Go backend: public menu endpoint `/api/v1/public/menu/:shopId`
- [ ] Cart session management
- [ ] Checkout flow (create order, payment)
- [ ] Order status tracking (SSE/WebSocket)
- [ ] Restaurant availability check (business hours)
- [ ] `web/ordering/` responsive web app (mobile + desktop)
- [ ] Cart + checkout UI
- [ ] Payment integration
- [ ] QR code table linking (QR menu → order)
- [ ] POS: online order accept/reject popup
- [ ] Online order → same order engine
- [ ] Pickup code generation

### Phase 7: Customer Mobile App
- [ ] `apps/customer/` Flutter project (Android + iOS)
- [ ] Restaurant menu browsing
- [ ] Order placing (delivery/takeaway)
- [ ] Real-time order tracking
- [ ] Order history + reorder
- [ ] Push notifications
- [ ] Payment integration

### Phase 8: ODS — Order Display Screen (scaffolded, not wired)
- [ ] Customer-facing order status screen (scaffolded, needs real data)
- [ ] Large screen / TV optimization
- [ ] "Order #42 — Preparing", "Order #43 — Ready" states
- [ ] LAN sync or WebSocket auto-update
- [ ] Estimated wait time (optional)

### Phase 10: Germany Pack (full, see Epic 10 above)

### Phase 11: Switzerland Pack — Remaining
- [ ] Tax rate effective dates (admin sets future rate) — V-04
- [ ] QR-bill invoice generation — Q-01 through Q-04
- [ ] MWST-Nr format validation (CHE-XXX.XXX.XXX) — V-08b
- [ ] Swiss receipt format finalization
- [ ] UID/VAT format validation in Settings

### Phase 12: ERPNext Bridge
- [ ] ERPNext v15 Community Docker setup
- [ ] Go bridge: master data sync (Item, PriceList, Tax)
- [ ] Sales posting (Sales Invoice, Payment Entry)
- [ ] Stock deduction (Stock Entry)
- [ ] Journal Entry (cash movements)
- [ ] End-of-day reconciliation report
- [ ] Queue management when ERPNext is down

### Phase 13: Retail / Market Mode
- [ ] Barcode quick product search
- [ ] Weight-based products (scale integration)
- [ ] Quick sale mode (no table, direct sale)
- [ ] Retail receipt format
- [ ] Retail reports
- [ ] Stock count

### Infrastructure / DevOps (not fully done)
- [ ] Docker Compose production config (dev exists, prod needs hardening)
- [ ] PostgreSQL backup automation
- [ ] APK release signing (keystore)
- [ ] Play Store developer account
- [ ] Monitoring / alerting
- [ ] Error tracking (Sentry or Firebase Crashlytics)

---

## DEFERRED (Explicitly Out of Scope for v1 / 365 Days)

| ID | Item | Notes |
|----|------|-------|
| DEF-01 | Online ordering web channel | After LAN sync proven |
| DEF-02 | QR table self-ordering | After online ordering |
| DEF-03 | Kiosk mode | ✅ DONE (flavor implemented 2026-03-21) |
| DEF-04 | Retail / barcode mode | Phase 13, post Day 365 |
| DEF-05 | Customer display (ODS) | Scaffolded, needs wiring |
| DEF-06 | Loyalty / points program | Future |
| DEF-07 | Inventory / stock management | Future |
| DEF-08 | Delivery management / driver dispatch | Future |
| DEF-09 | Multi-region cloud | Post 50 tenants |
| DEF-10 | Redis infrastructure | Post 50 tenants |
| DEF-11 | iOS support | Not in v1 |
| DEF-12 | SIX payment terminal | Swiss acquiring integration, future |
| DEF-13 | PostFinance integration | Swiss payment, future |

### Future Backlog (from TODO.md)
- [ ] Loyalty / customer rewards program
- [ ] Coupon system
- [ ] Promotion engine (happy hour, combo)
- [ ] Multi-language UI (i18n — DE, EN, TR, FR)
- [ ] Multi-currency full support
- [ ] Advanced analytics dashboard
- [ ] AI-powered sales prediction
- [ ] Kitchen prep time ML model
- [ ] 3rd-party delivery integration (Uber Eats, Wolt)
- [ ] Reservation system
- [ ] QR table ordering (with waiter approval)
- [ ] Digital menu board (TV menu)
- [ ] Staff shift scheduling
- [ ] Inventory management (recipe-based stock deduction)

---

## MILESTONE EXIT CRITERIA (not yet met)

### Day 90 (2026-06-20) — 0/5 criteria met
- [ ] 2 Swiss restaurants processing real transactions daily
- [ ] Zero data loss incidents in first 2 weeks
- [ ] KDS operational on single tablet
- [ ] Swiss receipts passing legal review
- [ ] Play Console account ready for internal track

### Day 180 (2026-09-20) — 0/6 criteria met
- [ ] 5 Swiss restaurants using GastroCore
- [ ] POS + KDS on separate tablets in ≥2 restaurants
- [ ] Cloud sync in staging: restaurant data visible from web
- [ ] Play Store closed beta available
- [ ] MRR CHF 250–400
- [ ] Zero data loss since pilot launch

### Day 365 (2027-03-20) — 0/7 criteria met
- [ ] 20+ paying Swiss customers
- [ ] 2+ paying German pilot customers (fiscal pack running)
- [ ] Play Store production listing, 4.0+ rating
- [ ] Cloud sync: zero data loss in 3 months of production
- [ ] MRR CHF 1,500+
- [ ] German fiscal: DSFinV-K export passes BSI validation
- [ ] CI/CD: automated build + test on every PR

---

## EFFORT SUMMARY

| Phase | Effort | Target |
|-------|--------|--------|
| P0 Pilot Blockers (Epics 0+1+VAT remaining) | ~8d | 2026-05-01 |
| P1 Pre-Commercial (Epics 3+4+5) | ~14d | 2026-06-01 |
| Phase 2 LAN Sync + CI/CD (Epics 6+12) | ~26d | 2026-07-15 |
| Phase 3 Cloud + Dashboard (Epics 7+8+9+11) | ~50d | 2026-09-20 |
| Phase 5 Germany Fiscal (Epic 10) | ~25d | 2027-01-15 |
| Ongoing tests (Epic 13) | ~13d | ongoing |
| **Total tracked** | **~136d** | |

Additional untracked effort: shared packages, web dashboard app, patron app, hardware integration, online ordering, customer app, retail mode.
