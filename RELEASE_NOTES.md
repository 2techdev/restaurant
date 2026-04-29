# GastroCore Platform — Release Notes

---

## v1.3.0-beta — Swiss Pilot, Blok 2 / 3

> **Release Date:** 2026-04-22
> **Build:** Flutter 3.35 / Dart ^3.9.2 | Android minSdk 26
> **Package:** `com.gastrocore.gastrocore_pos`
> **Target Market:** Switzerland (DE/FR/IT/EN) + Türkiye staff UI (TR)

### Highlights

- **Happy hour rules** — per-day time windows with category/product scope and stackable flag. Managers can set up brunch, aperitif, and late-night promotions directly from Settings → Happy Hour.
- **Loyalty tuning** — earn rate, redemption ratio, and Silver/Gold/Platinum thresholds are now configurable. Points calculation rebuilds automatically.
- **Shift break / pause** — staff can clock a break from the Mesai panel; overtime is derived from `standardHours` vs actual clocked duration and surfaced on the Z-report.
- **Turkish UI** — 157 translation keys added; TR joins DE/FR/IT/EN in `supportedLocales`.
- **App self-update** — manifest-based checker (signed SHA-256 APK) with audit trail and mandatory-update floor. Operators trigger the download from Settings → Güncelleme; the platform share sheet hands the APK URL to the browser.
- **Screen-reader coverage** — PIN pad, floor-plan tiles, and payment method tiles expose localised Semantics labels. A11y regression test locks the labels.
- **Golden baselines @ 1920×1200** — 5 screens (PIN login, empty order panel, payment tiles, table tiles, update card) are pinned so padding/colour/typography regressions surface as pixel diffs.

### Known Limitations

- Offline sync dead-letter queue (DLQ) for poison events ships in the next release.
- MWST-Nr format validation (CHE-XXX.XXX.XXX) still pending (Phase 2).
- QR-Bill generation for on-demand invoices still pending (Phase 3).

---

## v1.0.0-beta — Swiss Pilot Release

> **Release Date:** 2026-03-23
> **Build:** Flutter 3.9.2 | Android minSdk 26 | Go 1.22
> **Package:** `com.gastrocore.gastrocore_pos`
> **Target Market:** Switzerland (German-speaking, French-speaking, Italian-speaking regions)

---

### What Is GastroCore?

GastroCore is a modular, offline-first restaurant management platform built for the Swiss hospitality industry. It runs on Android tablets (POS, KDS, Waiter, Kiosk, ODS) and optionally connects to a Go cloud backend for multi-device sync, reporting, and online ordering.

---

## Per-App Status

### POS App — Production Ready
**Entry:** `main.dart` | **Mode:** Tablet, landscape

The primary point-of-sale application for cashiers and managers.

**Implemented:**
- PIN authentication (4–6 digit) with user avatar grid (staff selection)
- 3-column POS screen: category rail → product grid → live order panel
- Full order entry: add items, modifiers, notes, quantities
- Swiss VAT handling: dine-in vs. takeaway rate differentiation, per-item tax group
- Cash payment with change calculation and 5-Rappen CHF rounding
- Card payment with hardware abstraction layer (Wallee/myPOS stubs)
- Split bill: by product, equal shares, or custom amounts
- Table management with visual floor plan (drag-to-seat not yet implemented)
- Shift open/close with cash count and Z-report
- End-of-day summary and cash reconciliation
- Thermal receipt printing (Bluetooth, USB, Network/WiFi)
- Kitchen ticket printing to kitchen printer
- Refund and void with manager PIN gate
- Discount framework (FareEngine ready; discount dialog UI in progress)
- Back office: menu CRUD, staff CRUD, table CRUD, basic sales chart
- Dashboard with revenue stats and order counts
- Full audit log on all data changes
- Offline-first: all data stored locally in SQLite/Drift; syncs to backend when online
- Seed data: 40+ products, 8 categories, 5 staff, 14 tables on first launch

**Known Limitations:**
- Product/staff photo upload not yet wired (image picker TODO)
- Discount dialog shows button but opens placeholder (FareEngine logic complete)
- Settings are read correctly but tenant config save to DB needs final wiring
- Payment terminal hardware integration requires vendor SDK testing (Wallee/myPOS)
- `flutter analyze` reports ~187 lint warnings (no crashes; cleanup in progress)

---

### KDS App (Kitchen Display System) — MVP
**Entry:** `main_kds.dart` | **Mode:** Landscape, wall-mounted display

**Implemented:**
- KDS login with station PIN
- Live kitchen ticket cards with auto-refresh
- Timer color coding: green < 10 min, orange < 20 min, red > 20 min
- Bump (mark complete) per ticket and per item
- Course management: first course, second course grouping
- Station filter: kitchen, bar, pastry, hot kitchen
- Settings screen (station selection)

**Known Limitations:**
- Audio alert on new ticket not yet implemented (audioplayers package integration pending)
- KDS is embedded in POS APK as a separate entry point; not yet a standalone APK
- Recall of bumped tickets not implemented

---

### Waiter App (Handheld) — MVP
**Entry:** `main_waiter.dart` | **Mode:** Portrait, one-hand optimized

**Implemented:**
- Waiter PIN login (shows only waiter-role users)
- Table overview with status badges (Available / Occupied / Reserved)
- Menu browse with product grid and quick-add
- Active orders overview per table
- Bottom navigation for one-thumb operation
- Order submission to shared SQLite database

**Known Limitations:**
- Waiter app embedded in POS APK; standalone `apps/waiter/` project not yet extracted
- Course fire button not implemented
- Bill split initiation from waiter app not implemented

---

### Kiosk App (Self-Service) — MVP
**Entry:** `main_kiosk.dart` | **Mode:** Portrait or landscape, customer-facing

**Implemented:**
- Welcome screen with language selector (DE / FR / IT / EN)
- Language selection screen (4 languages)
- Full-screen menu browse with large product cards
- Product detail screen with modifier selection
- Cart screen with item editing
- Payment screen with terminal handoff
- Order confirmation with pickup code display

**Known Limitations:**
- Payment terminal integration requires hardware SDK testing
- Idle timeout / screensaver not implemented
- Kiosk is embedded in POS APK; standalone project not extracted

---

### ODS App (Order Display Screen) — Scaffolded
**Entry:** `main_ods.dart` | **Mode:** Landscape, customer-facing TV/monitor

**Implemented:**
- ODS app entry point and basic scaffold
- Two placeholder screens

**Not Yet Implemented:**
- Live order status ticker (Preparing / Ready)
- Pickup number display (large font)
- Estimated time countdown
- TV full-screen mode lock

**Note:** ODS is scaffolded only. Not production-ready.

---

### Online Ordering (Web App) — Scaffolded
**Location:** `apps/online/` | **Mode:** Flutter Web, customer browser

**Implemented (UI only):**
- Landing screen
- Menu browse (categories + products)
- Product detail screen
- Cart screen
- Checkout screen
- Order confirmation screen
- Order tracking screen
- 4-language support (DE / FR / IT / EN)

**Not Yet Implemented:**
- Backend API integration (all HTTP calls are stubs)
- Payment gateway (Stripe / Datatrans / TWINT)
- Real-time order status via WebSocket
- Order acceptance popup on POS when online order arrives

**Note:** Online ordering UI is complete but not connected to backend. Not production-ready.

---

## Swiss-Specific Features

### VAT (MWST) Compliance
GastroCore implements Swiss MWST fully for Phase 1:

| Rate | Code | Applied To | Dine-In | Takeaway |
|------|------|------------|---------|----------|
| 8.1% | A | Food (normal), Beverages | 8.1% | 8.1% |
| 2.6% | B | Food (reduced) | 2.6% | 2.6% |
| 3.8% | C | Accommodation services | 3.8% | — |

- All prices are gross-inclusive (Bruttopreise); tax is extracted, never added
- Formula: `tax = gross × rate / (100 + rate)`
- Per-item `tax_group` is snapshot at order creation time (not recalculated from master data)
- Dine-in vs. takeaway toggled per ticket with automatic recalculation of all items

### Swiss Receipt (Verkaufsbeleg)
Every customer receipt includes:
- Restaurant name + address (German)
- MWST-Nr (CHE-XXX.XXX.XXX format)
- Receipt number, date, time, cashier name, table number
- Itemized list with modifiers and notes
- Order type label: `Hier essen` or `Zum Mitnehmen`
- Subtotal → Discount → Total (large font)
- Payment method, amount given, change
- MWST breakdown table by rate (Net | Tax | Gross per rate)
- Rounding line: `Rundung +/-CHF 0.05` when applicable
- Footer message (configurable)
- QR placeholder for future QR-Bill integration

### 5-Rappen Rounding (CHF)
Final order totals are rounded to the nearest CHF 0.05 per Swiss convention. The rounding amount is tracked separately in `FareBreakdown.roundingAmount` and printed on the receipt.

### Multilingual UI
All four Swiss national languages are supported:

| Language | Code | Coverage |
|----------|------|----------|
| German | `de` | Complete — primary language |
| French | `fr` | Complete |
| Italian | `it` | Complete |
| English | `en` | Complete |

Language is selectable per device in Settings and at the Kiosk welcome screen.

### Payment Methods
| Method | Status |
|--------|--------|
| Cash (Bar) | Production ready |
| Credit card | Hardware abstraction ready |
| Debit card | Hardware abstraction ready |
| TWINT | Label present; API integration in Phase 2 |
| Split payment | Production ready |

---

## Technical Specifications

### Platform Requirements
- **Android:** 8.0+ (API 26), ARM64
- **Minimum RAM:** 2 GB (4 GB recommended for POS tablet)
- **Storage:** 500 MB free (database grows with transaction history)
- **Network:** LAN recommended; fully offline-capable

### Database
- Local: SQLite via Drift ORM, 29 tables
- All monetary values stored as INTEGER (cents) — no floating-point errors
- All records have `tenant_id` (multi-tenant foundation)
- Soft deletes via `is_deleted` flag
- Sync status tracking per row

### Go Backend (Self-Hosted)
- PostgreSQL 16 + Redis 7 (optional)
- 32+ REST endpoints
- WebSocket hub for KDS live updates
- Docker Compose deployment
- Ed25519 license validation

### Security
- PIN hashing via `crypto` package
- Ed25519 license signatures
- JWT token authentication (24-hour expiry)
- Audit log for all data mutations
- No passwords stored in plain text

---

## Known Issues

| # | Severity | Description | Workaround |
|---|----------|-------------|------------|
| 1 | Medium | Image picker not implemented — products show initials avatar | Use text-only product names |
| 2 | Medium | Discount dialog opens placeholder — no dynamic discounts at POS | Apply discounts via Back Office product pricing |
| 3 | Low | Settings screen tenant config not persisted between sessions | Reconfigure on restart (seed data covers common defaults) |
| 4 | Low | KDS audio alert silent on new ticket | Staff must watch screen visually |
| 5 | Low | ~187 flutter analyze lint warnings | No functional impact; cleanup in progress |
| 6 | Low | Payment terminal (Wallee/myPOS) requires hardware SDK setup | Use cash-only mode for pilot |
| 7 | Info | ODS and Online Ordering are scaffolded only | Do not deploy to customers |

---

## Upgrade Path

From `v0.1.0+1` → `v1.0.0-beta`:
- Database schema is forward-compatible (migrations run automatically)
- No breaking changes to local SQLite schema in this release
- Go backend: run `go run ./cmd/migrate/main.go` before starting server

---

## What's Next (v1.1.0)

- Image picker for product photos
- Discount dialog (%, fixed amount, named presets)
- KDS audio alerts
- ODS live ticker display
- Wallee payment terminal testing
- Standalone KDS APK
- `flutter analyze` clean to 0 issues

---

*GastroCore is developed by 2TechHub. For support or pilot onboarding, contact the development team.*
