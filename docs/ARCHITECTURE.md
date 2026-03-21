# GastroCore — System Architecture

## Table of Contents

- [Overview](#overview)
- [Three-Layer Architecture](#three-layer-architecture)
- [Flutter Multi-App Architecture](#flutter-multi-app-architecture)
- [Go Backend Module Map](#go-backend-module-map)
- [Offline-First Sync Protocol](#offline-first-sync-protocol)
- [State Management](#state-management)
- [Swiss VAT & Fare Engine](#swiss-vat--fare-engine)
- [Real-Time WebSocket Layer](#real-time-websocket-layer)
- [Licensing System](#licensing-system)
- [Security Model](#security-model)
- [Key Design Decisions](#key-design-decisions)

---

## Overview

GastroCore is an **offline-first** restaurant POS platform designed for the Swiss market. It ships five Flutter apps (POS, Kiosk, KDS, ODS, Waiter) from a single repository, all sharing the same Drift-backed SQLite database on device, syncing to a central Go/PostgreSQL cloud hub.

The guiding constraint is **zero-dependency operation**: a restaurant that loses internet must continue processing orders, accepting payments, printing receipts, and dispatching to the kitchen without any degradation. Sync happens opportunistically in the background.

---

## Three-Layer Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  LAYER 1 — Branch Runtime (devices at the restaurant)           │
│                                                                 │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ │
│  │   POS   │ │  Kiosk  │ │   KDS   │ │   ODS   │ │ Waiter  │ │
│  └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘ │
│       └──────────────────────┬─────────────────────────┘       │
│                        SQLite (Drift)                           │
│                        Shared on-device DB                      │
└────────────────────────────┬────────────────────────────────────┘
                             │ REST + WebSocket
                             │ /api/v1/sync/push
                             │ /api/v1/sync/pull
                             │ /ws/sync
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  LAYER 2 — Cloud Hub (Go server + PostgreSQL + Redis)           │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │              Go API Server (net/http)                     │ │
│  │  auth │ sync │ menu │ orders │ kds │ reports │ online     │ │
│  └──────────────────────┬────────────────────────────────────┘ │
│                         │                                       │
│          ┌──────────────┴──────────────┐                       │
│          ▼                             ▼                        │
│   PostgreSQL 16                    Redis 7                      │
│   (source of truth)                (pub/sub, cache)             │
└─────────────────────────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  LAYER 3 — External Integrations (future phases)                │
│                                                                 │
│  ERPNext Bridge │ Fiskaly (DE fiscal) │ Swiss QR-bill           │
└─────────────────────────────────────────────────────────────────┘
```

---

## Flutter Multi-App Architecture

### Entry Points

| File | App | Behavior |
|---|---|---|
| `lib/main.dart` | POS | Standard dark-theme app, PIN auth |
| `lib/main_kiosk.dart` | Kiosk | Landscape-only, immersive, device ID `K-{uuid}` |
| `lib/main_kds.dart` | KDS | Minimal kitchen display, WebSocket listener |
| `lib/main_ods.dart` | ODS | Customer-facing order status display |
| `lib/main_waiter.dart` | Waiter | Handheld, same logic as POS but mobile UI |

All five share:
- `AppDatabase` (Drift, 31 tables)
- `SyncQueue` outbox pattern
- Riverpod state management
- Core services (FareEngine, ESC-POS, Money)

### Directory Structure

```
apps/pos/lib/
├── core/
│   ├── database/        # Drift ORM — AppDatabase, 31 table definitions
│   ├── sync/            # Outbox, SyncApiClient, WebSocketSyncClient, providers
│   ├── services/        # FareEngine, PricingService
│   ├── payment/         # PaymentProvider interface, Wallee, MyPOS
│   ├── printing/        # EscPosBuilder, SwissReceiptBuilder, KitchenTicketBuilder
│   ├── theme/           # AppTheme, AppColors, PosColors ThemeExtension
│   ├── router/          # GoRouter with 14+ named routes
│   ├── di/              # Riverpod providers (databaseProvider, tenantIdProvider…)
│   ├── utils/           # Money, IdGenerator
│   └── constants/       # Enums, AppConstants
├── features/
│   ├── auth/            # PIN auth, roles, permissions
│   ├── menu/            # Categories, Products, ModifierGroups
│   ├── orders/          # Tickets, OrderItems, POS screen
│   ├── kiosk/           # KioskOrderService, KioskSessionNotifier, 7 screens
│   ├── kitchen/         # KDS queue, KitchenTicket management
│   ├── payments/        # Payment entity, split bill, hardware providers
│   ├── shifts/          # Shift open/close, CashMovement, DayCloseCalculator
│   ├── tables/          # Floor layout, table positions (x, y, width, height)
│   ├── reports/         # Dashboard, sales, product performance
│   ├── audit_log/       # Immutable action trail
│   ├── licensing/       # LicenseTier, LicenseValidator, FeatureGate widget
│   ├── inventory/       # Stock, InventoryTransaction, Supplier
│   ├── onboarding/      # Setup wizard
│   └── settings/        # User preferences, receipt config
├── shared/widgets/      # Shared UI components
├── l10n/                # Localizations: DE, FR, IT, EN
├── app.dart             # MaterialApp.router root (POS)
├── kiosk_app.dart       # Kiosk root with inactivity listener
└── main*.dart           # 5 entry points
```

### Database Layer (Drift)

`AppDatabase` defines **31 tables** with two factory constructors:

```dart
// Production — file-backed SQLite
AppDatabase.create(File dbFile)

// Tests — in-memory SQLite
AppDatabase.createInMemory()
```

Schema version: **7** — migrated via `MigrationStrategy` with per-version SQL.

All entities use `freezed` for immutability + `json_serializable` for sync payloads.

---

## Go Backend Module Map

```
server/
├── cmd/
│   ├── server/       # main.go — HTTP server bootstrap
│   ├── migrate/      # Run pending SQL migrations
│   └── seed/         # Insert demo data
├── internal/
│   ├── auth/         # JWT generation, PIN login, token refresh
│   ├── sync/         # Push/pull change events, device registry
│   ├── menu/         # Categories, products, modifiers CRUD
│   ├── orders/       # Tickets, bills, payments
│   ├── online/       # Public menu + online order submission
│   ├── kds/          # Kitchen display WebSocket hub
│   ├── reports/      # Sales, product, shift aggregations
│   ├── devices/      # Device registration + status
│   ├── licenses/     # License validation, tier lookup
│   ├── stores/       # Multi-store management
│   ├── docs/         # OpenAPI spec serving
│   └── shared/
│       ├── config/   # Env-based config struct
│       ├── database/ # PostgreSQL connection + query helpers
│       └── middleware/ # RequestID, Logger, Recover, CORS, RateLimit
└── migrations/       # 001–005 SQL migration files
```

Each internal module exposes a `Module` struct:

```go
type Module struct { ... }

func NewModule(db *sql.DB, cfg *config.Config) *Module

func (m *Module) RegisterRoutes(mux *http.ServeMux)
```

### Request Lifecycle

```
Client request
  → Middleware chain: RequestID → Logger → Recover → CORS → RateLimit
  → mux.HandleFunc pattern matching
  → Auth middleware (JWT validation, except public routes)
  → Handler function
  → JSON response (stdlib encoding/json)
```

### Middleware Chain

| Middleware | Purpose |
|---|---|
| `RequestID` | Injects `X-Request-ID` header for trace correlation |
| `Logger` | Structured JSON logs via `log/slog` |
| `Recover` | Panic recovery → 500 response |
| `CORS` | Cross-origin headers for web clients |
| `RateLimit` | Token bucket: 200 requests/minute global |

---

## Offline-First Sync Protocol

### Outbox Pattern

Every local write is **dual-committed**: once to the entity table, once to `sync_queue`:

```
┌──────────────────────────────────────────────────────┐
│  Device                                               │
│                                                       │
│  User action                                         │
│    → Drift DAO write (entity table)                  │
│    → SyncQueue INSERT (status: pending)               │
│                                                       │
│  Background sync (timer / connectivity change)        │
│    → Collect pending events                           │
│    → POST /api/v1/sync/push (batch, max 100 events)   │
│    → On success: mark events as uploaded              │
│    → On failure: increment retryCount (max 5)         │
│                                                       │
│  Pull loop                                            │
│    → GET /api/v1/sync/pull?since=<last_seq>           │
│    → Apply server changes to local tables             │
│    → Update sync_metadata.last_pulled_at              │
└──────────────────────────────────────────────────────┘
```

### SyncEvent Schema

```dart
class SyncEventEntity {
  final String id;           // UUID
  final String tableName;    // e.g. "tickets"
  final String recordId;     // entity UUID
  final SyncOperation op;    // insert | update | delete
  final Map<String,dynamic> payload; // full entity JSON
  final String deviceId;     // originating device
  final SyncEventStatus status; // pending | uploading | uploaded | failed
  final int retryCount;
  final DateTime createdAt;
}
```

### Device-Type Sync Config

Each flavor syncs only the tables it needs:

| Flavor | Pushes | Pulls |
|---|---|---|
| `pos` | tickets, order_items, payments, shifts, receipts | menu, products, tables, users |
| `kiosk` | tickets, order_items | menu, products, categories |
| `kds` | kitchen_ticket_items (status updates) | kitchen_tickets, order_items |
| `ods` | — | tickets (status only) |
| `waiter` | tickets, order_items | menu, tables |

### Conflict Resolution

- **Last-write-wins** on `updated_at` timestamp (TIMESTAMPTZ with millisecond precision)
- **Soft-delete** — entities have `is_deleted BOOLEAN`, never hard-deleted during sync
- Device changes always win over stale server state for that device's records

### WebSocket Real-Time

After push, the server fans out a notification on `/ws/sync` to all connected devices for the same `tenant_id`. KDS additionally receives notifications via `/ws/kds` when a new kitchen ticket is created.

---

## State Management

GastroCore uses **Riverpod 2** exclusively. No `StatefulWidget` state, no global singletons.

### Key Provider Hierarchy

```
databaseProvider (AppDatabase)
  ↓ used by all DAO providers

tenantIdProvider (String)
  ↓ used by all feature providers

deviceIdProvider (String)
  ↓ used by sync providers

syncServerUrlProvider (String)
  ↓
webSocketSyncClientProvider (WebSocketSyncClient)
  ↓
connectivityAutoSyncProvider — auto-syncs on reconnect

swissTicketFareProvider (FareBreakdown?)
  ↓ computed from active ticket + order type
```

### Kiosk Session

`KioskSessionNotifier` (Riverpod `AsyncNotifier`) manages:
- Cart state (List<KioskCartItem>)
- Selected order type (dine-in / takeaway)
- Inactivity timer (60s → emit `sessionTimeout` event)
- Order submission via `KioskOrderService`

---

## Swiss VAT & Fare Engine

### Tax Rates (as of 2026-01-01)

| Code | Rate | Applies to |
|---|---|---|
| A | 8.1% | Food (dine-in), beverages, alcohol, standard goods |
| B | 2.6% | Food (takeaway), non-alcoholic beverages (takeaway) |
| C | 3.8% | Accommodation |

### FareEngine

`core/services/fare_engine.dart` is the single source of financial truth:

```
Input: List<OrderItemEntity>, OrderType, discounts, serviceCharge

Output: FareBreakdown {
  subtotal         // sum of gross item amounts
  discountAmount   // fixed or percentage discount
  serviceCharge    // optional service fee
  taxByRate        // Map<String, int> — cents per MWST code
  total            // subtotal - discount + serviceCharge
  roundingAmount   // CHF 5-Rappen rounding delta (cash only)
  grandTotal       // total + roundingAmount
}
```

**Tax extraction** (Bruttopreise — prices are tax-inclusive):
```
tax = gross × rate / (100 + rate)
```

**Order-type toggle**: When `OrderType` switches (dine-in ↔ takeaway), `TicketEntity.updateOrderType()` re-runs `_extractItemTax()` on every item to reclassify food items between A and B.

### Receipt

`SwissReceiptBuilder` outputs ESC-POS byte sequences with:
- `Bestellart: Hier essen / Zum Mitnehmen`
- MWST breakdown table (Code | Rate | Net | Tax | Gross)
- `Rundung: ±CHF 0.xx` line for cash payments
- MWST-Nr (CHE-XXX.XXX.XXX) in footer

---

## Real-Time WebSocket Layer

### KDS Hub

```go
// kds/hub.go
type Hub struct {
    clients  map[string]*Client  // deviceID → connection
    incoming chan KDSNotification
    register chan *Client
    unregister chan string
}

type KDSNotification struct {
    TenantID    string
    TicketID    string
    OrderNumber string
    EventType   string  // "new_order" | "item_ready" | "ticket_cancelled"
}
```

The hub runs as a goroutine (`go hub.Run()`) started before any module. When `online.Module` creates an order, it calls `hub.NotifyNewOrder(tenantID, ticketID, orderNumber)`, which is delivered only to KDS clients with matching `tenant_id`.

### Sync WebSocket

`/ws/sync` broadcasts `SyncEvent` JSON to all devices in the tenant after a push, enabling near-instant multi-device updates without polling.

---

## Licensing System

### Tiers

| Tier | Limits | Price |
|---|---|---|
| **Free** | 50 menu items, no cloud sync, no KDS | CHF 0 |
| **Professional** | Unlimited menu, KDS, LAN multi-device, advanced reports | CHF 79/mo |
| **Enterprise** | Cloud sync, API access, multi-location | CHF 199/mo |

### Token Validation

License tokens are Ed25519-signed payloads (JWT-like structure):

```
header.payload.signature

payload: {
  tenantId, tier, expiresAt, features: [...], maxDevices
}
```

`LicenseValidator` verifies the signature with `LICENSE_SIGNING_KEY` (public key). Tokens are cached in-memory after first validation. Invalid / expired tokens degrade to Free tier.

`FeatureGate` widget wraps premium UI:
```dart
FeatureGate(
  feature: Feature.cloudSync,
  child: SyncSettingsScreen(),
  fallback: UpgradePrompt(feature: Feature.cloudSync),
)
```

---

## Security Model

| Concern | Mechanism |
|---|---|
| **Staff authentication** | 4–6 digit PIN, hashed with bcrypt (server) / SHA-256+salt (device) |
| **Device auth** | JWT issued at device registration, 24h expiry, refresh token |
| **API authorization** | Bearer JWT, validated on every request |
| **License integrity** | Ed25519 signature, cannot be forged without private key |
| **Transport** | HTTPS enforced in production (nginx TLS termination) |
| **Rate limiting** | 200 req/min global at server level |
| **SQL injection** | Parameterized queries only — no string interpolation in SQL |
| **Audit trail** | `audit_log` table records every mutating action with old/new values |

---

## Key Design Decisions

See [`docs/adr/`](adr/) for full Architecture Decision Records. Summary:

| Decision | Choice | Rationale |
|---|---|---|
| Mobile framework | Flutter | Single codebase for 5 apps, strong offline story |
| ORM | Drift | Type-safe SQLite on device, PostgreSQL-compatible SQL |
| Backend language | Go | Minimal dependencies, single binary deploy, fast cold start |
| HTTP framework | stdlib `net/http` | No heavy framework — Go 1.22 patterns + routing suffice |
| State management | Riverpod 2 | Compile-time safe, testable, no context threading |
| Sync strategy | Outbox (push/pull) | Simple, auditable, works offline; avoids CRDT complexity |
| Tax model | Gross-inclusive extraction | Swiss law requires Bruttopreise on receipts |
| ID strategy | UUID v4 | Offline-safe, no coordination required |
| Auth | PIN-only | Restaurant context — speed over password complexity |
| ERPNext | Async bridge (Phase 9) | Accounting is batch, not real-time; reduces coupling |
