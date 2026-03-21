# GastroCore — Developer Guide

## Table of Contents

- [Prerequisites](#prerequisites)
- [Initial Setup](#initial-setup)
- [Project Structure](#project-structure)
- [Flutter Development](#flutter-development)
- [Go Backend Development](#go-backend-development)
- [Code Generation](#code-generation)
- [Coding Conventions](#coding-conventions)
- [Adding a New Feature](#adding-a-new-feature)
- [Adding a New API Endpoint](#adding-a-new-api-endpoint)
- [Adding a Database Table](#adding-a-database-table)
- [Internationalization (i18n)](#internationalization-i18n)
- [PR Process](#pr-process)
- [Common Tasks](#common-tasks)

---

## Prerequisites

| Tool | Version | Notes |
|---|---|---|
| Flutter | 3.35.0 | `flutter doctor -v` must show no errors |
| Dart SDK | ^3.9.2 | Bundled with Flutter |
| Java | 17 (Temurin) | Required for Android builds |
| Go | 1.22+ | Backend only |
| Docker | 24+ | For local Postgres + Redis |
| VS Code or Android Studio | Latest | Both work; VS Code + Flutter extension recommended |

Install Flutter: https://docs.flutter.dev/get-started/install

---

## Initial Setup

```bash
# Clone
git clone https://github.com/gastrocore/restaurant.git
cd restaurant

# Start infrastructure (Postgres + Redis + Go server)
docker-compose up -d

# Flutter: install dependencies and generate code
cd apps/pos
flutter pub get
dart run build_runner build --delete-conflicting-outputs

# Verify Flutter setup
flutter doctor
flutter analyze

# Go: download dependencies
cd ../../server
go mod download
go build ./...
```

### VS Code recommended extensions

- Flutter (Dart Code)
- Dart (Dart Code)
- Go (golang.go)
- Error Lens
- GitLens

### Android Studio setup

File → Settings → Plugins → install "Flutter" and "Dart".

---

## Project Structure

```
restaurant/
├── apps/
│   ├── pos/                # Main Flutter app (all 5 flavors)
│   │   ├── lib/            # Dart source
│   │   ├── test/           # Unit + widget tests
│   │   ├── integration_test/ # End-to-end tests
│   │   ├── android/        # Android-specific config
│   │   └── pubspec.yaml
│   └── online/             # Flutter Web online ordering
├── server/                 # Go backend
│   ├── cmd/                # Entry points: server, migrate, seed
│   ├── internal/           # All business logic
│   └── migrations/         # SQL migration files
├── design/                 # Stitch design system
├── docs/                   # This documentation
├── .github/workflows/      # CI/CD
└── docker-compose.yml
```

---

## Flutter Development

### Running apps

```bash
cd apps/pos

# POS (default)
flutter run

# With specific device
flutter run -d emulator-5554

# Kiosk flavor
flutter run -t lib/main_kiosk.dart

# KDS
flutter run -t lib/main_kds.dart

# Web (requires Chrome)
flutter run -d chrome
```

### Layered architecture

Each feature follows clean architecture with three layers:

```
features/my_feature/
├── domain/
│   ├── entities/          # Immutable data classes (freezed)
│   └── repositories/      # Abstract interfaces
├── data/
│   ├── daos/              # Drift DAOs (database queries)
│   └── repositories/      # Concrete implementations
└── presentation/
    ├── providers/         # Riverpod providers/notifiers
    ├── screens/           # Full-page widgets
    └── widgets/           # Reusable components
```

### Drift DAOs

DAOs extend `DatabaseAccessor<AppDatabase>`:

```dart
part 'my_dao.g.dart';

@DriftAccessor(tables: [MyTable])
class MyDao extends DatabaseAccessor<AppDatabase> with _$MyDaoMixin {
  MyDao(super.db);

  Future<List<MyTableData>> findAll(String tenantId) =>
      (select(myTable)..where((t) => t.tenantId.equals(tenantId))).get();

  Stream<List<MyTableData>> watchAll(String tenantId) =>
      (select(myTable)..where((t) => t.tenantId.equals(tenantId))).watch();

  Future<void> upsert(MyTableCompanion data) =>
      into(myTable).insertOnConflictUpdate(data);

  Future<int> softDelete(String id) =>
      (update(myTable)..where((t) => t.id.equals(id)))
          .write(const MyTableCompanion(isDeleted: Value(true)));
}
```

**Never** hard-delete records — always use `is_deleted = true` to preserve sync integrity.

### Riverpod providers

```dart
// Simple provider
final myServiceProvider = Provider<MyService>((ref) {
  final db = ref.watch(databaseProvider);
  return MyService(db.myDao);
});

// AsyncNotifier for screens
@riverpod
class MyNotifier extends _$MyNotifier {
  @override
  Future<MyState> build() async {
    final service = ref.watch(myServiceProvider);
    return service.loadInitialState();
  }

  Future<void> doSomething() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final service = ref.read(myServiceProvider);
      return service.doSomething();
    });
  }
}
```

### Money values

All monetary amounts are stored and transmitted as **integer cents (Rappen)**:

```dart
// Use the Money value object
final price = Money.fromCents(2850);    // CHF 28.50
final tax   = price.extractTax(8.1);    // gross-inclusive extraction
final formatted = price.format();       // "28.50"
final display = price.formatCHF();      // "CHF 28.50"

// 5-Rappen rounding (cash payments)
final rounded = price.roundTo5Rappen(); // nearest 0.05
```

Never use `double` for money. Never divide monetary integers without checking for truncation.

### Sync-aware writes

When a Drift write should be synced to the cloud, queue a `SyncEvent`:

```dart
// In your repository:
await db.transaction(() async {
  await db.myDao.upsert(companion);
  await db.syncQueueDao.enqueue(SyncQueueCompanion(
    tableName: Value('my_table'),
    recordId: Value(companion.id.value),
    operation: Value(SyncOperation.insert.name),
    payload: Value(jsonEncode(companion.toJson())),
    deviceId: Value(ref.read(deviceIdProvider)),
  ));
});
```

---

## Go Backend Development

### Running locally

```bash
cd server

# With hot-reload via Air (optional)
go install github.com/air-verse/air@latest
air

# Without hot-reload
go run ./cmd/server

# Set environment
export DATABASE_URL="postgres://gastrocore:gastrocore@localhost:5432/gastrocore?sslmode=disable"
export JWT_SECRET="dev-secret-change-in-production"
export LICENSE_SIGNING_KEY="dev-key"
go run ./cmd/server
```

### Module structure

Each module is self-contained:

```go
// internal/mymodule/module.go
package mymodule

import (
    "database/sql"
    "net/http"
)

type Module struct {
    db      *sql.DB
    handler *Handler
}

func NewModule(db *sql.DB) *Module {
    store := &Store{db: db}
    handler := &Handler{store: store}
    return &Module{db: db, handler: handler}
}

func (m *Module) RegisterRoutes(mux *http.ServeMux) {
    mux.HandleFunc("GET /api/v1/my-resource", m.handler.list)
    mux.HandleFunc("POST /api/v1/my-resource", m.handler.create)
    mux.HandleFunc("GET /api/v1/my-resource/{id}", m.handler.get)
}
```

Register in `cmd/server/main.go`:
```go
myModule := mymodule.NewModule(db)
// ...
myModule.RegisterRoutes(mux)
```

### Handler pattern

```go
// internal/mymodule/handlers.go
func (h *Handler) list(w http.ResponseWriter, r *http.Request) {
    tenantID := r.Header.Get("X-Tenant-ID")  // set by auth middleware
    if tenantID == "" {
        http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
        return
    }

    items, err := h.store.FindAll(r.Context(), tenantID)
    if err != nil {
        slog.Error("list failed", "error", err)
        http.Error(w, `{"error":"internal_error"}`, http.StatusInternalServerError)
        return
    }

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(map[string]any{"items": items})
}
```

### Database queries

Use parameterized queries only:

```go
// internal/mymodule/store.go
type Store struct{ db *sql.DB }

func (s *Store) FindAll(ctx context.Context, tenantID string) ([]Item, error) {
    const q = `
        SELECT id, name, created_at
        FROM my_table
        WHERE tenant_id = $1 AND is_deleted = FALSE
        ORDER BY created_at DESC
    `
    rows, err := s.db.QueryContext(ctx, q, tenantID)
    if err != nil {
        return nil, fmt.Errorf("FindAll: %w", err)
    }
    defer rows.Close()

    var items []Item
    for rows.Next() {
        var item Item
        if err := rows.Scan(&item.ID, &item.Name, &item.CreatedAt); err != nil {
            return nil, fmt.Errorf("scan: %w", err)
        }
        items = append(items, item)
    }
    return items, rows.Err()
}
```

---

## Code Generation

### Flutter (Drift + Riverpod + Freezed)

```bash
cd apps/pos

# Run once
dart run build_runner build --delete-conflicting-outputs

# Watch mode (during development)
dart run build_runner watch --delete-conflicting-outputs
```

Generated files (`*.g.dart`, `*.freezed.dart`) are committed to the repository for CI builds without requiring code generation in CI.

### What gets generated

| Source annotation | Generator | Output |
|---|---|---|
| `@DriftDatabase` / `@DriftAccessor` | `drift_dev` | `*.g.dart` (DAOs, companions, query methods) |
| `@freezed` | `freezed` | `*.freezed.dart` (copyWith, equality, pattern matching) |
| `@JsonSerializable` | `json_serializable` | `*.g.dart` (fromJson, toJson) |
| `@riverpod` | `riverpod_generator` | `*.g.dart` (provider classes) |

---

## Coding Conventions

### Dart / Flutter

- **Immutable entities** — always use `freezed`. No mutable data classes.
- **No `late` without reason** — prefer `final` and nullable types.
- **Providers over singletons** — all dependencies via Riverpod. No `GetIt.instance.get<X>()` in UI code.
- **Cents for money** — `int` only. No `double`, no `Decimal`.
- **`is_deleted` soft deletes** — never `DELETE FROM` synced tables.
- **Named routes** — use `GoRouter` named routes, not `Navigator.push`.
- **One screen per file** — screens go in `presentation/screens/`, widgets in `presentation/widgets/`.
- **Test file mirrors source** — `lib/features/x/y.dart` → `test/features/x/y_test.dart`.

### Go

- **One module per domain** — do not put auth logic in the orders module.
- **Wrap errors** — `fmt.Errorf("operation: %w", err)`.
- **Structured logging** — `slog.Info(...)`, `slog.Error(...)`. No `fmt.Println` in handlers.
- **Context propagation** — every DB query takes a `context.Context`.
- **No global state** — dependencies injected via struct fields, not package-level vars.
- **Parameterized SQL** — never interpolate user input into SQL strings.
- **Test files alongside source** — `handlers_test.go` next to `handlers.go`.

### Git

- Branch naming: `feat/feature-name`, `fix/bug-description`, `docs/what-you-changed`
- Commit messages: imperative, present tense — `add Swiss VAT extraction`, `fix KDS WebSocket reconnect`
- No force-push to `main`
- All PRs require at least one approval

---

## Adding a New Feature

### Flutter feature checklist

```
features/my_feature/
├── domain/
│   ├── entities/
│   │   └── my_entity.dart          # @freezed class
│   └── repositories/
│       └── my_repository.dart      # abstract interface
├── data/
│   ├── daos/
│   │   └── my_dao.dart             # @DriftAccessor
│   └── repositories/
│       └── my_repository_impl.dart # implements domain interface
└── presentation/
    ├── providers/
    │   └── my_provider.dart        # @riverpod
    └── screens/
        └── my_screen.dart
```

1. Define the entity (`@freezed`)
2. Define the repository interface (abstract class)
3. Add the Drift table to `AppDatabase` (see [DATABASE.md](DATABASE.md))
4. Implement the DAO
5. Implement the repository
6. Write Riverpod providers
7. Build the UI
8. Write tests
9. Add route to `app_router.dart` if needed
10. Add `SyncConfig` entry if the table should sync

---

## Adding a New API Endpoint

1. Create or update the module in `server/internal/mymodule/`
2. Add the handler method to `handlers.go`
3. Register the route in `module.go`'s `RegisterRoutes`
4. Add a SQL query to `store.go` (parameterized)
5. Write a test in `handlers_test.go`
6. Document the endpoint in `docs/API.md`

---

## Adding a Database Table

### Flutter (Drift)

1. Define the table class in `apps/pos/lib/core/database/app_database.dart`:

```dart
class MyNewTable extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text().references(Tenants, #id)();
  TextColumn get name => text()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
```

2. Add to `@DriftDatabase(tables: [..., MyNewTable])` annotation
3. Increment schema version in `AppDatabase` and add migration
4. Run `dart run build_runner build`

### Go (PostgreSQL)

1. Create `server/migrations/006_my_table.up.sql`:

```sql
CREATE TABLE my_new_table (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id   UUID NOT NULL REFERENCES tenants(id),
    name        TEXT NOT NULL,
    is_deleted  BOOLEAN NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_my_new_table_tenant_id ON my_new_table(tenant_id);

CREATE TRIGGER update_my_new_table_updated_at
    BEFORE UPDATE ON my_new_table
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
```

2. Create `server/migrations/006_my_table.down.sql`:

```sql
DROP TABLE IF EXISTS my_new_table;
```

3. Document the table in `docs/DATABASE.md`

---

## Internationalization (i18n)

GastroCore supports DE, FR, IT, and EN.

### Adding a new string

1. Add to `apps/pos/lib/l10n/app_de.arb` (German, the primary locale):

```json
{
  "myNewString": "Mein neuer Text",
  "@myNewString": {
    "description": "Used on the main screen header"
  }
}
```

2. Add translations to `app_fr.arb`, `app_it.arb`, `app_en.arb`
3. Run Flutter to regenerate:

```bash
flutter gen-l10n
```

4. Use in code:

```dart
Text(context.l10n.myNewString)
```

---

## PR Process

1. **Branch** — create from `main`: `git checkout -b feat/my-feature`
2. **Develop** — write code + tests
3. **Generate** — run `dart run build_runner build` if you changed Drift/Riverpod/Freezed
4. **Test** — `flutter test` and `go test ./...` must pass
5. **Analyze** — `flutter analyze --no-fatal-infos` must pass with 0 errors
6. **PR** — open PR against `main`; fill in description, link related issues
7. **Review** — at least one approval required
8. **Merge** — squash merge preferred for feature PRs; merge commit for releases

### CI must pass

- `flutter analyze --no-fatal-infos`
- `flutter test --coverage`
- `flutter build apk --debug`

PRs that fail CI will not be merged.

---

## Common Tasks

### Reset local database

```bash
# Flutter — delete the SQLite file (location varies by platform)
# Android emulator:
adb shell "run-as com.gastrocore.pos rm /data/data/com.gastrocore.pos/databases/gastrocore.db"

# Docker — reset Postgres
docker-compose down -v   # removes pgdata volume
docker-compose up -d
# Then run migrations and seed
```

### Add a dependency (Flutter)

```bash
cd apps/pos
flutter pub add <package_name>
# or edit pubspec.yaml and run:
flutter pub get
```

### Add a dependency (Go)

```bash
cd server
go get github.com/some/package@latest
go mod tidy
```

### View Drift-generated SQL

Set `logStatements: true` in `NativeDatabase`:
```dart
NativeDatabase.createInBackground(file, logStatements: kDebugMode)
```

### Check coverage

```bash
cd apps/pos
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

### Profile Go server

```bash
# Enable pprof (only in dev!)
curl http://localhost:8080/debug/pprof/goroutine?debug=1
```

### Update Flutter version

Edit `.github/workflows/ci.yml`:
```yaml
env:
  FLUTTER_VERSION: '3.XX.X'
```

Also update `apps/pos/pubspec.yaml` SDK constraint if needed.
