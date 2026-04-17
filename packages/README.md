# GastroCore shared packages

Flutter/Dart workspace packages that are consumed by every GastroCore
application (`apps/pos`, `apps/dashboard`, `apps/online`, and the upcoming
`apps/waiter`, `apps/kds`, `apps/ods`, `apps/kiosk`).

| Package             | Purpose                                                        | Flutter? |
| ------------------- | -------------------------------------------------------------- | -------- |
| `gastrocore_models` | Pure-Dart domain entities, enums, fare engine, money utils.    | no       |
| `gastrocore_api`    | Typed HTTP client for the Go backend (endpoints, DTOs, auth).  | no       |
| `gastrocore_sync`   | Offline-first engine — outbox, cursor pull, LAN sync, merge.   | no       |
| `gastrocore_ui`     | Material 3 theme + `Gc*` design-system widgets.                | yes      |

## Importing

Each workspace app declares path dependencies:

```yaml
dependencies:
  gastrocore_models: { path: ../../packages/gastrocore_models }
  gastrocore_api:    { path: ../../packages/gastrocore_api }
  gastrocore_sync:   { path: ../../packages/gastrocore_sync }
  gastrocore_ui:     { path: ../../packages/gastrocore_ui }
```

and consume a single barrel:

```dart
import 'package:gastrocore_models/gastrocore_models.dart';
import 'package:gastrocore_api/gastrocore_api.dart';
import 'package:gastrocore_sync/gastrocore_sync.dart';
import 'package:gastrocore_ui/gastrocore_ui.dart';
```

## Local development

The monorepo is orchestrated by [melos](https://melos.invertase.dev/).
Windows shortcuts live under `scripts/`:

```
scripts\bootstrap.cmd      rem installs melos if missing, wires path deps
scripts\analyze-all.cmd    rem runs `flutter analyze` across every package
scripts\test-all.cmd       rem runs `flutter test` in every package with tests
```

Equivalent direct commands (any shell):

```
melos bootstrap
melos run analyze
melos run test
```

## Stability contract

These packages are shared by **parallel apps and teams**.

- **No breaking changes** — evolve the public API additively (new fields,
  new methods, new classes). Removing or renaming a public symbol requires
  coordinated migration across every consumer app.
- **Immutable entities** — add fields as nullable with safe defaults, or
  as required on a new constructor; preserve existing constructor shapes.
- **Pure-Dart rule** — `gastrocore_models` / `_api` / `_sync` must not
  import `package:flutter/*`. Only `gastrocore_ui` may depend on Flutter.
- **Integer money** — every monetary value is stored as `int` cents;
  Swiss 5-rappen rounding lives in `Money` (see `gastrocore_models`).

## Layering

```
   apps/* ──► gastrocore_ui ──► gastrocore_models
          └─► gastrocore_sync ──► gastrocore_api ──► gastrocore_models
```

`gastrocore_models` has no internal dependencies and is the single source
of truth for the domain.
