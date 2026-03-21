# 23 - Architecture Freeze

> **Document Status:** FROZEN | **Last Updated:** 2026-03-20 | **Owner:** CTO
>
> This document freezes the architecture for v1 (Swiss pilot through Germany launch).
> No architectural changes may be made without updating this document and adding an ADR.

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
Layer 3 — Custom Backoffice: Team's own infrastructure (separate project)
```

**What changed from original docs:**
- Layer 3 is NO LONGER ERPNext. It is the team's own accounting/backoffice infrastructure.
- The Go cloud hub does NOT bridge to ERPNext. It exposes data export APIs (CSV/JSON) that the custom backoffice consumes on its own schedule.
- There is no bridge service between Layer 2 and Layer 3 in v1. Export = pull.

---

### FRZ-02: ERPNext Is Removed Permanently

**Decision:** ERPNext is removed from GastroCore architecture at all layers.

**Rationale:** The team is building their own infrastructure. ERPNext integration adds complexity (version pinning, API fragility, GPL risk) with zero benefit given this decision.

**Consequences:**
- `internal/erpnext_bridge/module.go` in Go server: keep as dead code until cleanup sprint, do not add functionality
- `FeatureFlags.ERPNextBridge` field in license models: rename to `CustomBackofficeExport` in next refactor
- All documentation references to ERPNext: replaced with "custom backoffice"
- Export API (CSV/JSON): owned by Cloud Hub — sufficiently generic for any consumer

**Recorded in:** This document. ADR to be written as ADR-016.

---

### FRZ-03: Redis Is Not Needed for v1

**Decision:** Redis is removed from the v1 critical path.

**Evidence from code:** Redis is in `docker-compose.yml` but has zero usage in `go.mod`. No Redis client is imported anywhere in the Go server.

**Rationale:**
- Sync queue runs on PostgreSQL (outbox table `sync_queue`)
- Pub/sub for KDS real-time: use SSE (Server-Sent Events) or WebSocket directly from Go — no broker needed at v1 scale
- Cache for reports: PostgreSQL materialized views or application-level cache is sufficient at <100 tenants

**When to add Redis:** When concurrent sync load from 50+ tenants degrades PostgreSQL, OR when cross-server WebSocket routing is needed.

**Action:** Remove Redis from `docker-compose.yml` for production config. Keep in local dev only if useful.

---

### FRZ-04: Offline-First Branch Runtime Is Non-Negotiable

Every feature must work fully offline on the branch runtime. Cloud connectivity is optional and additive. No feature may block a transaction because cloud is unreachable.

**Enforcement rule:** If a feature requires cloud to function, it is a cloud-only feature (dashboard, reporting) and must not be visible in the branch runtime POS flow.

---

### FRZ-05: Flutter POS as Android Tablet Application

- Target platform: Android tablets (10"–15")
- Single Flutter app contains POS mode, KDS mode, and settings
- KDS runs as a screen within the same app (not a separate binary in v1)
- Web and iOS are not targeted in v1

---

### FRZ-06: Go Modular Monolith — No Microservices

The Go cloud backend is one deployable binary. Modules are internal Go packages, not separate services.

**Allowed to split into separate service only if:**
- Fiscal signing volume requires separate scaling (Germany at 500k+ transactions/day)
- OR a team member owns a different service with no shared codebase

**Not allowed:**
- Splitting for "clean boundaries" without scaling evidence
- Separate service per module (auth-service, sync-service, etc.)

---

### FRZ-07: SQLite via Drift ORM — No Change

Local database is SQLite via Drift. Schema version is 2. Migrations use Drift's `MigrationStrategy`.

**Frozen:** No migration to Realm, ObjectBox, Hive, or any other local DB in v1.

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

### FRZ-11: LAN Sync Before Cloud Sync

Multi-device coordination within a branch uses LAN sync first. Cloud sync is for backup, remote reporting, and multi-branch coordination.

**Sequence:**
1. Single device (current state)
2. Primary/secondary LAN model (Phase 2)
3. Cloud sync for off-branch access and backup (Phase 3)

---

### FRZ-12: Switzerland First, Germany Second

Swiss pilot is the first market. Germany fiscal pack (Fiskaly/TSE/DSFinV-K) begins only after the Swiss pilot is stable and generating revenue.

**Rationale:** Germany fiscal adds 6–8 weeks of compliance work. Starting before the core is validated risks building compliance on an unstable foundation.

---

### FRZ-13: Country Packs as Pluggable Modules

Tax profiles, receipt formats, and fiscal compliance are country-specific modules that bolt onto the core without modifying core order/payment logic.

**Existing mechanism:** `tax_profiles` table, `TaxSettings`, `SwissReceiptBuilder`, `OrderTypeRules` — this pattern is established and must be followed.

---

### FRZ-14: Single Order Engine — No Separate Channel Engines

Online ordering, QR table ordering, and kiosk all inject into the same `tickets` table via the same order engine. There is no separate "online order service." Channel adapters create tickets; the kitchen sees tickets regardless of origin.

---

### FRZ-15: Feature Flags via License Token (Ed25519)

Feature gating uses JWT tokens signed with Ed25519. Tokens are validated locally (no cloud call required for offline operation). Grace period: 7 days offline before features are gated.

**Tiers:**
- Starter: offline POS, cash + 1 terminal, 1 device, receipts, shifts
- Professional: + KDS, LAN sync, multi-device (5), reports, country packs
- Enterprise: + cloud sync, multi-branch, API, custom backoffice export

---

## 3. Architecture Diagram (v1 Frozen)

```
┌─────────────────────────────────────────────────────────────────┐
│                    Branch Runtime (Layer 1)                       │
│                                                                   │
│  ┌─────────────────┐    ┌─────────────────┐                      │
│  │  POS Terminal    │    │  Kitchen Display │                     │
│  │  (Flutter)       │    │  (same Flutter   │                     │
│  │                  │◄──►│   app, KDS mode) │                     │
│  │  SQLite (Drift)  │    │                  │                     │
│  └────────┬─────────┘    └──────────────────┘                    │
│           │                                                       │
│           │ LAN (HTTP/SSE, Phase 2)                               │
│           ▼                                                       │
│  ┌─────────────────┐                                              │
│  │  Waiter Device   │                                             │
│  │  (same app, Phase 2)                                           │
│  └─────────────────┘                                              │
└──────────────────────────────┬──────────────────────────────────┘
                               │ Cloud Sync (HTTPS, Phase 3)
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Cloud Hub (Layer 2)                            │
│                                                                   │
│  Go Modular Monolith                 PostgreSQL                   │
│  ┌──────┐ ┌──────┐ ┌───────┐       ┌──────────────────────┐     │
│  │ Auth │ │ Sync │ │Reports│       │  Tenant data         │     │
│  └──────┘ └──────┘ └───────┘       │  Synced transactions │     │
│  ┌──────┐ ┌──────┐ ┌───────┐       │  License records     │     │
│  │ Menu │ │Lic.  │ │Fiscal │       └──────────────────────┘     │
│  └──────┘ └──────┘ └───────┘                                     │
│                                                                   │
│  Export API: /api/v1/export/daily-summary (CSV/JSON)             │
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

## 4. Decisions Still Open (Not Frozen)

These are decided per-implementation, not frozen:

| Decision | Guidance |
|----------|----------|
| HTTP framework in Go | Use stdlib `net/http` or chi. No heavy frameworks. |
| SSE vs WebSocket for KDS LAN push | Start with SSE (simpler). Upgrade to WebSocket if needed. |
| Flutter state for sync status | Use Riverpod StreamProvider watching `sync_queue` table |
| Local backup storage path | Android Downloads directory |
| Web dashboard framework | Any React/Vue/Flutter Web — team preference |
| Printer discovery UI | Settings screen → scan → connect — implementation detail |

---

## 5. ADRs Required from This Freeze

| ADR | Title | Status |
|-----|-------|--------|
| ADR-016 | ERPNext Removed; Custom Backoffice via Export API | To be written |
| ADR-017 | Redis Removed from v1; PostgreSQL Outbox Only | To be written |
| ADR-018 | KDS as Screen Within POS App, Not Separate Binary | To be written |

---

## 6. Freeze Review Policy

This document is reviewed:
- **Before each phase gate** — verify frozen decisions still hold
- **When a new requirement is raised** that seems to require architecture change
- **Once per 90-day plan cycle**

To change a frozen decision: write an ADR, get CTO sign-off, update this document.
