# 22 - Gap Analysis

> **Document Status:** Authoritative | **Last Updated:** 2026-03-20
>
> Gaps from current state to Swiss pilot-ready, then to market-ready product.

---

## 1. Gap Categories

| Category | Priority | Description |
|----------|----------|-------------|
| **BLOCKING** | P0 | Cannot run a real pilot restaurant without this |
| **PILOT-REQUIRED** | P1 | Needed for Swiss pilot to run cleanly |
| **MARKET-REQUIRED** | P2 | Required before charging money / public launch |
| **GROWTH** | P3 | Needed for scale, multi-branch, channels |
| **DEFERRED** | — | Not needed until explicitly triggered |

---

## 2. P0 — BLOCKING: Cannot Pilot Without These

### GAP-01: KDS Not Connected to Real Data

**Current:** `KitchenDisplayScreen` uses hardcoded `_buildDemoTickets()`. The `kitchen_tickets` and `kitchen_ticket_items` tables exist and have the right schema, but the screen never queries them.

**Required:**
- Wire KDS screen to Drift Stream on `kitchen_tickets` table
- When an order is submitted from POS, write `kitchen_tickets` + `kitchen_ticket_items` rows
- KDS screen reacts to new rows via Drift reactive queries
- Bump action writes `status = completed` to DB
- On single-device: this works immediately (same SQLite)
- On multi-device: requires LAN sync (see GAP-02)

**Effort:** 2–3 days (single device wiring). 1–2 weeks (multi-device via LAN sync).

---

### GAP-02: No Multi-Device / LAN Sync

**Current:** Every device is a complete island. Two tablets on the same WiFi cannot see each other's orders, tables, or kitchen tickets.

**Required for pilot (minimum):**
- Primary device model: one device owns the SQLite DB
- Secondary devices: read/write via HTTP API to primary device over LAN
- Discovery: mDNS or simple IP configuration
- POS → KDS ticket delivery: same network, primary pushes to KDS

**Full LAN sync (Phase 2):**
- Outbox/inbox tables already exist (`sync_queue`, `sync_metadata`)
- Implement bidirectional sync over LAN HTTP
- Conflict resolution: last-writer-wins on master data, append-only on transactions

**Effort:** 2–3 weeks.

---

### GAP-03: No License / Feature Flag Enforcement

**Current:** License module is all TODO stubs in Go. No `FlagGate` or tier checks anywhere in Dart code. The app runs all features unconditionally.

**Minimum for pilot (offline-capable license):**
- Hardcoded "pilot license" — no server needed
- OR: simple JSON license file in app assets
- Feature flags read from license at startup

**Minimum for commercial launch:**
- Go license service: validate key → return feature flags JSON
- Dart: check flags before rendering locked features
- Grace mode: 7-day offline window before features are gated

**Effort:** 3–5 days (pilot mode). 1–2 weeks (production license service).

---

### GAP-04: No Production Build Pipeline

**Current:** `gastrocore-release.jks` is referenced in `android/app/build.gradle.kts` via `key.properties` but the actual keystore file is unverified. No CI/CD exists. No AAB build verified.

**Required:**
- Verify or create release keystore and `key.properties`
- Test `flutter build appbundle --release` produces valid AAB
- Verify app ID, version code, target SDK
- Minimum: documented manual release checklist

**Effort:** 1–2 days.

---

## 3. P1 — PILOT-REQUIRED

### GAP-05: Swiss VAT Dine-In vs Takeaway Toggle

**Current:** Tax profiles exist in DB. Swiss MWST rates (2.6%, 3.8%, 8.1%) exist in seed data and `SwissReceiptBuilder`. But the **per-order toggle** (dine-in = 8.1% for beverages, takeaway = 2.6%) is not surfaced in the POS order flow.

**Required:**
- Order-level or item-level dine-in/takeaway toggle in POS screen
- Tax rate resolver reads toggle → applies correct rate
- Receipt shows correct MWST breakdown per rate
- `FareEngine` already exists and handles rate resolution — wire the toggle to it

**Effort:** 2–3 days.

---

### GAP-06: 5-Rappen Rounding Not Enforced at Payment

**Current:** `SwissReceiptBuilder` formats 5-Rappen rounded amounts, but rounding logic at the payment screen (cash vs card differentiation) is not verified end-to-end.

**Required:**
- Cash payment: total rounded to nearest CHF 0.05
- Card payment: exact amount (no rounding)
- Rounding difference tracked in `payments` table as rounding line
- Unit tests already exist in `swiss_receipt_builder_test.dart` — verify they cover payment flow too

**Effort:** 1 day.

---

### GAP-07: Manager Override / Void Authorization

**Current:** Void is implemented (creates new record). But no manager PIN confirmation is enforced for voids above a threshold.

**Required:**
- Void/discount above threshold: require manager PIN
- Role-based: `cashier` cannot void; `manager` can
- Threshold configurable in settings (default: CHF 20 or any void)
- Audit log records void with authorizing manager ID

**Effort:** 1–2 days.

---

### GAP-08: Day Close / End-of-Day Report

**Current:** Z-report prints on shift close. But "day close" as a formal workflow (all shifts closed, daily summary, backup signal) is not explicit.

**Required:**
- Day close procedure: verify all shifts closed, print daily summary
- Export daily report as PDF or CSV (local file)
- Timestamp daily close in audit log
- "Audit trail complete" indicator

**Effort:** 2–3 days.

---

### GAP-09: Local Backup / Restore

**Current:** SQLite file exists in app documents directory. No backup export flow.

**Required for pilot:**
- Manual "Export backup" in settings → saves SQLite snapshot to device Downloads
- "Restore from backup" with manager PIN confirmation
- Auto-backup trigger on shift close (save to device storage)

**Effort:** 1–2 days.

---

### GAP-10: Offline Behavior Documentation and Testing

**Current:** Architecture is offline-first but no offline scenario tests exist (connection loss mid-payment, airplane mode, reconnect).

**Required:**
- Integration test: complete full order flow in airplane mode
- Test: payment terminal reconnects after Bluetooth drop
- Test: KDS receives ticket without cloud (LAN only)

**Effort:** 2–3 days testing.

---

## 4. P2 — MARKET-REQUIRED

### GAP-11: Cloud Sync Engine

**Current:** `sync_queue` and `sync_metadata` tables exist. Go sync handlers are complete stubs. No sync logic anywhere.

**Required:**
- Flutter outbox: write changes to `sync_queue` on every mutation
- Go sync service: upload endpoint consumes batch, resolves conflicts, stores in PostgreSQL
- Go sync service: download endpoint returns delta since cursor
- Flutter inbox: apply downloaded changes to local SQLite
- Cursor-based pagination for large initial sync (seed)
- Conflict resolution: last-writer-wins for master data, append-only for transactions

**Effort:** 4–6 weeks.

---

### GAP-12: Cloud Dashboard (Owner-Facing)

**Current:** Not started.

**Required (minimal):**
- Web app (or Flutter web)
- Login with email+password
- Sales reports: daily/weekly/monthly
- Device status: last sync, online/offline
- Menu management: push changes to devices

**Effort:** 4–6 weeks (minimal), 8+ weeks (full-featured).

---

### GAP-13: Go Backend — Real Implementation

**Current:** All handlers are TODO stubs returning hardcoded empty responses.

**Required per module:**
- Auth: JWT generation, refresh, device token
- Sync: full upload/download/seed/status implementation
- Licenses: key validation, feature flags, grace period
- Stores: tenant/branch CRUD
- Devices: registration, heartbeat, status
- Reports: aggregate queries from synced data
- Menu: receive and serve menu from cloud

**Effort:** 6–8 weeks total for all modules.

---

### GAP-14: CI/CD Pipeline

**Current:** None.

**Required:**
- GitHub Actions (or similar): lint → test → build APK/AAB on PR merge
- Auto-increment version code on release branch
- Test on Android emulator (or Firebase Test Lab)
- Go: go vet, go test, docker build on server changes

**Effort:** 3–5 days.

---

### GAP-15: Germany Fiscal Pack (Fiskaly SIGN DE v2)

**Current:** Stub fiscal module in Go. No implementation.

**Required (see doc 30 for full spec):**
- TSE client initialization and lifecycle
- Transaction start → update → finish with Fiskaly API
- DSFinV-K export
- Receipt with TSE QR code and required fields
- Offline queue for fiscal signing

**Effort:** 6–8 weeks. **Dependency:** Cloud sync must be stable first.

---

### GAP-16: Swiss QR-Bill Generation

**Current:** Not implemented.

**Required:**
- Swiss QR-bill format (ISO 20022) for B2B invoices
- QR code with payment reference, IBAN, amount
- Print on A4 or append to receipt
- Scope: on-demand invoice printing, not automated

**Effort:** 1–2 weeks (use established Swiss QR-bill library).

---

### GAP-17: Localization Completeness

**Current:** de/fr ARB files exist but coverage is partial.

**Required:**
- Audit all user-facing strings
- Complete German and French translations
- Swiss German consideration (primarily Hochdeutsch)

**Effort:** 1 week.

---

## 5. P3 — GROWTH (Post-Swiss-Pilot)

| Gap | Description | Effort |
|-----|-------------|--------|
| GAP-18: Online ordering | Web ordering channel | 8–10 weeks |
| GAP-19: QR table ordering | Customer self-order via QR | 4–6 weeks |
| GAP-20: Kiosk mode | Self-service tablet | 6–8 weeks |
| GAP-21: Multi-branch management | Central menu, cross-branch reports | 6–8 weeks |
| GAP-22: Retail mode | Barcode scanning, weight items | 8–12 weeks |
| GAP-23: Custom backoffice | Team's own accounting infrastructure | TBD by team |
| GAP-24: Waiter handheld app | Separate compact UI for phone | 4–6 weeks |
| GAP-25: Customer display | Facing-customer order confirmation | 2–3 weeks |

---

## 6. Gap Priority Matrix

```
                    Effort (Low → High)
Impact     Low           Medium          High
(High)  GAP-04(build) GAP-01(KDS)    GAP-02(LAN sync)
        GAP-06(round) GAP-05(VAT)    GAP-11(cloud sync)
        GAP-09(backup)GAP-07(void)   GAP-13(Go backend)
                      GAP-03(license)GAP-15(fiscal DE)
(Med)                 GAP-08(dayclose)GAP-12(dashboard)
                      GAP-10(offline) GAP-14(CI/CD)
(Low)                 GAP-17(i18n)   GAP-16(QR-bill)
```

---

## 7. Critical Path to Pilot

Minimum viable for a **first paying Swiss pilot restaurant**:

```
GAP-04 (build) →  GAP-01 (KDS wired) → GAP-02 (LAN sync, basic)
                                                     ↓
GAP-05 (VAT toggle) → GAP-06 (rounding) → GAP-07 (manager override)
                                                     ↓
GAP-03 (license, pilot mode) → GAP-08 (day close) → GAP-09 (backup)
                                                     ↓
                              PILOT-READY ✅
```

Estimated: **10–14 weeks** from today with 1–2 focused developers.
