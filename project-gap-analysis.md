# GastroCore Platform — Gap Analysis
**Date:** 2026-03-21
**Scope:** Missing, stub, skeleton, and untested items only. Completed items excluded.
**Evidence base:** 287 Dart files, 54 Go files, 51 architecture docs, 63 test files

---

## LEGEND
- **CRITICAL** — Blocks production use / demo flow
- **HIGH** — Blocks a key product feature / revenue scenario
- **MEDIUM** — Incomplete but workaround exists or feature is non-core
- **LOW** — Polish, edge case, or deferred feature

---

## 1. BACKEND (Go Server) GAPS

### 1.1 Orders Module — All Endpoints TODO
**Severity: CRITICAL**
**File:** `server/internal/orders/handlers.go`
All three handlers are comment stubs:
- `handleListOrders` — TODO
- `handleGetOrder` — TODO
- `handleOrderSummary` — TODO

No order data can be fetched from the cloud. POS push-only sync cannot be verified. Reporting and backoffice that depend on server-side order aggregation are broken.

---

### 1.2 Online Ordering — Order Placement Endpoint Stub
**Severity: CRITICAL**
**File:** `server/internal/online/handlers.go` — `handlePlaceOrder`
Menu GET is implemented; order POST is a stub with a response template only. Online ordering channel cannot complete a transaction end-to-end.

---

### 1.3 Online Ordering — Order Status WebSocket Not Wired to Real Orders
**Severity: HIGH**
The online ordering frontend polls `/api/v1/online/orders/{orderId}/status`. The WebSocket hub exists in the KDS module but there is no bridge from an online order → KDS ticket → status update back to the customer. The order status screen (`order_status_screen.dart`) has no live data.

---

### 1.4 ERPNext Bridge — Complete Stub
**Severity: HIGH** (for accounting-integrated customers)
**File:** `server/internal/erpnext_bridge/module.go` (4 lines, comment only)
No handlers, no models, no HTTP client, no sync job. Planned for Phase 9. Blocks any integration with existing ERP/accounting systems.

---

### 1.5 Fiscal / Fiskaly TSE — Complete Stub
**Severity: HIGH** (for German market)
**File:** `server/internal/fiscal/module.go` (4 lines, comment only)
No TSE lifecycle, no transaction signing, no Fiskaly SDK integration. KassenSichV compliance (mandatory in Germany) is zero. Planned Phase 10.

---

### 1.6 Go Orders Module — No Create/Update/Delete Endpoints
**Severity: HIGH**
Even beyond list/get, there are no server-side order mutation endpoints (create, update status, cancel, refund). All order writes currently go through the sync queue which is push-only. The cloud hub cannot act as an order source of truth.

---

### 1.7 Stores Module — Device Pairing QR Not Tested
**Severity: MEDIUM**
`server/internal/stores/` has device pairing via QR code in code, but no test files and no integration test covers the pairing flow. QR pairing is critical for KDS/Waiter device onboarding.

---

### 1.8 Reports Module — Day Close Only, No Weekly/Monthly Aggregation
**Severity: MEDIUM**
**File:** `server/internal/reports/`
Doc-16 specifies daily, weekly, monthly, and product-performance reports. Only day-close and revenue endpoints are present. Weekly/monthly aggregation SQL and handlers are missing.

---

## 2. FRONTEND — POS & COMPANION APPS

### 2.1 Online Ordering — Checkout Flow Not Connected to Real Backend
**Severity: CRITICAL**
`apps/online/lib/screens/checkout_screen.dart` submits to `api_client.dart` which calls POST `/api/v1/online/orders`. Backend is a stub (see 1.2). Demo uses `mock_api_client.dart` with hardcoded success. Real payment (card/TWINT) integration for web orders does not exist.

---

### 2.2 KDS App — Bump Action Not Persisted to Backend
**Severity: HIGH**
`features/kds_app/` has bump-to-complete UI. The bump action updates local state but there is no sync event or HTTP call that marks the kitchen ticket as completed on the server. POS cannot know when a dish is ready.

---

### 2.3 Waiter App — LAN Sync Uses mDNS (No Fallback)
**Severity: HIGH**
`features/waiter/services/waiter_order_service.dart` syncs via mDNS discovery + WebSocket. There is no fallback if mDNS fails (iOS/some Android setups block mDNS). Waiter app will silently fail to sync in those environments. No error UI to indicate sync loss.

---

### 2.4 Kiosk App — Payment Screen Not Connected to Hardware Payment Engine
**Severity: HIGH**
`features/kiosk/screens/kiosk_checkout_screen.dart` shows a payment screen but the `KioskOrderService` does not call `PaymentEngine`. Kiosk cash/card payment is unimplemented — tapping "Pay" does not invoke Wallee or MyPOS.

---

### 2.5 Inventory — No Backend Endpoints, No Sync Events
**Severity: HIGH**
`features/inventory/` has 3 screens + full DAO. However:
- No corresponding Go handler in `server/internal/` for inventory
- No `SyncEvent` type for inventory transactions in the sync queue
- Stock deductions on order completion are not wired (order paid → reduce stock)
- Inventory is purely local with no cloud persistence

---

### 2.6 ODS — No Real-Time Data Source
**Severity: HIGH**
`features/ods/screens/ods_main_screen.dart` displays order status. There is no WebSocket subscription or polling in the ODS provider. The screen renders static/demo data. Real-time order display for customers does not work.

---

### 2.7 Reports Screen — Single Screen, Missing Product/Staff Reports
**Severity: HIGH**
`features/reports/` has one screen (daily summary). Doc-16 specifies: product performance, top sellers, category breakdown, staff performance, hourly sales, and X/Z reports. None of these additional views exist.

---

### 2.8 Backoffice — Staff Management Screen Incomplete
**Severity: MEDIUM**
`features/backoffice/` has 4 tabs. Staff management tab shows a list but Create/Edit/Delete staff flows are skeleton-only. PIN assignment and role editing are missing.

---

### 2.9 Menu Management — Image Upload Stub
**Severity: MEDIUM**
`features/menu/` references image upload for products. The upload call targets `/api/v1/menu/products/{id}/image` but there is no corresponding Go handler. Product images always fall back to placeholder.

---

### 2.10 Settings Screen — Printer Discovery Not Functional
**Severity: MEDIUM**
`features/settings/` has a printer settings section. WiFi IP is entered manually. Bluetooth device scan is listed but `PrinterService.scanBluetooth()` returns an empty list (not implemented). USB auto-detect on Android is implemented; BT discovery is not.

---

### 2.11 Floor Plan Editor — Table Layout Cannot Be Saved
**Severity: MEDIUM**
`features/tables/screens/` includes a floor management screen (`floor_mgmt_screen.dart`). Table drag-and-drop positions are rendered but the save path is a TODO — repositioning tables is not persisted to the database.

---

### 2.12 Overrides Module — Manager PIN Override Not Enforced on All Actions
**Severity: MEDIUM**
`features/overrides/` handles discount, void, and split. Discount override checks manager PIN. Void and split currently only check `PermissionService` roles but do not trigger the manager PIN override flow in all paths.

---

### 2.13 Shifts — End-of-Day Cash Count Screen Missing
**Severity: MEDIUM**
`features/shifts/` has shift open/close. The close flow calls `DayCloseSummary` but has no interactive cash count screen (enter denominations → calculate over/short). This is listed in doc-17 as required for the cash reconciliation report.

---

## 3. INTERNATIONALIZATION GAPS

### 3.1 FR/IT/EN Translations Incomplete vs. German
**Severity: MEDIUM**
- `app_de.arb` — 492 lines (complete, source of truth)
- `app_en.arb` / `app_fr.arb` / `app_it.arb` — 185 lines each
EN/FR/IT are missing ~307 lines (~63%) of translation keys present in DE. Any string added after initial scaffolding is German-only. Missing keys fall back to key names in production.

---

### 3.2 Kiosk / KDS / ODS / Waiter Apps — l10n Not Verified
**Severity: MEDIUM**
Companion apps (`main_kds.dart`, `main_waiter.dart`, `main_kiosk.dart`, `main_ods.dart`) reference the same `AppLocalizations` but no test verifies that all string keys used in those apps exist in all 4 ARB files. Key-not-found errors would be silent at runtime.

---

## 4. MISSING MODULES (Not Started)

### 4.1 CRM Module
**Severity: MEDIUM**
No directory exists (`features/crm/`). Doc-04 lists CRM as a planned module: customer profiles, loyalty points, visit history, birthday offers. Required for PRO tier. Entirely absent.

---

### 4.2 Reservation / Table Booking System
**Severity: MEDIUM**
No directory exists (`features/reservation/`). Listed in product principles (doc-01) and the 365-day plan (doc-33). No backend endpoints either. Required for full-service restaurant use case.

---

### 4.3 QR-Bill / Swiss e-Invoice
**Severity: MEDIUM**
Doc-08 (Switzerland pack) specifies QR-bill generation for B2B invoicing (CHE reference number format, IBAN barcode). `swiss_receipt_builder.dart` prints MWST breakdown but has no QR-bill block. Required for compliance with Swiss B2B invoice regulations.

---

### 4.4 Online Payment Gateway for Web Orders
**Severity: HIGH**
Online ordering (`apps/online/`) has no payment integration. Checkout screen accepts the order but there is no Stripe/SumUp/TWINT QR integration for web-based payments. Customers cannot pay online — only "pay at pickup/delivery" flow is implied.

---

### 4.5 Push Notifications for Order Status
**Severity: MEDIUM**
Online ordering order status is poll-based only. No FCM/APNs integration for "your order is ready" push notification. Expected by customers ordering ahead.

---

## 5. TEST COVERAGE GAPS

### 5.1 Payment Hardware — No Real Hardware Tests
**Severity: HIGH**
`test/features/payments/` tests `PaymentEngine` routing logic. Wallee and MyPOS provider tests are mock-based. No integration test validates actual TCP/XML handshake with Wallee or TCP/IP with MyPOS. Hardware failure modes (timeout, malformed XML, reconnect) are untested.

---

### 5.2 Sync Engine — No Conflict Resolution Test
**Severity: HIGH**
`SyncRepositoryImpl` uses last-write-wins conflict resolution. No test covers concurrent edits from 2 devices to the same entity. Conflict resolution correctness is unverified.

---

### 5.3 Go Backend — No Tests for Online/KDS/Sync Handlers
**Severity: HIGH**
`server/internal/online/`, `server/internal/kds/`, and `server/internal/sync/` have no `*_test.go` files. The three most critical server-side paths (order placement, kitchen WebSocket, sync push/pull) have zero Go test coverage.

---

### 5.4 Database Migration — No Migration Regression Tests
**Severity: MEDIUM**
10 SQL migration files exist. No test verifies that running migrations from v001 to v010 on a clean database produces a valid schema, or that migrating an existing database from v005 to v010 succeeds without data loss.

---

### 5.5 FareEngine — Edge Cases Missing
**Severity: MEDIUM**
`fare_engine_test.dart` covers standard paths. Missing test cases:
- Mixed tax group order (standard + reduced in same ticket)
- Coupon + modifier interaction
- 0% tax item (gift card, voucher)
- Negative quantity (return/void item)
- Large order (>100 items, rounding accumulation)

---

### 5.6 Kiosk — No Test for Payment Engine Integration
**Severity: HIGH**
`test/features/kiosk/` has 3 test files for `KioskOrderService` but none test the payment path (kiosk checkout → PaymentEngine → Wallee/MyPOS result). This is the most critical kiosk path.

---

### 5.7 i18n — No Missing-Key Detection Test
**Severity: MEDIUM**
No test compares all keys in `app_de.arb` against `app_en.arb`, `app_fr.arb`, `app_it.arb` to detect missing translations. Missing keys are only discovered at runtime.

---

## 6. INFRASTRUCTURE / DEVOPS GAPS

### 6.1 CI — No Go Backend Tests in Pipeline
**Severity: HIGH**
`.github/workflows/` runs Flutter tests and build. No `go test ./...` step exists. Go backend changes are never automatically tested.

---

### 6.2 CI — No End-to-End Integration Test
**Severity: MEDIUM**
`integration_test/` covers app flows with a mock backend. No CI stage spins up the Go server + PostgreSQL and runs the Flutter integration tests against a real backend. Frontend/backend contract is never verified automatically.

---

### 6.3 Docker / Deployment — Production Config Not Finalized
**Severity: MEDIUM**
`server/` has a `Dockerfile` but no `docker-compose.yml` for local dev (Go + PostgreSQL + migrations). Environment variables for production (`DB_URL`, `JWT_SECRET`, `LICENSE_PUBLIC_KEY`) have no `.env.example` or Vault/secrets management documented.

---

### 6.4 Database — No Soft-Delete Purge Job
**Severity: LOW**
29 Drift tables use `is_deleted = true` for soft deletes. There is no background job or scheduled SQL to hard-delete old records after a retention window. Long-running databases will accumulate deleted rows indefinitely.

---

### 6.5 Monitoring — Sentry Integrated but No Alerting Rules
**Severity: LOW**
`core/monitoring/app_logger.dart` sends errors to Sentry. No alert rules, ignored error categories, or performance transaction sampling are configured. All errors are captured but no signal/noise filtering exists.

---

## 7. SECURITY GAPS

### 7.1 Online Ordering — No Rate Limiting on Public Menu/Order Endpoints
**Severity: HIGH**
`server/internal/online/` endpoints are public (no auth). There is no rate limiting middleware. `/api/v1/online/orders` could be spammed to create phantom orders.

---

### 7.2 Sync API — No Per-Device Token Rotation
**Severity: MEDIUM**
Sync push/pull uses a static device JWT. There is no token rotation on device re-registration or forced logout. A stolen device token would have indefinite sync access.

---

### 7.3 License Validator — Public Key Hardcoded in Binary
**Severity: MEDIUM**
`features/licensing/data/services/license_validator.dart` embeds the Ed25519 public key as a string literal. The key can be extracted from the APK/IPA with basic tooling. Consider a remote key fetch + local hash check pattern.

---

## PRIORITY SUMMARY

| # | Gap | Severity |
|---|-----|----------|
| 1.1 | Go orders module — all handlers TODO | CRITICAL |
| 1.2 | Online order placement endpoint stub | CRITICAL |
| 2.1 | Online checkout not connected to backend | CRITICAL |
| 1.3 | Online order status not live | HIGH |
| 1.4 | ERPNext bridge stub | HIGH |
| 1.5 | Fiscal/TSE stub (Germany blocked) | HIGH |
| 1.6 | No server-side order mutations | HIGH |
| 2.2 | KDS bump not persisted | HIGH |
| 2.3 | Waiter LAN sync no fallback | HIGH |
| 2.4 | Kiosk payment not wired to PaymentEngine | HIGH |
| 2.5 | Inventory no backend/no sync/no stock deduction | HIGH |
| 2.6 | ODS no real-time data | HIGH |
| 2.7 | Reports — only day-close exists | HIGH |
| 4.4 | No online payment gateway | HIGH |
| 5.1 | No real hardware payment tests | HIGH |
| 5.2 | Sync conflict resolution untested | HIGH |
| 5.3 | No Go tests for online/KDS/sync | HIGH |
| 5.6 | Kiosk payment path untested | HIGH |
| 6.1 | CI has no Go test step | HIGH |
| 7.1 | Online API no rate limiting | HIGH |
| 1.7 | Device pairing QR untested | MEDIUM |
| 1.8 | Reports — weekly/monthly missing | MEDIUM |
| 2.8 | Backoffice staff management skeleton | MEDIUM |
| 2.9 | Menu image upload stub | MEDIUM |
| 2.10 | Bluetooth printer discovery unimplemented | MEDIUM |
| 2.11 | Floor plan positions not persisted | MEDIUM |
| 2.12 | Void/split override PIN not enforced | MEDIUM |
| 2.13 | Shifts — cash count screen missing | MEDIUM |
| 3.1 | FR/IT/EN missing 63% of translation keys | MEDIUM |
| 3.2 | Companion app l10n not verified | MEDIUM |
| 4.1 | CRM module — not started | MEDIUM |
| 4.2 | Reservation module — not started | MEDIUM |
| 4.3 | QR-Bill / Swiss e-invoice missing | MEDIUM |
| 4.5 | No push notifications for online orders | MEDIUM |
| 5.4 | DB migration regression tests missing | MEDIUM |
| 5.5 | FareEngine edge cases missing | MEDIUM |
| 5.7 | No missing-key i18n detection test | MEDIUM |
| 6.2 | No full-stack CI integration test | MEDIUM |
| 6.3 | No docker-compose / .env.example | MEDIUM |
| 7.2 | Sync token not rotated | MEDIUM |
| 7.3 | License public key hardcoded | MEDIUM |
| 6.4 | No soft-delete purge job | LOW |
| 6.5 | Sentry — no alert rules configured | LOW |

---

*Total gaps identified: 43 (3 critical, 22 high, 16 medium, 2 low)*
