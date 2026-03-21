# 27 - Sync MVP Design

> **Document Status:** Authoritative | **Last Updated:** 2026-03-20
>
> Two-phase sync design: LAN first (Phase 2), Cloud second (Phase 3).

---

## 1. Decision: LAN Before Cloud

**Verdict:** LAN sync is built in Phase 2. Cloud sync in Phase 3.

**Rationale:**
1. Multi-device coordination within a branch (POS + KDS + waiter) runs entirely on LAN — no cloud needed
2. Most restaurants have reliable LAN even when internet is slow or down
3. Cloud sync adds PostgreSQL, server deployment, and sync conflict complexity — too much for Phase 2
4. Building LAN first validates the sync data model before cloud adds complexity
5. Pilot restaurants need multi-device first; cloud reports are a nice-to-have

---

## 2. Phase 2: LAN Sync (Primary / Secondary Model)

### 2.1 Architecture

```
┌────────────────────────────────────────────┐
│           Branch Local Network              │
│                                             │
│  ┌─────────────────────┐                   │
│  │   PRIMARY DEVICE     │                   │
│  │   (POS Tablet)       │                   │
│  │   SQLite (source)    │◄────write────┐    │
│  │   HTTP + SSE server  │              │    │
│  └────────┬─────────────┘              │    │
│           │ SSE events / HTTP          │    │
│           │ LAN (same WiFi)            │    │
│     ┌─────▼──────┐  ┌─────────────┐   │    │
│     │ KDS Tablet  │  │Waiter Phone │───┘    │
│     │ (secondary) │  │ (secondary) │        │
│     └─────────────┘  └─────────────┘        │
└────────────────────────────────────────────┘
```

**Primary device** = owns the SQLite database. Always the main POS terminal.
**Secondary devices** = connect to primary. All mutations go through primary.

### 2.2 Primary Device: Local HTTP Server

The primary device runs an embedded HTTP server (Flutter app, background isolate or Shelf package).

**Endpoints exposed by primary:**

| Method | Path | Description |
|--------|------|-------------|
| GET | `/lan/health` | Ping — confirm primary is alive |
| GET | `/lan/info` | Primary device ID, tenant ID, schema version |
| POST | `/lan/orders` | Submit new order or item addition |
| POST | `/lan/orders/{id}/items` | Add items to existing order |
| POST | `/lan/orders/{id}/void` | Void an order item |
| GET | `/lan/tables` | Full table status snapshot |
| GET | `/lan/kitchen-tickets/stream` | SSE stream of kitchen ticket events |
| POST | `/lan/kitchen-tickets/{id}/complete` | Bump a ticket |
| GET | `/lan/menu` | Full menu snapshot (categories, products, modifiers) |
| GET | `/lan/shift/current` | Current shift status |

**Authentication:** Shared HMAC secret generated at tenant setup. All requests include `Authorization: Bearer {shared_secret}`. Not production-grade auth, but prevents accidental cross-restaurant connections.

### 2.3 Device Discovery

**Method:** mDNS (multicast DNS) — announce service on local network.

Primary announces: `gastrocore-{deviceId}._gastrocore._tcp.local` on port 7291

Secondary scans: looks for `_gastrocore._tcp` services → shows found primaries in Settings → user confirms connection.

**Fallback:** Manual IP entry in Settings for networks where mDNS is blocked (some enterprise routers).

**Port:** 7291 (non-standard — avoids conflicts with common services)

### 2.4 Secondary Device Behavior

Secondary devices:
1. Connect to primary at startup (or when configured in Settings)
2. Fetch full snapshot: GET `/lan/menu` → seed local SQLite
3. Fetch current tables: GET `/lan/tables` → seed local SQLite
4. Subscribe to SSE: GET `/lan/kitchen-tickets/stream` → update KDS in real time

For order mutations, secondary routes through primary:
- Secondary POS taps "Send to Kitchen" → POST `/lan/orders` to primary → primary writes SQLite
- Primary confirms success → secondary caches locally → UI updates

**Degraded mode:** If primary is unreachable > 15 seconds:
- Show "Primary Disconnected" banner in red
- Secondary can still view cached data
- Secondary cannot submit new orders (orders queue locally — manual retry)
- Secondary KDS shows "Last update: X seconds ago" indicator

### 2.5 Sync Scope (LAN Phase)

**Synced via LAN:**
- Kitchen tickets (new/completed) — real time via SSE
- Table status (occupied/available/dirty) — on change
- Order submissions — on submit
- Menu changes — on request (pull only)

**Not synced via LAN (each device manages locally):**
- Payments — POS device only; payment must occur on device that holds the order
- Shifts — each device has its own shift; consolidated in cloud sync later
- Receipts — generated on payment device; printed locally
- Audit log — local per device; consolidated in cloud sync later

### 2.6 Conflict Scenarios (LAN Phase)

| Scenario | Resolution |
|----------|-----------|
| Two waiters add items to same table simultaneously | Primary processes in order received. Last write wins for additions (both items kept — additive). |
| Waiter 1 voids item, Waiter 2 adds same item | Primary applies in request order. If void arrived first: item is voided then re-added. Logged in audit. |
| Primary device goes offline mid-order | Secondary enters degraded mode. In-flight orders are lost unless secondary can reach primary within retry window. Restaurant falls back to primary device. |
| Menu updated on primary | Secondaries re-fetch menu on reconnect. Stale menu cached locally for degraded mode. |

**Guarantee:** No transaction is silently lost. Either it commits on primary and is confirmed, or it fails with an error shown to the waiter.

---

## 3. Phase 3: Cloud Sync

### 3.1 What Changes from LAN to Cloud

- LAN sync remains for real-time coordination within the branch
- Cloud sync adds: backup, remote dashboard access, multi-branch data, cross-device restore
- LAN and cloud sync coexist — different purposes, different cadence

| | LAN Sync | Cloud Sync |
|-|----------|-----------|
| **Purpose** | Real-time coordination | Backup, reporting, multi-branch |
| **Latency** | < 1 second | 30 seconds to 5 minutes |
| **Transport** | Local network HTTP/SSE | HTTPS to cloud |
| **Conflict resolution** | Primary device wins | Server wins (last write with higher vector clock) |
| **Offline tolerance** | Minutes (branch network outage) | Hours to days |
| **What syncs** | Orders, tickets, tables | Everything (full delta) |

### 3.2 Outbox Pattern (Flutter Side)

Every DB mutation in Flutter writes to `sync_queue` table:

```sql
-- sync_queue table (already in schema):
CREATE TABLE sync_queue (
  id TEXT PRIMARY KEY,           -- UUID v7
  entity_type TEXT NOT NULL,     -- 'tickets', 'payments', 'products', etc.
  entity_id TEXT NOT NULL,       -- ID of changed entity
  operation TEXT NOT NULL,       -- 'insert', 'update', 'soft_delete'
  payload TEXT NOT NULL,         -- JSON snapshot of entity at time of change
  created_at INTEGER NOT NULL,   -- Unix timestamp
  synced_at INTEGER,             -- NULL = pending, set when cloud confirms
  retry_count INTEGER DEFAULT 0,
  error TEXT                     -- Last error message if failed
);
```

The outbox writer is a Drift DAO method called after every successful mutation. It does not add round-trips — it's a second INSERT in the same transaction.

### 3.3 Sync Runner (Flutter Background Process)

A background isolate (or Flutter `compute` + timer) runs every 30 seconds when online:

```
1. SELECT * FROM sync_queue WHERE synced_at IS NULL ORDER BY created_at LIMIT 100
2. POST /api/v1/sync/upload with batch payload
3. Server returns: { accepted: [...ids], rejected: [...ids], conflicts: [...] }
4. UPDATE sync_queue SET synced_at = now() WHERE id IN accepted
5. Handle conflicts: log for now, emit to conflict monitor
```

**Retry logic:**
- Max 10 retries per record
- Exponential backoff: 30s, 1m, 2m, 4m, 8m, 16m, 30m, 1h, 2h, 4h
- After 10 failures: mark as `error`, surface in admin screen
- Failed records do NOT block other records from syncing

### 3.4 Download / Inbox (Flutter)

The download runner polls GET `/api/v1/sync/download?cursor={last_cursor}` every 30 seconds:

```
1. GET /api/v1/sync/download?cursor={cursor}&entity_types=menu,users,settings
2. Server returns: { changes: [...], cursor: "new_cursor", has_more: true/false }
3. Apply each change to local SQLite (idempotent upsert)
4. Save new cursor to sync_metadata
5. If has_more: immediately poll again (don't wait 30s)
```

**What is downloaded:**
- Menu changes pushed from cloud dashboard
- User/staff changes
- Settings changes
- In multi-branch: other branches' data is NOT downloaded (tenant-scoped)

**What is NOT downloaded:**
- Orders from cloud → device (orders are device-originated, never cloud-originated)
- Payments (same)
- Receipts (same)
- Print jobs (always local)

### 3.5 Cloud Sync Service (Go)

The `internal/sync` handlers need real implementation:

**Upload handler (POST /api/v1/sync/upload):**
```
1. Parse batch of entity changes from body
2. Validate: device owns tenant, entities belong to tenant
3. For each entity change:
   a. Check if entity exists in PostgreSQL
   b. If not: INSERT
   c. If exists and change.updated_at > db.updated_at: UPDATE
   d. If conflict (change.updated_at < db.updated_at): add to conflicts list
4. Return { accepted: [ids], rejected: [ids], conflicts: [{id, server_version, device_version}] }
```

**Download handler (GET /api/v1/sync/download):**
```
1. Parse cursor (last_updated_at timestamp from device's perspective)
2. Parse entity_types filter
3. SELECT * FROM {entity_type} WHERE tenant_id = ? AND updated_at > cursor ORDER BY updated_at LIMIT 200
4. Return { changes: [...], cursor: max(updated_at), has_more: count > 200 }
```

**Seed handler (POST /api/v1/sync/seed):**
```
Called when a new device registers or restores from cloud.
Returns full current state for all seedable entities for the tenant.
```

### 3.6 Conflict Resolution Strategy

| Entity Type | Strategy | Rationale |
|-------------|----------|-----------|
| Orders / tickets | Append-only, no conflict possible | Items are added, never edited; void creates new record |
| Payments | Append-only, no conflict possible | Each payment is immutable |
| Menu (products, categories, modifiers) | Last-writer-wins (server timestamp) | Menu edits are rare; losing one edit is acceptable |
| Table layout | Last-writer-wins | Physical layout changes rarely |
| Users / staff | Server wins on conflict | Identity management is authoritative on server |
| Settings | Last-writer-wins with field-level merge | Device-specific settings stay on device; shared settings merge |
| Tax profiles | Server wins | Compliance data is authoritative on server |

### 3.7 Entity Types in Sync Scope (Cloud)

**Synced UP (device → cloud):**
- All completed tickets + order items
- All payments
- All receipts
- Shifts + cash movements
- Audit log entries

**Synced DOWN (cloud → device):**
- Products, categories, modifiers (menu management from dashboard)
- Users + PINs (staff management from dashboard)
- Tax profiles
- Settings overrides
- License token

**NOT synced:**
- Print jobs (local, ephemeral)
- Bluetooth/WiFi printer configuration (device-local)
- UI state (current screen, open drawers)
- `sync_queue` table itself
- `sync_metadata` table itself

### 3.8 Device Registration

Before sync, device must be registered:

```
POST /api/v1/devices/register
{
  "device_id": "uuid-v7",
  "tenant_id": "uuid-v7",
  "license_key": "GC-XXXX-XXXX-XXXX",
  "device_name": "POS Terminal 1",
  "platform": "android",
  "model": "Samsung Galaxy Tab S8"
}

Response: { "device_token": "jwt...", "expires_at": "..." }
```

Device token is a JWT used for all subsequent API calls (Authorization header).

### 3.9 What Printer Jobs Must Never Sync

Printer jobs are ephemeral and device-local. They must never be replicated to other devices or the cloud. The print queue in the printer service is local state only.

**Why:** If a receipt print job were synced, it could trigger a double-print on another device. Print jobs contain sensitive receipt data that should not be buffered in cloud.

---

## 4. Sync Priority Classes

| Priority | Entity Types | Cadence | Reason |
|----------|-------------|---------|--------|
| P0 - Critical | Shifts, payments | Immediate (within 30s of shift close) | Financial data must reach cloud ASAP |
| P1 - High | Tickets, order items, audit log | 30-second batch | Operational data for reporting |
| P2 - Normal | Menu, users, settings | 5-minute interval (down only) | Master data changes are infrequent |
| P3 - Background | Historical receipts, large blobs | Nightly / when on WiFi | Not time-sensitive |

---

## 5. Idempotency

Every sync operation is idempotent:

- Upload: entity_id + updated_at as idempotency key. Sending same batch twice = no harm.
- Download: applying same change twice = idempotent upsert (ON CONFLICT DO UPDATE)
- Seed: receiving full state and re-applying = no harm (idempotent upserts)

This means the sync runner can retry freely without fear of data corruption.

---

## 6. Tombstone / Soft Delete Propagation

All deletes are soft deletes (ADR-015). The `is_deleted = true` flag must sync:

1. Device soft-deletes a product: outbox records `operation = 'soft_delete'`, payload includes `{id, is_deleted: true}`
2. Cloud receives: sets `is_deleted = true` in PostgreSQL
3. Other devices download: apply `is_deleted = true` to local SQLite
4. UI: `is_deleted = true` items are hidden from menus (filter in all queries)

Tombstones are never physically deleted from cloud. They provide the authoritative "this was deleted" signal.

---

## 7. Sync Status UI

`pos_sync_indicator.dart` already exists. Wire it to real sync state:

```dart
// Sync states:
enum SyncStatus { synced, syncing, pendingChanges, error, offline }

// Indicator shows:
// ✓ Synced (green dot)
// ↑ Syncing (animated arrow)
// ● 12 pending (orange dot + count)
// ✗ Sync error (red dot — tap for details)
// ~ Offline (grey dot)
```

Tapping the indicator shows a drawer with last sync time, pending count, and error details.
