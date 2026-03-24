# 32 — Implementation Backlog

> **Document Status:** Living | **Last Updated:** 2026-03-24
>
> Ordered by delivery phase. Each epic contains concrete tasks with effort estimates.
> Update `Status` column as items are completed.
>
> **Updated 2026-03-24:** Epic 6 changed from "LAN Sync" to "Cloud Multi-Device."
> LAN sync removed from architecture. See doc 23 FRZ-11.

---

## Epic 0: Build Infrastructure (P0 — Do First)

| ID | Task | Effort | Status |
|----|------|--------|--------|
| B-01 | Verify/create release keystore + `key.properties` | 2h | TODO |
| B-02 | Test `flutter build appbundle --release` produces signed AAB | 1h | TODO |
| B-03 | Set explicit `targetSdk 35`, `minSdk 26` in `build.gradle.kts` | 30m | TODO |
| B-04 | Set version `1.0.0+1000` in `pubspec.yaml` + `build.gradle.kts` | 30m | TODO |
| B-05 | Add `--obfuscate --split-debug-info` flags to release build | 30m | TODO |
| B-06 | Document manual release procedure | 2h | TODO |

---

## Epic 1: KDS Wiring (P0 — Pilot Blocker)

| ID | Task | Effort | Status |
|----|------|--------|--------|
| K-01 | Create `KitchenRepositoryImpl` with `watchActiveTickets()` stream | 1d | TODO |
| K-02 | Create `KitchenTicketWithItems` aggregate entity | 2h | TODO |
| K-03 | Add `activeKitchenTicketsProvider` Riverpod StreamProvider | 2h | TODO |
| K-04 | Wire KDS screen to real provider (remove `_buildDemoTickets()`) | 3h | TODO |
| K-05 | Implement `createTicketFromOrder()` in order submit flow | 1d | TODO |
| K-06 | Wire bump button to `completeTicket()` DB write | 2h | TODO |
| K-07 | Wire stats bar to real counts (pending from stream, completed from query) | 3h | TODO |
| K-08 | Audible alert on new ticket arrival (`audioplayers` already in pubspec) | 3h | TODO |
| K-09 | Station filter UI (single station default; multi-station schema ready) | 4h | TODO |
| K-10 | Print fallback: if no KDS active, auto-print kitchen ticket | 2h | TODO |
| K-11 | Timer thresholds configurable in Settings (green/orange/red minutes) | 2h | TODO |
| K-12 | Unit tests: KitchenRepository, ticket creation, bump logic | 1d | TODO |

---

## Epic 2: Swiss VAT Compliance (P0 — Pilot Blocker)

| ID | Task | Effort | Status |
|----|------|--------|--------|
| V-01 | Dine-in / Takeaway toggle in POS order screen (top bar) | 4h | TODO |
| V-02 | Wire toggle to `OrderType` in ticket entity | 2h | TODO |
| V-03 | FareEngine: resolve tax rate from order type + product category | 3h | TODO |
| V-04 | Verify FareEngine uses `effective_from` date on tax profiles | 2h | TODO |
| V-05 | 5-Rappen rounding at cash payment screen | 3h | TODO |
| V-06 | Rounding delta recorded as `payments` line item (`type: 'rounding'`) | 2h | TODO |
| V-07 | Receipt shows rounding line for cash payments | 1h | TODO |
| V-08 | Add UID and MWST number fields to RestaurantSettings (save working) | 2h | TODO |
| V-09 | `SwissReceiptBuilder`: include UID, MWST number from settings | 1h | TODO |
| V-10 | Unit tests: all dine-in/takeaway VAT scenarios | 1d | TODO |
| V-11 | Unit tests: 5-Rappen rounding edge cases | 3h | TODO |

---

## Epic 3: Manager Override and Operations (P1)

| ID | Task | Effort | Status |
|----|------|--------|--------|
| M-01 | Manager PIN dialog component (if not already fully wired) | 3h | TODO |
| M-02 | Void: require manager PIN for amounts above configurable threshold | 4h | TODO |
| M-03 | Discount dialog: wired to FareEngine; manager PIN above threshold | 4h | TODO |
| M-04 | Role-based access: cashier cannot void/discount without manager auth | 2h | TODO |
| M-05 | Audit log: record void/discount with authorizing manager ID | 2h | TODO |
| M-06 | Void rate report per staff member per shift | 3h | TODO |
| M-07 | Reprint receipt by receipt number | 3h | TODO |

---

## Epic 4: Day Close and Backup (P1)

| ID | Task | Effort | Status |
|----|------|--------|--------|
| D-01 | Day close workflow screen (verify all shifts closed) | 4h | TODO |
| D-02 | Daily summary print: totals, taxes, payment methods, voids | 4h | TODO |
| D-03 | Day close entry in audit log | 1h | TODO |
| D-04 | Daily CSV export to device Downloads (Swiss accounting format) | 4h | TODO |
| D-05 | Verify local backup export button in Settings | 2h | TODO |
| D-06 | Auto-backup trigger on shift close | 2h | TODO |
| D-07 | Restore from backup: manager PIN + file picker | 4h | TODO |

---

## Epic 5: License Basics (P1)

| ID | Task | Effort | Status |
|----|------|--------|--------|
| L-01 | License token structure (JWT, Ed25519, feature flags JSON) | 1d | TODO |
| L-02 | Pilot mode: hardcoded "all Professional features" token | 2h | TODO |
| L-03 | Flutter: parse and validate license JWT at startup | 1d | TODO |
| L-04 | Flutter: `LicenseProvider` with feature flag accessors | 3h | TODO |
| L-05 | Flutter: `FlagGate` widget (shows upgrade prompt if not licensed) | 4h | TODO |
| L-06 | Gate: KDS behind Professional flag | 1h | TODO |
| L-07 | Gate: multi-device/cloud sync behind Professional flag | 1h | TODO |
| L-08 | Gate: multi-branch behind Enterprise flag | 1h | TODO |
| L-09 | Grace period: 7-day offline window before gating | 3h | TODO |
| L-10 | Receipt-only mode: > 90 days expired → gate reports/KDS | 4h | TODO |

---

## Epic 6: Cloud Multi-Device (Phase 2) ⚠️ UPDATED — No LAN Sync

*Previous Epic 6 was "LAN Sync." Removed per architecture freeze (doc 23 FRZ-11).
Multi-device now runs entirely over cloud.*

| ID | Task | Effort | Status |
|----|------|--------|--------|
| CM-01 | Outbox writer: `sync_queue` INSERT in every Drift mutation transaction | 3d | TODO |
| CM-02 | `SyncRunner` background task: drain outbox → POST `/api/v1/sync/upload` | 2d | TODO |
| CM-03 | `DownloadRunner`: poll `/api/v1/sync/download?cursor=` every 30s | 2d | TODO |
| CM-04 | Idempotent upsert: apply downloaded changes to local SQLite | 2d | TODO |
| CM-05 | Cursor management in `sync_metadata` | 1d | TODO |
| CM-06 | Exponential backoff retry (30s → 4h, max 10 retries) | 1d | TODO |
| CM-07 | Wire `pos_sync_indicator.dart` to real sync state | 1d | TODO |
| CM-08 | Device registration flow: POST `/api/v1/devices/register` on first cloud connect | 1d | TODO |
| CM-09 | KDS WebSocket client: subscribe to cloud WS for kitchen ticket events | 2d | TODO |
| CM-10 | KDS bump via cloud: POST to sync upload; POS receives via download | 1d | TODO |
| CM-11 | Waiter phone: table status from cloud + order submission | 2d | TODO |
| CM-12 | "Cloud Disconnected" banner on all non-primary screens | 1d | TODO |
| CM-13 | Print fallback: auto-print kitchen ticket when cloud unreachable | 1d | TODO |
| CM-14 | Integration test: two-device order → KDS scenario via cloud | 2d | TODO |

---

## Epic 7: Cloud Backend — Go (Phase 2)

| ID | Task | Effort | Status |
|----|------|--------|--------|
| G-01 | Auth: JWT generation + device token + refresh | 3d | TODO |
| G-02 | Devices: register, heartbeat, status | 2d | TODO |
| G-03 | Stores: tenant + branch CRUD | 2d | TODO |
| G-04 | Sync: upload handler (batch, conflict resolution, per-entity) | 5d | TODO |
| G-05 | Sync: download handler (cursor-based delta, entity_type filter) | 3d | TODO |
| G-06 | Sync: seed handler (full state for new device) | 2d | TODO |
| G-07 | KDS WebSocket hub: broadcast kitchen_ticket events to subscribed clients | 2d | TODO |
| G-08 | Licenses: key validation, feature flags, grace period | 3d | TODO |
| G-09 | Reports: aggregate queries (revenue, shifts, top products) | 3d | TODO |
| G-10 | Go unit tests for all handlers | 3d | TODO |
| G-11 | PostgreSQL: VPS deployment, SSL, automated daily backups | 2d | TODO |
| G-12 | Health check endpoint: `GET /health` for monitoring | 1h | TODO |

---

## Epic 8: Cloud Dashboard (Phase 3)

| ID | Task | Effort | Status |
|----|------|--------|--------|
| W-01 | Owner login (email + password) | 2d | TODO |
| W-02 | Daily/weekly/monthly revenue charts | 3d | TODO |
| W-03 | Top products report | 2d | TODO |
| W-04 | Device status dashboard (last sync, online/offline) | 2d | TODO |
| W-05 | Menu management CRUD with sync push to devices | 3d | TODO |
| W-06 | Staff management (PINs, roles) | 2d | TODO |
| W-07 | CSV export for accounting (daily + period) | 2d | TODO |
| W-08 | License management: activate, renew, view tier | 2d | TODO |

---

## Epic 9: Swiss Pilot Hardening (Phase 3)

| ID | Task | Effort | Status |
|----|------|--------|--------|
| CH-01 | Swiss QR-bill generator (on-demand B2B invoices) | 1w | TODO |
| CH-02 | Invoice print template (A4 with QR-bill section) | 2d | TODO |
| CH-03 | Tax rate effective dates admin UI | 2d | TODO |
| CH-04 | UID format validation in Settings | 1d | TODO |
| CH-05 | Allergen flags on products → shown on kitchen ticket | 2d | TODO |
| CH-06 | Cash drawer open on cash payment confirmation | 1d | TODO |
| CH-07 | Reprint receipt by order number | 1d | TODO |
| CH-08 | First-run onboarding wizard | 2d | TODO |

---

## Epic 10: Germany Fiscal (Phase 5)

| ID | Task | Effort | Status |
|----|------|--------|--------|
| F-01 | Fiskaly account + SIGN DE v2 sandbox setup | 1d | TODO |
| F-02 | Fiskaly HTTP client in Go (`internal/fiscal/`) | 3d | TODO |
| F-03 | TSE initialization + transaction lifecycle | 3d | TODO |
| F-04 | TSE response storage in `receipts` table | 1d | TODO |
| F-05 | Retry logic + offline queue for fiscal signing | 3d | TODO |
| F-06 | German receipt builder with TSE QR code | 2d | TODO |
| F-07 | Flutter: async fiscal signing after payment | 2d | TODO |
| F-08 | Flutter: "Signatur ausstehend" receipt state | 1d | TODO |
| F-09 | DSFinV-K export via Fiskaly SUBMIT DE | 3d | TODO |
| F-10 | Dashboard: fiscal status + export button | 2d | TODO |
| F-11 | German VAT rates (19%, 7%) in tax profiles | 1d | TODO |
| F-12 | 1000-transaction compliance test | 2d | TODO |

---

## Epic 11: CI/CD (Phase 2)

| ID | Task | Effort | Status |
|----|------|--------|--------|
| CI-01 | GitHub Actions: Flutter lint + test on PR | 1d | TODO |
| CI-02 | GitHub Actions: release AAB build on main merge | 1d | TODO |
| CI-03 | Go: `go vet` + `go test` in CI | 1d | TODO |
| CI-04 | Auto versionCode increment in CI | 1d | TODO |
| CI-05 | Keystore as GitHub Secret (base64-encoded) | 1d | TODO |
| CI-06 | Upload AAB to Play internal track automatically | 1d | TODO |

---

## Epic 12: Test Coverage (Ongoing)

| ID | Task | Effort | Status |
|----|------|--------|--------|
| T-01 | Integration test: full order cycle offline | 2d | TODO |
| T-02 | Integration test: Swiss VAT all scenarios end-to-end | 1d | TODO |
| T-03 | Integration test: shift open/close/Z-report cycle | 1d | TODO |
| T-04 | Integration test: backup/restore cycle | 1d | TODO |
| T-05 | Go unit tests: auth, sync, licenses handlers | 3d | TODO |
| T-06 | Multi-device sync simulation (2 Flutter instances → cloud) | 3d | TODO |
| T-07 | Stress test: 200 orders in sequence — no crash or data loss | 1d | TODO |

---

## Deferred (Not in Any Current Phase)

| ID | Epic | Description |
|----|------|-------------|
| DEF-01 | Online ordering | Web ordering channel with payment |
| DEF-02 | QR table ordering | Customer self-order via QR |
| DEF-03 | Standalone Kiosk APK | `apps/kiosk/` separate build |
| DEF-04 | Standalone Waiter APK | `apps/waiter/` separate build |
| DEF-05 | Retail mode | Barcode scanning, weight items |
| DEF-06 | Customer display (ODS) | Live order status screen |
| DEF-07 | Loyalty / points | Customer rewards program |
| DEF-08 | Inventory management | Stock tracking (custom backoffice) |
| DEF-09 | Delivery management | Driver dispatch |
| DEF-10 | Multi-region cloud | Cross-timezone scale |
| DEF-11 | Redis infrastructure | Post-50-tenant throughput need |
| DEF-12 | iOS support | Not in v1 |
| DEF-13 | SIX payment terminal | Swiss acquiring integration |
| DEF-14 | PostFinance | Swiss payment method |
| DEF-15 | LAN sync | Removed from architecture — see doc 23 FRZ-11 |

---

## Backlog Maintenance Notes

- Update `Status` as items complete: `TODO` → `IN_PROGRESS` → `DONE`
- Add new items with next available ID prefix
- Move completed epics to `CHANGELOG.md` with release version
- Review deferred items quarterly — promote to active backlog only with explicit decision
- Do not add items without assigning to a phase and estimating effort
