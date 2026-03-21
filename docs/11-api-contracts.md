# API Contracts

> **Document Status:** Living document | **Last Updated:** 2026-03-20 | **Owner:** Architecture Team

---

## Table of Contents

1. [Overview](#1-overview)
2. [Branch Local API (Dart Interfaces)](#2-branch-local-api-dart-interfaces)
3. [Cloud API (REST)](#3-cloud-api-rest)
4. [ERPNext Bridge API](#4-erpnext-bridge-api)
5. [Online Ordering API](#5-online-ordering-api)
6. [Kiosk API](#6-kiosk-api)
7. [Webhook / Event Contracts](#7-webhook--event-contracts)

---

## 1. Overview

The platform exposes six distinct API surfaces. Each surface serves a different consumer and follows its own authentication and transport model.

```mermaid
graph TB
    subgraph "Branch Device"
        LOCAL["Branch Local API<br/>(Dart Interfaces)"]
    end

    subgraph "Cloud Hub"
        REST["Cloud REST API<br/>/v1/*"]
        WH["Webhook Emitter"]
    end

    subgraph "ERPNext"
        BRIDGE["ERPNext Bridge API<br/>(Internal Go Module)"]
    end

    subgraph "Customer-Facing"
        ONLINE["Online Ordering API<br/>(Public REST)"]
        KIOSK["Kiosk API<br/>(Local/Cloud REST)"]
    end

    LOCAL -->|"Sync over HTTPS"| REST
    REST --> BRIDGE
    REST --> WH
    ONLINE --> REST
    KIOSK --> REST
```

### Common Conventions

| Convention | Detail |
|---|---|
| **ID format** | UUID v7 (time-sortable), represented as lowercase hyphenated string |
| **Timestamps** | ISO 8601 with timezone for REST (`2026-03-20T14:30:00Z`), Unix milliseconds (INTEGER) for local storage |
| **Money** | Integer in smallest currency unit (cents/Rappen). Field suffix: `_cents` |
| **Pagination** | Cursor-based for all list endpoints |
| **Versioning** | URL-based: `/v1/`, `/v2/` |
| **Idempotency** | `X-Idempotency-Key` header required for all mutations (POST, PUT, PATCH, DELETE) |
| **Rate limiting** | Per-device and per-tenant limits, communicated via `X-RateLimit-*` headers |
| **Content type** | `application/json` for all request and response bodies |

### Standard Error Model

All APIs return errors in a consistent envelope:

```json
{
  "error": {
    "code": "ERR_VALIDATION_FAILED",
    "message": "Human-readable description of the error.",
    "details": {
      "field": "quantity",
      "reason": "must be greater than 0"
    }
  }
}
```

| HTTP Status | Error Code Pattern | Meaning |
|---|---|---|
| 400 | `ERR_VALIDATION_*` | Request body or parameters invalid |
| 401 | `ERR_AUTH_*` | Missing or invalid authentication |
| 403 | `ERR_FORBIDDEN_*` | Authenticated but insufficient permissions |
| 404 | `ERR_NOT_FOUND` | Resource does not exist |
| 409 | `ERR_CONFLICT_*` | Idempotency conflict or version conflict |
| 422 | `ERR_BUSINESS_*` | Business rule violation (e.g., shift already closed) |
| 429 | `ERR_RATE_LIMITED` | Too many requests |
| 500 | `ERR_INTERNAL` | Server error, safe to retry |
| 503 | `ERR_UNAVAILABLE` | Service temporarily unavailable |

### Standard Pagination Envelope

```json
{
  "data": [ ... ],
  "cursor": "eyJpZCI6IjAxOTBhYjNjLWRlZjAifQ==",
  "has_more": true
}
```

Query parameters: `?cursor=xxx&limit=50` (default limit 50, max 200).

---

## 2. Branch Local API (Dart Interfaces)

The Branch Local API is **not HTTP-based**. It consists of Dart repository interfaces consumed through the Riverpod provider layer. All data access follows the pattern:

```
Repository (SQLite/Drift) --> UseCase --> Provider (Riverpod) --> Widget
```

### 2.1 Architecture Pattern

```mermaid
graph LR
    W["Widget"] --> P["Riverpod Provider"]
    P --> UC["UseCase"]
    UC --> R["Repository Interface"]
    R --> DB["Drift Database<br/>(SQLite)"]
```

- **Repository**: Pure data access. Returns `Future<T>` or `Stream<T>`. No business logic.
- **UseCase**: Orchestrates one or more repositories. Contains business rules and validation.
- **Provider**: Riverpod `StateNotifier`, `AsyncNotifier`, or `StreamProvider`. Manages UI state and triggers use cases.

### 2.2 Repository Interfaces by Module

#### Auth Module

```dart
abstract class AuthRepository {
  Future<User?> authenticateByPin(String pinHash);
  Future<List<User>> getActiveUsers();
  Future<User> createUser(UserCreateParams params);
  Future<void> updateUser(String userId, UserUpdateParams params);
  Future<void> deactivateUser(String userId);
  Future<bool> validateManagerPin(String pinHash);
  Future<void> recordLoginEvent(String userId, String deviceId);
  Future<void> recordLogoutEvent(String userId, String deviceId);
}
```

#### Menu Module

```dart
abstract class MenuRepository {
  // Categories
  Future<List<Category>> getCategories();
  Stream<List<Category>> watchCategories();
  Future<Category> createCategory(CategoryCreateParams params);
  Future<void> updateCategory(String categoryId, CategoryUpdateParams params);
  Future<void> reorderCategories(List<String> categoryIds);
  Future<void> deleteCategory(String categoryId); // soft delete

  // Products
  Future<List<Product>> getProductsByCategory(String categoryId);
  Stream<List<Product>> watchProductsByCategory(String categoryId);
  Future<Product> getProduct(String productId);
  Future<Product> createProduct(ProductCreateParams params);
  Future<void> updateProduct(String productId, ProductUpdateParams params);
  Future<void> toggleProductAvailability(String productId, bool available);
  Future<void> deleteProduct(String productId); // soft delete

  // Modifiers
  Future<List<ModifierGroup>> getModifierGroups();
  Future<ModifierGroup> createModifierGroup(ModifierGroupCreateParams params);
  Future<void> updateModifierGroup(String groupId, ModifierGroupUpdateParams params);
  Future<void> deleteModifierGroup(String groupId); // soft delete

  // Price Lists
  Future<PriceList> getActivePriceList();
  Future<int> getProductPrice(String productId, {String? priceListId});
}
```

#### Orders Module

```dart
abstract class OrderRepository {
  Future<Ticket> createTicket(TicketCreateParams params);
  Future<Ticket> getTicket(String ticketId);
  Stream<Ticket> watchTicket(String ticketId);
  Future<List<Ticket>> getOpenTickets();
  Stream<List<Ticket>> watchOpenTickets();
  Future<void> addOrderItem(String ticketId, OrderItemCreateParams params);
  Future<void> updateOrderItem(String orderItemId, OrderItemUpdateParams params);
  Future<void> voidOrderItem(String orderItemId, VoidParams params);
  Future<void> moveOrderItems(List<String> itemIds, String targetTicketId);
  Future<void> updateTicketStatus(String ticketId, TicketStatus status);
  Future<void> setCourseFiring(String ticketId, int courseNumber);
  Future<List<Ticket>> getTicketsByDateRange(DateTime start, DateTime end);
}
```

#### Tables Module

```dart
abstract class TableRepository {
  Future<List<Floor>> getFloors();
  Stream<List<Floor>> watchFloors();
  Future<Floor> createFloor(FloorCreateParams params);
  Future<void> updateFloor(String floorId, FloorUpdateParams params);

  Future<List<RestaurantTable>> getTablesByFloor(String floorId);
  Stream<List<RestaurantTable>> watchTablesByFloor(String floorId);
  Future<RestaurantTable> createTable(TableCreateParams params);
  Future<void> updateTable(String tableId, TableUpdateParams params);

  Future<TableSession> openTable(String tableId, TableSessionCreateParams params);
  Future<void> closeTable(String sessionId);
  Future<void> transferTable(String sessionId, String newTableId);
  Future<TableSession?> getActiveSession(String tableId);
  Stream<List<TableSession>> watchActiveSessions();
}
```

#### Payments Module

```dart
abstract class PaymentRepository {
  Future<Bill> createBill(BillCreateParams params);
  Future<Bill> getBill(String billId);
  Future<List<Bill>> getBillsByTicket(String ticketId);
  Future<Payment> recordPayment(PaymentCreateParams params);
  Future<void> voidPayment(String paymentId, VoidParams params);
  Future<Refund> processRefund(RefundCreateParams params);
  Future<void> recordTip(String paymentId, int tipAmountCents);
  Future<int> calculateChange(int billAmountCents, int tenderedCents);
}
```

#### Kitchen Module

```dart
abstract class KitchenRepository {
  Future<KitchenTicket> createKitchenTicket(KitchenTicketCreateParams params);
  Future<List<KitchenTicket>> getPendingTickets();
  Stream<List<KitchenTicket>> watchPendingTickets();
  Future<void> bumpTicket(String ticketId);
  Future<void> bumpItem(String itemId);
  Future<void> recallTicket(String ticketId);
  Future<void> updateItemStatus(String itemId, KitchenItemStatus status);
  Future<void> prioritizeTicket(String ticketId);
  Future<Duration> getAverageTicketTime({DateTime? since});
}
```

#### Shifts Module

```dart
abstract class ShiftRepository {
  Future<Shift> openShift(ShiftOpenParams params);
  Future<Shift?> getCurrentShift();
  Stream<Shift?> watchCurrentShift();
  Future<void> closeShift(String shiftId, ShiftCloseParams params);
  Future<CashMovement> recordCashMovement(CashMovementCreateParams params);
  Future<List<CashMovement>> getCashMovements(String shiftId);
  Future<ShiftSummary> getShiftSummary(String shiftId);
  Future<List<Shift>> getShiftHistory({int limit = 20, String? cursor});
}
```

#### Reports Module

```dart
abstract class ReportsRepository {
  Future<DailySalesSummary> getDailySales(DateTime date);
  Future<List<ProductSalesEntry>> getProductSales(DateTime start, DateTime end);
  Future<List<HourlyRevenueEntry>> getHourlyRevenue(DateTime date);
  Future<ShiftReport> getShiftReport(String shiftId);
  Future<StaffPerformance> getStaffPerformance(String userId, DateTime start, DateTime end);
  Future<CategorySalesBreakdown> getCategorySales(DateTime start, DateTime end);
  Future<PaymentMethodBreakdown> getPaymentBreakdown(DateTime start, DateTime end);
}
```

#### Sync Module

```dart
abstract class SyncRepository {
  Future<void> enqueueChange(SyncQueueEntry entry);
  Future<List<SyncQueueEntry>> getPendingChanges({int limit = 100});
  Future<void> markSynced(List<String> entryIds);
  Future<void> markFailed(String entryId, String errorMessage);
  Future<SyncMetadata> getLastSyncMetadata(String entityType);
  Future<void> updateSyncMetadata(String entityType, SyncMetadata metadata);
  Future<int> getPendingSyncCount();
  Stream<int> watchPendingSyncCount();
  Future<void> processIncomingChanges(List<SyncChange> changes);
}
```

#### Printing Module

```dart
abstract class PrintingRepository {
  Future<List<Printer>> getConfiguredPrinters();
  Future<void> addPrinter(PrinterConfig config);
  Future<void> removePrinter(String printerId);
  Future<void> testPrint(String printerId);
  Future<void> printReceipt(String billId, {bool duplicate = false});
  Future<void> printKitchenTicket(String kitchenTicketId);
  Future<void> printShiftReport(String shiftId);
  Future<void> openCashDrawer(String printerId);
}
```

#### Settings Module

```dart
abstract class SettingsRepository {
  Future<Map<String, dynamic>> getAllSettings();
  Future<T> getSetting<T>(String key);
  Future<void> setSetting(String key, dynamic value);
  Future<void> setSettings(Map<String, dynamic> settings);
  Stream<Map<String, dynamic>> watchSettings();
  Future<void> resetToDefaults();
  Future<License> getLicenseInfo();
  Future<void> updateLicense(String licenseToken);
}
```

---

## 3. Cloud API (REST)

**Base URL:** `https://api.{product}.com/v1/`

### 3.1 Authentication

All Cloud API requests require a `Bearer` token in the `Authorization` header. Two token types exist:

| Token Type | Issued Via | Lifetime | Use Case |
|---|---|---|---|
| **Device Token** | `POST /auth/device` | 30 days, auto-refresh | Device-to-cloud sync |
| **User Token** | `POST /auth/login` | 24 hours | Cloud admin dashboard |

```
Authorization: Bearer eyJhbGciOiJFUzI1NiJ9...
```

### 3.2 Auth Endpoints

#### `POST /v1/auth/device`

Register or re-authenticate a device.

**Request:**
```json
{
  "device_id": "019abc12-3456-7def-8901-234567890abc",
  "device_secret": "base64-encoded-device-secret",
  "branch_id": "019abc12-0000-7def-8901-234567890abc",
  "device_name": "POS-Terminal-1",
  "device_type": "pos_terminal",
  "app_version": "1.4.2"
}
```

**Response (200):**
```json
{
  "token": "eyJhbGciOiJFUzI1NiJ9...",
  "expires_at": "2026-04-19T14:30:00Z",
  "tenant_id": "019abc12-9999-7def-8901-234567890abc",
  "branch_id": "019abc12-0000-7def-8901-234567890abc",
  "features": ["multi_device", "kds", "cloud_sync", "country_ch"]
}
```

#### `POST /v1/auth/login`

Authenticate a cloud admin user.

**Request:**
```json
{
  "email": "owner@restaurant.ch",
  "password": "...",
  "totp_code": "123456"
}
```

**Response (200):**
```json
{
  "token": "eyJhbGciOiJFUzI1NiJ9...",
  "expires_at": "2026-03-21T14:30:00Z",
  "user": {
    "id": "019abc12-1111-7def-8901-234567890abc",
    "email": "owner@restaurant.ch",
    "name": "Marco Rossi",
    "role": "owner",
    "tenant_id": "019abc12-9999-7def-8901-234567890abc"
  }
}
```

#### `POST /v1/auth/refresh`

Refresh an expiring token.

**Request:**
```json
{
  "token": "eyJhbGciOiJFUzI1NiJ9..."
}
```

**Response (200):**
```json
{
  "token": "eyJhbGciOiJFUzI1NiJ9...(new token)",
  "expires_at": "2026-04-20T14:30:00Z"
}
```

### 3.3 Sync Endpoints

#### `POST /v1/sync/upload`

Upload a batch of local changes to the cloud.

**Headers:**
```
Authorization: Bearer ...
X-Idempotency-Key: 019abc12-batch-001
Content-Type: application/json
```

**Request:**
```json
{
  "device_id": "019abc12-3456-7def-8901-234567890abc",
  "batch_id": "019abc12-batch-001",
  "changes": [
    {
      "entity_type": "order_item",
      "entity_id": "019abc12-item-0001",
      "action": "create",
      "data": {
        "ticket_id": "019abc12-tick-0001",
        "product_id": "019abc12-prod-0042",
        "quantity": 2,
        "unit_price_cents": 1450,
        "created_at": 1710942600000
      },
      "local_timestamp": 1710942600000
    },
    {
      "entity_type": "ticket",
      "entity_id": "019abc12-tick-0001",
      "action": "update",
      "data": {
        "status": "closed",
        "closed_at": 1710943200000
      },
      "local_timestamp": 1710943200000
    }
  ],
  "last_sync_cursor": "eyJpZCI6IjAxOTBhYiJ9"
}
```

**Response (200):**
```json
{
  "batch_id": "019abc12-batch-001",
  "accepted": 2,
  "rejected": 0,
  "conflicts": [],
  "server_cursor": "eyJpZCI6IjAxOTBhYzRkIn0="
}
```

#### `GET /v1/sync/download?cursor={cursor}&limit=100`

Download changes from cloud that the device has not yet seen.

**Response (200):**
```json
{
  "data": [
    {
      "entity_type": "product",
      "entity_id": "019abc12-prod-0099",
      "action": "update",
      "data": {
        "name": "Margherita Pizza",
        "price_cents": 1600,
        "updated_at": "2026-03-20T10:00:00Z"
      },
      "server_timestamp": "2026-03-20T10:00:00Z"
    }
  ],
  "cursor": "eyJpZCI6IjAxOTBhYzRkLWVmZzAifQ==",
  "has_more": false
}
```

#### `POST /v1/sync/seed`

Request a full data seed for a newly registered or factory-reset device.

**Request:**
```json
{
  "device_id": "019abc12-3456-7def-8901-234567890abc",
  "entity_types": ["categories", "products", "modifier_groups", "modifiers", "floors", "tables", "users", "settings", "price_lists", "tax_categories"]
}
```

**Response (200):**
```json
{
  "seed_id": "019abc12-seed-001",
  "status": "ready",
  "download_url": "https://api.example.com/v1/sync/seed/019abc12-seed-001/download",
  "size_bytes": 2450000,
  "expires_at": "2026-03-20T15:30:00Z"
}
```

### 3.4 Menu Endpoints

#### `GET /v1/menu/categories?cursor={cursor}&limit=50`

**Response (200):**
```json
{
  "data": [
    {
      "id": "019abc12-cat-001",
      "name": "Pizzas",
      "sort_order": 1,
      "color": "#E74C3C",
      "icon": "pizza",
      "is_active": true,
      "product_count": 12,
      "created_at": "2026-01-15T09:00:00Z",
      "updated_at": "2026-03-18T14:22:00Z"
    }
  ],
  "cursor": "eyJpZCI6IjAxOTBhYmMxMi1jYXQtMDAxIn0=",
  "has_more": true
}
```

#### `POST /v1/menu/products`

**Headers:**
```
X-Idempotency-Key: 019abc12-create-prod-001
```

**Request:**
```json
{
  "name": "Quattro Stagioni",
  "category_id": "019abc12-cat-001",
  "sku": "PIZ-004",
  "price_cents": 2200,
  "tax_category_id": "019abc12-tax-reduced",
  "description": "Four seasons pizza with ham, mushrooms, artichokes, olives",
  "is_active": true,
  "sort_order": 4,
  "modifier_group_ids": ["019abc12-mod-size", "019abc12-mod-extras"],
  "tags": ["vegetarian_option"],
  "image_url": null
}
```

**Response (201):**
```json
{
  "id": "019abc12-prod-0100",
  "name": "Quattro Stagioni",
  "category_id": "019abc12-cat-001",
  "sku": "PIZ-004",
  "price_cents": 2200,
  "tax_category_id": "019abc12-tax-reduced",
  "description": "Four seasons pizza with ham, mushrooms, artichokes, olives",
  "is_active": true,
  "sort_order": 4,
  "modifier_groups": [
    {
      "id": "019abc12-mod-size",
      "name": "Size",
      "required": true,
      "min_select": 1,
      "max_select": 1
    },
    {
      "id": "019abc12-mod-extras",
      "name": "Extra Toppings",
      "required": false,
      "min_select": 0,
      "max_select": 5
    }
  ],
  "tags": ["vegetarian_option"],
  "image_url": null,
  "created_at": "2026-03-20T14:30:00Z",
  "updated_at": "2026-03-20T14:30:00Z"
}
```

#### `PATCH /v1/menu/products/{product_id}`

**Request:**
```json
{
  "price_cents": 2350,
  "is_active": false
}
```

**Response (200):** Returns the full updated product object.

### 3.5 Branches Endpoints

#### `GET /v1/branches`

**Response (200):**
```json
{
  "data": [
    {
      "id": "019abc12-0000-7def-8901-234567890abc",
      "name": "Hauptstandort Zurich",
      "address": {
        "street": "Bahnhofstrasse 42",
        "city": "Zurich",
        "postal_code": "8001",
        "country": "CH"
      },
      "timezone": "Europe/Zurich",
      "currency": "CHF",
      "is_active": true,
      "device_count": 3,
      "floor_count": 2
    }
  ],
  "cursor": null,
  "has_more": false
}
```

#### `POST /v1/branches/{branch_id}/floors`

**Request:**
```json
{
  "name": "Terrace",
  "sort_order": 2
}
```

**Response (201):**
```json
{
  "id": "019abc12-floor-002",
  "branch_id": "019abc12-0000-7def-8901-234567890abc",
  "name": "Terrace",
  "sort_order": 2,
  "table_count": 0,
  "created_at": "2026-03-20T14:35:00Z"
}
```

#### `POST /v1/branches/{branch_id}/floors/{floor_id}/tables`

**Request:**
```json
{
  "number": "T5",
  "label": "Terrace 5",
  "seats": 4,
  "shape": "round",
  "position_x": 320,
  "position_y": 180,
  "width": 80,
  "height": 80
}
```

**Response (201):**
```json
{
  "id": "019abc12-tbl-T5",
  "floor_id": "019abc12-floor-002",
  "number": "T5",
  "label": "Terrace 5",
  "seats": 4,
  "shape": "round",
  "position_x": 320,
  "position_y": 180,
  "width": 80,
  "height": 80,
  "status": "available",
  "created_at": "2026-03-20T14:36:00Z"
}
```

### 3.6 Reports Endpoints

#### `GET /v1/reports/sales?date=2026-03-20&branch_id={branch_id}`

**Response (200):**
```json
{
  "date": "2026-03-20",
  "branch_id": "019abc12-0000-7def-8901-234567890abc",
  "summary": {
    "gross_revenue_cents": 845000,
    "net_revenue_cents": 783333,
    "tax_total_cents": 61667,
    "order_count": 67,
    "average_order_cents": 12612,
    "covers": 142
  },
  "by_payment_method": [
    { "method": "cash", "amount_cents": 338000, "count": 28 },
    { "method": "card", "amount_cents": 507000, "count": 39 }
  ],
  "by_hour": [
    { "hour": 11, "revenue_cents": 125000, "order_count": 10 },
    { "hour": 12, "revenue_cents": 210000, "order_count": 18 }
  ]
}
```

#### `GET /v1/reports/products?start=2026-03-14&end=2026-03-20&branch_id={branch_id}&limit=20`

**Response (200):**
```json
{
  "data": [
    {
      "product_id": "019abc12-prod-0042",
      "product_name": "Margherita Pizza",
      "category_name": "Pizzas",
      "quantity_sold": 145,
      "gross_revenue_cents": 232000,
      "percentage_of_total": 18.5
    }
  ],
  "cursor": "eyJpZCI6IjAxOTBhYmMxMi1wcm9kLTAwNDIifQ==",
  "has_more": true
}
```

#### `GET /v1/reports/shifts/{shift_id}`

**Response (200):**
```json
{
  "shift_id": "019abc12-shft-001",
  "user_name": "Anna Mueller",
  "opened_at": "2026-03-20T07:00:00Z",
  "closed_at": "2026-03-20T15:30:00Z",
  "opening_cash_cents": 20000,
  "closing_cash_cents": 52500,
  "expected_cash_cents": 53800,
  "cash_variance_cents": -1300,
  "total_sales_cents": 425000,
  "order_count": 34,
  "void_count": 2,
  "void_amount_cents": 3200,
  "refund_count": 1,
  "refund_amount_cents": 1500,
  "cash_movements": [
    { "type": "cash_in", "amount_cents": 5000, "reason": "Change refill", "timestamp": "2026-03-20T10:15:00Z" }
  ]
}
```

### 3.7 Orders Endpoints (Read-Only from Cloud)

#### `GET /v1/orders?branch_id={branch_id}&status=closed&date=2026-03-20&cursor={cursor}&limit=50`

**Response (200):**
```json
{
  "data": [
    {
      "id": "019abc12-tick-0001",
      "branch_id": "019abc12-0000-7def-8901-234567890abc",
      "table_number": "A3",
      "order_type": "dine_in",
      "status": "closed",
      "covers": 4,
      "waiter_name": "Luca Bianchi",
      "subtotal_cents": 12800,
      "tax_cents": 985,
      "total_cents": 13785,
      "created_at": "2026-03-20T12:15:00Z",
      "closed_at": "2026-03-20T13:22:00Z",
      "item_count": 6
    }
  ],
  "cursor": "eyJpZCI6IjAxOTBhYmMxMi10aWNrLTAwMDEifQ==",
  "has_more": true
}
```

#### `GET /v1/orders/{order_id}`

**Response (200):**
```json
{
  "id": "019abc12-tick-0001",
  "branch_id": "019abc12-0000-7def-8901-234567890abc",
  "table_number": "A3",
  "order_type": "dine_in",
  "status": "closed",
  "covers": 4,
  "waiter": {
    "id": "019abc12-user-003",
    "name": "Luca Bianchi"
  },
  "items": [
    {
      "id": "019abc12-item-0001",
      "product_name": "Margherita Pizza",
      "quantity": 2,
      "unit_price_cents": 1450,
      "modifiers": [
        { "name": "Extra Mozzarella", "price_cents": 200 }
      ],
      "line_total_cents": 3100,
      "status": "served",
      "course": 1
    }
  ],
  "bills": [
    {
      "id": "019abc12-bill-001",
      "amount_cents": 13785,
      "payments": [
        {
          "method": "card",
          "amount_cents": 13785,
          "tip_cents": 200,
          "timestamp": "2026-03-20T13:20:00Z"
        }
      ]
    }
  ],
  "subtotal_cents": 12800,
  "tax_cents": 985,
  "total_cents": 13785,
  "created_at": "2026-03-20T12:15:00Z",
  "closed_at": "2026-03-20T13:22:00Z"
}
```

### 3.8 Devices Endpoints

#### `POST /v1/devices/register`

**Request:**
```json
{
  "device_id": "019abc12-3456-7def-8901-234567890abc",
  "branch_id": "019abc12-0000-7def-8901-234567890abc",
  "pairing_code": "A3X9K2",
  "device_name": "KDS-Kitchen-1",
  "device_type": "kds",
  "os": "android",
  "os_version": "13",
  "app_version": "1.4.2",
  "capabilities": ["display", "audio"]
}
```

**Response (201):**
```json
{
  "device_id": "019abc12-3456-7def-8901-234567890abc",
  "device_secret": "base64-encoded-secret-for-secure-storage",
  "branch_id": "019abc12-0000-7def-8901-234567890abc",
  "tenant_id": "019abc12-9999-7def-8901-234567890abc",
  "registered_at": "2026-03-20T14:40:00Z"
}
```

#### `POST /v1/devices/{device_id}/health`

**Request:**
```json
{
  "battery_level": 78,
  "storage_free_mb": 4200,
  "app_version": "1.4.2",
  "last_sync_at": "2026-03-20T14:35:00Z",
  "pending_sync_count": 3,
  "uptime_seconds": 28800
}
```

**Response (204):** No content.

#### `GET /v1/devices?branch_id={branch_id}`

**Response (200):**
```json
{
  "data": [
    {
      "device_id": "019abc12-3456-7def-8901-234567890abc",
      "device_name": "POS-Terminal-1",
      "device_type": "pos_terminal",
      "branch_id": "019abc12-0000-7def-8901-234567890abc",
      "status": "online",
      "last_seen_at": "2026-03-20T14:45:00Z",
      "app_version": "1.4.2",
      "battery_level": 78
    }
  ],
  "cursor": null,
  "has_more": false
}
```

### 3.9 Licenses Endpoints

#### `POST /v1/licenses/validate`

**Request:**
```json
{
  "license_token": "eyJhbGciOiJFUzI1NiJ9...",
  "device_id": "019abc12-3456-7def-8901-234567890abc"
}
```

**Response (200):**
```json
{
  "valid": true,
  "tenant_id": "019abc12-9999-7def-8901-234567890abc",
  "tier": "professional",
  "features": ["multi_device", "kds", "cloud_sync", "country_ch"],
  "device_limit": 5,
  "devices_registered": 3,
  "valid_from": "2026-01-01T00:00:00Z",
  "valid_until": "2026-12-31T23:59:59Z"
}
```

#### `POST /v1/licenses/activate`

**Request:**
```json
{
  "license_key": "XXXX-XXXX-XXXX-XXXX",
  "tenant_id": "019abc12-9999-7def-8901-234567890abc"
}
```

**Response (200):**
```json
{
  "license_token": "eyJhbGciOiJFUzI1NiJ9...",
  "tier": "professional",
  "valid_until": "2026-12-31T23:59:59Z"
}
```

### 3.10 Fiscal Endpoints

#### `POST /v1/fiscal/sign`

Proxy a transaction signing request to the configured fiscal provider (Fiskaly TSE for Germany).

**Request:**
```json
{
  "branch_id": "019abc12-0000-7def-8901-234567890abc",
  "transaction_type": "receipt",
  "receipt_data": {
    "receipt_number": "2026-0320-0042",
    "total_cents": 13785,
    "tax_lines": [
      { "rate": "7.70", "net_cents": 12800, "tax_cents": 985 }
    ],
    "payment_method": "card",
    "timestamp": "2026-03-20T13:20:00Z"
  }
}
```

**Response (200):**
```json
{
  "signature": "MEUCIQDx...base64-signature",
  "tse_serial": "TSE-SN-12345",
  "transaction_number": 42,
  "signature_counter": 1337,
  "start_time": "2026-03-20T13:20:00Z",
  "end_time": "2026-03-20T13:20:01Z",
  "qr_code_data": "V0;TSE-SN-12345;42;2026-03-20T13:20:00;13.785;7.70;..."
}
```

#### `GET /v1/fiscal/receipts/{receipt_id}`

Retrieve a previously signed fiscal receipt.

**Response (200):**
```json
{
  "receipt_id": "019abc12-rcpt-0042",
  "receipt_number": "2026-0320-0042",
  "signature": "MEUCIQDx...base64-signature",
  "qr_code_data": "V0;TSE-SN-12345;42;...",
  "pdf_url": "https://storage.example.com/receipts/019abc12-rcpt-0042.pdf",
  "signed_at": "2026-03-20T13:20:01Z"
}
```

#### `POST /v1/fiscal/dsfinvk/export`

Trigger a DSFinV-K export for a date range (Germany compliance).

**Request:**
```json
{
  "branch_id": "019abc12-0000-7def-8901-234567890abc",
  "start_date": "2026-01-01",
  "end_date": "2026-03-31"
}
```

**Response (202):**
```json
{
  "export_id": "019abc12-dsfk-001",
  "status": "processing",
  "estimated_completion": "2026-03-20T15:00:00Z"
}
```

### 3.11 Online Orders Endpoints

#### `POST /v1/online-orders`

Create an order received from the online ordering channel.

**Request:**
```json
{
  "branch_id": "019abc12-0000-7def-8901-234567890abc",
  "channel": "web",
  "customer": {
    "name": "Sarah Weber",
    "phone": "+41791234567",
    "email": "sarah@example.com"
  },
  "order_type": "pickup",
  "requested_time": "2026-03-20T18:30:00Z",
  "items": [
    {
      "product_id": "019abc12-prod-0042",
      "quantity": 1,
      "modifiers": [
        { "modifier_id": "019abc12-modopt-003", "quantity": 1 }
      ],
      "special_instructions": "No onions"
    }
  ],
  "payment_method": "online_card",
  "payment_reference": "pi_3abc123def456"
}
```

**Response (201):**
```json
{
  "id": "019abc12-onl-001",
  "order_number": "W-0042",
  "status": "pending_acceptance",
  "estimated_ready_at": null,
  "created_at": "2026-03-20T17:45:00Z"
}
```

#### `PATCH /v1/online-orders/{order_id}/status`

Update the status of an online order (accept, reject, ready, etc.).

**Request:**
```json
{
  "status": "accepted",
  "estimated_ready_at": "2026-03-20T18:15:00Z"
}
```

**Response (200):**
```json
{
  "id": "019abc12-onl-001",
  "status": "accepted",
  "estimated_ready_at": "2026-03-20T18:15:00Z",
  "updated_at": "2026-03-20T17:46:00Z"
}
```

#### `POST /v1/online-orders/{order_id}/cancel`

**Request:**
```json
{
  "reason": "customer_requested",
  "message": "Customer called to cancel"
}
```

**Response (200):**
```json
{
  "id": "019abc12-onl-001",
  "status": "cancelled",
  "cancel_reason": "customer_requested",
  "cancelled_at": "2026-03-20T17:50:00Z"
}
```

### 3.12 Admin Endpoints

#### `GET /v1/admin/tenant`

**Response (200):**
```json
{
  "id": "019abc12-9999-7def-8901-234567890abc",
  "name": "Pizzeria Napoli GmbH",
  "country": "CH",
  "currency": "CHF",
  "timezone": "Europe/Zurich",
  "subscription": {
    "tier": "professional",
    "status": "active",
    "current_period_end": "2026-12-31T23:59:59Z"
  },
  "branches": 1,
  "devices": 3,
  "users": 8
}
```

#### `POST /v1/admin/users`

**Request:**
```json
{
  "name": "Maria Gonzalez",
  "email": "maria@restaurant.ch",
  "role": "waiter",
  "pin": "1234",
  "branches": ["019abc12-0000-7def-8901-234567890abc"]
}
```

**Response (201):**
```json
{
  "id": "019abc12-user-009",
  "name": "Maria Gonzalez",
  "email": "maria@restaurant.ch",
  "role": "waiter",
  "branches": ["019abc12-0000-7def-8901-234567890abc"],
  "created_at": "2026-03-20T15:00:00Z"
}
```

#### `PATCH /v1/admin/settings`

**Request:**
```json
{
  "receipt_header": "Pizzeria Napoli\nBahnhofstrasse 42\n8001 Zurich",
  "receipt_footer": "Thank you for your visit!",
  "default_tax_rate": "7.70",
  "rounding_mode": "five_rappen",
  "auto_accept_online_orders": false,
  "kitchen_ticket_auto_print": true
}
```

**Response (200):** Returns the full updated settings object.

### 3.13 Rate Limiting

| Scope | Limit | Window |
|---|---|---|
| Per device (sync) | 60 requests | 1 minute |
| Per device (general) | 300 requests | 1 minute |
| Per tenant (aggregate) | 1000 requests | 1 minute |
| Per tenant (reports) | 30 requests | 1 minute |

**Rate limit headers:**
```
X-RateLimit-Limit: 300
X-RateLimit-Remaining: 287
X-RateLimit-Reset: 1710943260
```

When rate limited, the response is:
```json
{
  "error": {
    "code": "ERR_RATE_LIMITED",
    "message": "Rate limit exceeded. Retry after 13 seconds.",
    "details": {
      "retry_after_seconds": 13
    }
  }
}
```

---

## 4. ERPNext Bridge API

The ERPNext Bridge is an **internal Go module** within the Cloud Hub. It is not exposed as a public API. It communicates with a Frappe/ERPNext instance via the Frappe REST API.

### 4.1 Architecture

```mermaid
graph LR
    HUB["Cloud Hub<br/>(Go)"] --> BRIDGE["ERPNext Bridge<br/>(Go Module)"]
    BRIDGE -->|"Frappe REST API"| ERP["ERPNext Instance"]
    ERP -->|"Webhooks"| BRIDGE
```

### 4.2 Internal Interface (Go)

```go
type ERPNextBridge interface {
    // Sales posting
    PostSalesInvoice(ctx context.Context, req SalesInvoiceRequest) (*SalesInvoiceResponse, error)
    PostPaymentEntry(ctx context.Context, req PaymentEntryRequest) (*PaymentEntryResponse, error)

    // Master data sync
    SyncItems(ctx context.Context, tenantID string) (*SyncResult, error)
    SyncPrices(ctx context.Context, tenantID string) (*SyncResult, error)
    SyncCustomers(ctx context.Context, tenantID string) (*SyncResult, error)

    // Webhook handling
    HandleWebhook(ctx context.Context, event WebhookEvent) error

    // Health
    Ping(ctx context.Context) error
}
```

### 4.3 Key Operations

#### Post Sales Invoice

Triggered when a shift closes or on a periodic schedule. Aggregates tickets into ERPNext Sales Invoices.

**Frappe API Call:**
```
POST /api/resource/Sales Invoice
Authorization: token api_key:api_secret
```

**Payload (to ERPNext):**
```json
{
  "doctype": "Sales Invoice",
  "naming_series": "POS-INV-.YYYY.-",
  "customer": "Walk-in Customer",
  "pos_profile": "Branch Zurich POS",
  "is_pos": 1,
  "posting_date": "2026-03-20",
  "items": [
    {
      "item_code": "PIZ-001",
      "item_name": "Margherita Pizza",
      "qty": 2,
      "rate": 14.50,
      "amount": 29.00
    }
  ],
  "payments": [
    {
      "mode_of_payment": "Cash",
      "amount": 29.00
    }
  ],
  "taxes": [
    {
      "charge_type": "On Net Total",
      "account_head": "VAT 7.7% - PNZ",
      "rate": 7.7
    }
  ]
}
```

#### Post Payment Entry

Records payment reconciliation in ERPNext when a shift is closed.

**Frappe API Call:**
```
POST /api/resource/Payment Entry
```

**Payload:**
```json
{
  "doctype": "Payment Entry",
  "payment_type": "Receive",
  "party_type": "Customer",
  "party": "Walk-in Customer",
  "paid_amount": 845.00,
  "received_amount": 845.00,
  "mode_of_payment": "Cash",
  "reference_date": "2026-03-20"
}
```

#### Sync Items (ERPNext to POS)

Pull item master data from ERPNext and update local product catalog.

**Frappe API Call:**
```
GET /api/resource/Item?filters=[["item_group","=","POS Items"]]&fields=["name","item_name","item_group","standard_rate","tax_category"]&limit_page_length=0
```

#### Webhook Registration

The bridge registers webhooks in ERPNext to receive real-time notifications:

| ERPNext DocType | Event | Bridge Action |
|---|---|---|
| Item | on_update | Re-sync product |
| Item Price | on_update | Re-sync price |
| Customer | on_update | Re-sync customer |

**Webhook endpoint:** `POST /internal/erpnext/webhook` (not publicly accessible, firewall-restricted to ERPNext IP).

---

## 5. Online Ordering API

Public-facing REST API consumed by the restaurant's online ordering website or progressive web app.

### 5.1 Base URL

```
https://order.{restaurant-slug}.{product}.com/api/v1/
```

Or: `https://api.{product}.com/v1/online/{restaurant-slug}/`

### 5.2 Authentication

| Consumer | Auth Method |
|---|---|
| Guest customer | Session token (auto-generated, stored in cookie) |
| Returning customer | Session token + optional phone/email verification |
| Restaurant staff | Not applicable (uses Cloud API) |

**CORS:** Allowed origins configured per restaurant (e.g., `https://order.pizzeria-napoli.ch`).

### 5.3 Endpoints

#### `GET /api/v1/menu`

Public menu for the restaurant.

**Response (200):**
```json
{
  "restaurant": {
    "name": "Pizzeria Napoli",
    "logo_url": "https://cdn.example.com/logo.png",
    "opening_hours": [
      { "day": "monday", "open": "11:00", "close": "22:00" },
      { "day": "tuesday", "open": "11:00", "close": "22:00" }
    ],
    "accepts_orders": true,
    "order_types": ["pickup", "delivery"],
    "estimated_wait_minutes": 25
  },
  "categories": [
    {
      "id": "019abc12-cat-001",
      "name": "Pizzas",
      "image_url": "https://cdn.example.com/categories/pizza.jpg",
      "products": [
        {
          "id": "019abc12-prod-0042",
          "name": "Margherita Pizza",
          "description": "Classic tomato, mozzarella, basil",
          "price_cents": 1450,
          "image_url": "https://cdn.example.com/products/margherita.jpg",
          "is_available": true,
          "allergens": ["gluten", "dairy"],
          "modifier_groups": [
            {
              "id": "019abc12-mod-size",
              "name": "Size",
              "required": true,
              "min_select": 1,
              "max_select": 1,
              "options": [
                { "id": "019abc12-modopt-001", "name": "Regular", "price_cents": 0 },
                { "id": "019abc12-modopt-002", "name": "Large (+5)", "price_cents": 500 }
              ]
            }
          ],
          "tags": ["vegetarian"]
        }
      ]
    }
  ]
}
```

#### `POST /api/v1/cart`

Create or replace the session cart.

**Request:**
```json
{
  "items": [
    {
      "product_id": "019abc12-prod-0042",
      "quantity": 1,
      "modifier_selections": [
        { "modifier_id": "019abc12-modopt-002", "quantity": 1 }
      ],
      "special_instructions": "No onions"
    }
  ]
}
```

**Response (200):**
```json
{
  "session_id": "sess_abc123",
  "items": [
    {
      "product_id": "019abc12-prod-0042",
      "product_name": "Margherita Pizza",
      "quantity": 1,
      "unit_price_cents": 1450,
      "modifiers": [
        { "name": "Large (+5)", "price_cents": 500 }
      ],
      "line_total_cents": 1950,
      "special_instructions": "No onions"
    }
  ],
  "subtotal_cents": 1950,
  "tax_cents": 150,
  "total_cents": 2100
}
```

#### `POST /api/v1/checkout`

Submit the order and initiate payment.

**Request:**
```json
{
  "session_id": "sess_abc123",
  "order_type": "pickup",
  "requested_time": "2026-03-20T18:30:00Z",
  "customer": {
    "name": "Sarah Weber",
    "phone": "+41791234567",
    "email": "sarah@example.com"
  },
  "payment_method": "card",
  "payment_token": "tok_abc123"
}
```

**Response (201):**
```json
{
  "order_id": "019abc12-onl-001",
  "order_number": "W-0042",
  "status": "pending_acceptance",
  "estimated_ready_at": null,
  "payment_status": "captured",
  "created_at": "2026-03-20T17:45:00Z"
}
```

#### `GET /api/v1/order-status/{order_id}`

Track order status. Supports polling or Server-Sent Events.

**Response (200):**
```json
{
  "order_id": "019abc12-onl-001",
  "order_number": "W-0042",
  "status": "preparing",
  "status_history": [
    { "status": "pending_acceptance", "timestamp": "2026-03-20T17:45:00Z" },
    { "status": "accepted", "timestamp": "2026-03-20T17:46:00Z" },
    { "status": "preparing", "timestamp": "2026-03-20T17:50:00Z" }
  ],
  "estimated_ready_at": "2026-03-20T18:15:00Z"
}
```

**SSE endpoint:** `GET /api/v1/order-status/{order_id}/stream`

```
event: status_update
data: {"status":"ready","timestamp":"2026-03-20T18:12:00Z"}
```

---

## 6. Kiosk API

The Kiosk API is a simplified variant of the Online Ordering API, designed for self-service kiosk devices deployed within the restaurant.

### 6.1 Differences from Online Ordering API

| Aspect | Online Ordering | Kiosk |
|---|---|---|
| **Network** | Public internet | Local network or cloud |
| **Auth** | Session token (cookie) | Device token (paired kiosk) |
| **Payment** | Online payment gateway | In-store payment terminal |
| **Order type** | Pickup / Delivery | Dine-in / Takeaway |
| **Customer data** | Name, phone, email | Optional (order number only) |
| **Menu** | Full with images | Full with large images, optimized for touch |

### 6.2 Additional Kiosk-Specific Endpoints

#### `GET /api/v1/kiosk/config`

Retrieve kiosk device configuration and branding.

**Response (200):**
```json
{
  "kiosk_id": "019abc12-kiosk-001",
  "branch_id": "019abc12-0000-7def-8901-234567890abc",
  "name": "Kiosk Entrance",
  "mode": "takeaway_only",
  "language": "de",
  "currency": "CHF",
  "branding": {
    "logo_url": "https://cdn.example.com/logo.png",
    "primary_color": "#E74C3C",
    "background_image_url": "https://cdn.example.com/kiosk-bg.jpg"
  },
  "features": {
    "allow_dine_in": true,
    "allow_takeaway": true,
    "allow_special_instructions": false,
    "payment_methods": ["card_terminal"],
    "idle_timeout_seconds": 120,
    "receipt_mode": "print"
  }
}
```

#### `POST /api/v1/kiosk/heartbeat`

Periodic health check from the kiosk device.

**Request:**
```json
{
  "kiosk_id": "019abc12-kiosk-001",
  "status": "active",
  "current_session": null,
  "uptime_seconds": 43200,
  "last_order_at": "2026-03-20T14:22:00Z"
}
```

**Response (200):**
```json
{
  "ack": true,
  "server_time": "2026-03-20T15:00:00Z",
  "config_version": 12,
  "commands": []
}
```

### 6.3 Kiosk Order Flow

The kiosk uses the same `/cart` and `/checkout` endpoints as the Online Ordering API, with these differences:

- `payment_method` is `"terminal"` (in-store payment terminal)
- `customer` object is optional (only an order number is generated)
- Response includes `terminal_payment_reference` for the integrated payment terminal

**Kiosk Checkout Request:**
```json
{
  "session_id": "kiosk_sess_001",
  "order_type": "takeaway",
  "payment_method": "terminal",
  "terminal_id": "019abc12-term-001"
}
```

**Kiosk Checkout Response:**
```json
{
  "order_id": "019abc12-kiosk-ord-001",
  "order_number": "K-0015",
  "status": "awaiting_payment",
  "terminal_payment_reference": "txn_abc123",
  "display_message": "Please tap your card on the terminal."
}
```

---

## 7. Webhook / Event Contracts

The Cloud Hub emits webhooks for significant business events. Tenants configure webhook endpoints via the admin dashboard.

### 7.1 Webhook Delivery

| Property | Detail |
|---|---|
| **Method** | POST |
| **Content-Type** | application/json |
| **Signature** | `X-Webhook-Signature: sha256=HMAC(payload, secret)` |
| **Retry policy** | 3 retries with exponential backoff (1s, 10s, 60s) |
| **Timeout** | 10 seconds per attempt |
| **Idempotency** | Events include unique `event_id`; receivers should deduplicate |

### 7.2 Event Envelope

All webhook payloads share this envelope:

```json
{
  "event_id": "019abc12-evt-001",
  "event": "order.created",
  "version": "1.0",
  "timestamp": "2026-03-20T14:30:00Z",
  "tenant_id": "019abc12-9999-7def-8901-234567890abc",
  "branch_id": "019abc12-0000-7def-8901-234567890abc",
  "data": { }
}
```

### 7.3 Event Catalog

#### `order.created`

Fired when a new order (ticket) is created.

```json
{
  "event_id": "019abc12-evt-001",
  "event": "order.created",
  "version": "1.0",
  "timestamp": "2026-03-20T14:30:00Z",
  "tenant_id": "019abc12-9999-7def-8901-234567890abc",
  "branch_id": "019abc12-0000-7def-8901-234567890abc",
  "data": {
    "order_id": "019abc12-tick-0001",
    "order_type": "dine_in",
    "table_number": "A3",
    "covers": 4,
    "waiter_id": "019abc12-user-003",
    "item_count": 3,
    "total_cents": 5400,
    "source": "pos"
  }
}
```

#### `order.paid`

Fired when an order is fully paid.

```json
{
  "event_id": "019abc12-evt-002",
  "event": "order.paid",
  "version": "1.0",
  "timestamp": "2026-03-20T15:00:00Z",
  "tenant_id": "019abc12-9999-7def-8901-234567890abc",
  "branch_id": "019abc12-0000-7def-8901-234567890abc",
  "data": {
    "order_id": "019abc12-tick-0001",
    "total_cents": 5400,
    "payments": [
      { "method": "card", "amount_cents": 5400, "tip_cents": 100 }
    ],
    "fiscal_receipt_id": "019abc12-rcpt-0042"
  }
}
```

#### `order.cancelled`

Fired when an order is cancelled (including online orders rejected by the restaurant).

```json
{
  "event_id": "019abc12-evt-003",
  "event": "order.cancelled",
  "version": "1.0",
  "timestamp": "2026-03-20T15:05:00Z",
  "tenant_id": "019abc12-9999-7def-8901-234567890abc",
  "branch_id": "019abc12-0000-7def-8901-234567890abc",
  "data": {
    "order_id": "019abc12-onl-001",
    "reason": "customer_requested",
    "cancelled_by": "019abc12-user-003",
    "refund_amount_cents": 1950,
    "source": "online"
  }
}
```

#### `kitchen.ticket.ready`

Fired when all items on a kitchen ticket are marked as ready.

```json
{
  "event_id": "019abc12-evt-004",
  "event": "kitchen.ticket.ready",
  "version": "1.0",
  "timestamp": "2026-03-20T14:45:00Z",
  "tenant_id": "019abc12-9999-7def-8901-234567890abc",
  "branch_id": "019abc12-0000-7def-8901-234567890abc",
  "data": {
    "kitchen_ticket_id": "019abc12-kt-001",
    "order_id": "019abc12-tick-0001",
    "table_number": "A3",
    "preparation_time_seconds": 720,
    "item_count": 3
  }
}
```

#### `payment.completed`

Fired for each individual payment transaction (an order may have multiple payments in a split-bill scenario).

```json
{
  "event_id": "019abc12-evt-005",
  "event": "payment.completed",
  "version": "1.0",
  "timestamp": "2026-03-20T15:00:00Z",
  "tenant_id": "019abc12-9999-7def-8901-234567890abc",
  "branch_id": "019abc12-0000-7def-8901-234567890abc",
  "data": {
    "payment_id": "019abc12-pay-001",
    "bill_id": "019abc12-bill-001",
    "order_id": "019abc12-tick-0001",
    "method": "card",
    "amount_cents": 5400,
    "tip_cents": 100,
    "currency": "CHF"
  }
}
```

#### `shift.closed`

Fired when a cashier shift is closed with the Z-report.

```json
{
  "event_id": "019abc12-evt-006",
  "event": "shift.closed",
  "version": "1.0",
  "timestamp": "2026-03-20T22:05:00Z",
  "tenant_id": "019abc12-9999-7def-8901-234567890abc",
  "branch_id": "019abc12-0000-7def-8901-234567890abc",
  "data": {
    "shift_id": "019abc12-shft-001",
    "user_id": "019abc12-user-002",
    "user_name": "Anna Mueller",
    "opened_at": "2026-03-20T07:00:00Z",
    "closed_at": "2026-03-20T22:00:00Z",
    "total_sales_cents": 845000,
    "order_count": 67,
    "cash_variance_cents": -1300
  }
}
```

### 7.4 Webhook Configuration

Tenants configure webhooks via `POST /v1/admin/webhooks`:

```json
{
  "url": "https://hooks.restaurant.ch/pos-events",
  "secret": "whsec_abc123...",
  "events": ["order.created", "order.paid", "shift.closed"],
  "active": true
}
```

---

## Appendix: API Versioning Strategy

| Version | Status | Sunset Date |
|---|---|---|
| v1 | **Current** | -- |
| v2 | Planned (breaking changes only) | -- |

**Versioning rules:**
- Non-breaking changes (new fields, new endpoints) are added to the current version.
- Breaking changes (field removal, type changes, behavior changes) require a new version.
- Deprecated versions receive 12 months of support after sunset announcement.
- The `X-API-Version` response header confirms the version served.
