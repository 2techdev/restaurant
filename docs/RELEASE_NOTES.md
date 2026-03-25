# GastroCore Release Notes

## v0.1.0+1 — MVP (2026-03-24)

### Overview

First complete MVP release. All six GastroCore apps (POS, Waiter, Kiosk, KDS, ODS, Online) are connected through the shared backend and demonstrated via the **Club Demo** tenant.

---

## Club Demo Tenant (`cc000000-…`)

The Club Demo is the canonical showcase restaurant used for all app demonstrations, sales demos, and testing. It is seeded by `server/cmd/seed/seed_clubdemo.go`.

### Restaurant Info

| Field       | Value                                                         |
|-------------|---------------------------------------------------------------|
| Name        | Club Demo                                                     |
| Address     | Seestrasse 77, 8002 Zürich                                    |
| Phone       | +41 44 000 00 00                                              |
| Currency    | CHF                                                           |
| Country     | CH (Swiss VAT rules)                                          |
| Tenant UUID | `cc000000-0000-0000-0000-000000000001`                        |

### Staff (6 users, all roles covered)

| Name              | PIN    | Role     | UUID suffix `…0001` |
|-------------------|--------|----------|----------------------|
| Admin Demo        | `0000` | admin    | `…000000000001`      |
| Sophie Zimmermann | `1234` | manager  | `…000000000005`      |
| Lisa Moser        | `1111` | waiter   | `…000000000002`      |
| Jan Hofer         | `2222` | waiter   | `…000000000003`      |
| Marco Koch        | `3333` | kitchen  | `…000000000004`      |
| Tanja Kasse       | `4444` | cashier  | `…000000000006`      |

### Menu (38 products, 7 categories)

| Category               | Items | Tax group |
|------------------------|-------|-----------|
| Suppen & Vorspeisen    | 5     | food      |
| Salate                 | 4     | food      |
| Hauptspeisen           | 9     | food      |
| Pizza & Pasta          | 8     | food      |
| Desserts               | 5     | food      |
| Alkoholfreie Getränke  | 7     | beverage  |
| Weine & Bier           | 6     | alcohol   |

All products include **Unsplash image URLs** (`image_path` column) for use in the Online app and Kiosk.

### Modifiers / Extras (4 groups)

| Group                | Type     | Required | Options                                              |
|----------------------|----------|----------|------------------------------------------------------|
| Pizza-Grösse         | single   | yes      | Standard 32cm (default), Large 40cm (+CHF 5.00)     |
| Garpunkt             | single   | yes      | Rare, Medium (default), Well Done                    |
| Beilage              | multiple | no       | Pommes +4.50, Rösti +4.50, Salat +3.50, Reis +3.00  |
| Zusätzliche Zutaten  | multiple | no       | Mozzarella +2.50, Champignons +1.50, Peperoni +1.00, Zwiebeln +1.00, Oliven +1.50 |

**Product–modifier links:**
- Pizzen → Pizza-Grösse + Zusätzliche Zutaten
- Fleischgerichte (Entrecôte, Rumpsteak, Tagliata) → Garpunkt + Beilage
- Schnitzel / Cordon Bleu → Beilage

### Table Plan (2 floors)

| Floor         | Tables        | Shapes                      |
|---------------|---------------|-----------------------------|
| Erdgeschoss   | R1–R8 (8 tables) | rectangle, capacity 2–8  |
| Terrasse      | T1–T4 (4 tables) | circle + rectangle, cap 2–6 |

### Gang Templates (course structure)

| #  | Name       | Color      | UUID suffix         |
|----|------------|------------|---------------------|
| 1  | Vorspeise  | `#90ABFF`  | `cc000000-000f-…01` |
| 2  | Hauptgang  | `#69F6B8`  | `cc000000-000f-…02` |
| 3  | Dessert    | `#BF5AF2`  | `cc000000-000f-…03` |
| 4  | Getränke   | `#FF9F0A`  | `cc000000-000f-…04` |

Gang templates are stored in the `gang_templates` table (migration 007) and synced to the Flutter local Drift database at login.

### Tax Profiles (Swiss VAT)

| Order type | Food   | Beverage | Alcohol |
|------------|--------|----------|---------|
| Dine-in    | 8.1%   | 8.1%     | 8.1%    |
| Takeaway   | 2.6%   | 2.6%     | 8.1%    |
| Delivery   | 2.6%   | 2.6%     | 8.1%    |

### Demo Orders

Two completed orders are pre-seeded for dashboard/report demonstrations:

- **Order 2001** — Table R2, 2 guests, 2× Zürcher Geschnetzeltes + 2× Fendant, card payment, CHF 95.13
- **Order 2002** — Table T1 (Terrasse), 3 guests, 2× Pizza + 2× Tiramisu + 2× Espresso, cash, CHF 81.08

---

## Frohsinn Bubendorf Tenant (`ff000000-…`)

Real Swiss restaurant used for authenticity testing.

| Field    | Value                                |
|----------|--------------------------------------|
| Name     | Restaurant Pizzeria Frohsinn         |
| Address  | Hauptstrasse 35, 4416 Bubendorf      |
| Products | **141 items** across 18 categories   |

The Frohsinn seed is maintained separately in `server/cmd/seed/seed_frohsinn.go` and is **not modified** by Club Demo changes.

---

## Infrastructure Changes

### Migration 007 — Gang Templates (`007_gang_templates.up.sql`)

Added `gang_templates` table to PostgreSQL:

```sql
CREATE TABLE gang_templates (
    id          TEXT PRIMARY KEY,
    tenant_id   UUID NOT NULL REFERENCES tenants(id),
    name        TEXT NOT NULL,
    sort_order  INTEGER NOT NULL DEFAULT 1,
    color       TEXT NOT NULL DEFAULT '#528DFF',
    is_default  BOOLEAN NOT NULL DEFAULT FALSE,
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    sync_status INTEGER NOT NULL DEFAULT 0,
    is_deleted  BOOLEAN NOT NULL DEFAULT FALSE
);
```

### Demo HTML (`/demo` endpoint)

Both `server/internal/online/demo.html` and `apps/online/web/demo/index.html` updated to:

- Display **Club Demo** branding (Seestrasse 77, Zürich)
- Show all **38 products** with Unsplash images
- Support all **4 modifier groups** (single-select and multi-select)
- Swiss VAT toggle (dine-in 8.1% / takeaway 2.6%)

---

## App Connection Matrix

| App     | Transport     | Auth        | Demo tenant |
|---------|---------------|-------------|-------------|
| POS     | REST + WS     | PIN login   | ✅ Club Demo |
| Waiter  | REST + WS     | PIN login   | ✅ Club Demo |
| Kiosk   | REST          | device key  | ✅ Club Demo |
| KDS     | WebSocket     | device key  | ✅ Club Demo |
| ODS     | WebSocket     | device key  | ✅ Club Demo |
| Online  | REST (public) | none        | ✅ Club Demo |

---

## Seed Command

```bash
# Insert demo data (idempotent)
go run ./cmd/seed

# Wipe and re-seed (force)
go run ./cmd/seed --force

# Remove demo data only
go run ./cmd/seed --wipe
```

Default DSN: `postgres://gastrocore:gastrocore@localhost:5432/gastrocore?sslmode=disable`
Override with `DATABASE_URL` environment variable.
