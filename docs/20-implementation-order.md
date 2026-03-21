# 20 - Implementation Order

> The definitive guide to what to build, in what order, and what to avoid. This is the tactical counterpart to the strategic roadmap (doc 17).

---

## A. Priority 1 -- What to Build First (Weeks 1-16)

These items form the core POS that can sell food at a counter, food truck, or simple cafe. Each item builds on the previous. Do not skip ahead.

### 1. Project Scaffolding

**Week 1-2 | Effort: 2 person-weeks**

| What                                | Why                                                        |
|-------------------------------------|------------------------------------------------------------|
| Flutter project in monorepo (`apps/pos/`) | Foundation for all mobile work                         |
| Go project in monorepo (`server/`)  | Foundation for all backend work (even if unused until Phase 3) |
| Drift ORM setup with initial schema | Database layer must be decided early; migration path matters |
| CI/CD pipeline (GitHub Actions)     | Lint + test + build on every push prevents debt accumulation |
| App theme and design tokens         | Consistent UI from day 1; painful to retrofit              |
| Folder structure per feature module | Modular monolith starts with good folder hygiene           |
| Dev environment documentation       | Second developer can onboard without 2 days of setup       |

**Rationale:** Every hour spent on scaffolding saves 10 hours later. A clean monorepo with CI/CD from day 1 prevents the "works on my machine" trap and enforces code quality when the team grows.

### 2. Domain Model Core

**Week 2-3 | Effort: 1.5 person-weeks**

| What                                | Why                                                        |
|-------------------------------------|------------------------------------------------------------|
| Dart entity classes (Product, Category, Order, OrderItem, Payment, Shift, User) | Domain model is the language of the system |
| Value objects (Money, TaxRate, Quantity, PIN) | Type safety prevents entire categories of bugs      |
| Repository interfaces (abstract)    | Depend on abstractions, not on Drift directly              |
| Drift DAO implementations           | Concrete database operations behind repository interfaces  |
| Seed data script (sample cafe menu)  | Every developer and tester starts with realistic data      |

**Rationale:** Getting the domain model right early is critical. Every feature depends on these entities. Using value objects for money (integer cents, not floating point) prevents rounding bugs that are nearly impossible to find later.

### 3. Auth Module

**Week 3-4 | Effort: 1 person-week**

| What                                | Why                                                        |
|-------------------------------------|------------------------------------------------------------|
| PIN login screen                    | First thing the user sees; must feel fast and polished     |
| Local user storage (Drift)          | Users are local-first; no cloud dependency                 |
| PIN validation logic                | Simple but must be correct (hash PINs, not plaintext)      |
| Session management (current user)   | Every operation needs to know who did it (audit trail)     |
| Lock screen (auto-lock after idle)  | Restaurant tablets should lock after inactivity            |

**Rationale:** Auth is the gate to everything. Building it first means every subsequent feature has user context for audit logging. PIN-based auth (not email/password) matches restaurant workflow -- staff switch users dozens of times per shift.

### 4. Menu / Product Catalog

**Week 4-6 | Effort: 2.5 person-weeks**

| What                                | Why                                                        |
|-------------------------------------|------------------------------------------------------------|
| Category CRUD (name, sort order, color, icon) | Categories organize the order screen             |
| Product CRUD (name, price, tax rate, category, active/inactive) | Products are what you sell             |
| Modifier groups and modifiers (e.g., "Size: Small/Medium/Large", "Extras: Extra cheese +2.00") | Modifiers are how restaurants customize items |
| Product grid/list view              | The primary UI for finding products during order entry     |
| Search/filter products              | Staff with 80+ items need to find products fast            |
| Local storage and retrieval         | All catalog data in SQLite; no network dependency          |

**Rationale:** The product catalog is the second-most-used screen (after order entry). If browsing products is slow or confusing, the entire POS feels slow. Modifiers are not optional -- even a simple cafe has "regular/large" or "with milk/without."

### 5. Order Engine Core

**Week 6-9 | Effort: 3 person-weeks**

| What                                | Why                                                        |
|-------------------------------------|------------------------------------------------------------|
| Create new order/ticket             | The central action of the POS                              |
| Add items to order (with modifiers) | Line item management                                      |
| Adjust quantity, remove items       | Corrections before payment                                 |
| Calculate subtotal, tax, total      | Tax calculation must be correct from day 1 (integer math)  |
| Apply discount (percentage or fixed amount) | Basic discounting is expected                       |
| Void an item (with reason code)     | Items sent to kitchen can't be removed, only voided        |
| Order status lifecycle (open, paid, voided, refunded) | State machine for order progression      |
| Immutable transaction log           | Every state change logged; never delete, never modify      |
| Order list view (current shift)     | Staff needs to see recent orders                           |
| Order detail view                   | View full order with all items and modifications           |

**Rationale:** The order engine is the heart of the POS. Tax calculation using integer arithmetic (cents, not euros) is a non-negotiable architectural decision. The immutable transaction log starts here -- not as an afterthought, but as a foundational requirement for fiscal compliance (Germany) and audit trails.

### 6. Cash Payment

**Week 9-10 | Effort: 1.5 person-weeks**

| What                                | Why                                                        |
|-------------------------------------|------------------------------------------------------------|
| Cash payment screen                 | Amount tendered, change calculation                        |
| Quick-amount buttons (EUR 5, 10, 20, 50) | Speed up cash handling                               |
| Change calculation and display      | Must be correct; staff relies on this                      |
| Payment recording in transaction log | Immutable record of payment                               |
| Mark order as paid                  | Completes the order lifecycle                              |
| Cash rounding (Swiss 5 Rappen)      | Configurable per currency; implement early                 |

**Rationale:** Cash is king in small restaurants. In Switzerland, ~60% of payments at small cafes are cash. This is the simplest payment type to implement and immediately makes the POS functional for real sales.

### 7. Receipt Printing

**Week 10-12 | Effort: 2 person-weeks**

| What                                | Why                                                        |
|-------------------------------------|------------------------------------------------------------|
| ESC/POS command generation          | Standard thermal printer command language                   |
| Bluetooth printer discovery and pairing | User needs to find and connect their printer            |
| Receipt template: header (business name, address), items (name, qty, price), subtotal, tax breakdown, total, date/time, receipt number | Legal minimum for a receipt |
| Print queue with retry logic        | Bluetooth fails; queue and retry, don't lose the receipt   |
| Printer status indicator in UI      | Staff must know if printer is connected                    |
| Test print function                 | Verify setup without making a real sale                    |

**Rationale:** Restaurants judge a POS by its receipt. If the receipt looks bad, prints slowly, or fails intermittently, the POS is "broken" in the customer's eyes. Invest heavily in print reliability. The print queue with retry is essential -- Bluetooth will drop connections.

### 8. Shift Management

**Week 12-13 | Effort: 1.5 person-weeks**

| What                                | Why                                                        |
|-------------------------------------|------------------------------------------------------------|
| Open shift (enter opening cash float) | Starting point for cash accountability                  |
| Close shift (enter counted cash)    | End of shift reconciliation                                |
| Cash variance calculation           | Expected vs. actual cash                                   |
| Cash in/out events (petty cash, tips) | Track non-sale cash movements                            |
| Shift lock (no orders without open shift) | Prevent un-tracked sales                              |
| Shift history (view past shifts)    | Manager reviews previous shifts                            |

**Rationale:** Shift management is the accountability framework. Without it, there's no way to reconcile cash at end of day. Every restaurant operates on shifts, and the shift close ritual (count cash, compare to expected) is non-negotiable for cash control.

### 9. Basic Reports

**Week 13-16 | Effort: 2 person-weeks**

| What                                | Why                                                        |
|-------------------------------------|------------------------------------------------------------|
| Shift summary report (revenue, order count, avg ticket, payment breakdown, voids) | End-of-shift review |
| Daily sales flash (today vs. yesterday) | Quick dashboard widget                               |
| PDF export of shift report          | Manager emails/prints shift summary                        |
| Shift report on thermal printer     | Quick printed summary at shift close                       |

**Rationale:** Reports close the loop. Without reports, the POS is just an order entry tool. The shift summary is what gives the owner confidence that money is accounted for. PDF export and thermal print are the two delivery channels that restaurant managers actually use.

---

**After Priority 1 is complete:** You have a functional counter/food truck POS that can take orders, process cash payments, print receipts, manage shifts, and report basic sales data. This is MVP-0.

---

## B. Priority 2 -- What to Build Second (Weeks 17-30)

These items transform the counter POS into a full restaurant management system with table service, kitchen integration, and multi-device support.

### 10. Table Management

**Week 17-19 | Effort: 3 person-weeks**

| What                                | Why                                                        |
|-------------------------------------|------------------------------------------------------------|
| Floor plan editor (tables, areas)   | Visual representation of the restaurant                    |
| Table states (free, occupied, reserved, dirty) | Real-time floor status                          |
| Table properties (seats, shape, position) | Layout matches physical restaurant                   |
| Multiple floors/areas               | Indoor, outdoor, bar, private room                         |
| Visual status indicators            | Color-coded tables at a glance                             |

### 11. Table-Based Ordering

**Week 19-22 | Effort: 3 person-weeks**

| What                                | Why                                                        |
|-------------------------------------|------------------------------------------------------------|
| Open table session (assign, guest count) | Links physical table to digital order                 |
| Order items on a table's ticket     | Same order engine, but linked to a table session           |
| Table timer (time since seated)     | Identifies tables that have been waiting too long          |
| Waiter assignment per table         | "My tables" filter for waiters                             |
| Close table (pay + receipt + free table) | Complete lifecycle                                     |

### 12. Kitchen Tickets

**Week 22-24 | Effort: 2.5 person-weeks**

| What                                | Why                                                        |
|-------------------------------------|------------------------------------------------------------|
| Send items to kitchen               | Items marked "sent" generate kitchen ticket                |
| KDS app (separate Flutter app)      | Dedicated screen for kitchen staff                         |
| Ticket display with age coloring    | Green/yellow/red based on wait time                        |
| Bump (complete) tickets             | Kitchen marks items as done                                |
| Audible notification for new tickets | Kitchen staff hear new orders arrive                      |
| Kitchen printer fallback            | If KDS is down, print ticket on network printer            |

### 13. Course Management

**Week 24-25 | Effort: 1.5 person-weeks**

| What                                | Why                                                        |
|-------------------------------------|------------------------------------------------------------|
| Assign items to courses (1, 2, 3)   | Appetizer, main, dessert sequencing                        |
| Fire course (manual trigger)        | Waiter tells kitchen to start next course                  |
| KDS shows course grouping           | Kitchen sees which items belong to which course            |
| Auto-fire option (fire when previous course bumped) | Optional automation                        |

### 14. Split Bill / Merge Table / Move Table

**Week 25-27 | Effort: 2 person-weeks**

| What                                | Why                                                        |
|-------------------------------------|------------------------------------------------------------|
| Split by item (assign items to bills) | Most common split method                                |
| Split equally by N guests           | "Split 4 ways"                                             |
| Custom amount split                 | Flexible splitting                                         |
| Merge tables (combine sessions)     | Two tables join together                                   |
| Move table (transfer session)       | Group moves from bar to dining room                        |
| Partial payment (pay part of bill)  | One guest pays and leaves                                  |

### 15. Multi-Device LAN Sync

**Week 27-29 | Effort: 2.5 person-weeks**

| What                                | Why                                                        |
|-------------------------------------|------------------------------------------------------------|
| mDNS device discovery on LAN        | Tablets find each other automatically                      |
| Primary/secondary device model      | One source of truth, others replicate                      |
| Real-time state propagation         | Table status, order changes visible across devices         |
| Connection status UI                | Staff knows if their tablet is connected to primary        |
| Graceful degradation when primary unreachable | Secondary shows warning, can still take offline orders |

### 16. Card Payment Tracking

**Week 29-30 | Effort: 1 person-week**

| What                                | Why                                                        |
|-------------------------------------|------------------------------------------------------------|
| Payment method selection (cash/card/other) | Track how customers pay                            |
| Card payment recording (amount, reference) | Record card payment without processing it          |
| Payment method in reports           | Cash vs. card breakdown in shift and daily reports         |
| Mixed payment (part cash, part card) | Common scenario                                          |

---

**After Priority 2 is complete:** You have a full restaurant POS with table service, kitchen integration, and multi-device operation. This is MVP-1.

---

## C. Priority 3 -- What to Build Third (Weeks 31-44)

These items connect the local POS to the cloud and add market-specific compliance.

### 17. Cloud Backend Setup

**Week 31-33 | Effort: 3 person-weeks**

| What                                | Why                                                        |
|-------------------------------------|------------------------------------------------------------|
| Go HTTP server with routing         | Foundation for all cloud services                          |
| PostgreSQL schema with migrations   | Cloud data store                                           |
| JWT authentication (device + user)  | Secure API access                                          |
| Tenant isolation (RLS)              | Multi-tenant from the start                                |
| Health check and monitoring endpoints | Operational visibility                                   |
| Device registration API             | Devices register with cloud                                |

### 18. Cloud Sync Engine

**Week 33-36 | Effort: 3.5 person-weeks**

| What                                | Why                                                        |
|-------------------------------------|------------------------------------------------------------|
| Sync protocol design and implementation | Bi-directional delta sync                             |
| Conflict resolution logic           | Handle concurrent edits                                    |
| Sync queue on device                | Buffer changes for batch upload                            |
| Sync status UI (last synced, pending, errors) | User awareness of sync state                    |
| Retry with exponential backoff      | Handle transient network failures                          |
| Sync simulation test suite          | Validate sync under adverse conditions                     |

### 19. Web Dashboard

**Week 36-39 | Effort: 3 person-weeks**

| What                                | Why                                                        |
|-------------------------------------|------------------------------------------------------------|
| Login page (email/password)         | Owner accesses dashboard                                   |
| Daily/weekly/monthly sales reports  | Core cloud value proposition                               |
| Device status (online, last sync)   | Operational overview                                       |
| Menu management (CRUD from web)     | Owner manages menu without touching tablet                 |
| User management (staff PINs, roles) | Admin capabilities from desktop                            |
| Basic charts (revenue trend, top products) | Visual analytics                                    |

### 20. License System

**Week 39-40 | Effort: 1.5 person-weeks**

| What                                | Why                                                        |
|-------------------------------------|------------------------------------------------------------|
| Tenant registration flow            | New customer onboarding                                    |
| Subscription tiers (Starter, Professional, Enterprise) | Feature differentiation            |
| Feature flags per tier              | Gate features by subscription level                        |
| License validation on device        | Periodic check with offline grace period                   |
| License expiry handling             | Graceful degradation, not hard cutoff                      |

### 21. Germany Fiscal Pack

**Week 40-43 | Effort: 3.5 person-weeks**

| What                                | Why                                                        |
|-------------------------------------|------------------------------------------------------------|
| Fiskaly SIGN DE v2 integration      | Cloud TSE for German compliance                            |
| Transaction signing flow            | Start, update, finish lifecycle                            |
| TSE data on receipt (QR, signature) | Legal requirement                                          |
| DSFinV-K export                     | Audit export requirement                                   |
| Offline fiscal queue                | Handle signing when offline                                |

### 22. Switzerland Pack

**Week 43-44 | Effort: 1.5 person-weeks**

| What                                | Why                                                        |
|-------------------------------------|------------------------------------------------------------|
| Swiss VAT rates with effective dates | Configurable, future-proof                               |
| Dine-in vs. takeaway tax toggle     | Different VAT rates based on consumption location          |
| 5 Rappen rounding (cash only)       | Swiss currency requirement                                 |
| QR-bill generation                  | Swiss invoice format                                       |

---

**After Priority 3 is complete:** You have a cloud-connected restaurant POS compliant with German and Swiss regulations, with a web dashboard for remote management. This is MVP-2 + Market Packs.

---

## D. What NOT to Build Yet

These features are explicitly deferred. Building any of them before Priority 1-3 is complete would be a strategic error.

| Feature                    | Why Not Now                                                        | When                |
|----------------------------|--------------------------------------------------------------------|---------------------|
| Online ordering            | Requires solid cloud backend, payment processing, and customer UX. Core POS must work first. | Phase 6 (week 45+) |
| QR table ordering          | Depends on online ordering infrastructure. Premature without proven restaurant mode. | Phase 7 (week 55+) |
| Kiosk mode                 | Requires payment terminal integration and specialized UI. Not core value proposition. | Phase 8 (week 55+) |
| ERPNext bridge             | Accounting integration is enterprise-tier. Small restaurants don't need ERP. | Phase 9 (week 50+) |
| Retail mode                | Different UX paradigm. Focus on restaurant first, then expand. | Phase 10 (week 60+) |
| Loyalty / rewards program  | Nice-to-have, not a differentiator for initial customers. | V2.0+ |
| Inventory management       | Complex, low ROI for small restaurants. Use ERPNext later if needed. | Phase 9+ |
| Customer database / CRM    | Small restaurants don't need CRM. Online ordering will introduce customer data naturally. | Phase 6+ |
| Multi-language UI           | Ship with English + German. Proper i18n infrastructure is expensive to retrofit, but UI text is the smallest part of localization. | V2.0 |
| Custom receipt designer    | Provide good default templates. Custom design is a rabbit hole of UX complexity. | V3.0+ |
| Marketing website          | A simple landing page with pricing and contact form is sufficient for first 10 customers. | After first 5 customers |
| Delivery management        | Delivery is a different business. Partner with delivery platforms, don't build logistics. | Never (integrate, don't build) |
| Table reservation system   | Low priority. Most small restaurants take reservations by phone. | V2.0+ |
| Employee scheduling        | Out of scope. Use dedicated tools (Planday, When I Work). | Never |
| Tip management             | Track tip totals, but don't build tip pooling/distribution. | V2.0 |

---

## E. Top 10 Architecture Mistakes to Avoid

### 1. Starting with microservices

**The mistake:** Splitting the backend into 5+ services (auth-service, order-service, sync-service, fiscal-service) from day 1.

**Why it's wrong:** With 1-2 developers, microservices add operational overhead (deployment, networking, debugging) without any benefit. You don't know the service boundaries yet.

**What to do instead:** Modular monolith. Single Go binary with clean internal package boundaries. Extract a service only when you have a proven scaling reason (e.g., fiscal signing needs independent scaling).

### 2. Building ERPNext integration before POS works

**The mistake:** Connecting to ERPNext in Phase 1-2 because "we need proper accounting."

**Why it's wrong:** ERPNext integration is complex and fragile. If the POS can't reliably create orders, syncing bad data to ERPNext creates problems in two systems instead of one.

**What to do instead:** Build ERPNext bridge in Phase 9, after the POS has been proven with real customers. Use GastroCore's own reports for initial accounting needs.

### 3. Building cloud before local POS is solid

**The mistake:** Setting up cloud sync and web dashboard before the local POS can complete 1000 orders without a bug.

**Why it's wrong:** Cloud sync multiplies every local bug. A race condition that happens once locally will happen constantly with sync. Fix the foundation first.

**What to do instead:** Phases 1-2 are local-only. Prove the POS works offline with a real pilot customer before adding cloud complexity.

### 4. Over-engineering sync before understanding real conflicts

**The mistake:** Building a full CRDT implementation or operational transform system before seeing real-world usage patterns.

**Why it's wrong:** Most restaurant operations have low conflict rates (waiters work on different tables). You might build complex conflict resolution for scenarios that rarely occur.

**What to do instead:** Start with primary/secondary model (Phase 2). Track conflicts in Phase 3. Build sophisticated resolution only for conflicts that actually happen in production.

### 5. Trying to support every printer model

**The mistake:** Testing with 20 printer models and building device-specific drivers.

**Why it's wrong:** Printer diversity is a bottomless pit. Each model has quirks in Bluetooth pairing, ESC/POS dialect, paper width handling, and cut commands.

**What to do instead:** Certify 2-3 specific models (e.g., Epson TM-m30, Star SM-L200). Recommend these to customers. Add support for new models based on customer demand, not speculation.

### 6. Building QR/kiosk/online before restaurant mode is proven

**The mistake:** Adding multi-channel ordering before a waiter can reliably serve 25 tables.

**Why it's wrong:** Multi-channel adds complexity (channel routing, order prioritization, capacity management) that distracts from the core table service experience.

**What to do instead:** Prove restaurant mode with 2-3 pilot customers. Then add channels one at a time. Each channel builds on a proven core.

### 7. Skipping Germany fiscal requirements then retrofitting

**The mistake:** Ignoring TSE, DSFinV-K, and GoBD requirements during architecture, then trying to add them in Phase 4.

**Why it's wrong:** Fiscal compliance requires an immutable transaction log, sequential numbering, and specific data fields. Retrofitting these into an existing data model is painful and error-prone.

**What to do instead:** Design the transaction log with fiscal requirements in mind from day 1 (Phase 0). The log structure should accommodate TSE fields even before Fiskaly integration. This is why the immutable transaction log is in Priority 1, item 5.

### 8. Not having an immutable transaction log from day 1

**The mistake:** Storing orders as mutable records that can be updated or deleted.

**Why it's wrong:** For fiscal compliance (Germany), audit trails, and sync integrity, you need a complete history of every change. Mutating order records makes it impossible to reconstruct what happened.

**What to do instead:** Every state change creates a new log entry. Orders are never updated or deleted -- they transition through states (open, sent, paid, voided). The transaction log is append-only. This is foundational, not optional.

### 9. Using floating-point for money

**The mistake:** Representing prices and totals as `double` (e.g., `19.99`).

**Why it's wrong:** `0.1 + 0.2 != 0.3` in floating-point arithmetic. This causes rounding errors in tax calculations, split bills, and totals. A 1-cent error on a receipt destroys trust.

**What to do instead:** Use integer cents everywhere (1999 instead of 19.99). Use a `Money` value object that encapsulates currency, amount (int), and formatting. Only convert to decimal for display.

### 10. Not testing with real restaurant workflows

**The mistake:** Testing only happy paths in development, then being surprised when real waiters break the app in 5 minutes.

**Why it's wrong:** Waiters will tap faster than you thought possible, change their mind mid-order, get interrupted by customers, and use the app in ways you never imagined. No amount of unit testing replaces real-world observation.

**What to do instead:** Get a pilot customer by Phase 1 end. Observe them using the app during real service. Every friction point they discover is worth 10 bug reports.

---

## F. Top 10 Product Mistakes to Avoid

### 1. Adding features before core flow is fast and reliable

Every new feature is a liability until the core works. A restaurant with 50 features that crashes twice per shift will be replaced by a paper notepad.

### 2. Making UI complex to cover edge cases

90% of orders are simple: add items, pay, receipt. Design for the 90%. Put edge cases (split 5 ways with 3 payment methods and a coupon) behind extra taps, not on the main screen.

### 3. Not testing with real waiters

Developers tap differently than waiters. Waiters hold the tablet with one hand, tap with a thumb, get interrupted, and need to switch between tables in under 2 seconds. If you haven't watched a waiter use your app during Friday dinner rush, you haven't tested it.

### 4. Pricing too low

Restaurants are not price-sensitive for tools that work reliably. They pay EUR 50-150/month for POS systems happily. Pricing at EUR 9.99/month signals "hobby project" and attracts the wrong customers. Price for the value of reliable, compliant POS software.

### 5. Trying to compete with enterprise POS

Lightspeed and Toast have hundreds of developers. You cannot match their feature count. Compete on simplicity: "set up in 15 minutes, works offline, half the price, no long-term contract."

### 6. Not having proper offline UX

Users must always know: "Am I synced or not?" A small indicator (green checkmark = synced, orange dot = pending, red X = error) prevents confusion and support calls. Never silently fail a sync.

### 7. Ignoring receipt printing quality

The receipt is your product's physical output. If it's ugly, misaligned, missing info, or takes 10 seconds to print, the restaurant will judge the entire POS by that piece of paper. Invest in receipt quality early and continuously.

### 8. Building admin features before restaurant features

A beautiful web dashboard means nothing if the waiter can't take an order during dinner rush. Build restaurant-facing features first (order, kitchen, payment), admin second (reports, user management, settings).

### 9. Not planning for Germany fiscal from architecture phase

Germany fiscal compliance is not a "plugin" you add later. It affects your data model (immutable logs, sequential numbering), your receipt format (TSE QR codes), and your deployment architecture (cloud TSE connectivity). Plan for it in Phase 0.

### 10. Underestimating multi-device sync complexity

"Two tablets sharing data over WiFi" sounds simple. It is not. Network drops during peak hours, concurrent edits to the same table, one tablet rebooting while the other takes orders -- these are hard distributed systems problems. Budget twice the time you think you need.

---

## G. Repository / Folder Structure

```
gastrocore/                          # Monorepo root
├── apps/
│   ├── pos/                         # Flutter POS app (Android primary)
│   │   ├── lib/
│   │   │   ├── core/                # Shared infrastructure
│   │   │   │   ├── database/        # Drift schema, DAOs, migrations
│   │   │   │   ├── sync/            # LAN sync client, cloud sync client
│   │   │   │   ├── printing/        # ESC/POS commands, printer manager
│   │   │   │   ├── di/              # Dependency injection setup
│   │   │   │   ├── theme/           # Colors, typography, spacing tokens
│   │   │   │   ├── utils/           # Formatters, validators, constants
│   │   │   │   └── router/          # Navigation/routing
│   │   │   │
│   │   │   ├── features/            # Feature modules (vertical slices)
│   │   │   │   ├── auth/            # PIN login, session, lock screen
│   │   │   │   │   ├── data/        # Repositories, data sources
│   │   │   │   │   ├── domain/      # Entities, use cases
│   │   │   │   │   └── presentation/# Screens, widgets, state
│   │   │   │   │
│   │   │   │   ├── menu/            # Product catalog, categories, modifiers
│   │   │   │   │   ├── data/
│   │   │   │   │   ├── domain/
│   │   │   │   │   └── presentation/
│   │   │   │   │
│   │   │   │   ├── orders/          # Order creation, line items, totals
│   │   │   │   │   ├── data/
│   │   │   │   │   ├── domain/
│   │   │   │   │   └── presentation/
│   │   │   │   │
│   │   │   │   ├── tables/          # Floor plan, table management
│   │   │   │   │   ├── data/
│   │   │   │   │   ├── domain/
│   │   │   │   │   └── presentation/
│   │   │   │   │
│   │   │   │   ├── payments/        # Cash, card tracking, split bill
│   │   │   │   │   ├── data/
│   │   │   │   │   ├── domain/
│   │   │   │   │   └── presentation/
│   │   │   │   │
│   │   │   │   ├── kitchen/         # Kitchen ticket management
│   │   │   │   │   ├── data/
│   │   │   │   │   ├── domain/
│   │   │   │   │   └── presentation/
│   │   │   │   │
│   │   │   │   ├── shifts/          # Shift open/close, cash reconciliation
│   │   │   │   │   ├── data/
│   │   │   │   │   ├── domain/
│   │   │   │   │   └── presentation/
│   │   │   │   │
│   │   │   │   ├── reports/         # Shift summary, daily flash, charts
│   │   │   │   │   ├── data/
│   │   │   │   │   ├── domain/
│   │   │   │   │   └── presentation/
│   │   │   │   │
│   │   │   │   └── settings/        # App config, printer setup, tax rates
│   │   │   │       ├── data/
│   │   │   │       ├── domain/
│   │   │   │       └── presentation/
│   │   │   │
│   │   │   ├── shared/              # Cross-feature shared widgets
│   │   │   │   ├── widgets/         # Buttons, cards, dialogs, inputs
│   │   │   │   └── extensions/      # Dart extensions
│   │   │   │
│   │   │   └── main.dart            # App entry point
│   │   │
│   │   ├── android/                 # Android platform config
│   │   ├── web/                     # Future web build
│   │   ├── test/                    # Unit + widget tests
│   │   ├── integration_test/        # Integration tests
│   │   ├── pubspec.yaml
│   │   └── analysis_options.yaml
│   │
│   ├── kds/                         # Flutter KDS app (kitchen display)
│   │   ├── lib/
│   │   │   ├── core/
│   │   │   ├── features/
│   │   │   │   └── display/         # Ticket grid, bump, alerts
│   │   │   └── main.dart
│   │   ├── android/
│   │   ├── test/
│   │   └── pubspec.yaml
│   │
│   └── kiosk/                       # Flutter Kiosk app (future)
│       └── ...
│
├── server/                          # Go cloud backend (modular monolith)
│   ├── cmd/
│   │   └── server/
│   │       └── main.go              # Entry point, wire up modules
│   │
│   ├── internal/                    # Private application code
│   │   ├── auth/                    # JWT, device auth, user auth
│   │   │   ├── handler.go           # HTTP handlers
│   │   │   ├── service.go           # Business logic
│   │   │   ├── repository.go        # Data access
│   │   │   └── models.go            # Domain types
│   │   │
│   │   ├── sync/                    # Sync engine (device ↔ cloud)
│   │   │   ├── handler.go
│   │   │   ├── engine.go            # Sync logic, conflict resolution
│   │   │   ├── protocol.go          # Sync protocol types
│   │   │   └── repository.go
│   │   │
│   │   ├── menu/                    # Product catalog management
│   │   ├── orders/                  # Order processing, transaction log
│   │   ├── reports/                 # Materialized views, report queries
│   │   ├── devices/                 # Device registration, status
│   │   ├── licenses/                # Subscription, feature flags
│   │   ├── fiscal/                  # Fiskaly integration, TSE adapter
│   │   ├── online_ordering/         # Public menu API, order intake
│   │   ├── erpnext_bridge/          # ERPNext posting, data mapping
│   │   │
│   │   └── shared/                  # Cross-module utilities
│   │       ├── middleware/           # Auth, tenant, logging, CORS
│   │       ├── database/            # DB connection, transaction helpers
│   │       ├── money/               # Money type, tax calculation
│   │       └── errors/              # Error types, error handling
│   │
│   ├── pkg/                         # Shared public utilities
│   │   ├── config/                  # Configuration loading
│   │   └── logger/                  # Structured logging
│   │
│   ├── migrations/                  # PostgreSQL migrations (numbered)
│   │   ├── 001_initial_schema.sql
│   │   ├── 002_add_fiscal_tables.sql
│   │   └── ...
│   │
│   ├── go.mod
│   ├── go.sum
│   └── Makefile                     # Build, test, migrate commands
│
├── web/                             # Web dashboard (React or Flutter Web)
│   ├── src/
│   │   ├── pages/                   # Login, Dashboard, Reports, Menu, Users
│   │   ├── components/              # Charts, tables, forms
│   │   ├── services/                # API client
│   │   └── App.tsx
│   ├── package.json
│   └── ...
│
├── docs/                            # Architecture documentation
│   ├── 00-executive-summary.md
│   ├── 01-product-principles.md
│   ├── ...
│   ├── 20-implementation-order.md
│   └── adr/                         # Architecture Decision Records
│       ├── 001-offline-first.md
│       ├── 002-integer-money.md
│       ├── 003-modular-monolith.md
│       └── ...
│
├── infra/                           # Infrastructure and deployment
│   ├── docker-compose.yml           # Local dev: PostgreSQL, server
│   ├── docker-compose.prod.yml      # Production compose
│   ├── Dockerfile.server            # Go server container
│   ├── nginx.conf                   # Reverse proxy config
│   └── .github/
│       └── workflows/
│           ├── ci-flutter.yml       # Flutter lint, test, build
│           ├── ci-go.yml            # Go lint, test, build
│           └── deploy.yml           # Deploy to production
│
├── scripts/                         # Developer scripts
│   ├── seed_demo_data.sh            # Populate dev DB with sample data
│   ├── generate_license.sh          # Generate test license keys
│   ├── run_sync_simulation.sh       # Multi-device sync stress test
│   └── validate_dsfinvk.sh          # Validate DSFinV-K export
│
├── design/                          # Design assets
│   ├── figma-links.md               # Links to Figma designs
│   ├── wireframes/                  # Exported wireframe images
│   └── assets/                      # Icons, logos, brand assets
│
├── test/                            # Cross-project integration tests
│   ├── sync_simulation/             # Multi-device sync scenarios
│   │   ├── scenario_two_devices_offline.go
│   │   └── scenario_conflict_resolution.go
│   ├── fiscal_tests/                # Fiskaly sandbox tests
│   │   └── fiskaly_transaction_test.go
│   ├── printer_tests/               # ESC/POS output validation
│   │   └── receipt_format_test.dart
│   └── e2e/                         # End-to-end test scripts
│       └── full_order_flow_test.dart
│
├── fixtures/                        # Test data and sample content
│   ├── sample_menu_cafe.json        # Swiss cafe menu (30 items)
│   ├── sample_menu_restaurant.json  # German restaurant menu (80 items)
│   ├── sample_floor_plan.json       # 25-table restaurant layout
│   └── dsfinvk_reference/           # Reference DSFinV-K export data
│
├── .gitignore
├── .editorconfig
└── README.md                        # Project overview, setup instructions
```

### Key Structure Decisions

| Decision                              | Rationale                                                  |
|---------------------------------------|------------------------------------------------------------|
| Monorepo (all code in one repo)       | Shared tooling, atomic commits across Flutter + Go, easier dependency management for 1-5 person team |
| Feature-based folders in Flutter      | Each feature is a vertical slice (data, domain, presentation). Reduces cross-feature coupling. |
| `internal/` in Go                     | Go convention: internal packages cannot be imported by external code. Enforces encapsulation. |
| Separate `apps/kds/` and `apps/kiosk/` | KDS and kiosk are different apps with different UIs, not modes within the POS app. Separate build targets. |
| `migrations/` numbered sequentially   | Simple, predictable migration order. No framework magic. |
| `test/` at root for integration tests | Cross-project tests (sync simulation, fiscal) don't belong to a single app. |
| `fixtures/` for sample data           | Realistic test data shared across all developers and CI. |

---

## H. Test Strategy Overview

### Testing Pyramid

```
         /\
        /  \           E2E Tests
       / E2E\          (few, slow, high confidence)
      /------\
     / Integ. \        Integration Tests
    /----------\       (moderate count, medium speed)
   /   Unit     \      Unit Tests
  /--------------\     (many, fast, focused)
```

### Test Categories

#### 1. Unit Tests

**Scope:** Individual functions, methods, and classes in isolation.

| Area                    | Examples                                                     | Tool           |
|-------------------------|--------------------------------------------------------------|----------------|
| Price calculation        | Subtotal with quantities, tax calculation, rounding          | Dart test      |
| Tax calculation          | Swiss 8.1%, 2.6%, 3.8%; German 19%, 7%; dine-in vs takeaway | Dart test      |
| Money value object       | Addition, subtraction, multiplication, formatting, cents     | Dart test      |
| Split bill logic         | Split by item, equal split, rounding distribution            | Dart test      |
| 5 Rappen rounding        | Boundary cases: 0.01 to 0.05, 0.06 to 0.10, negative amounts | Dart test    |
| Discount application     | Percentage, fixed, combined, order-level vs item-level       | Dart test      |
| Order state transitions  | Valid transitions (open to paid), invalid (voided to open)   | Dart test      |
| Receipt template         | ESC/POS command generation, field formatting, alignment      | Dart test      |
| Sync conflict resolution | Last-writer-wins, item merge, conflict detection             | Go test        |
| Tenant isolation         | Query filtering by tenant_id, RLS policy validation          | Go test        |

**Target:** >90% coverage on domain logic. Run in <30 seconds. Every PR must pass.

#### 2. Integration Tests

**Scope:** Multiple components working together, including database.

| Area                    | Examples                                                     | Tool           |
|-------------------------|--------------------------------------------------------------|----------------|
| Drift DB operations      | CRUD for all entities, complex queries, migrations           | Dart integration test (in-memory SQLite) |
| Sync engine              | Device-to-cloud sync with realistic data, delta sync         | Go test with test DB |
| API endpoints            | Request/response validation, auth middleware, error handling  | Go httptest    |
| Fiscal posting           | Fiskaly sandbox transaction lifecycle                        | Go test with Fiskaly sandbox |
| ERPNext posting          | Sales invoice creation, payment entry, stock deduction       | Go test with ERPNext test instance |
| Report queries           | Materialized view refresh, aggregation accuracy              | Go test with test DB |

**Target:** Cover all critical data paths. Run in <5 minutes. Run on every PR.

#### 3. End-to-End Tests

**Scope:** Full user flows on the device.

| Flow                    | Steps                                                        | Tool           |
|-------------------------|--------------------------------------------------------------|----------------|
| Quick sale               | Login, add 3 items, pay cash, print receipt                 | Flutter integration test |
| Table order              | Open table, add items, send to kitchen, pay, close table    | Flutter integration test |
| Shift lifecycle          | Open shift, take orders, close shift, verify report         | Flutter integration test |
| Split bill               | Table with 4 items, split by item between 2 guests          | Flutter integration test |
| Void flow                | Add item, send to kitchen, void item with reason            | Flutter integration test |

**Target:** Cover top 5 user flows. Run in <15 minutes. Run before release.

#### 4. Fiscal Tests

**Scope:** German fiscal compliance with Fiskaly sandbox.

| Test                    | Validation                                                   | Frequency      |
|-------------------------|--------------------------------------------------------------|----------------|
| Transaction signing      | Start, update, finish returns valid signature                | Every PR       |
| Receipt QR code          | QR contains correct TSE data fields                         | Every PR       |
| DSFinV-K export          | Generated CSV passes DSFinV-K validation tool                | Weekly         |
| Offline queue recovery   | 50 transactions queued, all signed after reconnect           | Weekly         |
| Sequential numbering     | No gaps in transaction numbers after 1000 operations         | Before release |

#### 5. Sync Simulation Tests

**Scope:** Multi-device behavior under realistic conditions.

| Scenario                | Setup                                                        | Expected Result |
|-------------------------|--------------------------------------------------------------|-----------------|
| Two devices, no conflict | Device A creates orders, Device B creates orders, sync      | All orders in cloud |
| Same table conflict      | Device A and B edit same table offline, sync                 | Conflict resolved, no data loss |
| Network loss during sync | Start sync, kill network mid-transfer, reconnect            | Sync resumes, no corruption |
| Large offline backlog    | 500 orders offline, sync all at once                         | All synced within 5 minutes |
| Primary device failure   | Primary goes offline, secondary continues, primary returns   | Data reconciled |

#### 6. Printer Tests

**Scope:** ESC/POS output verification.

| Test                    | Method                                                       |
|-------------------------|--------------------------------------------------------------|
| Receipt formatting       | Generate ESC/POS commands, verify byte sequence against reference |
| Multi-line items         | Long product names wrap correctly within paper width         |
| Special characters       | Umlauts (a, o, u, ss), currency symbols (CHF, EUR)           |
| Cut command              | Paper cut command sent after receipt content                  |
| Encoding                 | CP437 / CP858 character encoding for European characters     |

#### 7. Network Interruption Tests

**Scope:** Behavior when connectivity is disrupted.

| Scenario                | Action                                                       | Expected        |
|-------------------------|--------------------------------------------------------------|-----------------|
| WiFi disabled mid-order  | Toggle airplane mode while creating an order                | Order saved locally, no error |
| Cloud unreachable        | Block cloud API endpoint, take 10 orders, unblock           | All 10 orders sync |
| Slow connection          | Throttle to 2G speed, attempt sync                          | Sync completes (slowly), no timeout |
| Fiskaly unreachable      | Block Fiskaly API, complete 5 orders, unblock               | 5 transactions signed after reconnect |

#### 8. Load Tests

**Scope:** Performance under stress.

| Test                    | Parameters                                                   | Target          |
|-------------------------|--------------------------------------------------------------|-----------------|
| 100 concurrent orders    | Simulate 100 orders in 10 minutes on single device          | No crashes, <500ms per order |
| 1000 orders in SQLite    | Query shift report with 1000 orders                         | Report in <2 seconds |
| 10 devices syncing       | 10 devices sync 50 orders each simultaneously               | All sync within 60 seconds |
| Materialized view refresh| Refresh with 100K orders across 10 tenants                  | Refresh in <30 seconds |

#### 9. Migration Tests

**Scope:** Database schema upgrades with existing data.

| Test                    | Method                                                       |
|-------------------------|--------------------------------------------------------------|
| SQLite migration (Drift) | Create DB with v1 schema, insert data, upgrade to v2, verify data integrity |
| PostgreSQL migration     | Apply migration to DB with production-like data, verify no data loss |
| Rollback safety          | Verify down migrations work (when applicable)                |
| Large dataset migration  | Migrate with 100K orders, verify performance                 |

#### 10. Manual QA Checklist (Per Release)

Before every release to a pilot customer or production, a human runs through:

- [ ] Fresh install on new tablet: app opens, setup wizard works
- [ ] PIN login works with correct and incorrect PINs
- [ ] Create product, create order, add product, pay cash, print receipt
- [ ] Receipt looks correct on physical printer (alignment, content, encoding)
- [ ] Open shift, process 5 orders, close shift, verify report totals
- [ ] Table flow: open table, order, send to kitchen, pay, close table
- [ ] Void an item: reason required, void appears in shift report
- [ ] Airplane mode: take 3 orders offline, reconnect, verify sync
- [ ] Cash variance: count cash at shift close, variance calculates correctly
- [ ] Settings: change business name, verify it appears on next receipt
- [ ] App survives 2 hours of continuous use without crash or slowdown
- [ ] Battery usage: app does not drain battery excessively in background
