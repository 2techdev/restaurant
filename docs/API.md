# GastroCore — REST API Reference

**Base URL:** `https://your-server.com/api/v1`
**OpenAPI UI:** `https://your-server.com/docs`
**OpenAPI JSON:** `https://your-server.com/docs/swagger.json`

## Authentication

All endpoints require a JWT Bearer token **except**:
- `GET /health`
- `POST /api/v1/auth/login`
- `POST /api/v1/auth/refresh`
- `POST /api/v1/devices/register`
- `GET /api/v1/online/menu`
- `POST /api/v1/online/orders`
- `GET /api/v1/online/demo`

```
Authorization: Bearer <jwt>
Content-Type: application/json
```

Tokens expire after **24 hours**. Use `/auth/refresh` with your refresh token to obtain a new access token.

---

## Table of Contents

- [Health](#health)
- [Auth](#auth)
- [Devices](#devices)
- [Sync](#sync)
- [Menu](#menu)
- [Orders](#orders)
- [KDS](#kds)
- [Reports](#reports)
- [Online Ordering](#online-ordering)
- [Licenses](#licenses)
- [Stores](#stores)
- [Error Responses](#error-responses)
- [WebSocket Endpoints](#websocket-endpoints)

---

## Health

### `GET /health`

Returns server and database status. No authentication required.

**Response 200:**
```json
{
  "status": "ok",
  "version": "0.1.0",
  "db": "ok",
  "timestamp": "2026-03-21T14:30:00Z"
}
```

**Response 503** (database unreachable):
```json
{
  "status": "degraded",
  "db": "error: connection refused",
  "timestamp": "2026-03-21T14:30:00Z"
}
```

---

## Auth

### `POST /api/v1/auth/login`

Authenticate a staff member with PIN and receive a JWT.

**Request:**
```json
{
  "tenant_id": "550e8400-e29b-41d4-a716-446655440000",
  "device_id": "d1e2f3a4-b5c6-7890-abcd-ef1234567890",
  "pin": "1234"
}
```

**Response 200:**
```json
{
  "access_token": "eyJhbGciOiJFZERTQSJ9...",
  "refresh_token": "eyJhbGciOiJFZERTQSJ9...",
  "expires_in": 86400,
  "user": {
    "id": "7f3c9a2b-1234-5678-abcd-000000000001",
    "name": "Maria Meier",
    "role": "manager",
    "permissions": ["orders:write", "reports:read", "shifts:manage"]
  }
}
```

**Response 401:**
```json
{ "error": "invalid_pin" }
```

---

### `POST /api/v1/auth/refresh`

Exchange a refresh token for a new access token.

**Request:**
```json
{
  "refresh_token": "eyJhbGciOiJFZERTQSJ9..."
}
```

**Response 200:**
```json
{
  "access_token": "eyJhbGciOiJFZERTQSJ9...",
  "expires_in": 86400
}
```

---

## Devices

### `POST /api/v1/devices/register`

Register a new device and receive a device JWT. Called once per device installation.

**Request:**
```json
{
  "tenant_id": "550e8400-e29b-41d4-a716-446655440000",
  "device_id": "d1e2f3a4-b5c6-7890-abcd-ef1234567890",
  "device_type": "pos",
  "name": "Counter 1",
  "registration_code": "ABC-123"
}
```

`device_type`: `pos` | `kiosk` | `kds` | `ods` | `waiter`

**Response 201:**
```json
{
  "device_token": "eyJhbGciOiJFZERTQSJ9...",
  "expires_in": 2592000
}
```

---

### `GET /api/v1/devices`

List all registered devices for the tenant.

**Response 200:**
```json
{
  "devices": [
    {
      "id": "d1e2f3a4-b5c6-7890-abcd-ef1234567890",
      "name": "Counter 1",
      "device_type": "pos",
      "last_seen_at": "2026-03-21T12:00:00Z",
      "is_active": true
    }
  ]
}
```

---

## Sync

### `POST /api/v1/sync/push`

Upload a batch of change events from a device to the cloud. The server applies them to PostgreSQL and fans out to other connected devices.

**Request:**
```json
{
  "device_id": "d1e2f3a4-b5c6-7890-abcd-ef1234567890",
  "tenant_id": "550e8400-e29b-41d4-a716-446655440000",
  "events": [
    {
      "id": "evt-uuid-001",
      "table_name": "tickets",
      "record_id": "tkt-uuid-001",
      "operation": "insert",
      "payload": {
        "id": "tkt-uuid-001",
        "tenant_id": "550e8400...",
        "order_number": "T-0042",
        "status": "open",
        "order_type": "dine_in",
        "table_id": "tbl-uuid-001",
        "total_amount": 3450,
        "created_at": "2026-03-21T13:00:00Z",
        "updated_at": "2026-03-21T13:00:00Z"
      },
      "created_at": "2026-03-21T13:00:00Z"
    }
  ]
}
```

`operation`: `insert` | `update` | `delete`

Max batch size: **100 events** per request.

**Response 200:**
```json
{
  "accepted": 1,
  "rejected": 0,
  "errors": []
}
```

**Response 207** (partial success):
```json
{
  "accepted": 5,
  "rejected": 1,
  "errors": [
    { "event_id": "evt-uuid-006", "reason": "conflict: stale timestamp" }
  ]
}
```

---

### `GET /api/v1/sync/pull`

Download changes that occurred after a given sequence number. Returns only changes relevant to the requesting device type.

**Query Parameters:**

| Parameter | Type | Required | Description |
|---|---|---|---|
| `since_seq` | integer | yes | Last sequence number received (0 for initial sync) |
| `limit` | integer | no | Max events to return (default 200, max 500) |

**Response 200:**
```json
{
  "events": [
    {
      "seq": 1042,
      "table_name": "products",
      "record_id": "prd-uuid-001",
      "operation": "update",
      "payload": { ... },
      "device_id": "d9e8f7a6-...",
      "created_at": "2026-03-21T12:30:00Z"
    }
  ],
  "next_seq": 1043,
  "has_more": false
}
```

---

### `GET /api/v1/sync/status`

Returns sync statistics for the device.

**Response 200:**
```json
{
  "device_id": "d1e2f3a4-...",
  "pending_pull_count": 3,
  "last_pushed_at": "2026-03-21T13:01:00Z",
  "last_pulled_at": "2026-03-21T13:01:05Z",
  "server_seq": 1043
}
```

---

## Menu

### `GET /api/v1/menu/categories`

**Query Parameters:** `include_inactive=true` (default false)

**Response 200:**
```json
{
  "categories": [
    {
      "id": "cat-uuid-001",
      "name": "Hauptgerichte",
      "display_order": 1,
      "color": "#FF5722",
      "icon": "restaurant",
      "parent_id": null,
      "is_active": true
    }
  ]
}
```

---

### `GET /api/v1/menu/products`

**Query Parameters:** `category_id`, `include_inactive=true`, `search`

**Response 200:**
```json
{
  "products": [
    {
      "id": "prd-uuid-001",
      "category_id": "cat-uuid-001",
      "name": "Zürich Geschnetzeltes",
      "description": "Mit Rösti, Saison-Salat",
      "price": 2850,
      "cost_price": 850,
      "tax_group": "food",
      "image_path": null,
      "barcode": null,
      "is_active": true,
      "display_order": 1,
      "prep_time_minutes": 15,
      "printer_group": "kitchen"
    }
  ]
}
```

> All monetary values are in **cents** (CHF rappen). 2850 = CHF 28.50.

---

### `POST /api/v1/menu/products`

**Request:**
```json
{
  "category_id": "cat-uuid-001",
  "name": "Rösti",
  "price": 1490,
  "tax_group": "food",
  "printer_group": "kitchen"
}
```

**Response 201:**
```json
{ "id": "prd-uuid-new", ... }
```

---

### `PATCH /api/v1/menu/products/:id`

Partial update. Only send fields to change.

**Request:**
```json
{ "price": 1590, "is_active": false }
```

**Response 200:** Updated product object.

---

### `GET /api/v1/menu/modifier-groups`

Returns all modifier groups with their modifiers.

**Response 200:**
```json
{
  "modifier_groups": [
    {
      "id": "mg-uuid-001",
      "name": "Grösse",
      "selection_type": "single",
      "is_required": true,
      "modifiers": [
        { "id": "mod-001", "name": "Klein", "price_delta": 0 },
        { "id": "mod-002", "name": "Gross", "price_delta": 300 }
      ]
    }
  ]
}
```

---

## Orders

### `POST /api/v1/orders/tickets`

Create a new order ticket.

**Request:**
```json
{
  "table_id": "tbl-uuid-001",
  "order_type": "dine_in",
  "channel": "pos",
  "cover_count": 2,
  "items": [
    {
      "product_id": "prd-uuid-001",
      "quantity": 1,
      "unit_price": 2850,
      "modifiers": [
        { "modifier_id": "mod-001", "price_delta": 0 }
      ],
      "notes": "ohne Zwiebeln"
    }
  ]
}
```

`order_type`: `dine_in` | `takeaway` | `delivery` | `online`
`channel`: `pos` | `waiter` | `qr` | `kiosk` | `web`

**Response 201:**
```json
{
  "id": "tkt-uuid-001",
  "order_number": "T-0042",
  "status": "open",
  "total_amount": 2850,
  "subtotal": 2850,
  "tax_amount": 232,
  "created_at": "2026-03-21T13:00:00Z"
}
```

---

### `GET /api/v1/orders/tickets/:id`

**Response 200:** Full ticket with items, modifiers, payments.

---

### `PATCH /api/v1/orders/tickets/:id`

Update ticket status or order type.

**Request:**
```json
{
  "status": "bill_requested",
  "order_type": "takeaway"
}
```

`status` transitions:
```
draft → open → sent → in_progress → ready → served → bill_requested → completed
                                                                      ↓
                                                               cancelled | voided
```

**Response 200:** Updated ticket object.

---

### `POST /api/v1/orders/tickets/:id/items`

Add an item to an existing ticket.

**Request:**
```json
{
  "product_id": "prd-uuid-002",
  "quantity": 2,
  "unit_price": 450,
  "notes": ""
}
```

**Response 201:** New order item.

---

### `DELETE /api/v1/orders/tickets/:id/items/:item_id`

Remove a line item from a ticket. Requires manager role.

**Response 204**

---

### `POST /api/v1/orders/bills`

Generate a bill for a ticket (or split bill).

**Request:**
```json
{
  "ticket_id": "tkt-uuid-001",
  "items": ["item-uuid-001", "item-uuid-002"],
  "discount_type": "percentage",
  "discount_value": 10
}
```

`discount_type`: `none` | `fixed` | `percentage`

**Response 201:**
```json
{
  "id": "bill-uuid-001",
  "ticket_id": "tkt-uuid-001",
  "subtotal": 5700,
  "discount_amount": 570,
  "tax_amount": 422,
  "total": 5130,
  "rounding_amount": 0,
  "grand_total": 5130
}
```

---

### `POST /api/v1/orders/payments`

Record a payment against a bill.

**Request:**
```json
{
  "bill_id": "bill-uuid-001",
  "method": "card",
  "amount": 5130,
  "tip": 200,
  "reference": "VISA-TXN-12345"
}
```

`method`: `cash` | `card` | `twint` | `wallee` | `mypos` | `voucher`

**Response 201:**
```json
{
  "id": "pay-uuid-001",
  "bill_id": "bill-uuid-001",
  "method": "card",
  "amount": 5130,
  "tip": 200,
  "change": 0,
  "reference": "VISA-TXN-12345",
  "created_at": "2026-03-21T13:15:00Z"
}
```

---

## KDS

### `GET /api/v1/kds/tickets`

List active kitchen tickets in queue order.

**Query Parameters:** `status=pending,in_progress`, `limit=50`

**Response 200:**
```json
{
  "tickets": [
    {
      "id": "kt-uuid-001",
      "order_number": "T-0042",
      "table_label": "Tisch 5",
      "status": "pending",
      "items": [
        {
          "id": "kti-uuid-001",
          "product_name": "Rösti",
          "quantity": 2,
          "notes": "extra knusprig",
          "status": "pending"
        }
      ],
      "created_at": "2026-03-21T13:00:00Z",
      "elapsed_seconds": 127
    }
  ]
}
```

---

### `PATCH /api/v1/kds/tickets/:id`

Update kitchen ticket status.

**Request:**
```json
{ "status": "in_progress" }
```

`status`: `pending` | `in_progress` | `ready` | `served`

---

## Reports

All report endpoints accept `start_date` and `end_date` query parameters (ISO 8601 date, e.g. `2026-03-01`).

### `GET /api/v1/reports/sales`

Daily sales summary.

**Query Parameters:** `start_date`, `end_date`, `group_by=day|week|month`

**Response 200:**
```json
{
  "period": { "start": "2026-03-01", "end": "2026-03-21" },
  "totals": {
    "revenue": 1245600,
    "tax_amount": 101250,
    "discount_amount": 24000,
    "order_count": 412,
    "avg_order_value": 3024
  },
  "by_day": [
    {
      "date": "2026-03-21",
      "revenue": 68400,
      "tax_a": 4200,
      "tax_b": 820,
      "order_count": 23
    }
  ]
}
```

---

### `GET /api/v1/reports/products`

Product performance (quantity sold, revenue).

**Response 200:**
```json
{
  "products": [
    {
      "product_id": "prd-uuid-001",
      "name": "Zürich Geschnetzeltes",
      "quantity_sold": 87,
      "revenue": 247950,
      "avg_price": 2850
    }
  ]
}
```

---

### `GET /api/v1/reports/shifts`

Shift summary with opening/closing cash and totals.

**Response 200:**
```json
{
  "shifts": [
    {
      "id": "shift-uuid-001",
      "user_name": "Maria Meier",
      "opened_at": "2026-03-21T07:00:00Z",
      "closed_at": "2026-03-21T16:00:00Z",
      "opening_cash": 20000,
      "closing_cash": 73400,
      "cash_revenue": 53400,
      "card_revenue": 120500,
      "total_revenue": 173900,
      "order_count": 58
    }
  ]
}
```

---

## Online Ordering

These endpoints are unauthenticated (public-facing for QR menus and web ordering).

### `GET /api/v1/online/menu`

Returns the active public menu for a tenant.

**Query Parameters:** `tenant_id` (required)

**Response 200:**
```json
{
  "tenant": {
    "name": "Restaurant Helvetia",
    "currency": "CHF"
  },
  "categories": [
    {
      "id": "cat-uuid-001",
      "name": "Hauptgerichte",
      "products": [
        {
          "id": "prd-uuid-001",
          "name": "Zürich Geschnetzeltes",
          "description": "Mit Rösti und Salat",
          "price": 2850,
          "modifier_groups": [...]
        }
      ]
    }
  ]
}
```

---

### `POST /api/v1/online/orders`

Submit an order from the web ordering interface or QR menu.

**Request:**
```json
{
  "tenant_id": "550e8400-e29b-41d4-a716-446655440000",
  "order_type": "dine_in",
  "table_id": "tbl-uuid-001",
  "customer_name": "Tisch 3",
  "items": [
    {
      "product_id": "prd-uuid-001",
      "quantity": 2,
      "modifiers": [],
      "notes": ""
    }
  ]
}
```

The server:
1. Creates the ticket
2. Dispatches a kitchen notification via KDS hub
3. Returns an order number for display

**Response 201:**
```json
{
  "order_id": "tkt-uuid-new",
  "order_number": "T-0043",
  "estimated_minutes": 15,
  "message": "Ihre Bestellung wurde aufgenommen!"
}
```

---

### `GET /api/v1/online/demo`

Returns the demo ordering page HTML (served at `pos.2tech.ch/demo`). No authentication required.

---

## Licenses

### `GET /api/v1/licenses/status`

Returns the license tier and feature flags for the current tenant.

**Response 200:**
```json
{
  "tenant_id": "550e8400-...",
  "tier": "professional",
  "expires_at": "2027-03-21T00:00:00Z",
  "features": [
    "cloud_sync", "kds", "advanced_reports", "custom_receipts",
    "multi_device_lan", "unlimited_menu"
  ],
  "max_devices": 10
}
```

---

### `POST /api/v1/licenses/validate`

Validate a license token string.

**Request:**
```json
{ "token": "eyJhbGciOiJFZERTQSJ9..." }
```

**Response 200:** Same as `/licenses/status`
**Response 422:** `{ "error": "invalid_signature" }` | `{ "error": "token_expired" }`

---

## Stores

### `GET /api/v1/stores`

List all stores for a multi-location enterprise tenant.

**Response 200:**
```json
{
  "stores": [
    {
      "id": "store-uuid-001",
      "name": "Zürich HB",
      "address": "Bahnhofplatz 1, 8001 Zürich",
      "is_active": true
    }
  ]
}
```

---

## Error Responses

All errors use a consistent JSON envelope:

```json
{
  "error": "error_code",
  "message": "Human-readable description",
  "details": {}
}
```

| HTTP Status | Error Code | Meaning |
|---|---|---|
| 400 | `bad_request` | Malformed JSON or missing required fields |
| 401 | `unauthorized` | Missing or invalid JWT |
| 403 | `forbidden` | Valid JWT but insufficient permissions |
| 404 | `not_found` | Resource does not exist |
| 409 | `conflict` | Unique constraint violation |
| 422 | `unprocessable` | Validation error (wrong enum value, etc.) |
| 429 | `rate_limited` | Exceeded 200 req/min |
| 500 | `internal_error` | Server error (check server logs) |
| 503 | `service_unavailable` | Database unreachable |

---

## WebSocket Endpoints

### `GET /ws/sync`

Real-time sync stream. Upgrade to WebSocket.

**Handshake query parameters:** `tenant_id`, `device_id`
**Auth:** `Authorization` header or `?token=<jwt>` query parameter.

**Server → Client messages:**

```json
{
  "type": "sync_event",
  "seq": 1044,
  "table_name": "tickets",
  "record_id": "tkt-uuid-001",
  "operation": "update",
  "payload": { ... }
}
```

```json
{
  "type": "ping"
}
```

**Client → Server messages:**
```json
{ "type": "pong" }
```

Connection is closed by the server after 30 seconds of inactivity (no pong). Clients should reconnect with exponential backoff.

---

### `GET /ws/kds`

Kitchen Display Screen notification stream.

**Server → Client messages:**
```json
{
  "type": "new_order",
  "ticket_id": "tkt-uuid-001",
  "order_number": "T-0043",
  "tenant_id": "550e8400-..."
}
```

```json
{
  "type": "item_ready",
  "ticket_id": "tkt-uuid-001",
  "item_id": "kti-uuid-001"
}
```

```json
{
  "type": "ticket_cancelled",
  "ticket_id": "tkt-uuid-001"
}
```
