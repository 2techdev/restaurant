# 26 - KDS MVP Design

> **Document Status:** Authoritative | **Last Updated:** 2026-03-20
>
> Kitchen Display System — minimum viable implementation on top of the existing UI skeleton.

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
| Print fallback if KDS unreachable | ✅ | |
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

### 3.2 KDS Screen Data Source

Replace `_buildDemoTickets()` with a Drift `StreamProvider`:

```dart
// New provider:
final activeKitchenTicketsProvider = StreamProvider<List<KitchenTicketWithItems>>(
  (ref) => ref.watch(kitchenRepositoryProvider)
    .watchActiveTickets(), // Drift Stream: status IN ('new', 'preparing')
);
```

The screen rebuilds automatically when new tickets arrive or tickets are bumped.

### 3.3 Bump Action → DB Write

```dart
void _bumpTicket(String kitchenTicketId) {
  ref.read(kitchenRepositoryProvider)
    .completeTicket(kitchenTicketId);
  // Drift stream will auto-remove from UI
}
```

DB write: `UPDATE kitchen_tickets SET status = 'completed', completed_at = now() WHERE id = ?`

---

## 4. Station Routing (MVP)

MVP supports a single default station. Station routing rules are prepared in the schema but not surfaced in UI yet.

**MVP behavior:**
- All kitchen tickets go to all KDS devices (no filtering)
- KDS shows all tickets for the current tenant

**Phase 2 behavior (station routing):**
- Each product/category has an optional `station_id`
- KDS device is configured with its `station_id` in settings
- Tickets are split by station: a ticket with items from two stations creates two `KitchenTicket` rows

**DB support:** `kitchen_tickets.station_id` column exists in schema. Populate with `null` in MVP (all-stations).

---

## 5. Timer Implementation

The existing timer logic is correct — keep it:

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

Sound: short beep sequence (2–3 beeps). Use Flutter `audioplayers` package or platform-native AudioManager. Volume respects device media volume. Cannot be silenced by mistake (UI "mute" in settings only).

---

## 7. Print Fallback

If KDS device is unreachable (multi-device scenario), POS automatically prints kitchen ticket to the kitchen printer.

**Logic in OrderRepository.submitOrder():**
```
IF (kds_device_registered AND kds_reachable):
    Write kitchen_ticket to DB (KDS will pick up via stream)
ELSE:
    Write kitchen_ticket to DB AND trigger print_kitchen_ticket use case
```

`print_kitchen_ticket_use_case.dart` already exists. KitchenTicketBuilder already implemented with 24 tests.

For MVP (single device): always print kitchen ticket AND display on KDS if on same device.

---

## 8. KDS Implementation Steps (Ordered)

### Step 1: KitchenRepository (new file)

```
lib/features/kitchen/data/repositories/kitchen_repository_impl.dart
```

Methods:
- `watchActiveTickets() → Stream<List<KitchenTicketWithItems>>`
- `completeTicket(String id) → Future<void>`
- `recallTicket(String id) → Future<void>` (deferred)

### Step 2: KitchenTicketWithItems model

```
lib/features/kitchen/domain/entities/kitchen_ticket_with_items.dart
```

A simple aggregate: `KitchenTicketEntity` + `List<KitchenTicketItemEntity>`

### Step 3: Wire KDS Screen to Provider

Replace `_buildDemoTickets()` call with:
```dart
final tickets = ref.watch(activeKitchenTicketsProvider);
```

Map `KitchenTicketWithItems` to `_KitchenTicket` display model (or replace display model with domain entity — either works).

### Step 4: Wire POS Submit to KitchenRepository

In `OrderRepository.submitOrder()` (or in the `OrderProvider` after submit succeeds):
```dart
await kitchenRepository.createTicketFromOrder(ticket, orderItems);
```

### Step 5: Bump Button Wire-Up

Replace `setState(() { _tickets.removeAt(index); })` with:
```dart
await kitchenRepository.completeTicket(ticket.id);
// Stream auto-removes the ticket — no setState needed
```

### Step 6: Stats Bar Wire-Up

- Pending = active tickets count (from stream)
- Preparing = tickets with status 'preparing' (manual status if implemented, else always 0)
- Completed = count completed today (separate DB query)

---

## 9. What KDS MVP Does NOT Do

| Feature | Why Deferred |
|---------|-------------|
| Item-level bump (individual item ready) | Adds per-item status tracking complexity; most kitchens work ticket-level |
| Course fire (hold course 2 until course 1 bumped) | Requires course management in order flow — Phase 2 feature |
| Multi-station routing UI | Schema ready, but routing rules editor adds setup complexity for pilot |
| Recall with full ticket history | Need bumped ticket log screen — defer |
| Waiter notification when ticket bumped | Requires push to waiter device — needs LAN sync first |
| Customer-facing pickup number display | Post-kiosk mode |
| KDS performance metrics | Post-cloud-sync |

---

## 10. Offline Behavior

KDS operates fully offline (same SQLite as POS on single device, or LAN-only on multi-device).

- No cloud dependency for KDS in v1
- Tickets written locally → KDS reads locally
- Cloud sync will replicate ticket data for reporting (Phase 3)
- Historical ticket data stays on device and in cloud after sync

---

## 11. Multi-Device KDS (Phase 2 Preview)

For two-tablet setup (POS + KDS), Phase 2 LAN sync delivers:

1. POS primary writes `kitchen_tickets` to its SQLite
2. POS primary broadcasts SSE event: `{"type": "new_kitchen_ticket", "id": "uuid"}`
3. KDS secondary listens to SSE stream from primary
4. KDS secondary: on new event, re-query local SQLite OR receive full ticket payload in SSE
5. Bump on KDS secondary: POST /lan/kitchen-tickets/{id}/complete → primary applies to DB

This is straightforward and does not require the full cloud sync engine.

---

## 12. Success Criteria for KDS MVP

- [ ] New kitchen ticket appears on KDS within 2 seconds of order submit (single device)
- [ ] Timer starts from correct `created_at` timestamp
- [ ] Bump button marks ticket as completed in DB; ticket disappears from screen
- [ ] Stats bar shows correct pending count
- [ ] Audible alert triggers on new ticket arrival
- [ ] KDS screen stays responsive under 20+ simultaneous tickets
- [ ] If KDS is not available, kitchen ticket prints automatically
