# GastroCore Platform — Living Roadmap

> **Last Updated:** 2026-03-23
> **Current Version:** v0.1.0+1 (MVP)
> **Next Target:** v1.0.0-beta (Swiss Pilot Release)

**Status Legend:**
✅ Done — feature complete and tested
🔄 In Progress — partially implemented
🔲 Planned — scoped but not started
❌ Blocked — dependency or decision pending

---

## Phase 1: Freemium POS — Swiss Pilot (v1.0.0)

> **Goal:** Ship a production-ready POS app to 1–3 pilot restaurants in Switzerland.
> **Target Date:** Q2 2026

### 1.1 Core POS

| Feature | Status | Notes |
|---------|--------|-------|
| PIN authentication (4–6 digit, user grid) | ✅ Done | |
| Product catalog (categories, products, modifiers) | ✅ Done | |
| Table management + floor plan | ✅ Done | |
| 3-column POS screen (categories / products / order) | ✅ Done | |
| Order entry with modifiers & notes | ✅ Done | |
| Cash payment + change calculation | ✅ Done | |
| Card payment (abstract hardware) | ✅ Done | |
| Split bill (equal, by product, custom) | ✅ Done | |
| Shift open / close + Z-report | ✅ Done | |
| Cash drawer control (ESC/POS) | ✅ Done | |
| Refund / void with manager PIN gate | ✅ Done | |
| Audit log (every user action) | ✅ Done | |
| Dashboard / home screen with stat cards | ✅ Done | |
| Back office panel (menu, staff, tables, reports) | ✅ Done | |
| Soft delete + offline-first SQLite/Drift | ✅ Done | |

### 1.2 Swiss Compliance

| Feature | Status | Notes |
|---------|--------|-------|
| Swiss VAT rates: A 8.1%, B 2.6%, C 3.8% | ✅ Done | |
| Dine-in vs. takeaway VAT differentiation | ✅ Done | |
| 5-Rappen CHF rounding (`roundTo5Rappen`) | ✅ Done | |
| Swiss receipt: MWST-Nr, rate breakdown, Rundung line | ✅ Done | |
| FareEngine: tax-inclusive extraction (gross model) | ✅ Done | |
| Order type label on receipt (Hier essen / Zum Mitnehmen) | ✅ Done | |
| 4-language UI: DE / FR / IT / EN | ✅ Done | |
| TWINT payment method label | 🔄 In Progress | UI label present; API integration pending |
| MWST-Nr format validation (CHE-XXX.XXX.XXX) | 🔲 Planned | Phase 2 |
| QR-Bill generation for on-demand invoices | 🔲 Planned | Phase 3 |
| Daily shift CSV export with MWST breakdown | 🔲 Planned | Phase 2 |

### 1.3 Printing

| Feature | Status | Notes |
|---------|--------|-------|
| ESC/POS customer receipt | ✅ Done | |
| ESC/POS kitchen ticket | ✅ Done | |
| ESC/POS shift / Z-report | ✅ Done | |
| Bluetooth printer (Star Micronics, Epson, generic) | ✅ Done | |
| USB thermal printer (Android USB host) | ✅ Done | |
| Network (Ethernet/WiFi) thermal printer | ✅ Done | |
| Cash drawer kick via ESC/POS | ✅ Done | |
| Image on receipt (logo) | 🔄 In Progress | Image picker TODO |
| Email receipt | 🔲 Planned | |
| PDF receipt export | 🔲 Planned | |

### 1.4 Remaining v1.0.0 Work Items

| Item | Status | Priority |
|------|--------|----------|
| Image picker (product/staff photos) | 🔄 In Progress | HIGH |
| Discount dialog (%, fixed, named presets) | 🔄 In Progress | HIGH |
| Settings persistence (tenant config save to DB) | 🔄 In Progress | HIGH |
| KDS audio alert on new ticket | 🔄 In Progress | MEDIUM |
| Customer selection dialog | 🔲 Planned | MEDIUM |
| Table merge / split / transfer dialogs | 🔲 Planned | MEDIUM |
| Quick-notes dialog for orders | 🔲 Planned | LOW |
| `flutter analyze` clean to 0 issues | 🔄 In Progress | HIGH |

---

## Phase 2: Add-ons — KDS, Kiosk, Waiter (v1.1.0)

> **Goal:** Standalone companion apps + hardware integrations.
> **Target Date:** Q3 2026

### 2.1 Kitchen Display System (KDS)

| Feature | Status | Notes |
|---------|--------|-------|
| KDS mode entry point (`main_kds.dart`) | ✅ Done | In POS app |
| Kitchen ticket display with timer color coding | ✅ Done | |
| Bump (mark complete) functionality | ✅ Done | |
| Course management (1st, 2nd course) | ✅ Done | |
| Station filter (kitchen, bar, pastry) | ✅ Done | |
| KDS login screen | ✅ Done | |
| Audio alert on new ticket | 🔄 In Progress | audioplayers TODO |
| Standalone `apps/kds/` Flutter project | 🔲 Planned | |
| LAN sync via mDNS + WebSocket | 🔲 Planned | |
| Full-screen landscape mode lock | 🔲 Planned | |
| Recall bumped tickets | 🔲 Planned | |

### 2.2 Self-Service Kiosk

| Feature | Status | Notes |
|---------|--------|-------|
| Kiosk entry point (`main_kiosk.dart`) | ✅ Done | |
| Welcome / language selection screen | ✅ Done | |
| Full-screen menu browse | ✅ Done | |
| Product detail with modifiers | ✅ Done | |
| Cart + checkout screens | ✅ Done | |
| Order confirmation with pickup code | ✅ Done | |
| Payment terminal integration | 🔄 In Progress | Hardware stubs present |
| Idle timeout + screensaver | 🔲 Planned | |
| Accessibility (large fonts, contrast modes) | 🔲 Planned | |

### 2.3 Waiter Handheld App

| Feature | Status | Notes |
|---------|--------|-------|
| Waiter entry point (`main_waiter.dart`) | ✅ Done | |
| Waiter PIN login | ✅ Done | |
| Table selection screen | ✅ Done | |
| Menu browse + quick-add | ✅ Done | |
| Active orders overview | ✅ Done | |
| Portrait, one-hand optimized UI | ✅ Done | |
| Standalone `apps/waiter/` Flutter project | 🔲 Planned | |
| Course fire button | 🔲 Planned | |
| Bill split initiation from waiter | 🔲 Planned | |

### 2.4 Order Display Screen (ODS)

| Feature | Status | Notes |
|---------|--------|-------|
| ODS entry point (`main_ods.dart`) | ✅ Done | |
| ODS screen scaffold (2 screens) | 🔄 In Progress | Screens present; logic stub |
| Live order status ticker (Preparing / Ready) | 🔲 Planned | |
| Pickup number display (large font, landscape) | 🔲 Planned | |
| Estimated time countdown | 🔲 Planned | |
| TV/Monitor full-screen mode | 🔲 Planned | |

### 2.5 Payment Hardware Integration

| Feature | Status | Notes |
|---------|--------|-------|
| PaymentEngine abstraction layer | ✅ Done | |
| Wallee LTI protocol client | 🔄 In Progress | Basic structure; field mapping incomplete |
| myPOS Android SDK bridge | 🔄 In Progress | Basic structure; needs SDK |
| TWINT API integration | 🔲 Planned | |
| SumUp integration | 🔲 Planned | |
| Telpo integration | 🔲 Planned | |
| Barcode scanner (Android intent) | 🔲 Planned | |
| Weight scale (serial/USB protocol) | 🔲 Planned | |

---

## Phase 3: Online Ordering + Cloud Backend (v1.2.0)

> **Goal:** Enable online ordering for restaurants; complete cloud backend.
> **Target Date:** Q4 2026

### 3.1 Online Ordering (Customer Web App)

| Feature | Status | Notes |
|---------|--------|-------|
| `apps/online` Flutter Web scaffold | 🔄 In Progress | 28 files, 6K LOC |
| Landing screen | ✅ Done | |
| Menu browse (categories + products) | ✅ Done | |
| Product detail screen | ✅ Done | |
| Cart screen | ✅ Done | |
| Checkout screen | ✅ Done | |
| Order confirmation screen | ✅ Done | |
| Order tracking screen | ✅ Done | |
| Backend API integration | 🔲 Planned | Stubs present |
| Payment gateway (Stripe / Datatrans) | 🔲 Planned | |
| Real-time order status (WebSocket) | 🔲 Planned | |
| Order acceptance popup on POS | 🔲 Planned | |
| SEO-optimized Flutter Web build | 🔲 Planned | |
| Custom domain per restaurant | 🔲 Planned | |

### 3.2 Go Cloud Backend

| Feature | Status | Notes |
|---------|--------|-------|
| HTTP server + graceful shutdown | ✅ Done | |
| JWT authentication + device registration | ✅ Done | |
| Device sync (upload / download REST) | ✅ Done | |
| WebSocket sync hub | ✅ Done | |
| Menu CRUD endpoints | ✅ Done | |
| Store management endpoints | ✅ Done | |
| License validation (Ed25519) | ✅ Done | |
| KDS WebSocket hub | ✅ Done | |
| Orders endpoint (full flow) | 🔄 In Progress | Create/list only |
| Reports / Z-report endpoint | 🔄 In Progress | Summary stubs |
| Online ordering public API | 🔲 Planned | |
| Payment gateway webhooks | 🔲 Planned | |
| Multi-store aggregation API | 🔲 Planned | |
| Rate limiting per tenant | 🔲 Planned | |
| HTTPS / TLS termination | 🔲 Planned | Infra-level |

### 3.3 QR-Bill (Swiss Invoicing Standard)

| Feature | Status | Notes |
|---------|--------|-------|
| Receipt structure prepared for QR-bill | ✅ Done | Placeholder in receipt |
| QR code generation (Swiss QR format) | 🔲 Planned | |
| SCOR reference generation | 🔲 Planned | |
| PDF invoice with embedded QR-bill | 🔲 Planned | |

### 3.4 Shared Package Extraction (Melos Monorepo)

| Feature | Status | Notes |
|---------|--------|-------|
| `packages/core_models/` | 🔲 Planned | Entities, enums, value objects |
| `packages/core_database/` | 🔲 Planned | Drift tables, AppDatabase |
| `packages/core_theme/` | 🔲 Planned | AppColors, widgets |
| `packages/core_auth/` | 🔲 Planned | PIN auth |
| `packages/core_sync/` | 🔲 Planned | Sync engine |
| `packages/core_printing/` | 🔲 Planned | Printer abstraction |
| Melos workspace (`melos.yaml`) | 🔲 Planned | |

---

## Phase 4: Multi-Location + Enterprise (v2.0.0)

> **Goal:** Enable multi-store restaurant groups; fiscal compliance for DE/AT; ERP integration.
> **Target Date:** Q1–Q2 2027

### 4.1 Multi-Store Management

| Feature | Status | Notes |
|---------|--------|-------|
| Multi-tenancy foundation (tenant_id on all rows) | ✅ Done | |
| Store hierarchy (tenant → stores) | ✅ Done | DB + backend endpoints |
| Cross-store reporting | 🔲 Planned | |
| Centralized menu management | 🔲 Planned | |
| Store-specific pricing overrides | 🔲 Planned | |
| Regional manager role | 🔲 Planned | |
| Franchise billing per store | 🔲 Planned | |

### 4.2 Germany Fiscal Pack (TSE / Fiskaly)

| Feature | Status | Notes |
|---------|--------|-------|
| Technical docs (30-germany-fiscal-pack-v1.md) | ✅ Done | |
| Fiskaly SDK integration (TSE) | 🔲 Planned | `fiscal/` stub exists |
| KassenSichV receipt elements | 🔲 Planned | |
| QR-Code TSS on receipt | 🔲 Planned | |
| DSFinV-K export | 🔲 Planned | |
| Umsatzsteuer rates (19%, 7%) | 🔲 Planned | |

### 4.3 Austria Fiscal Pack

| Feature | Status | Notes |
|---------|--------|-------|
| RKSV compliance (Registrierkassenpflicht) | 🔲 Planned | |
| DEP-7 / DEP-13 data export | 🔲 Planned | |
| Signaturerstellungseinheit (SEE) | 🔲 Planned | |

### 4.4 ERPNext Bridge

| Feature | Status | Notes |
|---------|--------|-------|
| Technical docs (09-erpnext-bridge.md) | ✅ Done | |
| ERPNext API client | 🔲 Planned | `erpnext_bridge/` stub exists |
| Item / POS Invoice sync | 🔲 Planned | |
| Payment Entry sync | 🔲 Planned | |
| Customer sync | 🔲 Planned | |
| Accounting ledger push | 🔲 Planned | |

### 4.5 Advanced Features

| Feature | Status | Notes |
|---------|--------|-------|
| Web management dashboard (Flutter Web / React) | 🔲 Planned | |
| Loyalty / points system | 🔲 Planned | |
| Customer mobile app (Boss App) | 🔲 Planned | |
| Delivery management + third-party integrations | 🔲 Planned | |
| Advanced analytics + BI dashboard | 🔲 Planned | |
| Inventory management | 🔲 Planned | |
| Supplier ordering | 🔲 Planned | |
| Staff scheduling | 🔲 Planned | |
| Retail / market mode (weight-based, open price) | 🔲 Planned | |

---

## Licensing Tiers

| Tier | Target | Key Features |
|------|--------|--------------|
| **Starter** (Free) | Single-location restaurant | POS, printer, 1 device |
| **Pro** (CHF 49/mo) | Growing restaurants | KDS, Kiosk, Waiter, sync, online ordering |
| **Enterprise** (CHF 149/mo) | Restaurant groups | Multi-store, ERPNext bridge, fiscal packs, priority support |

---

## Test Coverage Targets

| Suite | Current | Target (v1.0.0) |
|-------|---------|-----------------|
| Unit tests | 44 files | 60+ files |
| Integration tests | 9 suites | 15 suites |
| Widget tests | 3 tests | 10 tests |
| E2E tests | 0 | 5 core flows |
| `flutter analyze` issues | ~187 | 0 |

---

## Architecture Decisions (Frozen)

These are immutable per ADR-023 (architecture freeze):

- **Flutter** for all client apps (POS, Kiosk, Waiter, KDS, ODS, Online)
- **Go** for cloud backend (not Node, not Python)
- **PostgreSQL 16** for cloud database
- **Drift/SQLite** for device-local database
- **Riverpod** for state management (not GetX, not BLoC)
- **Offline-first** sync with outbox/inbox pattern
- **Ed25519** for license signing
- **ARB format** for i18n (DE, FR, IT, EN)

---

*This roadmap is reviewed and updated after each development session.*
