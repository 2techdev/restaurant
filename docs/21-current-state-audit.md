# 21 - Current State Audit

> **Document Status:** Authoritative | **Last Updated:** 2026-03-20 | **Based on:** Direct codebase inspection
>
> This document reflects **actual code**, not intentions. Every claim here was verified against the repository.

---

## 1. Audit Methodology

Inspected: `apps/pos/lib/` (164 Dart files), `server/` (32 Go files), `test/` (20 test files), all 33 DB table definitions, build configs, and all ADRs. Compared against docs 00–20.

---

## 2. What Is Actually Implemented

### 2.1 Auth / PIN Login — COMPLETE ✅

| Component | Status | Notes |
|-----------|--------|-------|
| PIN-based user auth | Done | SHA-256 via `crypto` package |
| Multi-user profiles | Done | cashier, waiter, manager roles |
| Failed PIN counter | Done | |
| `users` table | Done | id (UUID v7), tenantId, name, pin_hash, role, isActive, avatarPath |

**Test coverage:** Included in settings/auth tests.

---

### 2.2 Orders / POS Screen — COMPLETE ✅

| Component | Status | Notes |
|-----------|--------|-------|
| Full POS order creation | Done | |
| Modifier support | Done | paid add-ons, removals, substitutions |
| Void / refund (immutable) | Done | Creates new record, never mutates |
| Order types | Done | dine-in, takeaway, delivery, QR, kiosk (enum) |
| Order state machine | Done | draft→open→submitted→paid→cancelled |
| `tickets` + `order_items` + `order_item_modifiers` | Done | |
| Cashier + table-based order views | Done | |

---

### 2.3 Payments — COMPLETE ✅

| Method | Status | Notes |
|--------|--------|-------|
| Cash (manual) | Done | Change calculation |
| Wallee LTI | Done | TCP port 50000, XML framing, EP2 receipt fields, trxSyncNumber in SharedPreferences |
| MyPOS WiFi | Done | TCP port 60180, SlaveSDK AAR, 60s heartbeat PING, 15s ICMP watchdog, 10 reconnect retries |
| TWINT | Done | Via MyPOS |
| Split bill | Done | By item, equally by N guests, custom split |

**Hardware abstraction:** `HardwarePaymentProvider` interface — adding new terminal = new implementation.
**Test coverage:** mypos_payment_provider_test, wallee_payment_provider_test, payment_engine_test.

---

### 2.4 Menu Management — COMPLETE ✅

| Component | Status | Notes |
|-----------|--------|-------|
| Category CRUD | Done | Drag-drop ordering, color/emoji picker |
| Product CRUD | Done | name, description, price (cents), tax profile, active toggle |
| Modifier groups | Done | Single/multi select, mandatory/optional, min/max, CHF price delta |
| Product–modifier group linking | Done | Many-to-many |
| Product specifications/variants | Done | Atomic replace transaction |
| Bulk price update | Done | % adjustment, category scope, CHF preview |
| Swiss MWST tax groups | Done | food 2.6%, accommodation 3.8%, beverage/alcohol/standard 8.1% |

**Test coverage:** 45/45 unit tests passing.

---

### 2.5 Tables / Floor Plan — COMPLETE ✅

| Component | Status | Notes |
|-----------|--------|-------|
| Multi-floor plan | Done | |
| Table CRUD | Done | name, capacity, shape (circle/square/rectangle) |
| Drag-drop placement | Done | InteractiveViewer canvas 1200×800 px |
| Table states | Done | available, occupied, reserved, dirty |
| Guest count | Done | |
| Table merge | Done | primary←secondary order transfer |
| Order transfer | Done | table-to-table |
| Real-time Drift Stream | Done | live state updates |

**Test coverage:** 22/22 unit tests passing.

---

### 2.6 Shifts — COMPLETE ✅

| Component | Status | Notes |
|-----------|--------|-------|
| Open/close shift flow | Done | |
| Opening float | Done | |
| Cash movements | Done | `cash_movements` table |
| Payment breakdown | Done | cash/card/TWINT, progress bar |
| Shift history | Done | All terminals / this terminal filter |
| ShiftIndicatorWidget | Done | Live timer on home screen, updates every minute |
| Z-report auto-print on close | Done | Non-blocking (close proceeds even if print fails) |
| Multi-register device ID | Done | StateProvider, configurable in Settings |

**Test coverage:** 27/27 unit tests passing.

---

### 2.7 Printing — COMPLETE ✅

| Type | Status | Notes |
|------|--------|-------|
| WiFi/TCP | Done | Port 9100, socket |
| USB | Done | 20+ USB vendor IDs, auto-reconnect |
| Bluetooth | Done | RFCOMM SPP, EventChannel |

| ESC/POS Module | Tests | Status |
|---------------|-------|--------|
| EscPosBuilder | Unit | Done |
| SwissReceiptBuilder | 36 | Done (incl. MWST breakdown, 5-Rappen rounding) |
| KitchenTicketBuilder | 24 | Done |
| ReportBuilder (Z/X reports) | 45 | Done |

---

### 2.8 Dashboard / Home — COMPLETE ✅

- Home screen with shift indicator, daily sales summary, order stats.
- `DashboardRepository` + `DashboardSummary` entity.
- `fl_chart` integration for revenue trend.

---

### 2.9 Settings — COMPLETE ✅

- `AppSettings`, `PaymentSettings`, `PrinterSettings`, `ReceiptSettings`, `RestaurantSettings`, `TaxSettings`
- All persisted via `SharedPreferences`.
- Separate settings repository + Riverpod provider.

---

### 2.10 Database Schema — SOLID ✅

33 tables in Drift ORM, schema version 2, with migration strategy:

```
Tenants, Users, Categories, Products, ModifierGroups, Modifiers,
ProductModifierGroups, Floors, RestaurantTables, Tickets, OrderItems,
OrderItemModifiers, Bills, Payments, Shifts, CashMovements,
KitchenTickets, KitchenTicketItems, Receipts, SyncQueue, SyncMetadata,
AuditLog, TaxProfiles, ProductPrices, OrderTypeRules, ComboItems,
ProductSpecifications
```

Key design decisions confirmed in code:
- UUID v7 for all IDs (uuid 4.5.1)
- Money as integer cents (no floats)
- Soft deletes via `is_deleted` flag
- Audit log table from day 1
- Sync tables (`sync_queue`, `sync_metadata`) exist but not populated

---

### 2.11 Go Backend Skeleton — EXISTS, NOT IMPLEMENTED ✅/⚠️

Modules registered and routing set up:

| Module | Route Prefix | Handler Status |
|--------|-------------|----------------|
| Auth | `/api/v1/auth` | Stub — all TODO |
| Menu | `/api/v1/menu` | Stub — all TODO |
| Orders | `/api/v1/orders` | Stub — all TODO |
| Sync | `/api/v1/sync` | Stub — all TODO |
| Reports | `/api/v1/reports` | Stub — all TODO |
| Devices | `/api/v1/devices` | Stub — all TODO |
| Stores | `/api/v1/stores` | Stub — all TODO |
| Licenses | `/api/v1/licenses` | Stub — all TODO |
| ERPNext Bridge | — | Stub module, no routes |
| Fiscal | — | Stub module, no routes |

**Middleware:** CORS, logging, panic recovery — implemented.
**Database:** PostgreSQL connection pooling via `lib/pq` — wired up, migrations exist.
**Go version:** 1.22.0

---

### 2.12 KDS — UI ONLY, NOT WIRED ⚠️

The `KitchenDisplayScreen` is visually complete and impressive:
- Color-coded ticket cards (green/orange/red borders by elapsed time)
- Per-ticket timer (seconds precision, refreshes every 1s)
- Bump (READY) button that removes ticket from grid
- Pending/Preparing/Ready stats bar
- Responsive grid (1–4 columns)

**Critical gap:** All data is **hardcoded demo data** (`_buildDemoTickets()` function). No connection to `kitchen_tickets` or `kitchen_ticket_items` database tables. No real-time updates from actual POS orders.

The `kitchen_tickets` and `kitchen_ticket_items` tables exist in the schema. The `KitchenTicketEntity` domain entity exists. The bridge between orders and KDS display is not built.

---

### 2.13 Localization — PARTIAL ✅/⚠️

- German (de) and French (fr) ARB files exist
- `l10n.yaml` configured
- Generated `AppLocalizations` class exists
- **Gap:** Coverage is partial — not all strings are localized

---

## 3. What Does NOT Exist (Code-Verified)

| Feature | Doc Reference | Code Status |
|---------|-------------|-------------|
| Sync engine (Flutter ↔ Go) | ADR-014, doc 10 | Tables exist, zero logic |
| Cloud sync (Go handlers) | doc 10 | All TODO stubs |
| License enforcement in app | ADR-011 | No feature flag checks in Dart code |
| License service (Go) | doc 14 | All TODO stubs |
| ERPNext bridge | doc 09 | Stub module only — **REMOVED per architecture decision** |
| Germany fiscal (Fiskaly) | doc 07 | Stub module only |
| Switzerland QR-bill | doc 08 | Not implemented |
| Feature flags in Flutter | ADR-011 | No FlagGate checks in feature code |
| CI/CD pipeline | doc 03 | No .github/workflows or similar |
| E2E tests (real) | — | `integration_test/app_test.dart` is empty skeleton |
| Web dashboard | doc 03 | Not started |
| LAN sync (mDNS/discovery) | ADR-014 | Not started |
| Device registration | doc 03 | Not started |
| Redis (pub/sub) | doc 03 | In docker-compose, NOT in go.mod — never used |
| Online ordering | doc 17 | Not started |
| QR ordering | doc 17 | Not started |
| Kiosk mode | doc 17 | Not started |
| Retail mode | doc 17 | Not started |
| Multi-branch | doc 03 | Not started |
| Custom backoffice | — | Not started (replacing ERPNext per latest decision) |

---

## 4. Android Build State

| Item | Status | Notes |
|------|--------|-------|
| App ID | `com.gastrocore.gastrocore_pos` | Set |
| Version | `0.1.0+1` | Needs increment before release |
| Target SDK | Flutter default | Needs explicit `targetSdk 35` for Play compliance |
| Min SDK | Flutter default | Should be explicit `minSdk 26` |
| Signing config | `gastrocore-release.jks` key.properties | Config references it, file must exist |
| AAB build | Not verified | Needs CI/CD |
| MyPOS SDK AAR | `slavesdk2.1.8.aar` | Bundled in `android/app/libs/` |

---

## 5. Test Coverage Summary

| Area | Tests | Passing | Coverage Level |
|------|-------|---------|----------------|
| Menu | 45 | 45 | High |
| SwissReceiptBuilder | 36 | 36 | High |
| ReportBuilder | 45 | 45 | High |
| Tables | 22 | 22 | High |
| Shifts | 27 | 27 | High |
| KitchenTicketBuilder | 24 | 24 | High |
| Payments (hardware) | ~15 | ~15 | Medium |
| Settings | ~10 | ~10 | Medium |
| Integration tests | 1 | 0 | Skeleton only |
| E2E / UI tests | 0 | — | None |
| Go backend | 0 | — | None |

**Total unit tests:** ~220+ passing.
**Gap:** No integration tests, no Go tests, no E2E tests.

---

## 6. Contradiction Index (Docs vs Code)

| # | Doc Claims | Code Reality |
|---|-----------|-------------|
| 1 | Redis for pub/sub in architecture | Not in `go.mod`, never instantiated |
| 2 | ERPNext Bridge module | Stub only — now **officially removed** |
| 3 | "Layer 3 ERPNext Bridge" in architecture diagram | Does not exist in code |
| 4 | Phase 0 spikes are complete | Phase 0 largely done via implementation |
| 5 | KDS described as a separate Flutter app | It is a screen in the same POS app |
| 6 | LAN sync described with mDNS/gRPC | Not started |
| 7 | Feature flags enforced in Flutter | No `FlagGate` or tier checks in app code |
| 8 | License token validation (Ed25519) | License service is all TODO |
| 9 | Sync queue described as outbox pattern | Tables exist, no outbox logic |
| 10 | Executive summary references ERPNext in "Why this architecture" | Decision reversed — ERPNext removed |

---

## 7. Summary Verdict

**What GastroCore is today (2026-03-20):**

A **single-device, offline-only restaurant POS** with:
- Solid order entry, table management, payment processing, receipt printing
- Good test coverage on core business logic
- Beautiful UI including a non-functional KDS demo
- Database schema ready for sync and multi-device
- Go backend skeleton that compiles and routes but does nothing

**What GastroCore is not yet:**
- Multi-device (no LAN sync)
- Cloud-connected (no sync engine)
- Kitchen-operational (KDS has no real data)
- License-enforcing (no feature flags)
- Compliant (no Germany fiscal, no Swiss QR-bill)
- Production-distributed (no keystore, no CI/CD, no Play listing)

**Gap to pilot-ready:** ~12–16 weeks of focused development (KDS wiring, LAN sync, Swiss VAT hardening, license basics, production build pipeline).
