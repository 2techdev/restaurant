# 23 — Architecture Freeze

> **Document Status:** FROZEN | **Last Updated:** 2026-03-24 | **Owner:** CTO
>
> This document freezes the architecture for v1 (Swiss pilot through Germany launch).
> No architectural changes may be made without updating this document and adding an ADR.
> **Updated 2026-03-24:** FRZ-11 changed from "LAN sync first" to "Cloud sync only."

---

## 1. What "Frozen" Means

Architecture freeze means:
- The decisions below are **not open for debate** during v1 development
- New requirements must fit within these constraints or require explicit ADR override
- Implementing team can make local decisions (file names, widget structure, query patterns) but cannot change the listed frozen decisions

---

## 2. Frozen Decisions

### FRZ-01: Three-Layer Architecture (Branch Runtime + Cloud Hub + Custom Backoffice)

```
Layer 1 — Branch Runtime:    Flutter POS + SQLite (per device, offline-first)
Layer 2 — Cloud Hub:         Go modular monolith + PostgreSQL
Layer 3 — Custom Backoffice: Team's own infrastructure (separate project, not coupled to GastroCore)
```

**What changed from original docs:**
- Layer 3 is **NOT ERPNext**. It is the team's own accounting/backoffice infrastructure.
- The Go Cloud Hub exposes a pull-based export API (CSV/JSON). The custom backoffice consumes it on its own schedule.
- There is no bridge service between Layer 2 and Layer 3 in v1.

---

### FRZ-02: ERPNext Is Removed Permanently

**Decision:** ERPNext is removed from GastroCore at all layers.

**Consequences:**
- `internal/erpnext_bridge/module.go`: keep as dead code until cleanup sprint
- All doc references to ERPNext: replaced with "custom backoffice"
- Export API (CSV/JSON): owned by Cloud Hub — generic enough for any consumer

**ADR:** ADR-016 (to be written)

---

### FRZ-03: Redis Is Not Needed for v1

**Decision:** Redis removed from v1 critical path.

**Evidence:** Redis is in `docker-compose.yml` but has zero usage in `go.mod`. No Redis client is imported anywhere.

**Rationale:**
- Sync queue runs on PostgreSQL outbox (`sync_queue` table)
- KDS real-time: WebSocket directly from Go — no broker at v1 scale
- Reports cache: PostgreSQL is sufficient at < 100 tenants

**When to add Redis:** Concurrent sync load from 50+ tenants degrades PostgreSQL, OR cross-server WebSocket routing is needed.

**Action:** Remove Redis from production docker-compose config. Keep in local dev only.

---

### FRZ-04: Offline-First Branch Runtime Is Non-Negotiable

Every feature must work fully offline on the branch runtime (single device). Cloud connectivity is optional and additive.

**Rule:** If a feature requires cloud to function, it is a cloud-only feature (dashboard, reporting) and must not block a transaction because cloud is unreachable.

**Multi-device clarification:** Multi-device operation requires cloud connectivity. When cloud is unavailable, each device operates independently in single-device mode (no real-time coordination between devices). This is acceptable — the primary use case is single-device operation; multi-device is a Professional/Enterprise tier enhancement.

---

### FRZ-05: Flutter POS as Android Tablet Application

- Target platform: Android tablets (10"–15")
- Single Flutter app binary contains POS mode, KDS mode, waiter mode, kiosk mode — all via different entry point `main_*.dart` files
- KDS and other modes are **not separate APKs in v1** (separate APKs are Phase 2)
- Web and iOS are not targeted in v1

---

### FRZ-06: Go Modular Monolith — No Microservices

The Go cloud backend is one deployable binary. Modules are internal Go packages, not separate services.

**Allowed to split only if:**
- Fiscal signing volume requires separate scaling (Germany at 500k+ transactions/day)
- A team member owns a completely different service with no shared codebase

**Never:** Splitting for "clean boundaries" without scaling evidence. No auth-service, sync-service, etc.

---

### FRZ-07: SQLite via Drift ORM — No Change

Local database is SQLite via Drift. Schema version 2. Migrations use Drift's `MigrationStrategy`. No migration to Realm, ObjectBox, Hive, or any other local DB in v1.

---

### FRZ-08: UUID v7 for All Entity IDs

All entities use time-ordered UUID v7. No auto-increment integers, no UUID v4. This enables merge-safe distributed inserts.

---

### FRZ-09: Money as Integer Cents — No Floats

All monetary values are stored and computed as integer cents (CHF 1.05 = 105). The `Money` class in `core/utils/money.dart` is the only entry point for money arithmetic.

---

### FRZ-10: Immutable Transaction Log

Completed orders, payments, and receipts are never modified or deleted. Void and refund create new records that reference the original. The `audit_log` table captures all state changes.

This is non-negotiable for fiscal compliance and fraud prevention.

---

### FRZ-11: Cloud Sync Only — No LAN Sync ⚠️ CHANGED 2026-03-24

**Decision:** Multi-device coordination uses **cloud sync only**. LAN sync (mDNS discovery, embedded HTTP server, primary/secondary model) is **not built**.

**Rationale:**
- 1–5 person AI-assisted dev team: LAN sync adds significant complexity (mDNS, embedded server, primary/secondary failover, LAN-specific auth) for a feature that requires cloud anyway for backup and remote reporting
- Cloud sync covers all multi-device use cases (KDS tablet, waiter phone, second POS) via WebSocket push from Go backend
- Modern Swiss restaurants have reliable internet; 4G router backup is standard
- Simpler architecture = faster delivery = earlier pilot revenue

**Architecture for multi-device:**
1. **Single device (current):** POS + KDS in same app — fully offline
2. **Multi-device (Phase 2):** Each device connects to Go Cloud Hub over HTTPS
   - POS writes to local SQLite + outbox → cloud sync uploads
   - KDS subscribes to cloud WebSocket for `kitchen_ticket` events
   - Waiter phone connects to cloud for table status + order submission
3. **Offline degradation on multi-device:** Each device operates independently; shows "Cloud Disconnected" banner; falls back to print-only kitchen tickets

**What this eliminates from previous plans:**
- mDNS service discovery
- Embedded HTTP server in Flutter
- Primary/secondary device model
- LAN HMAC shared secret
- `shelf` package for local HTTP
- `_gastrocore._tcp.local` mDNS service

**ADR:** ADR-017 (to be written: Cloud Sync Only — LAN Sync Removed)

---

### FRZ-12: Switzerland First, Germany Second

Swiss pilot is the first market. Germany fiscal pack (Fiskaly/TSE/DSFinV-K) begins only after the Swiss pilot is stable and generating revenue (minimum 30 days, 5+ customers).

---

### FRZ-13: Country Packs as Pluggable Modules

Tax profiles, receipt formats, and fiscal compliance are country-specific modules that bolt onto the core without modifying core order/payment logic.

**Existing mechanism:** `tax_profiles` table, `TaxSettings`, `SwissReceiptBuilder`, `OrderTypeRules` — this pattern is established and must be followed for Germany and future markets.

---

### FRZ-14: Single Order Engine — No Separate Channel Engines

Online ordering, QR table ordering, and kiosk all inject into the same `tickets` table via the same order engine. There is no separate "online order service." Channel adapters create tickets; the kitchen sees tickets regardless of origin.

---

### FRZ-15: Feature Flags via License Token (Ed25519)

Feature gating uses JWT tokens signed with Ed25519. Tokens are validated locally (no cloud call required for offline operation). Grace period: 7 days offline before features are gated.

**Tiers:**
- **Starter:** Offline POS, cash + 1 terminal, 1 device, receipts, shifts
- **Professional:** + KDS, cloud sync, multi-device (5 devices), reports, country packs
- **Enterprise:** + Multi-branch, API access, custom backoffice export, unlimited devices

**Note:** `lan_sync` feature flag removed from token structure. Replace with `multi_device` (cloud-dependent).

---

### FRZ-16: myPOS as Primary Payment Terminal

**Decision:** myPOS WiFi is the primary payment terminal for Swiss pilot. Wallee LTI is the secondary option.

**Rationale:**
- myPOS SlaveSDK AAR is already bundled (`slavesdk2.1.8.aar`)
- TWINT (Switzerland's dominant mobile payment) is natively supported by myPOS
- Both bridges are implemented and tested

---

## 3. Architecture Diagram (v1 Frozen)

```
┌─────────────────────────────────────────────────────────────────┐
│                    Branch Runtime (Layer 1)                       │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐    │
│  │  POS Tablet (Android)                                     │    │
│  │  Flutter App: POS mode + KDS mode + Waiter mode           │    │
│  │  SQLite via Drift (offline-first, 29 tables)              │    │
│  │  myPOS WiFi terminal  │  Wallee LTI terminal              │    │
│  │  Thermal printers (Bluetooth / WiFi / USB)                │    │
│  └──────────────────────────────┬────────────────────────────┘   │
│                                 │ HTTPS (cloud sync, optional)   │
└─────────────────────────────────┼──────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Cloud Hub (Layer 2)                            │
│                                                                   │
│  Go Modular Monolith (pos.2tech.ch VPS)      PostgreSQL 16        │
│  ┌──────┐ ┌──────┐ ┌───────┐               ┌──────────────────┐  │
│  │ Auth │ │ Sync │ │Reports│               │  Tenant data      │  │
│  └──────┘ └──────┘ └───────┘               │  Transactions     │  │
│  ┌──────┐ ┌──────┐ ┌───────┐               │  License records  │  │
│  │ Menu │ │Lic.  │ │Fiscal │               └──────────────────┘  │
│  └──────┘ └──────┘ └───────┘                                     │
│                                                                   │
│  WebSocket hub: KDS live push (kitchen tickets)                  │
│  Export API: /api/v1/export/* (CSV/JSON pull)                    │
└──────────────────────────────┬──────────────────────────────────┘
                               │ Pull-based export (Phase 3+)
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                Custom Backoffice (Layer 3)                        │
│                                                                   │
│  Team's own infrastructure — separate project                     │
│  Consumes export API from Cloud Hub on own schedule               │
│  Not coupled to GastroCore release cycle                          │
└─────────────────────────────────────────────────────────────────┘
```

---

## 4. Multi-Device Flow (Cloud-Based, Phase 2)

```
POS Tablet                Cloud Hub              KDS Tablet
    │                         │                      │
    │─── submit order ───────►│                      │
    │    (outbox + HTTPS)      │                      │
    │                         │── WebSocket push ───►│
    │                         │   {new_kitchen_ticket}│
    │                         │                      │── show ticket
    │                         │                      │
    │                         │◄── bump ticket ──────│
    │                         │    (HTTPS)           │
    │◄── sync download ───────│                      │
    │    (table status, etc.)  │                      │
```

---

## 5. Decisions Still Open (Not Frozen)

| Decision | Guidance |
|----------|----------|
| HTTP framework in Go | Use stdlib `net/http` or chi. No heavy frameworks. |
| WebSocket vs SSE for KDS cloud push | Start with WebSocket (better for real-time push at scale). Go WebSocket hub exists. |
| Flutter state for sync status | Riverpod StreamProvider watching `sync_queue` table |
| Local backup storage path | Android Downloads directory |
| Web dashboard framework | Any React/Vue/Flutter Web — team preference |
| Cloud dashboard hosting | Same VPS as Go server (nginx reverse proxy) |

---

## 6. ADRs Required from This Freeze Update

| ADR | Title | Status |
|-----|-------|--------|
| ADR-016 | ERPNext Removed; Custom Backoffice via Export API | To be written |
| ADR-017 | LAN Sync Removed; Cloud Sync Only for Multi-Device | To be written |
| ADR-018 | Redis Removed from v1; PostgreSQL Outbox Only | To be written |
| ADR-019 | KDS as Mode Within POS App, Not Separate Binary in v1 | To be written |
| ADR-020 | myPOS as Primary Payment Terminal; Wallee as Secondary | To be written |

---

## 7. Freeze Review Policy

This document is reviewed:
- **Before each phase gate** — verify frozen decisions still hold
- **When a new requirement seems to require architecture change**
- **Once per 90-day plan cycle**

To change a frozen decision: write an ADR, get CTO sign-off, update this document.
