# Cloud-Master Menu Sync — JSON Contract v1

> **Status:** Authoritative as of 2026-04-29.
> Cloud (gastro2hub Next.js + Prisma) is the source of truth.
> POS (GastroCore Flutter + Drift) consumes immutable snapshots and applies them transactionally.

This document defines the wire format and HTTP surface that the two repositories
must agree on. Any change to the snapshot shape is a contract version bump
(`schemaVersion`) and requires coordinated releases.

---

## 1. Versioning model

* **`schemaVersion`** (int, currently `1`) — bumped only when the contract shape changes.
* **`menuVersion`** (int, monotonic per tenant) — incremented by the Cloud each time
  an admin presses "Yayınla". POS stores the last-applied version; pulling an
  older version is a no-op.
* **`publishedAt`** (ISO 8601 UTC) — server clock, not edit time.
* **`tenantId`** — opaque cuid string. Maps to gastro2hub `Restaurant.id` and
  GastroCore `Tenants.id`. Both ends MUST agree on the value.

The Cloud never deletes old versions; it just keeps the latest as "current". The
POS only ever asks for the current snapshot.

---

## 2. HTTP surface

All endpoints are namespaced under `/api/menu/`.

### 2.1 `GET /api/menu/version/:tenantId`

Lightweight check used by the POS to decide whether a pull is needed.

**Auth:** API key in `X-API-Key` header (per-tenant key, see §4).

**200 OK**
```json
{
  "success": true,
  "data": {
    "tenantId": "ckxyz...",
    "menuVersion": 17,
    "publishedAt": "2026-04-29T08:42:11.000Z",
    "schemaVersion": 1
  }
}
```

**404** when no version has been published yet:
```json
{ "success": false, "error": "no_published_version" }
```

### 2.2 `GET /api/menu/snapshot/:tenantId`

Returns the latest published snapshot in full. Always served from the
`MenuVersion.snapshot` JSON column — never recomputed on the fly. If the
admin wants fresh data, they press "Yayınla" again.

**Auth:** API key.

**200 OK** — see §3 for the body shape.

**Optional query params**
* `?since=<int>` — if set and equal to or greater than the current version,
  the server returns `304 Not Modified` (no body). Used by POS background
  poll to save bandwidth.

### 2.3 `POST /api/menu/publish/:tenantId`

Snapshot the live admin tables and persist a new `MenuVersion` row.

**Auth:** Admin session cookie (NextAuth-style — same `getSession()` used
by every other admin route). API keys CANNOT publish; only humans can.

**Request body** — empty. The Cloud reads the live tables and freezes them.

**200 OK**
```json
{
  "success": true,
  "data": {
    "menuVersion": 18,
    "publishedAt": "2026-04-29T09:01:42.000Z",
    "summary": {
      "categories": 8,
      "products": 96,
      "modifierGroups": 5,
      "modifiers": 24
    }
  }
}
```

**409** when a publish is already in flight (table-level advisory lock).
**403** when the session has no `restaurantId` or it does not match
`:tenantId`.

---

## 3. Snapshot body

### 3.1 Top-level envelope

```jsonc
{
  "schemaVersion": 1,
  "tenantId": "ckxyz...",
  "menuVersion": 18,
  "publishedAt": "2026-04-29T09:01:42.000Z",
  "currency": "CHF",            // ISO-4217. POS validates against its own currency.
  "locale": "de-CH",            // BCP-47. Hint for the POS; not enforced.

  "business": { /* §3.2 */ },
  "taxProfiles": [ /* §3.3 */ ],
  "categories": [ /* §3.4 */ ],
  "products": [ /* §3.5 */ ],
  "modifierGroups": [ /* §3.6 */ ],
  "happyHourRules": [ /* §3.7 */ ],
  "gangs": [ /* §3.8 */ ],
  "receiptTemplate": { /* §3.9 */ }
}
```

### 3.2 Business profile (`business`)

Cloud-managed restaurant identity. Overrides the POS' local
`RestaurantSettings.{name,address,phone,mwstNr,logoPath}` when the POS is in
`menuEditMode = cloud`.

```jsonc
{
  "name": "Restaurant Alpiva",
  "address": "Bahnhofstrasse 12, 8001 Zürich",
  "phone": "+41 44 123 45 67",
  "email": "info@alpiva.ch",
  "mwstNr": "CHE-123.456.789 MWST",   // empty string if not registered
  "logoUrl": "https://cdn.gastro2hub.ch/u/abc.png",  // null if not uploaded
  "primaryColor": "#E63946"           // brand colour for receipts
}
```

### 3.3 Tax profiles

```jsonc
[
  {
    "id": "tax-ch-std",
    "countryCode": "CH",
    "orderType": "*",            // "dine_in" | "takeaway" | "delivery" | "*"
    "productTaxGroup": "standard", // matches Product.taxGroup
    "taxRate": 8.1,              // percent
    "taxName": "MwSt 8.1%",
    "isDefault": true,
    "validFrom": null,           // ISO 8601 or null
    "validUntil": null
  }
]
```

### 3.4 Categories

Map 1-to-1 to Drift `Categories` rows. Cloud-side they live in
`MenuCategory`. Sort by `displayOrder` ascending.

```jsonc
[
  {
    "id": "cat-drinks",          // stable cuid; reused on republish
    "name": "Getränke",
    "displayOrder": 0,
    "color": "#1E88E5",          // hex with #, 7 chars; null allowed
    "icon": null,                // material icon name or emoji; null allowed
    "parentId": null,            // self-reference for sub-categories
    "isActive": true,
    "defaultGangId": null        // matches gangs[].id
  }
]
```

### 3.5 Products

```jsonc
[
  {
    "id": "prod-pizza-margh",
    "categoryId": "cat-pizza",
    "name": "Pizza Margherita",
    "description": "Tomate, Mozzarella, Basilikum",
    "priceCents": 1800,           // INTEGER cents (CHF * 100). Authoritative.
    "costPriceCents": 0,
    "taxGroup": "standard",
    "imageUrl": "https://cdn.gastro2hub.ch/u/pizza-margh.webp",
    "barcode": null,
    "isActive": true,
    "isAvailable": true,          // 86'd flag; default true on publish
    "displayOrder": 0,
    "prepTimeMinutes": 12,
    "printerGroup": "kitchen",    // free string; POS routes by this
    "buttonColor": "#FFB300",     // POS tile background; null inherits category
    "defaultGangId": null,
    "isCombo": false,
    "comboDiscountCents": null,
    "stockStatus": "in_stock",    // 'in_stock'|'out_of_stock'|'out_of_stock_today'|'delisted'
    "isOpenPrice": false,
    "isWeightBased": false,
    "weightUnit": null,           // 'kg'|'g'|null

    "modifierGroupIds": ["mg-size", "mg-extras"],

    "priceOverrides": [           // per-order-type overrides
      { "orderType": "takeaway", "priceCents": 1700 },
      { "orderType": "delivery", "priceCents": 1900 }
    ],

    "variants": [                 // legacy gastro2hub variants. POS may flatten.
      { "id": "v1", "name": "Klein",  "priceCents": 1500, "isDefault": false, "displayOrder": 0 },
      { "id": "v2", "name": "Gross",  "priceCents": 1800, "isDefault": true,  "displayOrder": 1 }
    ],

    "allergens": ["gluten", "lactose"]
  }
]
```

**Money rule:** every monetary value is an INTEGER number of cents. The Cloud
uses Prisma `Decimal`; the publish endpoint converts to cents using
`Math.round(value * 100)`. Floats are forbidden in the wire format.

### 3.6 Modifier groups

```jsonc
[
  {
    "id": "mg-size",
    "name": "Grösse",
    "selectionType": "single",   // "single" | "multiple"
    "minSelections": 1,
    "maxSelections": 1,          // 0 = unlimited
    "isRequired": true,
    "askQuantity": false,
    "freeTagging": false,
    "columnCount": 3,
    "prefix": "",
    "displayOrder": 0,
    "modifiers": [
      {
        "id": "mod-small",
        "name": "Klein",
        "priceDeltaCents": 0,
        "isDefault": false,
        "displayOrder": 0
      },
      {
        "id": "mod-large",
        "name": "Gross",
        "priceDeltaCents": 300,  // +CHF 3.00
        "isDefault": true,
        "displayOrder": 1
      }
    ]
  }
]
```

### 3.7 Happy-hour rules

Optional. Empty array when the cloud has no rules configured.

```jsonc
[
  {
    "id": "hh-bira",
    "name": "Beer Hour",
    "categoryId": "cat-bier",       // null OR productNameContains must be set
    "productNameContains": null,
    "discountPercent": 20,
    "startTime": "17:00",           // local wall-clock HH:MM
    "endTime": "19:00",
    "daysOfWeek": [1, 2, 3, 4, 5],  // ISO weekday list (Mon=1..Sun=7); [] = every day
    "isActive": true
  }
]
```

### 3.8 Gangs (course definitions)

```jsonc
[
  {
    "id": "gang-vorspeise",
    "name": "Vorspeise",
    "sortOrder": 1,
    "color": "#1E88E5",
    "isDefault": true,
    "isActive": true
  }
]
```

### 3.9 Receipt template

Soft-typed JSON the POS' receipt printer renders. The shape below is what the
Cloud writes today; unknown fields are forwarded verbatim and ignored by old
clients.

```jsonc
{
  "headerLines": [
    "Restaurant Alpiva",
    "Bahnhofstrasse 12, 8001 Zürich",
    "+41 44 123 45 67"
  ],
  "footerLines": [
    "Vielen Dank für Ihren Besuch!",
    "www.alpiva.ch"
  ],
  "showLogo": true,
  "showMwstBreakdown": true,
  "fontSize": "normal"            // "small" | "normal" | "large"
}
```

---

## 4. Authentication

### Per-tenant API key

The Cloud generates a random opaque token on first publish (or via an admin
"Generate API key" button) and stores it in the `Restaurant.posApiKey` column
(hashed at rest with bcrypt, like passwords). The plaintext is shown ONCE at
generation time.

Wire format: `X-API-Key: <opaque-string>` request header. The server compares
the hash in constant time and looks up the tenant.

POS reads/writes its key from the existing settings store
(`SettingsRepository`) under the new key `cloudApiKey`.

### Admin publish

`POST /api/menu/publish/:tenantId` requires the same admin session as every
other dashboard route. Implementation reuses `getSession()` and
`session.restaurantId === :tenantId`.

---

## 5. Idempotency, ordering, and apply rules

Cloud guarantees:

* The snapshot is **internally consistent** — every `categoryId` referenced by
  a product exists in the same payload, every `modifierGroupId` exists, every
  `defaultGangId` exists.
* Stable IDs across publishes — POS deletes are by ID, so a product that
  disappears from the snapshot is hard-deleted from the POS DB.
* `publishedAt` is monotonic; if it isn't, the POS treats the snapshot as
  invalid and refuses to apply.

POS guarantees:

* Apply happens in a single Drift transaction. Failure rolls back; the POS
  never ends up half-synced.
* Apply order: tax profiles → gangs → categories → modifier groups (with
  modifiers) → products → product-modifier links → happy-hour rules →
  business profile → receipt template.
* Audit trail: emits `menuSyncStarted` before the transaction,
  `menuSyncApplied` (with `{from, to, addedCount, updatedCount, removedCount}`
  in the new value JSON) on commit, `menuSyncFailed` (with the error
  message) on rollback.

---

## 6. Reserved fields / forward compatibility

* The POS MUST ignore unknown top-level keys and unknown object keys. The
  Cloud may add fields without bumping `schemaVersion`.
* The Cloud MUST NOT remove or repurpose an existing field within the same
  `schemaVersion`. Removals require a contract version bump.
* `null` is the universal "not set". Empty strings are allowed only where
  noted (e.g. `mwstNr`).

---

## 7. Error surface

```jsonc
// 400 — schema violation in published draft
{ "success": false, "error": "invalid_draft", "details": [...] }

// 401 — bad / missing API key
{ "success": false, "error": "unauthorized" }

// 403 — session/tenant mismatch
{ "success": false, "error": "forbidden" }

// 404 — tenant unknown OR no published version yet (snapshot)
{ "success": false, "error": "not_found" }

// 429 — rate-limited (existing middleware)
{ "success": false, "error": "rate_limited" }

// 500 — server error
{ "success": false, "error": "internal" }
```

---

## 8. End-to-end test recipe

1. Cloud admin opens `/admin/menu`, edits the price of `Pizza Margherita`
   from `CHF 18.00` → `CHF 19.00`.
2. Admin presses "Yayınla".
3. POS BackOffice → "Menü Senkronizasyonu" tab.
4. Tap "Cloud'dan Güncelle".
5. Diff dialog shows: `0 added · 1 updated · 0 removed`.
6. Confirm. Apply runs in <1s. Toast "Güncellendi → v18".
7. Audit log shows three rows: `menuSyncStarted`, `menuSyncApplied` (with
   the from/to versions in `newValueJson`), and back to normal.

---

*Last edit: 2026-04-29 — initial contract.*
