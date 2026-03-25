# GastroCore — Project Stats

> Generated: 2026-03-24

---

## Lines of Code

| Component | LOC |
|-----------|-----|
| POS app (`apps/pos/lib`) | 79,484 |
| Online ordering app (`apps/online/lib`) | 6,025 |
| Test files | 17,795 |
| **Total Dart (excl. generated)** | **105,447** |
| Go backend (`server/`) | 11,945 |
| **Grand total** | **~117,000** |

---

## File Counts

| Type | Count |
|------|-------|
| Dart source files (excl. generated) | 362 |
| Generated `.g.dart` files | 3 |
| Go source files | 56 |
| SQL migration files | 12 |
| YAML/YML config files | 11 |
| JSON files (excl. build) | 63 |

---

## Architecture

### Flutter Apps (entry points)
| App | Entry Point | Status |
|-----|-------------|--------|
| POS | `main.dart` | Production ready |
| KDS | `main_kds.dart` | MVP |
| Waiter | `main_waiter.dart` | MVP |
| Kiosk | `main_kiosk.dart` | MVP |
| ODS | `main_ods.dart` | Scaffolded |
| Online Ordering | `apps/online/` | UI only, API stubs |

### POS Feature Modules (21)
`audit_log` · `auth` · `backoffice` · `brand_auth` · `gang` · `home` · `kds_app` · `kiosk` · `kitchen` · `licensing` · `menu` · `ods` · `online_orders` · `orders` · `overrides` · `payments` · `settings` · `shifts` · `sync` · `tables` · `waiter`

---

## Database — Drift Tables (31)

`AuditLog` · `Bills` · `CashMovements` · `Categories` · `ComboItems` · `DayCloseSummaries` · `Floors` · `GangTemplates` · `KitchenTicketItems` · `KitchenTickets` · `LicenseTokens` · `ModifierGroups` · `Modifiers` · `OrderGangStates` · `OrderItemModifiers` · `OrderItems` · `OrderTypeRules` · `Payments` · `ProductModifierGroups` · `ProductPrices` · `ProductSpecifications` · `Products` · `Receipts` · `RestaurantTables` · `Shifts` · `SyncMetadata` · `SyncQueue` · `TaxProfiles` · `Tenants` · `Tickets` · `Users`

---

## State Management — Riverpod Providers

| Metric | Count |
|--------|-------|
| Files containing providers | 146 |
| Provider declarations | 622 |

---

## Screens & Pages (49 total)

### POS App (42 screens)
| Feature | Screens |
|---------|---------|
| Auth / Brand Auth | `pin_login`, `brand_login`, `register` |
| Home | `home_screen` |
| Orders / POS | `pos_screen`, `order_center`, `order_history`, `receipt_preview`, `refund`, `void` |
| Payments | `payment_screen`, `split_bill` |
| Tables | `floor_plan` |
| Menu | `menu_management` |
| Shifts | `shift_open`, `shift_close`, `day_close`, `shift_history` |
| Kitchen / KDS | `kitchen_display`, `kds_main`, `kds_login`, `kds_settings`, `kds_station_filter` |
| Waiter | `waiter_login`, `waiter_menu`, `waiter_order`, `waiter_active_orders`, `table_select`, `waiter_shell` |
| Kiosk | `kiosk_welcome`, `kiosk_menu`, `kiosk_cart`, `kiosk_product_detail`, `kiosk_payment`, `kiosk_confirmation`, `kiosk_language` |
| Backoffice | `back_office` |
| ODS | `ods_main`, `ods_settings` |
| Settings | `settings_screen` |
| Audit Log | `audit_log` |

### Online App (7 screens)
`landing` · `menu` · `product_detail` · `cart` · `checkout` · `order_confirmation` · `order_tracking`

---

## Go Backend

### API Endpoints (91 routes)

| Module | LOC | Notes |
|--------|-----|-------|
| `auth` | 1,281 | Multi-tenant JWT, device pairing |
| `stores` | 2,496 | Tenant CRUD + store API |
| `shared` | 892 | Middleware, JWT, helpers |
| `sync` | 983 | WebSocket hub + offline queue |
| `online` | 649 | Online ordering API |
| `menu` | 636 | Menu + categories |
| `orders` | 601 | Order lifecycle |
| `reports` | 408 | Day close, shift reports |
| `pos` | 362 | POS-specific endpoints |
| `devices` | 345 | Device registration |
| `licenses` | 315 | License validation |
| `kds` | 469 | KDS endpoints |
| `docs` | 50 | Swagger/OpenAPI |
| `erpnext_bridge` | 4 | Stub |
| `fiscal` | 3 | Stub |

### Migrations
12 SQL migration files (through migration 006 — multi-tenant auth)

---

## Tests

| Category | Count |
|----------|-------|
| Dart unit test files | 46 |
| Dart widget test files | 3 |
| Integration test helpers | 2 |
| Go test files | 1 |
| **Total test files** | **52** |
| Test lines of code | 17,795 |

### Test Coverage Areas
- Core: `seed_data`, `esc_pos_builder`, `kitchen_ticket_builder`, `printer_service`, `report_builder`, `swiss_receipt_builder`, `swiss_vat_receipt`
- Services: `audit_service`, `backup_service`, `fare_engine`, `permission_service`, `money`
- Features: `dashboard`, `kiosk`, `kitchen`, `licensing`, `menu`, `orders`, `payments`, `settings`, `shifts`, `sync`, `tables`, `waiter`

---

## Documentation

| Type | Count |
|------|-------|
| Architecture docs (`docs/`) | 38 |
| Architecture Decision Records (`docs/adr/`) | 15 |
| Root markdown files | `PROJECT_STATUS.md`, `ROADMAP.md`, `RELEASE_NOTES.md`, `CHANGELOG.md`, `TODO.md` |
