# 22 — Gap Analysis

> **Document Status:** Authoritative | **Last Updated:** 2026-03-24
>
> Gaps from current state to Swiss pilot-ready, then to market-ready product.
> Updated to reflect **cloud sync only** (no LAN sync) architecture decision.

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
- On single-device: this works immediately (same SQLite, no sync needed)
- On multi-device: requires cloud sync (see GAP-11)

**Effort:** 3–5 days (single device wiring)

---

### GAP-02: No Production Build Pipeline

**Current:** `gastrocore-release.jks` is referenced in `android/app/build.gradle.kts` via `key.properties` but the actual keystore file is unverified. No CI/CD. No AAB build confirmed.

**Required:**
- Verify or create release keystore and `key.properties`
- Test `flutter build appbundle --release` produces a valid, signed AAB
- Set `targetSdk 35`, `minSdk 26` explicitly in `build.gradle.kts`
- Define version policy: `1.0.0+1000` for first release
- Document manual release checklist

**Effort:** 1–2 days

---

### GAP-03: No License / Feature Flag Enforcement

**Current:** License module (`LicenseValidator`, `FlagGate` widget) is implemented and tested, but **zero feature gate checks exist in actual feature code**. App runs all features unconditionally.

**Minimum for pilot (offline mode):**
- Hardcoded "pilot license" JWT with all Professional features — no server needed
- Feature flags read from license at startup
- `FlagGate` widget placed at KDS, cloud sync, multi-branch entry points

**Minimum for commercial launch:**
- Go license service validates key → returns signed JWT
- Flutter checks flags at startup + 7-day offline grace period
- Upgrade prompt shown on locked features

**Effort:** 3–5 days (pilot mode). 1–2 weeks (production license service).

---

## 3. P1 — PILOT-REQUIRED

### GAP-04: Swiss VAT Dine-In vs Takeaway Toggle

**Current:** Tax profiles and FareEngine exist. Swiss MWST rates (2.6%, 3.8%, 8.1%) are in seed data and `SwissReceiptBuilder`. The **per-order toggle** is not surfaced in the POS order flow.

**Required:**
- Visible dine-in/takeaway toggle in POS order screen (top bar, not buried)
- FareEngine resolves correct tax rate from toggle + product category
- Receipt shows correct MWST breakdown per rate

**Effort:** 2–3 days

---

### GAP-05: 5-Rappen Rounding at Payment Screen

**Current:** `SwissReceiptBuilder` formats rounded amounts. Cash vs card rounding logic at the actual payment screen is not verified end-to-end.

**Required:**
- Cash payment: total rounded to nearest CHF 0.05
- Card/TWINT: exact amount (no rounding)
- Rounding delta tracked as `payments` table line item (`type = 'rounding'`)
- Receipt shows explicit rounding line

**Effort:** 1 day

---

### GAP-06: Settings Save Incomplete

**Current:** Restaurant name, UID number, and MWST number fields in settings don't reliably persist on save.

**Required:**
- Fix save callbacks for all RestaurantSettings fields
- Settings verified persisted across app restarts
- SwissReceiptBuilder reads UID and MWST number from settings

**Effort:** 1 day

---

### GAP-07: Manager Override for Void / Discount

**Current:** Void is implemented (creates new record). No manager PIN enforcement above threshold.

**Required:**
- Void/discount above configurable threshold: require manager PIN
- Role-based: `cashier` cannot void without manager auth
- Audit log records void/discount with authorizing manager ID

**Effort:** 1–2 days

---

### GAP-08: Day Close / End-of-Day Report

**Current:** Z-report prints on shift close. No formal day-close procedure.

**Required:**
- Day close: verify all shifts closed + daily summary print + audit log entry
- Daily CSV export (shift summary, revenue by tax rate, payment methods) to device Downloads

**Effort:** 2–3 days

---

### GAP-09: Local Backup / Restore

**Current:** SQLite backup to Downloads and restore with manager PIN — both complete in `BackupService`. The **trigger UI** (manual export button in settings, auto-backup on shift close) may not be fully wired.

**Required:**
- Verify backup button in Settings exports SQLite snapshot
- Auto-backup on each shift close
- Restore from backup: manager PIN confirmation + file picker

**Effort:** 0.5–1 day (verify and wire triggers)

---

### GAP-10: KDS Audio Alert

**Current:** `audioplayers` package is in `pubspec.yaml`. Integration with KDS new-ticket event not wired.

**Required:**
- Short beep sequence when new kitchen ticket arrives
- Volume respects device media volume
- Setting to disable in Settings

**Effort:** 0.5 day

---

### GAP-11: Discount Dialog UI

**Current:** Discount button is present in the UI. `FareEngine` can calculate discounts. The dialog is not wired.

**Required:**
- Discount dialog: % or CHF amount input
- Manager PIN if above configurable threshold
- FareEngine applies discount; receipt shows discount line

**Effort:** 1 day

---

## 4. P2 — MARKET-REQUIRED

### GAP-12: Cloud Sync Engine (Flutter + Go)

**Current:** `sync_queue` and `sync_metadata` tables exist. Go sync handlers (upload/download/seed) are structural stubs — routing exists but no real logic. Flutter outbox is never written on mutations.

**Required (see doc 27 for full spec):**
- Flutter: write to `sync_queue` on every DB mutation (outbox pattern)
- Go sync service: real upload/download/seed implementation with PostgreSQL
- Flutter: background sync runner — drain outbox, apply downloads
- Conflict resolution: last-writer-wins for master data, append-only for transactions

**This is the multi-device enabler.** KDS on a separate device, waiter phone, cloud dashboard all depend on cloud sync.

**Effort:** 5–8 weeks

---

### GAP-13: Go Backend — Real Implementation

**Current:** auth, sync, menu, stores, devices, licenses, kds modules are MVP-complete. orders lifecycle, reports, and online modules are stubs.

**Required per module:**
- Orders: full lifecycle (state transitions, refunds, line-item updates)
- Reports: aggregate queries from PostgreSQL
- Online: full online ordering flow (see GAP-19)

**Effort:** 4–6 weeks

---

### GAP-14: Cloud Dashboard (Owner-Facing)

**Current:** Not started.

**Required (minimal):**
- Web app with email + password login
- Daily/weekly/monthly revenue charts
- Device status (last sync, online/offline)
- Menu management (CRUD with sync push to devices)

**Effort:** 4–8 weeks

---

### GAP-15: CI/CD Pipeline

**Current:** `.github/workflows/` folder exists but empty.

**Required:**
- GitHub Actions: lint → test → build AAB on PR merge
- Auto-increment versionCode on release branch
- Go: `go vet`, `go test`, Docker build on server changes
- Keystore stored as encrypted GitHub Secret

**Effort:** 3–5 days

---

### GAP-16: Germany Fiscal Pack (Fiskaly SIGN DE v2)

**Current:** Stub `internal/fiscal/` module. No implementation.

**Required (see doc 30 for full spec):**
- TSE client initialization and transaction lifecycle
- DSFinV-K export
- German receipt format with TSE QR code
- Offline signing queue

**Dependency:** Cloud sync must be stable first.

**Effort:** 6–8 weeks

---

### GAP-17: Swiss QR-Bill Generation

**Current:** Not implemented.

**Required:**
- Swiss QR-bill (ISO 20022) for on-demand B2B invoices
- On-demand only: staff triggers "Print Invoice" manually

**Effort:** 1–2 weeks

---

### GAP-18: Localization Completeness

**Current:** German and French ARB files exist, coverage partial.

**Required:**
- Audit all user-facing strings
- Complete German translations (Hochdeutsch)
- French translations complete for French-speaking Switzerland

**Effort:** 1 week

---

## 5. P3 — GROWTH (Post-Swiss-Pilot)

| Gap | Description | Effort |
|-----|-------------|--------|
| GAP-19: Online ordering | Web ordering channel with payment | 8–10 weeks |
| GAP-20: QR table ordering | Customer self-order via QR | 4–6 weeks |
| GAP-21: Multi-branch management | Central menu, cross-branch reports | 6–8 weeks |
| GAP-22: Retail mode | Barcode scanning, weight items | 8–12 weeks |
| GAP-23: Custom backoffice export API | Pull-based CSV/JSON for team's own accounting | 2–3 weeks |
| GAP-24: Waiter app improvements | Deeper waiter-specific UX, standalone APK | 3–4 weeks |
| GAP-25: Customer display (ODS) | Live order status on customer-facing screen | 2–3 weeks |

---

## 6. Gap Priority Matrix

```
                    Effort (Low → High)
Impact     Low             Medium            High
(High)  GAP-02(build)   GAP-01(KDS)      GAP-12(cloud sync)
        GAP-05(round)   GAP-04(VAT)      GAP-13(Go backend)
        GAP-06(settings)GAP-07(void)     GAP-16(fiscal DE)
        GAP-09(backup)  GAP-03(license)
(Med)   GAP-10(audio)   GAP-08(dayclose) GAP-14(dashboard)
        GAP-11(discount)GAP-18(i18n)     GAP-15(CI/CD)
(Low)                   GAP-17(QR-bill)
```

---

## 7. Critical Path to Pilot (Single Device)

Minimum viable for a **first paying Swiss pilot restaurant on a single device**:

```
GAP-02 (build pipeline)
        ↓
GAP-01 (KDS wired — single device)
        ↓
GAP-04 (VAT toggle) → GAP-05 (rounding) → GAP-06 (settings save)
        ↓
GAP-07 (manager override) → GAP-08 (day close) → GAP-09 (backup)
        ↓
GAP-03 (pilot license mode)
        ↓
        ✅ PILOT-READY (single device)
```

**Estimated: 3–5 focused weeks** with a 1-person AI-assisted development setup.

---

## 8. Critical Path to Multi-Device

After single-device pilot is validated:

```
GAP-12 (cloud sync — Flutter outbox + Go backend)
        ↓
KDS on separate tablet ← cloud WebSocket push
Waiter phone ← table status from cloud
        ↓
        ✅ MULTI-DEVICE (cloud-based)
```

**No LAN sync. All multi-device coordination goes through cloud.**

---

## 9. What Is Explicitly Out of Scope (Do Not Build)

| Item | Reason |
|------|--------|
| ERPNext bridge | Permanently removed — custom backoffice is separate project |
| LAN sync / mDNS discovery | Architecture decision: cloud sync only |
| Redis | Not needed at v1 scale — PostgreSQL outbox is sufficient |
| Microservices | Architecture freeze: Go modular monolith only |
| iOS / web POS | Android tablet only for v1 |
| Customer loyalty / CRM | Not restaurant core in v1 |
| Inventory management | Custom backoffice handles it |
| Delivery platform integration | Post-channel work |
