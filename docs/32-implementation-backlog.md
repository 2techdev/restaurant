# 32 - Implementation Backlog

> **Document Status:** Living | **Last Updated:** 2026-03-20
>
> Ordered by delivery phase. Each epic contains concrete tasks.
> Update status as items are completed.

---

## Epic 0: Build Infrastructure (P0 — Do First)

| ID | Task | Effort | Status |
|----|------|--------|--------|
| B-01 | Verify/create release keystore + key.properties | 2h | TODO |
| B-02 | Test `flutter build appbundle --release` succeeds | 1h | TODO |
| B-03 | Set explicit `targetSdk 35`, `minSdk 26` in build.gradle.kts | 30m | TODO |
| B-04 | Set up version policy: `1.0.0+1000` for first release | 30m | TODO |
| B-05 | Add obfuscation flags to release build | 30m | TODO |
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
| K-08 | Add audible alert on new ticket arrival | 3h | TODO |
| K-09 | Station filter UI (single station default, multi-station prep) | 4h | TODO |
| K-10 | Print fallback: if no KDS registered, auto-print kitchen ticket | 2h | TODO |
| K-11 | Timer thresholds in Settings (green/orange/red minutes, configurable) | 2h | TODO |
| K-12 | Unit tests: KitchenRepository, ticket creation, bump logic | 1d | TODO |

---

## Epic 2: Swiss VAT Compliance (P0 — Pilot Blocker)

| ID | Task | Effort | Status |
|----|------|--------|--------|
| V-01 | Dine-in / Takeaway toggle in POS order screen (top bar) | 4h | TODO |
| V-02 | Wire toggle to order type in ticket entity | 2h | TODO |
| V-03 | FareEngine: resolve tax rate from order type + product category | 3h | TODO |
| V-04 | Verify FareEngine uses `effective_from` date on tax profiles | 2h | TODO |
| V-05 | 5-Rappen rounding at cash payment screen | 3h | TODO |
| V-06 | Rounding delta recorded as `payments` line item (type: 'rounding') | 2h | TODO |
| V-07 | Receipt shows rounding line for cash payments | 1h | TODO |
| V-08 | Add UID and MWST number fields to RestaurantSettings | 2h | TODO |
| V-09 | SwissReceiptBuilder: include UID, MWST number from settings | 1h | TODO |
| V-10 | Unit tests for tax resolution (all dine-in/takeaway scenarios) | 1d | TODO |
| V-11 | Unit tests for 5-Rappen rounding edge cases | 3h | TODO |

---

## Epic 3: Manager Override and Operations (P1)

| ID | Task | Effort | Status |
|----|------|--------|--------|
| M-01 | Manager PIN dialog component | 3h | TODO |
| M-02 | Void: require manager PIN for amounts above configurable threshold | 4h | TODO |
| M-03 | Discount: require manager PIN above configurable percentage | 3h | TODO |
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
| D-04 | Daily CSV export to device Downloads | 4h | TODO |
| D-05 | Local backup: export SQLite snapshot to device Downloads | 3h | TODO |
| D-06 | Auto-backup trigger on shift close | 2h | TODO |
| D-07 | Restore from backup: manager PIN + file picker | 4h | TODO |

---

## Epic 5: License Basics (P1)

| ID | Task | Effort | Status |
|----|------|--------|--------|
| L-01 | License token structure (JWT, Ed25519, feature flags JSON) | 1d | TODO |
| L-02 | Pilot mode: hardcoded "all Professional features" token for pilot | 2h | TODO |
| L-03 | Flutter: parse and validate license JWT at startup | 1d | TODO |
| L-04 | Flutter: LicenseProvider with feature flag accessors | 3h | TODO |
| L-05 | Flutter: `FlagGate` widget (shows upgrade prompt if feature not licensed) | 4h | TODO |
| L-06 | Gate: KDS behind Professional flag | 1h | TODO |
| L-07 | Gate: LAN sync behind Professional flag | 1h | TODO |
| L-08 | Gate: Cloud sync behind Enterprise flag | 1h | TODO |
| L-09 | Grace period: 7-day offline window before gating | 3h | TODO |
| L-10 | Receipt-only mode: < 90 days expired — warn only; > 90 days — gate reports/KDS | 4h | TODO |

---

## Epic 6: LAN Sync (Phase 2)

| ID | Task | Effort | Status |
|----|------|--------|--------|
| S-01 | Embedded HTTP server on primary device (shelf package) | 3d | TODO |
| S-02 | LAN health / info endpoints | 1d | TODO |
| S-03 | LAN order submission endpoint | 2d | TODO |
| S-04 | LAN kitchen ticket SSE stream | 2d | TODO |
| S-05 | LAN table status endpoint | 1d | TODO |
| S-06 | LAN menu sync endpoint | 1d | TODO |
| S-07 | mDNS service broadcast on primary | 2d | TODO |
| S-08 | mDNS device discovery on secondary | 2d | TODO |
| S-09 | Secondary device: connect to primary flow in Settings | 1d | TODO |
| S-10 | Secondary: heartbeat + disconnection detection | 1d | TODO |
| S-11 | Secondary: degraded mode banner | 1d | TODO |
| S-12 | HMAC shared secret auth for LAN connections | 1d | TODO |
| S-13 | Waiter compact UI for phone | 3d | TODO |
| S-14 | Integration test: two-device order + KDS scenario | 2d | TODO |

---

## Epic 7: Cloud Sync — Go Backend (Phase 3)

| ID | Task | Effort | Status |
|----|------|--------|--------|
| G-01 | Auth: JWT generation + device token + refresh | 3d | TODO |
| G-02 | Devices: register, heartbeat, status | 2d | TODO |
| G-03 | Stores: tenant + branch CRUD | 2d | TODO |
| G-04 | Sync: upload handler (batch conflict resolution) | 5d | TODO |
| G-05 | Sync: download handler (cursor-based delta) | 3d | TODO |
| G-06 | Sync: seed handler (full state for new device) | 2d | TODO |
| G-07 | Sync: status handler | 1d | TODO |
| G-08 | Licenses: key validation, feature flags, grace period | 3d | TODO |
| G-09 | Reports: aggregate queries from synced data | 3d | TODO |
| G-10 | Go unit tests for all handlers | 3d | TODO |
| G-11 | PostgreSQL deployment: VPS, SSL, automated backups | 2d | TODO |
| G-12 | CI/CD: GitHub Actions for Go build + test | 1d | TODO |

---

## Epic 8: Cloud Sync — Flutter Client (Phase 3)

| ID | Task | Effort | Status |
|----|------|--------|--------|
| C-01 | Outbox writer: write to sync_queue on every mutation | 3d | TODO |
| C-02 | Sync runner background isolate: drain sync_queue → POST upload | 3d | TODO |
| C-03 | Download runner: poll + apply changes to local DB | 2d | TODO |
| C-04 | Cursor management in sync_metadata | 1d | TODO |
| C-05 | Conflict resolution: apply server version on conflict | 2d | TODO |
| C-06 | Wire pos_sync_indicator to real sync state | 1d | TODO |
| C-07 | Device registration flow: on first cloud connect | 1d | TODO |
| C-08 | Cloud license token fetch + replace local pilot token | 1d | TODO |

---

## Epic 9: Cloud Dashboard (Phase 3)

| ID | Task | Effort | Status |
|----|------|--------|--------|
| W-01 | Owner login (email + password) | 2d | TODO |
| W-02 | Daily/weekly/monthly revenue charts | 3d | TODO |
| W-03 | Top products report | 2d | TODO |
| W-04 | Device status dashboard | 2d | TODO |
| W-05 | Menu management CRUD | 3d | TODO |
| W-06 | Staff management (PINs, roles) | 2d | TODO |
| W-07 | CSV export for accounting | 2d | TODO |

---

## Epic 10: Germany Fiscal (Phase 5)

| ID | Task | Effort | Status |
|----|------|--------|--------|
| F-01 | Fiskaly account + SIGN DE v2 sandbox setup | 1d | TODO |
| F-02 | Fiskaly HTTP client in Go (internal/fiscal) | 3d | TODO |
| F-03 | TSE initialization API call | 1d | TODO |
| F-04 | Start/finish transaction lifecycle | 3d | TODO |
| F-05 | TSE response storage in receipts table | 1d | TODO |
| F-06 | Retry logic + offline queue for fiscal signing | 3d | TODO |
| F-07 | German receipt format with TSE QR code | 2d | TODO |
| F-08 | Flutter: async fiscal signing after payment | 2d | TODO |
| F-09 | Flutter: "Signatur ausstehend" receipt state | 1d | TODO |
| F-10 | DSFinV-K export via Fiskaly SUBMIT DE | 3d | TODO |
| F-11 | Cloud dashboard: fiscal signing status + export button | 2d | TODO |
| F-12 | German VAT rates (19%, 7%) in tax profiles | 1d | TODO |
| F-13 | 1000-transaction compliance test | 2d | TODO |

---

## Epic 11: Swiss QR-Bill (Phase 3)

| ID | Task | Effort | Status |
|----|------|--------|--------|
| Q-01 | Evaluate Swiss QR-bill Dart library | 1d | TODO |
| Q-02 | QR-bill generator: creditor + debtor + amount + reference | 3d | TODO |
| Q-03 | Invoice print template (A4 with QR-bill section) | 2d | TODO |
| Q-04 | "Print Invoice" action from order screen | 1d | TODO |

---

## Epic 12: CI/CD (Phase 2)

| ID | Task | Effort | Status |
|----|------|--------|--------|
| CI-01 | GitHub Actions: Flutter lint + test on PR | 1d | TODO |
| CI-02 | GitHub Actions: release AAB build on main merge | 1d | TODO |
| CI-03 | Go: go vet + go test in CI | 1d | TODO |
| CI-04 | Auto version-code increment in CI | 1d | TODO |
| CI-05 | Keystore stored as GitHub Secret (base64) | 1d | TODO |
| CI-06 | Upload AAB to Play Internal track automatically | 1d | TODO |

---

## Epic 13: Test Coverage Improvements (Ongoing)

| ID | Task | Effort | Status |
|----|------|--------|--------|
| T-01 | Integration test: full order cycle offline | 2d | TODO |
| T-02 | Integration test: payment terminal (mock) | 2d | TODO |
| T-03 | Integration test: Swiss VAT all scenarios | 1d | TODO |
| T-04 | Integration test: shift open/close cycle | 1d | TODO |
| T-05 | Go unit tests: all handler logic | 3d | TODO |
| T-06 | Multi-device sync simulation (automated) | 3d | TODO |
| T-07 | Stress test: 200 orders in sequence | 1d | TODO |

---

## Deferred (Not in Any Current Phase)

| ID | Epic | Description |
|----|------|-------------|
| DEF-01 | Online ordering | Web ordering channel |
| DEF-02 | QR table ordering | Customer self-order |
| DEF-03 | Kiosk mode | Self-service tablet |
| DEF-04 | Retail mode | Barcode scanning |
| DEF-05 | Customer display | Facing-customer screen |
| DEF-06 | Loyalty / points | Customer rewards |
| DEF-07 | Inventory management | Stock tracking |
| DEF-08 | Delivery management | Driver dispatch |
| DEF-09 | Multi-region cloud | Cross-timezone scale |
| DEF-10 | Redis infrastructure | Post-50-tenant need |
| DEF-11 | iOS support | Not in v1 |
| DEF-12 | SIX payment terminal | Swiss acquiring integration |
| DEF-13 | PostFinance integration | Swiss payment |

---

## Backlog Maintenance Notes

- Update `Status` column as items complete: TODO → IN_PROGRESS → DONE
- Add new items with next available ID prefix
- Move completed epics to `CHANGELOG.md` with release version
- Review deferred items quarterly — promote to active backlog only with explicit decision
