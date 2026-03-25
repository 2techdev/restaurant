# 21 — Current State Audit

> **Document Status:** Authoritative | **Last Updated:** 2026-03-24 | **Based on:** Direct codebase inspection
>
> This document reflects **actual code**, not intentions. Every claim here was verified against the repository.
> Previous version (2026-03-20) is superseded by this audit.

---

## 1. Audit Methodology

Inspected: `apps/pos/lib/` (282 Dart files, ~25,656 LOC), `apps/online/lib/` (28 Dart files),
`server/` (56 Go files, ~6,768 LOC), `test/` (44 unit test files, 9 integration suites),
all 29 Drift table definitions, 6 PostgreSQL migration sets, build configs, pubspec.yaml, go.mod.

Compared against docs 00–20 and the architecture freeze (doc 23).

---

## 2. Flutter POS App — What Is Actually Implemented

### 2.1 Core Infrastructure ✅ COMPLETE

| Component | Status | Notes |
|-----------|--------|-------|
| Drift ORM + 29 SQLite tables | ✅ Complete | Schema version 2; generated `.g.dart` present |
| GetIt + Riverpod DI | ✅ Complete | All providers registered in `providers.dart` |
| GoRouter (14 named routes) | ✅ Complete | Route guards present |
| Money value object | ✅ Complete | Integer cents, CHF, 5-Rappen rounding in `money.dart` |
| UUID v7 generator | ✅ Complete | Order numbers, receipt numbers |
| Stitch design system | ✅ Complete | Colors, typography, 15+ shared widgets |
| App constants/enums | ✅ Complete | TableStatus, OrderStatus, PaymentMethod, OrderType |
| Error handling | ✅ Complete | Failures + exceptions typed hierarchy |

### 2.2 Fare Engine ✅ COMPLETE (Critical Business Logic)

| Component | Status | Notes |
|-----------|--------|-------|
| FareEngine (25-field calculator) | ✅ Complete | Tax, discount, rounding, modifiers |
| FareBreakdown + FareConfig models | ✅ Complete | Typed breakdown per tax rate |
| PriceResolver | ✅ Complete | Resolves price by order type |
| **Unit tests** | ✅ 30+ test cases passing | Full coverage of edge cases |

### 2.3 Authentication / PIN Login ✅ COMPLETE

| Component | Status |
|-----------|--------|
| 4-digit PIN login screen | ✅ Done |
| Multi-user avatar grid | ✅ Done |
| Failed PIN counter + lockout | ✅ Done |
| Role-based access (cashier / manager / admin) | ✅ Done |
| Manager PIN confirmation dialog | ✅ Done — used for restricted actions |

### 2.4 Menu Management ✅ COMPLETE

| Component | Status | Notes |
|-----------|--------|-------|
| Category CRUD (name, color, emoji, order) | ✅ Done | Drag-drop reorder |
| Product CRUD (price, tax profile, active) | ✅ Done | |
| Modifier groups (mandatory/optional, min/max) | ✅ Done | |
| Product–modifier group M2M | ✅ Done | |
| Bulk price update | ✅ Done | % adjustment, category scope |
| Swiss MWST tax groups (2.6%, 3.8%, 8.1%) | ✅ Done | In DB seed |
| Product image picker | 🔄 Package added | `image_picker` in pubspec; UI integration pending |
| **Unit tests** | ✅ 45/45 passing | |

### 2.5 Order Entry ✅ COMPLETE

| Component | Status | Notes |
|-----------|--------|-------|
| Order creation from POS grid | ✅ Done | |
| Item add/remove/quantity | ✅ Done | |
| Modifier selection dialog | ✅ Done | |
| Per-item and per-order notes | ✅ Done | |
| Order types: dine-in, takeaway, delivery | ✅ Done | Enum defined |
| Split bill (by item / by amount / equally) | ✅ Done | |
| Void / refund (immutable — creates new record) | ✅ Done | |
| Receipt preview before payment | ✅ Done | |
| **Discount dialog** | 🔄 Button present | FareEngine ready; dialog UI not wired |

### 2.6 Payments ✅ COMPLETE (Core Flows)

| Method | Status | Notes |
|--------|--------|-------|
| Cash with change calculation | ✅ Done | |
| Simulated card (for testing) | ✅ Done | |
| Split payment (mixed methods) | ✅ Done | |
| **myPOS WiFi bridge** | ✅ Done | TCP port 60180, SlaveSDK AAR (`slavesdk2.1.8.aar`), 60s heartbeat, 15s ICMP watchdog, 10 reconnects — field validation needed |
| **Wallee LTI bridge** | ✅ Done | TCP port 50000, XML framing, EP2 receipt fields — field validation needed |
| TWINT (via myPOS) | ✅ Done | |
| Abstract `HardwarePaymentProvider` interface | ✅ Done | Clean extension point for new terminals |
| `PaymentEngine` orchestrator | ✅ Done | |
| **Unit tests** | ✅ Passing | `mypos_payment_provider_test`, `wallee_payment_provider_test`, `payment_engine_test` |

### 2.7 Tables / Floor Plan ✅ COMPLETE

| Component | Status | Notes |
|-----------|--------|-------|
| Multi-floor plan | ✅ Done | |
| Table CRUD (name, capacity, shape) | ✅ Done | |
| Drag-drop placement (InteractiveViewer 1200×800) | ✅ Done | |
| Table states (available / occupied / reserved / dirty) | ✅ Done | |
| Guest count | ✅ Done | |
| Table merge (primary ← secondary order transfer) | ✅ Done | |
| Order transfer (table-to-table) | ✅ Done | |
| Drift Stream for live state updates | ✅ Done | |
| **Table split dialog** | 🔲 Missing | Not yet implemented |
| **Unit tests** | ✅ 22/22 passing | |

### 2.8 Printing ✅ COMPLETE

| Component | Status | Notes |
|-----------|--------|-------|
| WiFi/TCP printer (port 9100) | ✅ Done | |
| USB printer (20+ vendor IDs, auto-reconnect) | ✅ Done | |
| Bluetooth printer (RFCOMM SPP, EventChannel) | ✅ Done | |
| Raw ESC/POS byte builder | ✅ Done | |
| Swiss-compliant receipt (UID, MWST, 5-Rappen) | ✅ Done | 36 tests |
| Kitchen ticket builder (station-aware) | ✅ Done | 24 tests |
| Shift / Z-report builder | ✅ Done | 45 tests |
| Print queue with retry | ✅ Done | |

### 2.9 Kitchen Display System ✅ UI DONE / ⚠️ DATA NOT WIRED

| Component | Status | Notes |
|-----------|--------|-------|
| KDS screen (via `main_kds.dart`) | ✅ UI done | Visual is complete and polished |
| Color-coded urgency (green/orange/red by elapsed time) | ✅ Done | |
| Per-ticket countdown timer (1s precision) | ✅ Done | |
| Bump button + stats bar | ✅ Done | |
| Responsive grid (1–4 columns) | ✅ Done | |
| **Real data connection** | 🔲 **MISSING** | Still uses `_buildDemoTickets()` hardcoded demo data |
| `kitchen_tickets` + `kitchen_ticket_items` tables | ✅ Schema exists | DB tables ready, not queried by KDS screen |
| **KDS audio alert** | 🔄 Package added | `audioplayers` in pubspec; integration pending |
| **Station routing** | 🔄 Partial | Schema ready; UI routing not implemented |

### 2.10 Waiter App ✅ DONE (Embedded Mode)

All waiter app screens are complete inside `main_waiter.dart` entry point. PIN login, table selection (portrait), menu browse, order creation, active orders, bottom navigation — all functional.

**Standalone Waiter APK:** `apps/waiter/` not yet created (Phase 2).

### 2.11 Kiosk Mode ✅ DONE (Embedded Mode)

Welcome, language selection (DE/FR/IT/EN), menu browse, product detail, cart, checkout, confirmation — all complete via `main_kiosk.dart`. Hardware payment integration for kiosk-specific flow is TBD.

**Standalone Kiosk APK:** Phase 2.

### 2.12 Order Display Screen (ODS) 🔲 SCAFFOLDED ONLY

`main_ods.dart` exists as an entry point. Screen is blank. No live order ticker, no customer display logic.

### 2.13 Shifts ✅ COMPLETE

Shift open, opening float, cash movements, cash reconciliation, shift close, Z-report auto-print on close, shift history (all terminals / this terminal filter), multi-register device ID — all complete. **27/27 unit tests passing.**

### 2.14 Settings ✅ READ / 🔄 WRITE PARTIAL

Settings UI renders all configuration screens. `AppSettings`, `PaymentSettings`, `PrinterSettings`, `ReceiptSettings`, `RestaurantSettings`, `TaxSettings` persist via SharedPreferences. Some save callbacks incomplete — restaurant name and MWST number fields don't persist reliably.

### 2.15 Backoffice (Local) ✅ COMPLETE

In-app backoffice: Menu CRUD, Staff CRUD, Table CRUD, Reports tab — all functional.

### 2.16 Sync Infrastructure 🔄 SCAFFOLDED

`sync_queue` and `sync_metadata` tables exist in Drift schema. Outbox/Inbox DAOs defined. REST sync client partially defined. WebSocket hub structure exists. **Zero sync logic is wired** — outbox is never written on mutations.

### 2.17 Licensing ✅ COMPLETE (Framework)

Ed25519 JWT verification, tier definitions (Starter/Pro/Enterprise), `LicenseValidator`, `FlagGate` widget all implemented. **Unit tested.** However, **no feature gate checks exist in actual feature code** — app runs all features regardless of license tier.

### 2.18 Audit / Backup ✅ COMPLETE

Audit log writer, SQLite backup to Downloads, SQLite restore with manager PIN — all complete.

---

## 3. Online Ordering Web App (apps/online/) — Audit

**Status: UI Complete, Zero Backend Integration**

All 7 screens (landing, menu, product detail, cart, checkout, confirmation, tracking) are implemented in Flutter Web with 4-language i18n (DE/FR/IT/EN). Every screen uses `mock_api_client.dart` — no real API calls exist. No payment processing. No tests.

---

## 4. Go Backend — Audit

### 4.1 Infrastructure ✅ SOLID

HTTP server (graceful shutdown), PostgreSQL connection pooling, complete middleware chain (RequestID, Logger, Recover, CORS, Auth, Tenant, RateLimit), JWT, Ed25519, UUID generation — all implemented and working. Docker Compose with PostgreSQL + Go + Redis-alpine. **Redis: in docker-compose but zero usage in Go code — not needed for v1.**

### 4.2 Module Implementation Status

| Module | Status | What Works | What's Missing |
|--------|--------|------------|----------------|
| **auth** | ✅ MVP | JWT, device registration, multitenant | Refresh token rotation |
| **sync** | ✅ MVP | Upload/download REST, WebSocket hub | Real conflict resolution, delta sync |
| **menu** | ✅ MVP | Full CRUD endpoints | Bulk operations |
| **stores** | ✅ MVP | Store management, tenant API | Store hours |
| **devices** | ✅ MVP | Device CRUD | Health monitoring |
| **licenses** | ✅ MVP | License validation endpoint | License revocation |
| **kds** | ✅ MVP | WebSocket hub | Ticket routing rules |
| **orders** | 🔄 Partial | Create/list | Order lifecycle, refunds |
| **reports** | 🔄 Partial | Struct exists | All queries stubbed |
| **online** | 🔲 Stub | Demo handler | Full flow, payments |
| **fiscal** | 🔲 Empty | Module file only | Fiskaly TSE (Phase 5) |
| **erpnext_bridge** | 🔲 REMOVED | Dead code | Not building |

### 4.3 Database Migrations

6 migration sets (up/down pairs) covering 26 PostgreSQL tables: tenants, auth, menu, orders, payments, shifts, kitchen, sync, fiscal, stores. All migrations present and runnable.

### 4.4 Go Test Coverage

One test file: `sync/handlers_test.go`. All other modules have zero tests.

---

## 5. Test Coverage Summary

| Category | Files/Suites | Status | Gaps |
|----------|-------------|--------|------|
| Unit tests (Flutter) | 44 files, 280+ cases | ✅ Passing | ODS, online app, discount dialog |
| Integration tests (Flutter) | 9 suites | ✅ Present | E2E automated workflows |
| Go API tests | 1 file | ✅ Partial | All modules except sync |
| E2E / Appium tests | 0 | 🔲 None | Everything |
| Performance tests | 0 | 🔲 None | Everything |

---

## 6. Android Build State

| Item | Status | Notes |
|------|--------|-------|
| App ID | `com.gastrocore.gastrocore_pos` | Set |
| Current version | `0.1.0+1` | Must increment before pilot |
| targetSdk | Needs explicit `35` | Play Store requirement |
| minSdk | Needs explicit `26` | Android 8.0 |
| Release keystore | `gastrocore-release.jks` referenced | File existence unverified |
| Debug APK | ✅ Exists | `build/app/outputs/flutter-apk/app-debug.apk` (142 MB) |
| Release AAB | 🔲 Not verified | Needs signing test |
| myPOS AAR | ✅ Bundled | `android/app/libs/slavesdk2.1.8.aar` |

---

## 7. Known Bugs and Critical Gaps

| # | Issue | Severity | Location |
|---|-------|----------|----------|
| B1 | KDS shows demo data — not wired to real DB | **BLOCKS PILOT** | `kitchen/` feature |
| B2 | Discount dialog button non-functional | High | `orders/` feature |
| B3 | Settings save incomplete (restaurant name, MWST not persisting) | High | `settings/` feature |
| B4 | KDS audio alert not integrated | Medium | `kitchen/` feature |
| B5 | ODS screen blank | Medium | `ods/` feature |
| B6 | Online ordering 100% mock data | High | `apps/online/` |
| B7 | Go orders module lifecycle incomplete | High | `server/internal/orders/` |
| B8 | Go reports module stubbed | Medium | `server/internal/reports/` |
| B9 | Table split dialog missing | Medium | `tables/` feature |
| B10 | Cloud sync not wired (outbox never populated) | High | `sync/` feature |
| B11 | No feature gate checks in app code (license not enforced) | High | licensing |

---

## 8. What Is Production-Ready on a Single Device Today

The following can run in a Swiss pilot restaurant on a **single tablet** with **zero internet**:

- ✅ Full order flow: table → order with modifiers → payment → receipt
- ✅ Cash with change calculation and 5-Rappen rounding (in SwissReceiptBuilder)
- ✅ myPOS terminal bridge (needs field test)
- ✅ Wallee terminal bridge (needs field test)
- ✅ Swiss MWST receipt (8.1% / 2.6% / 3.8%) — SwissReceiptBuilder has 36 tests
- ✅ Kitchen ticket printing to thermal printer
- ✅ KDS embedded mode (displays demo data — B1 above blocks real data)
- ✅ Waiter app embedded mode
- ✅ Kiosk mode embedded
- ✅ Shift open/close with Z-report printing
- ✅ Full local backoffice (menu, staff, tables, reports)
- ✅ SQLite backup/restore
- ✅ Audit log

## 9. Gap to Pilot-Ready

See doc 22 for full gap analysis. Short list:

| Gap | Fix | Effort |
|-----|-----|--------|
| KDS wiring (B1) | Wire `_buildDemoTickets()` → Drift stream | 3–5 days |
| Discount dialog (B2) | Wire FareEngine to UI | 1 day |
| Settings save (B3) | Fix save callbacks | 1 day |
| Payment hardware field test | On-site with actual device | 1–2 days |
| Release signing | Keystore + AAB build | 0.5 day |
| Dine-in/takeaway VAT toggle | Wire toggle → FareEngine | 2 days |

**Estimated gap: 2–3 focused weeks to pilot-ready single-device.**

---

## 10. Contradiction Index (Docs vs Code)

| # | Doc Claims | Code Reality |
|---|-----------|-------------|
| 1 | Redis for pub/sub | Not in `go.mod`, never used |
| 2 | ERPNext Bridge | Dead stub — officially removed |
| 3 | Feature flags enforced | No `FlagGate` in feature code |
| 4 | License token validation live | License service is stub-complete but gating not wired |
| 5 | KDS is a separate Flutter app | It's a mode in the POS app via `main_kds.dart` |
| 6 | Sync queue populated on mutations | Tables exist; outbox never written |
| 7 | Settings fully persisted | Some fields don't save reliably |
| 8 | LAN sync (old docs) | Architecture decision changed: **cloud sync only** |
