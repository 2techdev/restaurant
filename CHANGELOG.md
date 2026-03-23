# Changelog

All notable changes to the GastroCore Platform are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added
- Comprehensive developer documentation suite in `docs/`:
  - `README.md` — project overview, architecture diagram (Mermaid), setup instructions, build commands for all 5 flavors, deploy instructions, API summary
  - `docs/ARCHITECTURE.md` — three-layer architecture, sync protocol, module map, fare engine, WebSocket layer, licensing, security model
  - `docs/API.md` — complete REST API reference with request/response examples for all 40+ endpoints and WebSocket protocols
  - `docs/DEPLOYMENT.md` — step-by-step VPS deployment guide, nginx config, Certbot SSL, environment variables reference, backup/restore, GitHub Pages deployment
  - `docs/DEVELOPMENT.md` — developer setup, Drift DAO patterns, Riverpod patterns, coding conventions, PR process, common tasks
  - `docs/DATABASE.md` — full schema reference for all 31 tables, indexes, materialized views, triggers, migration guide, schema conventions
  - `docs/TESTING.md` — running tests, writing unit/widget/integration tests, Go test patterns, test database setup, coverage targets
- `ROADMAP.md` — living roadmap with Phase 1–4, per-item status (✅/🔄/🔲/❌), licensing tiers, test targets, frozen architecture decisions
- `RELEASE_NOTES.md` — v1.0.0-beta release notes covering all apps (POS, KDS, Waiter, Kiosk, ODS, Online), Swiss-specific features, known issues, technical specs
- `PROJECT_STATUS.md` — comprehensive codebase status report: implemented features, stubs/TODOs, missing items, test coverage, build artifacts, error inventory

## [Unreleased — Swiss VAT Phase 1]

### Added
- ODS (Order Display Screen) feature module scaffolded — customer-facing order status display
- `apps/online` Flutter Web app scaffolded for online ordering (screens, widgets, providers)
- Go backend `stores` module (handlers, models, routes)
- Swiss VAT Phase 1: dine-in vs takeaway `OrderType` toggle on POS screen ("Hier essen" / "Zum Mitnehmen")
- Swiss VAT Phase 1: `_swissFareConfig` constant with correct Swiss rates (food 8.1%/2.6%, beverage 8.1%, accommodation 3.8%)
- Swiss VAT Phase 1: `_extractItemTax()` gross-inclusive extraction — tax = gross × rate / (100 + rate)
- Swiss VAT Phase 1: `addItem()` sets `taxGroup` + `taxAmount` per item on add; `updateOrderType()` recalculates all items on toggle change
- Swiss VAT Phase 1: `swissTicketFareProvider` — `Provider<FareBreakdown?>` auto-updates on ticket or order-type change
- Swiss VAT Phase 1: MWST breakdown in POS totals panel (shows per-rate breakdown from `fare.dishesTaxes`)
- Swiss VAT Phase 1: `MwStCode.forProduct({taxGroup, isDineIn})` static resolver (A=8.1%, B=2.6%, C=3.8%)
- Swiss VAT Phase 1: `SwissReceiptData.orderTypeLabel` — nullable, prints as `Bestellart:` line in receipt meta
- Swiss VAT Phase 1: `SwissReceiptData.roundingAmount` — prints as `Rundung +/-CHF` before Gegeben when non-zero
- `OrderItemEntity.taxGroup` field — snapshots product tax group at order time for per-item MwSt code
- `TicketEntity._withRecalculatedTotals()` fix — total = subtotal - discount (Swiss Bruttopreise; taxAmount is extracted, not added)

### Changed
- `swiss_receipt_builder.dart` `_meta()` — prints `Bestellart` line when `orderTypeLabel` is set
- `swiss_receipt_builder.dart` `_paymentSection()` — prints rounding line when `roundingAmount != 0`
- `print_models.dart` extended with `MwStCode`, `orderTypeLabel`, `roundingAmount`

### Pending (Swiss VAT Phase 2–3)
- Tax rate effective dates (admin-configurable future rates)
- Daily shift CSV export with MWST breakdown by rate
- MWST-Nr format validation (CHE-XXX.XXX.XXX)
- QR-bill generation for on-demand invoices

---

## [0.1.0+1] — 2026-03-20

### Added

#### Project Foundation
- Flutter project created: `gastrocore_pos` (package `com.gastrocore.pos`), targeting Android + Web
- `pubspec.yaml`: full dependency set — Drift 2.22, Riverpod 2.6, GoRouter 14.8, GetIt 8.0, crypto 3.0, pointycastle 3.9, http 1.3, web_socket_channel 3.0, fl_chart 0.69, intl 0.20, uuid 4.5, equatable 2.0, freezed_annotation 3.0, shared_preferences 2.3, permission_handler 11.3
- `analysis_options.yaml` with flutter_lints 5.0

#### Architecture Documentation (38 docs + 15 ADRs)
- `docs/00` through `docs/33` — 33 architecture documents covering executive summary, product principles, architecture alternatives, target architecture, module map, domain model, state machines, Germany fiscal pack, Switzerland pack, ERPNext bridge, sync engine, API contracts, data model, UX flows, pricing/licensing, security/compliance, reporting, roadmap, risk register, pilot rollout, implementation order, OrderPin gap analysis, multi-app architecture, gap analysis, architecture freeze, pricing by order type, execution plan, distribution/monetization, KDS MVP design, sync MVP design, Switzerland pilot pack, Germany fiscal pack v1, release readiness, implementation backlog, 90/180/365 plan
- `docs/adr/ADR-001` through `ADR-015` — 15 Architecture Decision Records
- `docs/legal/` — Legal documentation

#### Core Infrastructure
- `lib/core/utils/money.dart` — `Money` value object (int cents, CHF format, tax extraction, split, `roundTo5Rappen()`)
- `lib/core/utils/id_generator.dart` — UUID v4, order number, device ID, receipt number generation
- `lib/core/constants/app_constants.dart` — enums: `TableStatus`, `OrderStatus`, `PaymentMethod`, `KitchenTicketStatus`, `UserRole`, `OrderType`, `SyncStatus`
- `lib/core/theme/app_theme.dart` — dark theme, `PosColors` ThemeExtension
- `lib/core/theme/app_colors.dart` — 40+ color palette constants (Stitch design system)
- `lib/core/error/failures.dart` — `Failure` base + 6 subclasses
- `lib/core/error/exceptions.dart` — `AppException` base + 4 subclasses
- `lib/core/di/providers.dart` — `databaseProvider`, `tenantIdProvider` (GetIt + Riverpod)
- `lib/core/router/app_router.dart` — GoRouter with 14 named routes

#### Database (Drift ORM — 29 tables)
- `lib/core/database/app_database.dart` — `@DriftDatabase`, `LazyDatabase`, `NativeDatabase`
- Tables: tenants, users, categories, products, modifier_groups, modifiers, product_modifier_groups, product_prices, product_specifications, combo_items, tax_profiles, order_type_rules, floors, restaurant_tables, tickets, order_items, order_item_modifiers, bills, payments, shifts, cash_movements, day_close_summaries, kitchen_tickets, kitchen_ticket_items, receipts, sync_queue, sync_metadata, audit_log, license_tokens
- Conventions: UUID primary keys, `tenant_id` on all rows, `created_at`/`updated_at`, `sync_status`, `is_deleted` (soft delete), money stored as INTEGER (cents)
- Generated: `app_database.g.dart` + `sync_event_dao.g.dart`

#### Domain Entities
- `auth/domain/entities/user_entity.dart` — `UserEntity`, `UserRole` enum
- `menu/domain/entities/` — `CategoryEntity`, `ProductEntity`, `ModifierGroupEntity`, `ModifierEntity`
- `orders/domain/entities/` — `TicketEntity` (10 statuses, 4 channels, `addItem`, `removeItem`, `calculateTotals`), `OrderItemEntity`, `OrderItemModifierEntity`
- `payments/domain/entities/payment_entity.dart` — `PaymentEntity`, `BillEntity`
- `shifts/domain/entities/` — `ShiftEntity`, `CashMovementEntity`, `ShiftSummaryEntity`, `DayCloseSummaryEntity`
- `shifts/domain/day_close_calculator.dart` — `DayCloseCalculator` service
- `tables/domain/entities/table_entity.dart` — `FloorEntity`, `RestaurantTableEntity`
- `kitchen/domain/entities/kitchen_ticket_entity.dart` — `KitchenTicketEntity`, items
- `settings/domain/entities/` — `AppSettings`, `TaxSettings`, `PaymentSettings`, `PrinterSettings`, `ReceiptSettings`, `RestaurantSettings`
- `sync/domain/entities/` — `SyncEventEntity`, `DeviceRegistrationEntity`
- `licensing/domain/entities/` — `LicenseEntity`, `LicenseTier`, `AppFeature`

#### Data Repositories (6 feature repositories + sync + licensing)
- `auth/data/repositories/auth_repository_impl.dart`
- `menu/data/repositories/menu_repository_impl.dart`
- `orders/data/repositories/order_repository_impl.dart`
- `payments/data/repositories/payment_repository_impl.dart` + `refund_repository_impl.dart`
- `shifts/data/repositories/shift_repository_impl.dart` + `day_close_repository_impl.dart`
- `tables/data/repositories/table_repository_impl.dart`
- `kitchen/data/repositories/kitchen_repository_impl.dart`
- `menu/data/repositories/settings_repository_impl.dart`
- `sync/data/` — `sync_repository_impl.dart`, `sync_api_client.dart`, `websocket_sync_client.dart`, `sync_event_dao.dart`
- `licensing/data/repositories/license_repository_impl.dart`, `license_validator.dart` (Ed25519)
- `overrides/data/repositories/override_repository_impl.dart`
- `orders/data/repositories/void_repository_impl.dart`

#### Riverpod Providers
- `auth/presentation/providers/auth_provider.dart`
- `menu/presentation/providers/menu_provider.dart`
- `orders/presentation/providers/order_provider.dart`
- `payments/presentation/providers/refund_provider.dart`
- `payments/providers/hardware_payment_providers.dart`
- `shifts/presentation/providers/shift_provider.dart`, `day_close_provider.dart`
- `tables/presentation/providers/table_provider.dart`
- `sync/presentation/providers/sync_provider.dart`
- `licensing/presentation/providers/license_provider.dart`
- `settings/presentation/providers/settings_provider.dart`, `backup_provider.dart`
- `home/presentation/providers/dashboard_provider.dart`
- `kiosk/presentation/providers/kiosk_provider.dart`
- `waiter/presentation/providers/waiter_provider.dart`
- `core/providers/connectivity_provider.dart`

#### Seed Data
- `lib/core/data/seed_data.dart` — 40+ products, 5 staff (Marco/admin/1234, Julia/manager/5678, Renal/waiter/1111, Sarah/waiter/2222, Kemal/kitchen/3333), 8 categories, 4 modifier groups, 2 floors, 14 tables
- `lib/core/data/app_initializer.dart` — seeds DB on first launch

#### UI Screens (POS mode — 15+ screens)
- `auth/screens/pin_login_screen.dart` — PIN pad + user avatar grid
- `shifts/screens/shift_open_screen.dart` — cash drawer count + open shift
- `shifts/screens/shift_close_screen.dart` — Z-report totals + reconciliation
- `shifts/screens/shift_history_screen.dart` — past shift list
- `shifts/screens/day_close_screen.dart` — end-of-day summary
- `orders/screens/pos_screen.dart` — 3-column POS (categories | products | live order)
- `orders/screens/order_center_screen.dart` — active orders overview
- `orders/screens/order_history_screen.dart` — completed order archive
- `orders/screens/receipt_preview_screen.dart` — thermal receipt preview + print
- `orders/screens/refund_screen.dart` — item-level refund + manager PIN gate
- `orders/widgets/modifier_dialog.dart` — modifier bottom sheet
- `tables/screens/floor_plan_screen.dart` — visual floor plan with table status
- `kitchen/screens/kitchen_display_screen.dart` — KDS ticket cards
- `payments/screens/payment_screen.dart` — cash / card / split payment
- `payments/screens/split_bill_screen.dart` — by product / equal / custom split
- `backoffice/screens/back_office_screen.dart` — 4-tab admin panel
- `backoffice/widgets/menu_management_tab.dart` — category + product CRUD
- `backoffice/widgets/table_management_tab.dart` — floor + table CRUD
- `backoffice/widgets/staff_management_tab.dart` — user CRUD
- `backoffice/widgets/reports_tab.dart` — sales charts (fl_chart)
- `settings/screens/settings_screen.dart` — 7-section configuration
- `home/screens/home_screen.dart` — dashboard with stat cards

#### Kiosk Mode (7 screens)
- `kiosk/screens/kiosk_welcome_screen.dart`
- `kiosk/screens/kiosk_language_screen.dart`
- `kiosk/screens/kiosk_menu_screen.dart`
- `kiosk/screens/kiosk_product_detail_screen.dart`
- `kiosk/screens/kiosk_cart_screen.dart`
- `kiosk/screens/kiosk_payment_screen.dart`
- `kiosk/screens/kiosk_confirmation_screen.dart`
- `main_kiosk.dart` / `kiosk_app.dart` — standalone kiosk entry point

#### Waiter Handheld Mode (6 screens)
- `waiter/screens/waiter_login_screen.dart`
- `waiter/screens/table_select_screen.dart`
- `waiter/screens/waiter_menu_screen.dart`
- `waiter/screens/waiter_order_screen.dart`
- `waiter/screens/waiter_active_orders_screen.dart`
- `waiter/screens/waiter_shell_screen.dart` + `waiter_bottom_nav.dart`
- `main_waiter.dart` / `waiter_app.dart` — standalone waiter entry point

#### KDS App Mode
- `kds_app/screens/kds_login_screen.dart`
- `kds_app/screens/kds_settings_screen.dart`
- `kds_app/screens/kds_display_screen.dart`

#### Shared Widget Library
- `shared/widgets/pos_button.dart` — 4 variants (gradient, solid, ghost, surface)
- `shared/widgets/pos_numpad.dart` — 3×4 numeric keypad
- `shared/widgets/pos_top_bar.dart` — 56 px top bar + logo + online status
- `shared/widgets/pos_card.dart` — `PosCard` + `PosStatCard`
- `shared/widgets/pos_badge.dart` — Status, Table, Count, Role badges
- `shared/widgets/pos_dialog.dart` — Confirm dialog + Manager PIN dialog
- `shared/widgets/pos_text_field.dart` — border-less input with focus glow
- `shared/widgets/pos_empty_state.dart` — empty state placeholder
- `shared/widgets/pos_loading.dart` — overlay + shimmer + inline spinner
- `shared/widgets/pos_money_display.dart` — `PosMoneyDisplay` + `PosHeroMoney`
- `shared/widgets/pos_sync_indicator.dart` — online/offline status dot

#### Business Logic Services
- `core/services/fare_engine.dart` — full pricing calculation: item subtotal → tax → discount → service fee → rounding → receivable
- `core/services/fare_models.dart` — `FareBreakdown` (25 fields), `FareConfig`, `FareLineItem`, `TaxBreakdown`, `RoundingRule`, `ServiceFeeConfig`, `SpecialDiscount`, `AdditionalCost`, `OrderDiscount`
- `core/services/price_resolver.dart` — resolves product price by order type, price list, modifiers
- `core/services/audit_service.dart` — writes to `audit_log` table
- `core/services/backup_service.dart` — SQLite DB export/import
- `core/services/permission_service.dart` — runtime permission requests (camera, Bluetooth, storage)

#### Printing Subsystem
- `core/printing/escpos/esc_pos_builder.dart` — raw ESC/POS byte builder
- `core/printing/escpos/receipt_builder.dart` — customer receipt layout
- `core/printing/escpos/swiss_receipt_builder.dart` — Swiss-compliant receipt (UID, MwSt breakdown, QR placeholder)
- `core/printing/escpos/kitchen_ticket_builder.dart` — kitchen ticket layout
- `core/printing/escpos/report_builder.dart` — shift/Z-report layout
- `core/printing/printer_service.dart` — print queue + provider dispatch
- `core/printing/providers/bluetooth_printer_provider.dart`
- `core/printing/providers/usb_printer_provider.dart`
- `core/printing/providers/wifi_printer_provider.dart`
- `core/printing/use_cases/` — `PrintReceiptUseCase`, `PrintKitchenTicketUseCase`, `PrintReportUseCase`

#### Payment Hardware Abstraction
- `payments/data/hardware/payment_engine.dart` — orchestrates hardware provider selection
- `payments/data/hardware/wallee/wallee_payment_provider.dart` — Wallee LTI protocol client
- `payments/data/hardware/wallee/lti_client.dart` — HTTP LTI client
- `payments/data/hardware/mypos/mypos_payment_provider.dart` — myPOS Android SDK bridge
- `payments/data/hardware/mypos/mypos_client.dart`

#### Licensing System
- `licensing/data/services/license_validator.dart` — Ed25519 signature verification
- `licensing/domain/entities/license_tier.dart` — Starter / Pro / Enterprise
- `licensing/domain/entities/app_feature.dart` — per-feature enum
- `licensing/presentation/widgets/feature_gate.dart` — wraps any widget with tier check
- `licensing/presentation/widgets/upgrade_prompt_dialog.dart` — upgrade CTA dialog

#### Sync Engine
- `sync/data/daos/sync_event_dao.dart` — outbox/inbox DAO (Drift)
- `sync/data/clients/sync_api_client.dart` — REST sync client
- `sync/data/clients/websocket_sync_client.dart` — WebSocket real-time push
- `sync/presentation/widgets/sync_status_widget.dart`
- `sync/presentation/widgets/sync_settings_section.dart`

#### Go Cloud Backend
- `server/cmd/server/main.go` — HTTP server with graceful shutdown
- `server/cmd/migrate/main.go` — SQL migration runner
- `server/internal/shared/` — config, database (PostgreSQL), middleware (RequestID, Logger, Recover, CORS, Auth, Tenant), response helpers, types
- Modules: auth (JWT, device register), sync (upload/download/WebSocket hub), menu (CRUD), orders, reports, devices, licenses, stores, fiscal stub, ERPNext bridge stub
- `server/migrations/001_initial.up.sql` — 26 PostgreSQL tables + indexes + triggers
- `server/Dockerfile` — multi-stage Go build
- `docker-compose.yml` — PostgreSQL + server + Redis
- `server/Makefile`
- Compiled: `server/server.exe` (10 MB)

#### Store Listing + CI/CD
- `apps/pos/store_listing/store_listing_{de,en,fr,it}.md` — Play Store descriptions in 4 languages
- `apps/pos/store_listing/play_console_checklist.md`
- `apps/pos/store_listing/screenshot_*.html` — 5 screenshot templates
- `.github/workflows/ci.yml` — Flutter analyze + build on push/PR
- `.github/workflows/release.yml` — APK release workflow

#### Tests
- 43 unit tests covering: `Money`, `SeedData`, `TicketEntity`, `ShiftEntity`, `DayCloseCalculator`, `FareEngine`, `PriceResolver`, `AuditService`, `BackupService`, `PermissionService`, `MenuRepository`, `OrderRepository`, `PaymentRepository`, `ShiftRepository`, `TableRepository`, `KitchenRepository`, `SettingsRepository`, `LicenseRepository`, `LicenseTier`, `LicenseValidator`, `SyncProvider`, `SyncRepository`, `KioskOrderService`, `KioskSessionNotifier`, `WaiterOrderService`, `OverrideRepository`, `VoidRepository`, `RefundRepository`, `ESCPOSBuilder`, `KitchenTicketBuilder`, `ReportBuilder`, `SwissReceiptBuilder`, `SwissVatReceipt`, `DashboardRepository`, `DashboardSummary`, `PaymentEngine`, `WalleePaymentProvider`, `MyPOSPaymentProvider`, `PaymentDialog` widget, `POSScreen` widget, `TableMap` widget
- 9 integration tests: `app_test`, `login_flow_test`, `menu_management_test`, `order_flow_test`, `payment_flow_test`, `shift_flow_test` (+ helpers: robot, test_app, test_data)

#### Build
- Debug APK: `apps/pos/build/app/outputs/flutter-apk/app-debug.apk` (142 MB)
- Go binary: `server/server.exe` (10 MB, `go build` + `go vet` clean)

### Fixed
- Lint pass after sprint 1: removed 14 unused `dart:ui` imports, updated deprecated APIs, cleared unused elements → `flutter analyze` reported 0 issues at that milestone (since regressed to 187 issues from new code added in subsequent steps)

---

## [0.0.0] — 2026-03-19

### Added
- Initial project analysis: 8 open-source POS systems reviewed (ERPNext, SambaPOS, ViewTouch, Odoo, Lakasir, NexoPOS, OSPOS, FloreantPOS)
- Architecture decision: Option B selected (Flutter offline runtime + Go cloud + ERPNext bridge stub)
- Repository root created at `C:\Users\2tech\Restaurant`

---

[Unreleased]: https://github.com/gastrocore/gastrocore-platform/compare/v0.1.0+1...HEAD
[0.1.0+1]: https://github.com/gastrocore/gastrocore-platform/releases/tag/v0.1.0+1
[0.0.0]: https://github.com/gastrocore/gastrocore-platform/releases/tag/v0.0.0
