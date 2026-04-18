# Boss App (Owner Mobile)

**Status:** Not started — deferred to post-pilot.
**Phase:** 5 (per `docs/22-multi-app-architecture.md` and `roadmap-remaining.md`).
**Target start:** After Phase 4 (Web Dashboard / Cloud APIs) is live.
**Estimated effort:** 3–4 person-weeks.

## Why this folder exists

The Swiss fine-dining pilot (target 2026-05-01) ships without the Boss app. The pilot restaurant owner will read daily numbers from the POS back office and the Z-report until the mobile Boss app ships in Phase 5.

This folder is a placeholder so that:

1. Scope is visible in the repo tree (not "forgotten").
2. The backlog (`BACKLOG.md`) is version-controlled alongside the other app plans.
3. A future developer can `flutter create .` here when Phase 5 starts, without a git move.

## Do not add code here yet

Phase 5 depends on cloud REST endpoints that are built in Phase 3 (Cloud Sync — Go Backend) and Phase 4 (Web Dashboard). Starting the Flutter project before those APIs exist means throwing away mock-data screens.

See [`BACKLOG.md`](BACKLOG.md) for the full feature list and unblock dependencies.

## Naming history

Earlier architecture docs called this app the **"Patron App"**. The canonical name is now **"Boss app"** — folder, app id, and all new docs follow it. Legacy `patron` references are synonyms and should be updated when touched.
