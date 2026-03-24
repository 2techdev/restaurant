# 26 — KDS MVP Design

> **Document Status:** Authoritative | **Last Updated:** 2026-03-24
>
> Kitchen Display System — minimum viable implementation on top of the existing UI skeleton.
> Updated: multi-device section now uses cloud WebSocket (not LAN sync).

---

## 1. Current State Assessment

The `KitchenDisplayScreen` is visually complete:
- Color-coded urgency borders (green/orange/red)
- Per-ticket countdown timer (1s precision)
- Bump (READY) button
- Pending/Preparing/Ready stats bar
- Responsive ticket grid (1–4 columns by screen width)
- Station indicator in header

**The entire screen runs on hardcoded demo data.** `_buildDemoTickets()` creates 6 static tickets at startup. Nothing connects to the database.

The goal of KDS MVP is to replace demo data with real data — nothing else.

---

## 2. What KDS MVP Must Do

| Capability | In MVP | Deferred |
|-----------|--------|---------|
| Show live kitchen tickets from current shift | ✅ | |
| Color-coded timer (green/orange/red) | ✅ (already works) | |
| Bump ticket → mark completed | ✅ | |
| Show item name, quantity, modifiers | ✅ | |
| Show table name and waiter | ✅ | |
| Audible alert on new ticket | ✅ | |
| Station routing (filter by category) | ✅ | |
| Print fallback if KDS device not receiving | ✅ | |
| Recall bumped ticket | Deferred | |
| Item-level status (individual item bump) | Deferred | |
| Course/fire management | Deferred | |
| Rush/priority indicator per ticket | Deferred v2 | |
| Multi-station routing rules UI | Deferred v2 | |

---

## 3. Data Flow

### 3.1 POS → KDS (Order Submit Action)

When a waiter submits an order (POS "Send to Kitchen" button):

```
Ticket status changes to "submitted"
          ↓
OrderRepository.submitOrder(ticketId)
          ↓
Write KitchenTicket row:
  - id: UUID v7
  - tenant_id
  - ticket_id (FK to tickets)
  - table_name (denormalized for KDS display speed)
  - waiter_name (denormalized)
  - order_number
  - status: 'new'
  - created_at: now()
  - station_id: null (MVP: single station)
          ↓
Write KitchenTicketItem rows per order item:
  - id: UUID v7
  - kitchen_ticket_id
  - product_name (denormalized)
  - quantity
  - modifier_names (JSON array of strings)
  - status: 'pending'
  - note (from order item)
```

**Denormalization rationale:** KDS must be readable without joins. Product names and modifier names are snapshotted at ticket creation. If menu changes later, the ticket still shows what was ordered.

### 3.2 KDS Screen Data Source (Single Device)

Replace `_buildDemoTickets()` with a Drift `StreamProvider`:

```dart
// New provider:
final activeKitchenTicketsProvider = StreamProvider<List<KitchenTicketWithItems>>(
  (ref) => ref.watch(kitchenRepositoryProvider)
    .watchActiveTickets(), // Drift Stream: status IN ('new', 'preparing')
);
```

The screen rebuilds automatically when new tickets arrive or are bumped. On a single device (POS + KDS on same tablet), this works entirely offline via same SQLite database.

### 3.3 Bump Action → DB Write

```dart
void _bumpTicket(String kitchenTicketId) {
  ref.read(kitchenRepositoryProvider)
    .completeTicket(kitchenTicketId);
  // Drift stream auto-removes from UI
}
```

DB write: `UPDATE kitchen_tickets SET status = 'completed', completed_at = now() WHERE id = ?`

---

## 4. Station Routing (MVP)

MVP supports a single default station. Station routing rules are in the schema but not surfaced in UI.

**MVP behavior:**
- All kitchen tickets go to all KDS instances (no filtering)
- KDS shows all tickets for the current tenant

**Phase 2 behavior (station routing):**
- Each product/category has an optional `station_id`
- KDS device configured with its `station_id` in settings
- Tickets split by station at creation time

**DB support:** `kitchen_tickets.station_id` column exists. Populate with `null` in MVP (all-stations).

---

## 5. Timer Implementation

Keep the existing logic — it is correct:

```dart
// Already in KitchenDisplayScreen:
_Urgency _getUrgency(_KitchenTicket ticket) {
  final elapsed = DateTime.now().difference(ticket.sentAt);
  if (elapsed.inMinutes >= 20) return _Urgency.critical;
  if (elapsed.inMinutes >= 10) return _Urgency.warning;
  return _Urgency.normal;
}
```

**Wire `sentAt` to `kitchen_tickets.created_at` from DB.** The color logic is correct. The 1-second refresh timer is already running.

**Make thresholds configurable** in Settings: default green < 10m, orange < 20m, red ≥ 20m.

---

## 6. Audible Alert

When a new ticket arrives (stream emits a row not previously seen):

```dart
// In _KitchenDisplayScreenState:
@override
void didUpdateWidget(...) {
  final newTickets = // tickets not in previous list
  if (newTickets.isNotEmpty) {
    _playNewTicketSound();
  }
}
```

Sound: short beep sequence (2–3 beeps). Use `audioplayers` package (already in `pubspec.yaml`). Volume respects device media volume. UI "mute" toggle in KDS settings.

---

## 7. Print Fallback

For single-device MVP: always print kitchen ticket to kitchen printer AND display on KDS (same device, same SQLite — no conflict).

For multi-device (Phase 2): If cloud is unreachable and KDS tablet is not receiving events, POS automatically prints kitchen ticket to kitchen printer.

```
IF (cloud_sync_active AND kds_subscribed_via_websocket):
    Write kitchen_ticket to DB only (KDS receives via cloud WebSocket)
ELSE:
    Write kitchen_ticket to DB AND trigger print_kitchen_ticket use case
```

`print_kitchen_ticket_use_case.dart` already exists. `KitchenTicketBuilder` implemented with 24 tests.

---

## 8. KDS Implementation Steps (Ordered)

### Step 1: KitchenRepository

```
lib/features/kitchen/data/repositories/kitchen_repository_impl.dart
```

Methods:
- `watchActiveTickets() → Stream<List<KitchenTicketWithItems>>`
- `completeTicket(String id) → Future<void>`
- `createTicketFromOrder(TicketEntity ticket, List<OrderItemEntity> items) → Future<void>`

### Step 2: KitchenTicketWithItems Model

```
lib/features/kitchen/domain/entities/kitchen_ticket_with_items.dart
```

Aggregate: `KitchenTicketEntity` + `List<KitchenTicketItemEntity>`

### Step 3: Wire KDS Screen to Provider

Replace `_buildDemoTickets()` with:
```dart
final tickets = ref.watch(activeKitchenTicketsProvider);
```

Map `KitchenTicketWithItems` to `_KitchenTicket` display model.

### Step 4: Wire POS Submit to KitchenRepository

In `OrderRepository.submitOrder()`:
```dart
await kitchenRepository.createTicketFromOrder(ticket, orderItems);
```

### Step 5: Bump Button

Replace `setState(() { _tickets.removeAt(index); })` with:
```dart
await kitchenRepository.completeTicket(ticket.id);
// Stream auto-removes — no setState needed
```

### Step 6: Stats Bar

- Pending = active tickets count (from stream)
- Completed today = separate DB query
- Preparing = tickets with status 'preparing' (always 0 in MVP — single status bump)

### Step 7: Audible Alert

Wire `audioplayers` package to stream diff detection in widget lifecycle.

### Step 8: Unit Tests

```
test/unit/kitchen/kitchen_repository_test.dart
test/unit/kitchen/kitchen_ticket_creation_test.dart
```

---

## 9. What KDS MVP Does NOT Do

| Feature | Why Deferred |
|---------|-------------|
| Item-level bump | Per-item status adds tracking complexity; most kitchens work ticket-level |
| Course fire | Requires course management in order flow — Phase 3 |
| Multi-station routing UI | Schema ready; routing rules editor deferred |
| Recall with full history | Needs bumped ticket log screen — deferred |
| Waiter notification when bumped | Requires cloud sync for cross-device notification |
| Customer pickup number display | Post-kiosk mode |
| KDS performance metrics | Post-cloud-sync |

---

## 10. Offline Behavior

**Single device:** KDS operates 100% offline. POS and KDS share the same SQLite on the same tablet. Zero cloud dependency.

**Multi-device (Phase 2, cloud-based):** If cloud is unreachable:
- KDS shows "Cloud Disconnected — Kitchen tickets not syncing" banner
- New kitchen tickets from POS print to kitchen printer automatically (fallback)
- KDS displays last-known state from its local cache
- On cloud reconnect: missed tickets synced; KDS catches up

---

## 11. Multi-Device KDS (Phase 2 — Cloud WebSocket)

For two-tablet setup (POS + KDS on separate devices):

```
POS Tablet                Cloud Hub                  KDS Tablet
    │                         │                           │
    │──createTicketFromOrder──►│                           │
    │  (outbox → HTTPS upload) │                           │
    │                         │──WebSocket push──────────►│
    │                         │  {"type":"new_ticket",    │
    │                         │   "payload": {...}}       │
    │                         │                           │── display ticket
    │                         │                           │
    │                         │◄─bump(kitchenTicketId)────│
    │                         │  (HTTPS POST)             │
    │◄──sync download──────────│                           │
    │  (ticket status update)  │                           │
```

The Go `kds` WebSocket hub already exists (`internal/kds/`). It needs:
1. Integration with the sync upload handler: when a `kitchen_ticket` is uploaded, push event to all KDS WebSocket clients subscribed to that tenant
2. Flutter WebSocket client on KDS tablet: subscribe on app start, apply events

This is straightforward and does not require any LAN infrastructure.

---

## 12. Success Criteria for KDS MVP

- [ ] New kitchen ticket appears on KDS within 2 seconds of order submit (single device)
- [ ] Timer starts from correct `created_at` timestamp
- [ ] Bump button marks ticket as completed in DB; ticket disappears from screen automatically
- [ ] Stats bar shows correct pending count
- [ ] Audible alert triggers on new ticket arrival
- [ ] KDS screen stays responsive under 20+ simultaneous tickets
- [ ] If KDS is offline/unavailable, kitchen ticket prints automatically to thermal printer
