# GastroCore — Database Reference

## Table of Contents

- [Overview](#overview)
- [Dual-Database Architecture](#dual-database-architecture)
- [Table Reference](#table-reference)
- [Indexes & Performance](#indexes--performance)
- [Materialized Views](#materialized-views)
- [Triggers](#triggers)
- [Sync Metadata Tables](#sync-metadata-tables)
- [Tax & Pricing Tables](#tax--pricing-tables)
- [Migration Guide](#migration-guide)
- [Schema Conventions](#schema-conventions)

---

## Overview

GastroCore uses two databases:

| | Device (SQLite) | Cloud (PostgreSQL 16) |
|---|---|---|
| ORM | Drift 2.22 | `database/sql` (raw SQL) |
| ID type | TEXT (UUID string) | UUID (native) |
| JSON | TEXT (JSON string) | JSONB |
| Timestamps | INTEGER (epoch ms) | TIMESTAMPTZ |
| Schema version | 7 (Drift migration) | 005 (SQL migrations) |

The schemas are **functionally identical** for synced tables — the type mapping differences are handled by Drift's type converters.

---

## Dual-Database Architecture

```
Device (SQLite / Drift)          Cloud (PostgreSQL)
─────────────────────────        ─────────────────────────
Synced tables (31)          ←→   Synced tables (same schema)
                                 Cloud-only tables:
                                   device_registrations
                                   tenant_subscriptions
                                   sync_events
                                   sync_batches
                                   api_keys
```

**Synced tables** are replicated bidirectionally via the push/pull sync API. **Cloud-only tables** exist only in PostgreSQL and are never sent to devices.

---

## Table Reference

### tenants

Primary multi-tenant anchor. One row per restaurant.

| Column | Type | Nullable | Description |
|---|---|---|---|
| `id` | UUID | no | Primary key |
| `name` | TEXT | no | Restaurant name |
| `address` | TEXT | yes | Full address |
| `phone` | TEXT | yes | Contact phone |
| `tax_id` | TEXT | yes | MWST-Nr (CHE-XXX.XXX.XXX) |
| `default_tax_rate` | NUMERIC(5,2) | no | Legacy; use tax_profiles instead |
| `currency_code` | TEXT | no | Default: `CHF` |
| `country_code` | TEXT | no | Default: `CH` |
| `settings` | JSONB | yes | Free-form tenant settings JSON |
| `created_at` | TIMESTAMPTZ | no | |
| `updated_at` | TIMESTAMPTZ | no | Auto-updated by trigger |

---

### users

Staff members. Authentication uses PIN, not password.

| Column | Type | Nullable | Description |
|---|---|---|---|
| `id` | UUID | no | Primary key |
| `tenant_id` | UUID | no | FK → tenants |
| `name` | TEXT | no | Display name |
| `email` | TEXT | yes | Optional — not used for login |
| `password_hash` | TEXT | yes | Reserved for future use |
| `pin_hash` | TEXT | no | bcrypt hash of 4–6 digit PIN |
| `role` | TEXT | no | `waiter` \| `bartender` \| `manager` \| `owner` |
| `is_active` | BOOLEAN | no | Soft disable without deletion |
| `permissions` | JSONB | yes | Overrides for role-based permissions |
| `is_deleted` | BOOLEAN | no | Soft delete for sync |
| `sync_status` | INTEGER | no | 0=pending, 1=synced |

**Indexes:** `(tenant_id)`, `(email)` partial, `(tenant_id, role)`

---

### categories

Menu categories. Support parent-child hierarchy.

| Column | Type | Nullable | Description |
|---|---|---|---|
| `id` | UUID | no | |
| `tenant_id` | UUID | no | FK → tenants |
| `name` | TEXT | no | Display name |
| `display_order` | INTEGER | no | Sort order in POS UI |
| `color` | TEXT | yes | Hex color for category button |
| `icon` | TEXT | yes | Icon identifier |
| `parent_id` | UUID | yes | FK → categories (self-referential) |
| `is_active` | BOOLEAN | no | |
| `is_deleted` | BOOLEAN | no | |

---

### products

Menu items. `price` is always in cents (Rappen).

| Column | Type | Nullable | Description |
|---|---|---|---|
| `id` | UUID | no | |
| `tenant_id` | UUID | no | FK → tenants |
| `category_id` | UUID | no | FK → categories |
| `name` | TEXT | no | |
| `description` | TEXT | yes | |
| `price` | BIGINT | no | Price in cents (e.g. 2850 = CHF 28.50) |
| `cost_price` | BIGINT | no | Cost in cents (for margin reports) |
| `tax_group` | TEXT | no | `food` \| `beverage` \| `alcohol` \| `accommodation` \| `default` |
| `image_path` | TEXT | yes | Relative path or URL |
| `barcode` | TEXT | yes | EAN/UPC for scanner |
| `is_active` | BOOLEAN | no | |
| `display_order` | INTEGER | no | |
| `prep_time_minutes` | INTEGER | yes | Estimated preparation time |
| `printer_group` | TEXT | no | `kitchen` \| `bar` \| `none` |
| `is_deleted` | BOOLEAN | no | |

**Indexes:** `(tenant_id)`, `(category_id)`, `(barcode)` partial, `(tenant_id, is_active)` partial

---

### modifier_groups

Groups of optional or required product modifications (e.g. "Size", "Extras").

| Column | Type | Nullable | Description |
|---|---|---|---|
| `id` | UUID | no | |
| `tenant_id` | UUID | no | |
| `name` | TEXT | no | e.g. "Grösse" |
| `selection_type` | TEXT | no | `single` \| `multiple` |
| `is_required` | BOOLEAN | no | Must select one if true |
| `min_selections` | INTEGER | yes | Minimum choices |
| `max_selections` | INTEGER | yes | Maximum choices |
| `display_order` | INTEGER | no | |
| `is_deleted` | BOOLEAN | no | |

---

### modifiers

Individual modifier options within a group.

| Column | Type | Nullable | Description |
|---|---|---|---|
| `id` | UUID | no | |
| `group_id` | UUID | no | FK → modifier_groups |
| `name` | TEXT | no | e.g. "Gross" |
| `price_delta` | BIGINT | no | Price adjustment in cents (can be negative) |
| `display_order` | INTEGER | no | |
| `is_active` | BOOLEAN | no | |
| `is_deleted` | BOOLEAN | no | |

---

### product_modifier_groups

Join table linking products to modifier groups.

| Column | Type | Description |
|---|---|---|
| `product_id` | UUID | FK → products |
| `modifier_group_id` | UUID | FK → modifier_groups |
| `display_order` | INTEGER | |

---

### floors

Restaurant floor plans.

| Column | Type | Description |
|---|---|---|
| `id` | UUID | |
| `tenant_id` | UUID | |
| `name` | TEXT | e.g. "Hauptsaal", "Terrasse" |
| `is_active` | BOOLEAN | |
| `display_order` | INTEGER | |

---

### restaurant_tables

Individual tables within a floor. Position fields enable visual floor plan editor.

| Column | Type | Nullable | Description |
|---|---|---|---|
| `id` | UUID | no | |
| `tenant_id` | UUID | no | |
| `floor_id` | UUID | no | FK → floors |
| `label` | TEXT | no | e.g. "Tisch 5" |
| `capacity` | INTEGER | yes | Max covers |
| `shape` | TEXT | no | `rectangle` \| `circle` |
| `pos_x` | REAL | no | X position in floor plan (0–100) |
| `pos_y` | REAL | no | Y position in floor plan (0–100) |
| `width` | REAL | no | Width in floor plan units |
| `height` | REAL | no | Height in floor plan units |
| `status` | TEXT | no | `free` \| `occupied` \| `reserved` \| `cleaning` |
| `is_active` | BOOLEAN | no | |

---

### tickets

The central order document. One ticket per table session or takeaway order.

| Column | Type | Nullable | Description |
|---|---|---|---|
| `id` | UUID | no | |
| `tenant_id` | UUID | no | |
| `device_id` | UUID | no | Originating device |
| `order_number` | TEXT | no | Human-readable (e.g. "T-0042") |
| `table_id` | UUID | yes | FK → restaurant_tables |
| `table_label` | TEXT | yes | Denormalized snapshot |
| `status` | TEXT | no | See status machine below |
| `order_type` | TEXT | no | `dine_in` \| `takeaway` \| `delivery` \| `online` |
| `channel` | TEXT | no | `pos` \| `waiter` \| `qr` \| `kiosk` \| `web` |
| `cover_count` | INTEGER | no | Number of guests |
| `subtotal` | BIGINT | no | Sum of item prices (cents) |
| `discount_type` | TEXT | no | `none` \| `fixed` \| `percentage` |
| `discount_value` | BIGINT | no | Discount amount/percentage |
| `discount_amount` | BIGINT | no | Calculated discount in cents |
| `tax_amount` | BIGINT | no | Total extracted tax in cents |
| `total_amount` | BIGINT | no | Final total in cents |
| `notes` | TEXT | yes | Free-form order notes |
| `is_deleted` | BOOLEAN | no | |
| `created_at` / `updated_at` | TIMESTAMPTZ | no | |

**Ticket status machine:**
```
draft → open → sent → in_progress → ready → served → bill_requested → completed
                                                                      ↓
                                                               cancelled | voided
```

**Indexes:** `(tenant_id, status)`, `(table_id)`, `(device_id)`, `(order_number)` unique

---

### order_items

Line items within a ticket. Tax is snapshotted at order time.

| Column | Type | Nullable | Description |
|---|---|---|---|
| `id` | UUID | no | |
| `ticket_id` | UUID | no | FK → tickets |
| `tenant_id` | UUID | no | |
| `product_id` | UUID | yes | FK → products (null if product deleted) |
| `product_name` | TEXT | no | Snapshot of name at order time |
| `quantity` | REAL | no | Supports 0.5 portions |
| `unit_price` | BIGINT | no | Price per unit in cents at order time |
| `price_delta` | BIGINT | no | Modifier price adjustments |
| `subtotal` | BIGINT | no | `quantity × (unit_price + price_delta)` |
| `discount_amount` | BIGINT | no | Item-level discount |
| `tax_group` | TEXT | no | Snapshot of product tax_group |
| `tax_amount` | BIGINT | no | Extracted tax for this item |
| `notes` | TEXT | yes | Staff notes (e.g. "ohne Zwiebeln") |
| `status` | TEXT | no | `pending` \| `sent` \| `in_progress` \| `ready` \| `served` |
| `is_deleted` | BOOLEAN | no | |

---

### order_item_modifiers

Applied modifiers on a line item.

| Column | Type | Description |
|---|---|---|
| `id` | UUID | |
| `order_item_id` | UUID | FK → order_items |
| `modifier_id` | UUID | FK → modifiers |
| `modifier_name` | TEXT | Snapshot |
| `price_delta` | BIGINT | Price adjustment in cents |

---

### bills

Bill records. A ticket can have multiple bills for split-bill scenarios.

| Column | Type | Description |
|---|---|---|
| `id` | UUID | |
| `ticket_id` | UUID | FK → tickets |
| `tenant_id` | UUID | |
| `subtotal` | BIGINT | |
| `discount_amount` | BIGINT | |
| `tax_amount` | BIGINT | |
| `total` | BIGINT | |
| `rounding_amount` | BIGINT | CHF 5-Rappen rounding (cents) |
| `grand_total` | BIGINT | total + rounding_amount |
| `is_paid` | BOOLEAN | |

---

### payments

Individual payment transactions against a bill.

| Column | Type | Description |
|---|---|---|
| `id` | UUID | |
| `bill_id` | UUID | FK → bills |
| `tenant_id` | UUID | |
| `method` | TEXT | `cash` \| `card` \| `twint` \| `wallee` \| `mypos` \| `voucher` |
| `amount` | BIGINT | Amount paid in cents |
| `tip` | BIGINT | Tip in cents |
| `change` | BIGINT | Change given in cents (cash only) |
| `reference` | TEXT | Terminal transaction reference |
| `created_at` | TIMESTAMPTZ | |

---

### shifts

Staff shifts with opening/closing cash for reconciliation.

| Column | Type | Description |
|---|---|---|
| `id` | UUID | |
| `tenant_id` | UUID | |
| `user_id` | UUID | FK → users |
| `opened_at` | TIMESTAMPTZ | |
| `closed_at` | TIMESTAMPTZ (nullable) | Null if still open |
| `opening_cash` | BIGINT | Opening float in cents |
| `closing_cash` | BIGINT (nullable) | Actual closing cash |
| `expected_cash` | BIGINT (nullable) | Calculated expected cash |
| `status` | TEXT | `open` \| `closed` |
| `notes` | TEXT (nullable) | |

---

### cash_movements

Cash in/out records within a shift (e.g. petty cash, float adjustments).

| Column | Type | Description |
|---|---|---|
| `id` | UUID | |
| `shift_id` | UUID | FK → shifts |
| `tenant_id` | UUID | |
| `amount` | BIGINT | Positive = in, negative = out |
| `reason` | TEXT | Description of movement |
| `created_at` | TIMESTAMPTZ | |

---

### kitchen_tickets

Kitchen display queue entries. Created from `tickets` when order is sent.

| Column | Type | Description |
|---|---|---|
| `id` | UUID | |
| `ticket_id` | UUID | FK → tickets |
| `tenant_id` | UUID | |
| `order_number` | TEXT | Denormalized for display |
| `table_label` | TEXT | Denormalized for display |
| `status` | TEXT | `pending` \| `in_progress` \| `ready` \| `served` |
| `priority` | INTEGER | Higher = more urgent |
| `notes` | TEXT (nullable) | |
| `created_at` | TIMESTAMPTZ | Used for elapsed time calculation |

---

### kitchen_ticket_items

Line items on the kitchen display.

| Column | Type | Description |
|---|---|---|
| `id` | UUID | |
| `kitchen_ticket_id` | UUID | FK → kitchen_tickets |
| `order_item_id` | UUID | FK → order_items |
| `product_name` | TEXT | Snapshot |
| `quantity` | REAL | |
| `notes` | TEXT (nullable) | |
| `status` | TEXT | `pending` \| `in_progress` \| `ready` |

---

### receipts

Stored receipt records with pre-rendered ESC-POS content.

| Column | Type | Description |
|---|---|---|
| `id` | UUID | |
| `ticket_id` | UUID | FK → tickets |
| `bill_id` | UUID | FK → bills |
| `tenant_id` | UUID | |
| `receipt_number` | TEXT | Sequential receipt number |
| `escpos_content` | JSONB | Pre-rendered ESC-POS command array |
| `printed_at` | TIMESTAMPTZ (nullable) | |
| `reprint_count` | INTEGER | |

---

### tax_profiles

Named tax rate configurations per tenant.

| Column | Type | Description |
|---|---|---|
| `id` | UUID | |
| `tenant_id` | UUID | |
| `name` | TEXT | e.g. "Switzerland Standard" |
| `food_rate` | NUMERIC(5,2) | Standard food rate |
| `food_takeaway_rate` | NUMERIC(5,2) | Takeaway food rate |
| `beverage_rate` | NUMERIC(5,2) | |
| `alcohol_rate` | NUMERIC(5,2) | |
| `accommodation_rate` | NUMERIC(5,2) | |
| `effective_from` | DATE | When this profile takes effect |
| `is_active` | BOOLEAN | |

---

### sync_queue

Outbox for offline-first sync. One row per pending change event on device.

| Column | Type | Description |
|---|---|---|
| `id` | UUID | |
| `table_name` | TEXT | Target table name |
| `record_id` | TEXT | UUID of the changed record |
| `operation` | TEXT | `insert` \| `update` \| `delete` |
| `payload` | TEXT | Full entity JSON |
| `device_id` | TEXT | Originating device UUID |
| `status` | TEXT | `pending` \| `uploading` \| `uploaded` \| `failed` |
| `retry_count` | INTEGER | Failed upload attempts |
| `created_at` | INTEGER | Epoch ms |

---

### audit_log

Immutable action log. Never soft-deleted.

| Column | Type | Description |
|---|---|---|
| `id` | UUID | |
| `tenant_id` | UUID | |
| `user_id` | UUID (nullable) | Actor (null for system actions) |
| `device_id` | TEXT | |
| `action` | TEXT | e.g. `ticket.void`, `payment.refund` |
| `table_name` | TEXT | Affected table |
| `record_id` | TEXT | Affected record UUID |
| `old_value` | JSONB (nullable) | Previous state |
| `new_value` | JSONB (nullable) | New state |
| `created_at` | TIMESTAMPTZ | |

---

### license_tokens

Stored license token strings per device.

| Column | Type | Description |
|---|---|---|
| `id` | UUID | |
| `tenant_id` | UUID | |
| `token` | TEXT | Ed25519-signed JWT-like string |
| `tier` | TEXT | `free` \| `professional` \| `enterprise` |
| `expires_at` | TIMESTAMPTZ | |
| `activated_at` | TIMESTAMPTZ | |

---

### inventory_items

Stock tracking for ingredient/product inventory.

| Column | Type | Description |
|---|---|---|
| `id` | UUID | |
| `tenant_id` | UUID | |
| `name` | TEXT | |
| `unit` | TEXT | e.g. `kg`, `l`, `piece` |
| `quantity` | REAL | Current stock level |
| `reorder_level` | REAL (nullable) | Alert threshold |
| `supplier_id` | UUID (nullable) | FK → suppliers |
| `is_deleted` | BOOLEAN | |

---

### inventory_transactions

Stock movements (deliveries, usage, waste).

| Column | Type | Description |
|---|---|---|
| `id` | UUID | |
| `item_id` | UUID | FK → inventory_items |
| `tenant_id` | UUID | |
| `type` | TEXT | `delivery` \| `usage` \| `waste` \| `adjustment` |
| `quantity` | REAL | Positive = in, negative = out |
| `unit_cost` | BIGINT (nullable) | For delivery costing |
| `reference` | TEXT (nullable) | Invoice/order reference |
| `created_at` | TIMESTAMPTZ | |

---

### suppliers

Vendor master data for inventory.

| Column | Type | Description |
|---|---|---|
| `id` | UUID | |
| `tenant_id` | UUID | |
| `name` | TEXT | |
| `contact_name` | TEXT (nullable) | |
| `email` | TEXT (nullable) | |
| `phone` | TEXT (nullable) | |
| `is_deleted` | BOOLEAN | |

---

## Indexes & Performance

Critical query patterns and their covering indexes:

| Query pattern | Index |
|---|---|
| List open tickets by tenant | `(tenant_id, status)` on tickets |
| Menu by category | `(category_id)` on products |
| Active products | `(tenant_id, is_active) WHERE is_deleted = FALSE` |
| Ticket by order number | `(order_number)` UNIQUE on tickets |
| Sync events since timestamp | `(tenant_id, created_at)` on sync_events |
| Kitchen queue | `(tenant_id, status, created_at)` on kitchen_tickets |

---

## Materialized Views

Used for reports to avoid expensive aggregations on every request.

### `mv_daily_sales`

```sql
-- Refreshed nightly (or on demand)
SELECT
    tenant_id,
    date_trunc('day', created_at)::DATE AS day,
    COUNT(*)                            AS order_count,
    SUM(total_amount)                   AS revenue,
    SUM(tax_amount)                     AS tax_total,
    SUM(discount_amount)                AS discount_total,
    AVG(total_amount)::BIGINT           AS avg_order_value
FROM tickets
WHERE status = 'completed' AND is_deleted = FALSE
GROUP BY tenant_id, day;

CREATE UNIQUE INDEX ON mv_daily_sales(tenant_id, day);
```

Refresh: `REFRESH MATERIALIZED VIEW CONCURRENTLY mv_daily_sales;`

### `mv_product_performance`

```sql
SELECT
    oi.tenant_id,
    oi.product_id,
    oi.product_name,
    SUM(oi.quantity)  AS quantity_sold,
    SUM(oi.subtotal)  AS revenue
FROM order_items oi
JOIN tickets t ON t.id = oi.ticket_id
WHERE t.status = 'completed' AND oi.is_deleted = FALSE
GROUP BY oi.tenant_id, oi.product_id, oi.product_name;
```

---

## Triggers

All mutable tables have an `updated_at` auto-update trigger:

```sql
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Applied to: tenants, users, categories, products, tickets,
--             order_items, bills, payments, shifts, kitchen_tickets, ...
CREATE TRIGGER update_<table>_updated_at
    BEFORE UPDATE ON <table>
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
```

This means `updated_at` is always server-authoritative for conflict resolution in sync.

---

## Sync Metadata Tables (Cloud-only)

### `device_registrations`

| Column | Description |
|---|---|
| `device_id` | UUID from device |
| `tenant_id` | |
| `device_type` | `pos` \| `kiosk` \| `kds` \| `ods` \| `waiter` |
| `name` | Human label |
| `token_hash` | SHA-256 of device JWT |
| `last_seen_at` | |
| `is_active` | |

### `sync_events` (server-side outbox)

Server's copy of all change events, used for pull queries.

| Column | Description |
|---|---|
| `seq` | BIGSERIAL — monotonic sequence for pull cursor |
| `tenant_id` | |
| `device_id` | Source device |
| `table_name` | |
| `record_id` | |
| `operation` | `insert` \| `update` \| `delete` |
| `payload` | JSONB entity snapshot |
| `created_at` | |

Index: `(tenant_id, seq)` for efficient pull queries.

---

## Migration Guide

### Running migrations

```bash
# Via Docker
docker-compose exec gastrocore-server /app/gastrocore-server migrate up

# Locally
cd server
DATABASE_URL="postgres://..." go run ./cmd/migrate up
```

### Creating a new migration

```bash
# Naming convention: NNN_description.{up|down}.sql
# Example: 006_add_customer_profiles.up.sql
touch server/migrations/006_add_customer_profiles.up.sql
touch server/migrations/006_add_customer_profiles.down.sql
```

Migration files are embedded in the server binary via `//go:embed`. They run on startup if pending.

### Rollback

```bash
go run ./cmd/migrate down 1    # roll back 1 migration
go run ./cmd/migrate down 3    # roll back 3 migrations
```

---

## Schema Conventions

| Convention | Example |
|---|---|
| Primary keys | UUID (`uuid_generate_v4()`) — offline-safe |
| Foreign keys | `tenant_id UUID NOT NULL REFERENCES tenants(id)` |
| Timestamps | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` |
| Soft delete | `is_deleted BOOLEAN NOT NULL DEFAULT FALSE` |
| Sync tracking | `sync_status INTEGER NOT NULL DEFAULT 0` |
| Money | `BIGINT` in cents — never NUMERIC/FLOAT |
| JSON blobs | `JSONB` in PostgreSQL, `TEXT` (JSON string) in SQLite |
| Enum columns | `TEXT` with `CHECK` constraint (not PostgreSQL enum type — easier to migrate) |
| Table naming | `snake_case`, plural (e.g. `order_items`, not `OrderItem`) |
| Column naming | `snake_case` |
| Index naming | `idx_{table}_{column(s)}` |
| Trigger naming | `update_{table}_updated_at` |
