# GastroCore — Testing Guide

## Table of Contents

- [Overview](#overview)
- [Running Tests](#running-tests)
- [Flutter Test Types](#flutter-test-types)
- [Writing Unit Tests](#writing-unit-tests)
- [Writing Widget Tests](#writing-widget-tests)
- [Writing Integration Tests](#writing-integration-tests)
- [Go Tests](#go-tests)
- [Test Database Setup](#test-database-setup)
- [Test Coverage](#test-coverage)
- [CI Test Pipeline](#ci-test-pipeline)
- [Test Conventions](#test-conventions)

---

## Overview

| Layer | Tool | Location |
|---|---|---|
| Flutter unit tests | `flutter test` | `apps/pos/test/` |
| Flutter widget tests | `flutter test` | `apps/pos/test/` |
| Flutter integration tests | `flutter test integration_test/` | `apps/pos/integration_test/` |
| Go unit tests | `go test ./...` | `server/internal/*/` |
| Go integration tests | `go test -tags integration ./...` | `server/internal/*/` |

The project targets **high unit test coverage** for business logic (FareEngine, Money, SyncQueue, DAO queries) and **smoke-level widget tests** for UI screens.

---

## Running Tests

### Flutter

```bash
cd apps/pos

# All unit + widget tests
flutter test

# With verbose output
flutter test --reporter=expanded

# Single file
flutter test test/core/services/fare_engine_test.dart

# Single test by name
flutter test --name "extracts correct tax for takeaway food"

# With coverage
flutter test --coverage

# Watch mode (re-runs on file change)
flutter test --watch
```

### Go

```bash
cd server

# All tests
go test ./...

# Verbose
go test -v ./...

# Single package
go test -v ./internal/sync/...

# Single test function
go test -v -run TestPushHandler ./internal/sync/...

# With race detector
go test -race ./...

# Integration tests only (require DATABASE_URL)
DATABASE_URL="postgres://..." go test -tags integration ./...
```

---

## Flutter Test Types

### Unit tests (`test/`)

Test pure business logic with no Flutter framework:

- `test/core/utils/money_test.dart` — Money arithmetic, formatting, rounding
- `test/core/services/fare_engine_test.dart` — Tax extraction, discount calculation
- `test/features/orders/order_entity_test.dart` — TicketEntity state transitions
- `test/features/kiosk/kiosk_order_service_test.dart` — Order submission logic
- `test/core/printing/swiss_receipt_builder_test.dart` — Receipt generation

### Widget tests (`test/`)

Test UI widgets in isolation with a widget tester:

- `test/features/auth/pin_pad_widget_test.dart` — PIN entry UI
- `test/features/orders/pos_screen_test.dart` — POS main screen interactions
- `test/shared/widgets/money_display_test.dart` — Money formatting widget

### Integration tests (`integration_test/`)

Run on a real device or emulator, test full app flows end-to-end.

---

## Writing Unit Tests

### Standard structure

```dart
// test/core/services/fare_engine_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gastrocore_pos/core/services/fare_engine.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/order_item_entity.dart';

void main() {
  group('FareEngine', () {
    group('extractTax', () {
      test('extracts 8.1% from dine-in food item', () {
        final item = OrderItemEntity(
          id: 'item-1',
          productId: 'prod-1',
          productName: 'Rösti',
          quantity: 1.0,
          unitPrice: 1490,  // CHF 14.90
          taxGroup: 'food',
          // ...
        );

        final breakdown = FareEngine.calculate(
          items: [item],
          orderType: OrderType.dineIn,
        );

        // Tax = 1490 × 8.1 / 108.1 = 111.4... → 111 cents
        expect(breakdown.taxByRate['A'], 111);
        expect(breakdown.subtotal, 1490);
      });

      test('extracts 2.6% from takeaway food item', () {
        final item = OrderItemEntity(
          id: 'item-1',
          productId: 'prod-1',
          productName: 'Rösti',
          quantity: 1.0,
          unitPrice: 1490,
          taxGroup: 'food',
        );

        final breakdown = FareEngine.calculate(
          items: [item],
          orderType: OrderType.takeaway,
        );

        // Tax = 1490 × 2.6 / 102.6 = 37.8... → 37 cents
        expect(breakdown.taxByRate['B'], 37);
      });
    });

    group('discount', () {
      test('applies percentage discount correctly', () {
        // ...
      });

      test('does not allow discount to exceed subtotal', () {
        // ...
      });
    });
  });
}
```

### Testing with in-memory database (Drift)

```dart
import 'package:drift/native.dart';
import 'package:gastrocore_pos/core/database/app_database.dart';

AppDatabase createTestDatabase() {
  return AppDatabase.createInMemory();
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = createTestDatabase();
  });

  tearDown(() async {
    await db.close();
  });

  test('inserts and retrieves a product', () async {
    await db.into(db.products).insert(ProductsCompanion.insert(
      id: const Value('prod-001'),
      tenantId: 'tenant-001',
      categoryId: 'cat-001',
      name: 'Rösti',
      price: const Value(1490),
      taxGroup: const Value('food'),
    ));

    final results = await db.select(db.products).get();
    expect(results.length, 1);
    expect(results.first.name, 'Rösti');
    expect(results.first.price, 1490);
  });
}
```

### Testing Riverpod providers

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/features/orders/presentation/providers/ticket_provider.dart';

void main() {
  test('ticket provider starts empty', () async {
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(createTestDatabase()),
        tenantIdProvider.overrideWithValue('tenant-001'),
        deviceIdProvider.overrideWithValue('device-001'),
      ],
    );
    addTearDown(container.dispose);

    final tickets = await container.read(activeTicketsProvider.future);
    expect(tickets, isEmpty);
  });
}
```

### Testing Money

```dart
import 'package:gastrocore_pos/core/utils/money.dart';

void main() {
  group('Money', () {
    test('formats CHF correctly', () {
      expect(Money.fromCents(2850).formatCHF(), 'CHF 28.50');
      expect(Money.fromCents(100).formatCHF(), 'CHF 1.00');
      expect(Money.fromCents(5).formatCHF(), 'CHF 0.05');
    });

    test('rounds to nearest 5 Rappen', () {
      expect(Money.fromCents(101).roundTo5Rappen().cents, 100);
      expect(Money.fromCents(103).roundTo5Rappen().cents, 105);
      expect(Money.fromCents(107).roundTo5Rappen().cents, 105);
      expect(Money.fromCents(108).roundTo5Rappen().cents, 110);
    });

    test('extracts gross-inclusive tax', () {
      final gross = Money.fromCents(1000);
      final tax = gross.extractTax(10.0);
      // 1000 × 10 / 110 = 90.9... → 90
      expect(tax.cents, 90);
    });
  });
}
```

---

## Writing Widget Tests

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gastrocore_pos/features/auth/presentation/widgets/pin_pad.dart';

void main() {
  testWidgets('PinPad emits entered PIN on confirm', (tester) async {
    String? enteredPin;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: PinPad(
              onPinEntered: (pin) => enteredPin = pin,
            ),
          ),
        ),
      ),
    );

    // Tap digits
    await tester.tap(find.text('1'));
    await tester.tap(find.text('2'));
    await tester.tap(find.text('3'));
    await tester.tap(find.text('4'));
    await tester.pump();

    // Confirm
    await tester.tap(find.byIcon(Icons.check));
    await tester.pump();

    expect(enteredPin, '1234');
  });
}
```

---

## Writing Integration Tests

Integration tests run on a real device or emulator.

```dart
// integration_test/login_flow_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:gastrocore_pos/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('user can log in with PIN', (tester) async {
    app.main();
    await tester.pumpAndSettle();

    // Should show PIN screen
    expect(find.byKey(const Key('pin_pad')), findsOneWidget);

    // Enter PIN
    await tester.tap(find.text('1'));
    await tester.tap(find.text('2'));
    await tester.tap(find.text('3'));
    await tester.tap(find.text('4'));
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();

    // Should be on POS screen
    expect(find.byKey(const Key('pos_screen')), findsOneWidget);
  });
}
```

Run:
```bash
flutter test integration_test/login_flow_test.dart -d emulator-5554
```

---

## Go Tests

### Unit test structure

```go
// internal/sync/handlers_test.go
package sync_test

import (
    "bytes"
    "encoding/json"
    "net/http"
    "net/http/httptest"
    "testing"

    "github.com/gastrocore/server/internal/sync"
    "github.com/gastrocore/server/internal/shared/testutil"
)

func TestPushHandler_AcceptsValidBatch(t *testing.T) {
    db := testutil.NewTestDB(t)  // in-memory or test Postgres
    mod := sync.NewModule(db, testutil.TestConfig())

    mux := http.NewServeMux()
    mod.RegisterRoutes(mux)

    payload := map[string]any{
        "device_id": "dev-001",
        "tenant_id": "tenant-001",
        "events": []map[string]any{
            {
                "id":         "evt-001",
                "table_name": "tickets",
                "record_id":  "tkt-001",
                "operation":  "insert",
                "payload":    map[string]any{"id": "tkt-001"},
                "created_at": "2026-03-21T13:00:00Z",
            },
        },
    }

    body, _ := json.Marshal(payload)
    req := httptest.NewRequest("POST", "/api/v1/sync/push", bytes.NewReader(body))
    req.Header.Set("Content-Type", "application/json")
    req.Header.Set("X-Tenant-ID", "tenant-001")

    w := httptest.NewRecorder()
    mux.ServeHTTP(w, req)

    if w.Code != http.StatusOK {
        t.Fatalf("expected 200, got %d: %s", w.Code, w.Body)
    }

    var resp map[string]any
    json.Unmarshal(w.Body.Bytes(), &resp)
    if resp["accepted"].(float64) != 1 {
        t.Errorf("expected accepted=1, got %v", resp["accepted"])
    }
}
```

### KDS Hub test

```go
// internal/kds/hub_test.go
func TestHub_DeliversTenantFilteredNotifications(t *testing.T) {
    hub := kds.NewHub()
    go hub.Run()

    client1 := hub.RegisterTestClient("dev-001", "tenant-A")
    client2 := hub.RegisterTestClient("dev-002", "tenant-B")

    hub.Notify(kds.KDSNotification{
        TenantID:    "tenant-A",
        TicketID:    "tkt-001",
        OrderNumber: "T-001",
        EventType:   "new_order",
    })

    select {
    case msg := <-client1.Receive:
        // OK — correct tenant
        if msg.TicketID != "tkt-001" {
            t.Errorf("wrong ticket: %s", msg.TicketID)
        }
    case <-time.After(100 * time.Millisecond):
        t.Fatal("client1 should have received notification")
    }

    select {
    case msg := <-client2.Receive:
        t.Fatalf("client2 should NOT receive cross-tenant notification: %v", msg)
    case <-time.After(50 * time.Millisecond):
        // OK — no message
    }
}
```

---

## Test Database Setup

### Flutter (in-memory Drift)

```dart
// Creates a fresh in-memory SQLite database for each test
final db = AppDatabase.createInMemory();

// Optionally seed with test data
await db.into(db.tenants).insert(TenantsCompanion.insert(
  id: const Value('test-tenant'),
  name: 'Test Restaurant',
  // ...
));
```

### Go (test PostgreSQL)

For tests that need real SQL behavior:

```go
// internal/shared/testutil/db.go
func NewTestDB(t *testing.T) *sql.DB {
    t.Helper()
    url := os.Getenv("TEST_DATABASE_URL")
    if url == "" {
        t.Skip("TEST_DATABASE_URL not set — skipping integration test")
    }
    db, err := sql.Open("postgres", url)
    if err != nil {
        t.Fatalf("open test db: %v", err)
    }
    t.Cleanup(func() { db.Close() })
    return db
}
```

Start a test Postgres with Docker:
```bash
docker run --rm -e POSTGRES_DB=gastrocore_test \
    -e POSTGRES_USER=test -e POSTGRES_PASSWORD=test \
    -p 5433:5432 postgres:16-alpine

export TEST_DATABASE_URL="postgres://test:test@localhost:5433/gastrocore_test?sslmode=disable"
go test -tags integration ./...
```

---

## Test Coverage

### Generate coverage report

```bash
cd apps/pos
flutter test --coverage
# Output: coverage/lcov.info

# Optional: generate HTML report (requires lcov)
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html  # macOS
xdg-open coverage/html/index.html  # Linux
```

### Coverage targets

| Package | Target |
|---|---|
| `core/utils/` (Money, IdGenerator) | 100% |
| `core/services/` (FareEngine) | 95%+ |
| `core/printing/` (SwissReceiptBuilder) | 90%+ |
| `features/*/domain/` (entities) | 90%+ |
| `features/*/data/` (DAOs) | 80%+ |
| `features/*/presentation/` (screens, providers) | 60%+ |

### Go coverage

```bash
cd server
go test -coverprofile=coverage.out ./...
go tool cover -html=coverage.out -o coverage.html
```

---

## CI Test Pipeline

The `ci.yml` workflow runs on every push to `main` and every PR:

```yaml
# Jobs run in parallel:
#   analyze — flutter analyze --no-fatal-infos
#   test    — flutter test --coverage

# build-android runs after both pass:
#   flutter build apk --debug
```

Coverage artifacts (`lcov.info`) are uploaded and retained for 7 days.

**PRs are blocked from merging if any job fails.**

---

## Test Conventions

### Flutter

- **One `group` per class**, nested `group`s for methods
- **`test()` description format**: `"<does what> when <condition>"`
  - Good: `"returns 0 rounding amount when total is already a multiple of 5"`
  - Bad: `"test rounding"`
- **AAA pattern**: Arrange → Act → Assert. One assertion concept per test.
- **No `sleep` in tests** — use `pump()`, `pumpAndSettle()`, or `FakeAsync`
- **Override providers in tests** — never mock system globals

### Go

- **File naming**: `handlers_test.go` next to `handlers.go`
- **Package naming**: `package mymodule_test` for black-box tests (preferred), `package mymodule` for white-box
- **Table-driven tests** for multiple input/output scenarios:

```go
func TestMwStCode(t *testing.T) {
    cases := []struct {
        taxGroup string
        isDineIn bool
        want     string
    }{
        {"food", true, "A"},
        {"food", false, "B"},
        {"beverage", true, "A"},
        {"accommodation", true, "C"},
    }
    for _, tc := range cases {
        t.Run(fmt.Sprintf("%s_dineIn=%v", tc.taxGroup, tc.isDineIn), func(t *testing.T) {
            got := MwStCode(tc.taxGroup, tc.isDineIn)
            if got != tc.want {
                t.Errorf("MwStCode(%q, %v) = %q, want %q", tc.taxGroup, tc.isDineIn, got, tc.want)
            }
        })
    }
}
```

- **`t.Helper()`** in shared test utilities
- **`t.Cleanup()`** instead of `defer` for resource cleanup in test helpers
- **`testutil` package** for shared fixtures and test DB setup

### What NOT to test

- Generated code (`*.g.dart`, `*.freezed.dart`)
- Trivial getters/setters
- Third-party library internals
- Flutter framework rendering details
