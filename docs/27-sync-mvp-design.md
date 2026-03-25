# 27 — Sync MVP Design

> **Document Status:** Authoritative | **Last Updated:** 2026-03-24
>
> **Cloud sync only.** LAN sync has been removed from the architecture.
> See doc 23 FRZ-11 and ADR-017 for the decision rationale.
> Previous version included Phase 2 LAN sync — that phase is eliminated.

---

## 1. Decision: Cloud Sync Only

**Verdict:** Multi-device coordination uses cloud sync exclusively. No LAN sync.

**Rationale:**
1. A 1–5 person AI-assisted team can ship cloud sync faster than building LAN sync (which requires mDNS discovery, embedded HTTP server, primary/secondary failover, LAN-specific auth)
2. Cloud sync covers ALL multi-device use cases: KDS tablet, waiter phone, second POS, remote dashboard
3. LAN sync would still need cloud for backup and remote reporting — building both adds 4–6 weeks of complexity for minimal marginal benefit
4. Modern Swiss restaurants have reliable internet + 4G router backup
5. Simpler architecture = fewer failure modes = better support experience

**Offline behavior on multi-device:** When cloud is unreachable, each device operates independently in single-device mode. Kitchen tickets fall back to print. This is acceptable — the primary use case is single-device operation; multi-device is a Professional tier enhancement.

---

## 2. Architecture Overview

```
┌────────────────────────────┐     HTTPS      ┌──────────────────────────┐
│   POS Tablet (Flutter)      │◄──────────────►│   Cloud Hub (Go + PG)     │
│                             │                │                           │
│  SQLite (Drift)             │   sync upload  │  PostgreSQL 16            │
│  ┌────────────────────────┐ │──────────────►│  (tenant data)            │
│  │  sync_queue (outbox)   │ │                │                           │
│  │  sync_metadata         │ │◄──────────────│  WebSocket hub            │
│  └────────────────────────┘ │  sync download │  (KDS events)             │
│                             │                │                           │
│  SyncRunner (background)    │   WebSocket    │  Fiskaly TSE (Phase 5)    │
│  DownloadRunner (background) │◄─────────────►│  (Germany only)           │
└────────────────────────────┘                └──────────────────────────┘
              │
              │ WebSocket
              ▼
┌────────────────────────────┐
│   KDS Tablet (Flutter)      │
│   Subscribes to cloud WS   │
│   Receives kitchen events  │
└────────────────────────────┘
              │
              │ HTTPS
              ▼
┌────────────────────────────┐
│   Waiter Phone (Flutter)    │
│   REST + sync for orders    │
└────────────────────────────┘
```

---

## 3. Phase 1 (Current): Single Device

No sync needed. POS, KDS, waiter app all run on the same SQLite on the same Android tablet. Fully offline. No cloud required.

**Phase 1 sync status:** `sync_queue` table exists but is never written to. `pos_sync_indicator.dart` shows a static "offline" badge.

---

## 4. Phase 2: Cloud Sync Implementation

### 4.1 Outbox Pattern (Flutter Side)

Every DB mutation in Flutter writes to `sync_queue` table **in the same transaction**:

```sql
-- sync_queue table (already in schema):
CREATE TABLE sync_queue (
  id TEXT PRIMARY KEY,           -- UUID v7
  entity_type TEXT NOT NULL,     -- 'tickets', 'payments', 'kitchen_tickets', etc.
  entity_id TEXT NOT NULL,       -- ID of changed entity
  operation TEXT NOT NULL,       -- 'insert', 'update', 'soft_delete'
  payload TEXT NOT NULL,         -- JSON snapshot of entity
  created_at INTEGER NOT NULL,   -- Unix ms timestamp
  synced_at INTEGER,             -- NULL = pending; set when cloud confirms
  retry_count INTEGER DEFAULT 0,
  error TEXT                     -- last error if failed
);
```

**Implementation rule:** The outbox write is a second INSERT in the same Drift transaction as the mutation. It does not add round-trips. If the mutation fails, the outbox entry also rolls back.

```dart
// Pattern in every repository mutation:
await db.transaction(() async {
  await db.into(db.tickets).insert(ticketRow);
  await db.into(db.syncQueue).insert(SyncQueueCompanion.insert(
    id: const Value(IdGenerator.uuid()),
    entityType: const Value('tickets'),
    entityId: Value(ticketRow.id),
    operation: const Value('insert'),
    payload: Value(jsonEncode(ticketRow.toJson())),
    createdAt: Value(DateTime.now().millisecondsSinceEpoch),
  ));
});
```

### 4.2 Sync Runner (Flutter Background Task)

A background isolate or periodic timer runs every 30 seconds when online:

```
1. SELECT * FROM sync_queue WHERE synced_at IS NULL ORDER BY created_at LIMIT 100
2. POST /api/v1/sync/upload with batch
3. Server returns: { accepted: [...ids], rejected: [...ids], conflicts: [...] }
4. UPDATE sync_queue SET synced_at = now() WHERE id IN accepted
5. Handle conflicts: log to conflict_log, surface in admin screen
```

**Retry logic:**
- Max 10 retries per record
- Exponential backoff: 30s, 1m, 2m, 4m, 8m, 16m, 30m, 1h, 2h, 4h
- After 10 failures: mark `error`, surface in support screen
- Failed records do NOT block other records from syncing

### 4.3 Download Runner (Flutter)

Polls `GET /api/v1/sync/download?cursor={last_cursor}` every 30 seconds:

```
1. GET /api/v1/sync/download?cursor={cursor}&entity_types=menu,users,settings
2. Server returns: { changes: [...], cursor: "new_cursor", has_more: bool }
3. Apply each change to local SQLite (idempotent upsert via ON CONFLICT DO UPDATE)
4. Save new cursor to sync_metadata
5. If has_more: immediately poll again (don't wait 30s)
```

**What is downloaded (cloud → device):**
- Products, categories, modifiers (menu management from dashboard)
- Users + staff data (from dashboard)
- Tax profiles
- Settings overrides
- License token (renewal)

**What is NOT downloaded:**
- Orders (device-originated, never cloud-originated)
- Payments (same)
- Receipts (same)
- Print jobs (always local, ephemeral)

### 4.4 Device Registration

Before sync, device must be registered once:

```http
POST /api/v1/devices/register
{
  "device_id": "uuid-v7",
  "tenant_id": "uuid-v7",
  "license_key": "GC-XXXX-XXXX-XXXX",
  "device_name": "POS Terminal 1",
  "platform": "android",
  "model": "Samsung Galaxy Tab S9"
}

→ Response: { "device_token": "jwt...", "expires_at": "..." }
```

Device token (JWT) is used for all subsequent API calls (Authorization header).

---

## 5. Go Cloud Sync Service — Implementation

### 5.1 Upload Handler

```
POST /api/v1/sync/upload
```

```
1. Parse batch of entity changes
2. Validate: device_token → extract tenant_id; verify entities belong to tenant
3. For each entity change:
   a. Check if entity exists in PostgreSQL by entity_id
   b. Not exists → INSERT
   c. Exists AND change.updated_at > db.updated_at → UPDATE
   d. Conflict (change.updated_at ≤ db.updated_at) → add to conflicts list
4. Return { accepted: [ids], rejected: [ids], conflicts: [{id, server_version}] }
```

### 5.2 Download Handler

```
GET /api/v1/sync/download?cursor={timestamp}&entity_types={comma-list}
```

```
1. Parse cursor (last updated_at seen by device)
2. Parse entity_types filter
3. SELECT * FROM {entity_type}
   WHERE tenant_id = ? AND updated_at > cursor
   ORDER BY updated_at
   LIMIT 200
4. Return { changes: [...], cursor: max(updated_at), has_more: count == 200 }
```

### 5.3 Seed Handler (New Device Setup)

```
POST /api/v1/sync/seed
```

```
Called when a new device registers or restores from cloud.
Returns full current state for all seedable entities for the tenant.
Paginated by entity_type to avoid memory issues.
```

---

## 6. KDS Real-Time via Cloud WebSocket

The Go `internal/kds/` module contains a WebSocket hub. Wire it to the sync upload path:

### 6.1 Server Side

```go
// In sync upload handler, after writing kitchen_ticket to PostgreSQL:
if entityType == "kitchen_tickets" && operation == "insert" {
    kdsHub.Broadcast(tenantID, KDSEvent{
        Type:    "new_kitchen_ticket",
        Payload: entityPayload,
    })
}

// Bump event:
if entityType == "kitchen_tickets" && operation == "update" &&
   payload["status"] == "completed" {
    kdsHub.Broadcast(tenantID, KDSEvent{
        Type:    "ticket_completed",
        Payload: entityPayload,
    })
}
```

### 6.2 KDS Flutter Client

```dart
// KDS tablet: connect WebSocket on app start
final kdsChannel = WebSocketChannel.connect(
  Uri.parse('wss://pos.2tech.ch/api/v1/kds/ws'),
  headers: {'Authorization': 'Bearer ${deviceToken}'},
);

kdsChannel.stream.listen((message) {
  final event = KDSEvent.fromJson(json.decode(message));
  if (event.type == 'new_kitchen_ticket') {
    // Upsert to local SQLite; Drift stream auto-updates UI
    kitchenRepository.upsertTicket(KitchenTicketEntity.fromJson(event.payload));
    _playNewTicketSound();
  }
});
```

### 6.3 KDS Bump via Cloud

```dart
// KDS tablet bumps a ticket:
void _bumpTicket(String ticketId) async {
  // 1. Update local SQLite immediately (optimistic UI)
  await kitchenRepository.completeTicket(ticketId);
  // 2. Queue for sync upload (outbox pattern)
  await syncQueue.enqueue(entityType: 'kitchen_tickets', id: ticketId,
    operation: 'update', payload: {'id': ticketId, 'status': 'completed'});
}
// POS tablet receives the status update via sync download
```

---

## 7. Conflict Resolution Strategy

| Entity Type | Strategy | Rationale |
|-------------|----------|-----------|
| Orders / tickets | Append-only, no conflict possible | Items added, never edited; void creates new record |
| Payments | Append-only, no conflict possible | Each payment is immutable |
| Kitchen tickets | Append-only (inserts); last-writer-wins (status updates) | KDS bump is idempotent |
| Menu (products, categories, modifiers) | Last-writer-wins (server timestamp) | Menu edits are rare |
| Table layout | Last-writer-wins | Physical layout changes rarely |
| Users / staff | Server wins on conflict | Identity is authoritative on server |
| Settings | Last-writer-wins with field-level merge | Shared settings merge; device-local stay local |
| Tax profiles | Server wins | Compliance data is authoritative |

---

## 8. Sync Priority Classes

| Priority | Entities | Cadence |
|----------|---------|---------|
| P0 — Critical | Shifts, payments | Within 30s of shift close |
| P1 — High | Tickets, order items, kitchen tickets, audit log | 30-second batch |
| P2 — Normal | Menu, users, settings (download only) | 5-minute interval |
| P3 — Background | Historical receipts | Nightly, WiFi only |

---

## 9. Idempotency

Every sync operation is idempotent:
- Upload: `entity_id + updated_at` as idempotency key. Sending same batch twice = no harm.
- Download: applying same change twice = idempotent upsert (`ON CONFLICT DO UPDATE`)
- Seed: receiving full state and re-applying = no harm

The sync runner can retry freely without fear of data corruption.

---

## 10. Tombstone / Soft Delete Propagation

All deletes are soft deletes (`is_deleted = true`). Tombstones sync:

1. Device soft-deletes a product: outbox records `operation = 'soft_delete'`, payload: `{id, is_deleted: true}`
2. Cloud receives: sets `is_deleted = true` in PostgreSQL
3. Other devices download: apply `is_deleted = true` to local SQLite
4. UI: `is_deleted = true` items hidden from menus

Tombstones are never physically deleted from cloud. They provide the authoritative "deleted" signal.

---

## 11. Sync Status UI

`pos_sync_indicator.dart` already exists. Wire to real sync state:

```dart
enum SyncStatus { synced, syncing, pendingChanges, error, offline }

// Indicator shows:
// ✓ Synced (green dot) — all changes uploaded and confirmed
// ↑ Syncing (animated) — upload or download in progress
// ● 12 pending (orange) — changes queued for upload
// ✗ Sync error (red) — tap for details
// ~ Offline (grey) — no internet connectivity
```

Tapping the indicator shows a drawer with last sync time, pending count, and error log.

---

## 12. What Is NOT Synced (Never)

| Item | Why Not |
|------|---------|
| Print jobs | Ephemeral and device-local; double-print risk if synced |
| Bluetooth/WiFi printer config | Device-local hardware config |
| UI state (current screen) | Irrelevant to other devices |
| `sync_queue` table itself | Meta-table; not data |
| `sync_metadata` table itself | Meta-table; not data |
| Raw SQLite file | Too large; schema-incompatible if versions differ |

---

## 13. Deployment Requirements for Cloud Sync

| Requirement | Detail |
|-------------|--------|
| HTTPS only | TLS via nginx reverse proxy on VPS |
| PostgreSQL 16 | On same VPS (pos.2tech.ch) or managed DB |
| Daily automated backups | PostgreSQL dump to separate storage |
| WebSocket support | nginx `proxy_pass` with `upgrade` headers |
| Health check endpoint | `GET /health` returns 200 — for monitoring |
| Rate limiting | Already in Go middleware |
| Tenant isolation | All queries include `WHERE tenant_id = ?` |

---

## 14. Migration from Single-Device to Multi-Device

When a restaurant upgrades from single-device to multi-device (Professional tier):

1. First device registers and uploads full state (seed upload)
2. Cloud seeds second device from first device's data
3. Second device joins with full menu, staff, table layout
4. Both devices sync bidirectionally from that point

**Time to onboard second device from cloud seed:** < 5 minutes for a typical restaurant (< 500 products, < 100 staff, last 30 days of transactions).

---

## 15. Success Criteria for Sync MVP

- [ ] POS writes to `sync_queue` on every ticket, payment, and menu mutation
- [ ] Sync runner uploads batch to cloud within 30s of each mutation
- [ ] 8 hours offline then reconnect: full sync completes without data loss
- [ ] KDS tablet on separate device receives kitchen ticket via WebSocket within 10s
- [ ] New device seeded from cloud in < 5 minutes
- [ ] Sync status indicator correctly shows pending count and last sync time
- [ ] Conflict log records all conflicts; no data corruption in 1000-operation test
