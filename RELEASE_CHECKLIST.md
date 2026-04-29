# GastroCore POS — Release Checklist

Use this checklist for every production release. Complete all items before
tagging a release commit and distributing builds to customers.

---

## 1. Code & Version

- [ ] Bump `version` in `apps/pos/pubspec.yaml` (e.g. `1.2.0+42`)
- [ ] Bump `version` in `apps/online/pubspec.yaml` if changed
- [ ] Bump Go server `version` constant in `server/cmd/server/main.go`
- [ ] All feature branches merged and CI green on `main`
- [ ] No `TODO(release)` / `FIXME` comments left unresolved

## 2. Database Migrations

- [ ] New `schemaVersion` in `app_database.dart` incremented
- [ ] `onUpgrade` handles every intermediate version correctly
      (test: fresh install → current, and: v(n-1) → v(n))
- [ ] `beforeOpen` backup runs without error on a test device
- [ ] Migration tested on physical device (not just simulator)

## 3. Security

- [ ] `JWT_SECRET` is a 256-bit random value (not the default placeholder)
- [ ] `LICENSE_SIGNING_KEY` is set in the production environment
- [ ] SENTRY_DSN is injected via `--dart-define=SENTRY_DSN=…`
- [ ] No secrets or API keys committed to git
      (`git log --all -S "secret" --oneline` returns nothing sensitive)
- [ ] CORS origin list tightened for production (not `*` if possible)
- [ ] PIN hashing uses SHA-256 (no plain-text PINs in logs or DB)

## 4. Performance & Stability

- [ ] Sentry DSN configured — test that a sample error appears in the dashboard
- [ ] SQLite indexes present (schema v8+): verify with
      `SELECT name FROM sqlite_master WHERE type='index'`
- [ ] No N+1 queries: review recent DAOs using Drift query logging
- [ ] App starts cold in < 3 s on the target tablet hardware
- [ ] Sync push/pull completes with 100 events in < 5 s on 4G

## 5. Flutter Build

- [ ] `flutter analyze` — zero errors, zero warnings
- [ ] `flutter test` — all tests pass
- [ ] `flutter test test/goldens/` — golden baselines match (regenerate
      with `--update-goldens` only on a reviewed layout change)
- [ ] `flutter test test/a11y/` — Semantics labels locked (PIN pad, etc.)
- [ ] `flutter build apk --release --dart-define=SENTRY_DSN=…`
- [ ] `flutter build windows --release` (if targeting Windows POS hardware)
- [ ] APK / EXE tested on at least one physical device
- [ ] App size within budget (APK < 50 MB, Windows < 100 MB)
- [ ] APK SHA-256 captured and posted to the update manifest
      (`apkUrl` + `sha256` must match the distributed artifact)

## 6. Go Server Build

- [ ] `go vet ./...` — no issues
- [ ] `go test ./...` — all tests pass
- [ ] `docker build -t gastrocore-server:VERSION .` — builds cleanly
- [ ] Health endpoint returns `{"status":"ok"}` after startup
- [ ] Database migrations run cleanly: `docker run … migrate`
- [ ] Rate limiter tested under simulated load (> 200 req/min throttled correctly)

## 7. Localisation

- [ ] All user-visible strings present in DE / FR / IT / EN / TR `.arb` files
- [ ] `flutter gen-l10n` run after any `.arb` changes
- [ ] Decimal separator correct for Switzerland (apostrophe: 1'234.56 CHF)
- [ ] Turkish staff UI spot-checked on a physical tablet (PIN login,
      Mesai panel, Settings → Güncelleme)

## 8. Payments & Fiscal

- [ ] Swiss MWST rates correct: 8.1 % standard / 3.8 % accommodation / 2.6 % reduced
- [ ] FareEngine unit tests pass (`flutter test test/fare_engine_test.dart`)
- [ ] Wallee LTI integration tested with a real terminal (sandbox mode)
- [ ] MyPOS integration tested (if applicable)
- [ ] Receipts include all mandatory fields:
      business name, address, MWST-Nr., tax breakdown per rate, total CHF

## 9. Licensing

- [ ] License Ed25519 public key matches the signing key used in production
- [ ] FREE tier limits enforced (menu items, devices, features)
- [ ] License expiry handled gracefully (grace period UI shown, not hard block)

## 10. Backup & Data Safety

- [ ] Manual backup tested via Settings → Backup & Restore
- [ ] Restore tested: backup → clear data → restore → verify data intact
- [ ] Pre-migration backup created before schema upgrade (check `migration_backups/` folder)
- [ ] BackupService prune: > 30 backups get auto-deleted

## 11. Offline / Sync

- [ ] App works fully offline (all reads/writes to SQLite succeed without server)
- [ ] Sync queue drains correctly when connectivity resumes
- [ ] Retry logic tested: simulate 3× 500 errors → expect exponential back-off
- [ ] WebSocket reconnects after 30 s of silence (heartbeat timeout)

## 12. Release Tagging

```bash
# Tag the release
git tag -a v1.2.0 -m "Release v1.2.0"
git push origin v1.2.0

# Build the Docker image
docker build -t gastrocore-server:1.2.0 server/
docker tag gastrocore-server:1.2.0 gastrocore-server:latest

# Archive Flutter build artifacts
zip -r gastrocore_pos_v1.2.0_android.zip build/app/outputs/flutter-apk/
```

## 13. Post-Release

- [ ] Sentry release marker created (via Sentry CLI or CI)
- [ ] Smoke test on a real POS terminal: login → order → payment → receipt → kitchen ticket
- [ ] Day-close (Z-report) tested end-to-end
- [ ] Monitor Sentry for new crash groups in the first 24 h
- [ ] Update customer release notes / changelog

---

*Last updated: 2026-04-22*
