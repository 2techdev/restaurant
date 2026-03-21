# 31 - Release Readiness

> **Document Status:** Authoritative | **Last Updated:** 2026-03-20
>
> Checklist for each release milestone: pilot APK, Play internal testing, Play production.

---

## 1. Release Tracks and Their Requirements

| Track | Audience | Requirements |
|-------|----------|-------------|
| **Pilot APK** | 1–3 pilot restaurants, sideloaded | Signing, functional test, backup plan |
| **Play Internal** | Team + 100 testers | Full Play submission requirements |
| **Play Closed Beta** | 10–50 restaurants | Store listing, privacy policy, data safety |
| **Play Production** | Public | All of the above + 30 days stable beta |

---

## 2. Android Keystore and Signing

### 2.1 Release Keystore

The release keystore (`gastrocore-release.jks`) is referenced in `android/app/build.gradle.kts`. Before any release:

- [ ] Verify `gastrocore-release.jks` exists and is not corrupted
- [ ] Verify `key.properties` exists with correct `storePassword`, `keyAlias`, `keyPassword`, `storeFile` path
- [ ] Store keystore backup in **3 separate secure locations** (password manager, encrypted drive, offline backup)
- [ ] Document key alias and store password in secure vault (Bitwarden, 1Password)
- [ ] **NEVER commit `key.properties` or the JKS file to git** — verify `.gitignore` excludes them

**Warning:** If the release keystore is lost, the app must be re-published under a new package name (existing installations cannot be updated). Treat the keystore as more critical than the codebase.

### 2.2 Play Upload Key (Separate from Release Key)

For Google Play App Signing (recommended):
- Upload key: used to sign AAB before upload
- Release key: stored by Google Play, used to re-sign the final APK
- If upload key is compromised: can request reset via Google Play Console
- Enroll in Play App Signing when creating the app in Play Console

### 2.3 Build Verification

Before any release build:

```bash
# Verify signing config:
flutter build appbundle --release

# Check output:
ls -la build/app/outputs/bundle/release/app-release.aab

# Verify signing:
jarsigner -verify -verbose build/app/outputs/bundle/release/app-release.aab
```

---

## 3. Android Build Configuration Checklist

File: `apps/pos/android/app/build.gradle.kts`

- [ ] `namespace = "com.gastrocore.gastrocore_pos"` — confirm app ID
- [ ] `targetSdk = 35` — required for Google Play submissions (set explicitly)
- [ ] `minSdk = 26` — Android 8.0, covers 99%+ of tablets in use
- [ ] `compileSdk = 35`
- [ ] `versionCode` — auto-increment from CI or manually before each release
- [ ] `versionName` — semantic version matching pubspec.yaml `version` field
- [ ] Java 11 compatibility: `sourceCompatibility = JavaVersion.VERSION_11`
- [ ] `buildTypes.release.minifyEnabled = true` — code shrinking
- [ ] `buildTypes.release.shrinkResources = true` — resource shrinking

---

## 4. Versioning

### 4.1 Version Policy

| Component | Example | Rule |
|-----------|---------|------|
| versionName | `1.2.3` | Semantic: MAJOR.MINOR.PATCH |
| versionCode | `1023` | Integer: MAJOR×1000 + MINOR×10 + PATCH |
| pubspec version | `1.2.3+1023` | `versionName+versionCode` |

**Increment rules:**
- **MAJOR** (1.x.x): Schema migration requiring user action, or breaking change
- **MINOR** (x.1.x): New feature shipped (each phase gate = MINOR bump)
- **PATCH** (x.x.1): Bug fix, no new features

### 4.2 First Release

Current: `0.1.0+1`
First pilot APK: `1.0.0+1000`
First Play Internal: `1.0.0+1001` (or next build)

---

## 5. Permissions Checklist (AndroidManifest.xml)

- [ ] `BLUETOOTH` + `BLUETOOTH_ADMIN` + `BLUETOOTH_CONNECT` + `BLUETOOTH_SCAN` — for printer
- [ ] `ACCESS_FINE_LOCATION` or `ACCESS_COARSE_LOCATION` — required by Android for Bluetooth scanning (explain in store listing)
- [ ] `INTERNET` + `ACCESS_NETWORK_STATE` — for sync and terminal communication
- [ ] `USB_PERMISSION` via `UsbManager` — for USB printers (USB filter XML exists)
- [ ] `WAKE_LOCK` — to prevent tablet sleeping during service
- [ ] `RECEIVE_BOOT_COMPLETED` (optional) — auto-start on tablet power-on

**Data safety note:** Location permission is technically required for Bluetooth scanning by Android API but GastroCore does NOT use location data. Declare this in Play data safety form.

---

## 6. Network Security Config

For production: no HTTP cleartext allowed.

`android/app/src/main/res/xml/network_security_config.xml`:
```xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <!-- Allow cleartext for LAN communication only (same-network POS devices) -->
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="true">192.168.0.0/16</domain>
        <domain includeSubdomains="true">10.0.0.0/8</domain>
        <domain includeSubdomains="true">172.16.0.0/12</domain>
    </domain-config>
    <!-- All other traffic must be HTTPS -->
    <base-config cleartextTrafficPermitted="false" />
</network-security-config>
```

**Do not** use `android:usesCleartextTraffic="true"` globally — this is a Play policy violation and security risk.

---

## 7. Play Store Listing Requirements

### 7.1 App Metadata

- [ ] App name: "GastroCore POS" (30 chars max)
- [ ] Short description: 80 chars max — "Offline-first restaurant POS for Switzerland and Germany"
- [ ] Full description: 4000 chars — German (primary) and English
- [ ] App icon: 512×512 PNG, no transparency
- [ ] Feature graphic: 1024×500 PNG
- [ ] Phone screenshots: minimum 2 (use Android emulator at phone resolution)
- [ ] Tablet screenshots: minimum 1 (10" tablet)
- [ ] Category: Business
- [ ] Tags: restaurant, POS, Kasse, offline, tablet

### 7.2 Privacy Policy

A live privacy policy URL is **mandatory** for Play Store submission.

Minimum content (GDPR + Swiss nDSG compliant):
- Data controller identity and contact
- What data is collected: staff names, hashed PINs, transaction data
- Purpose of collection: restaurant operations, reporting
- Data storage: local device + cloud if subscribed
- Retention: 7–10 years for accounting records
- User rights: access, deletion, portability
- Data sharing: no third-party sharing; Fiskaly for German fiscal (when applicable)
- Contact: privacy@gastrocore.ch (or equivalent)

Existing file: `docs/legal/privacy-policy.html` — review and update for v1, then host at public URL.

### 7.3 Data Safety Declaration

Google Play requires a Data Safety form. Declare:

| Data Type | Collected | Shared | Optional |
|-----------|---------|--------|---------|
| Name (staff) | Yes | No | No |
| Financial info (transactions) | Yes | No (cloud backup if opted in) | Yes |
| Location | No | No | — |
| Device ID | Yes (for sync) | No | No |

---

## 8. Target SDK Compliance

Android's requirements for Google Play:
- From August 2024: all new apps must target API 34 (Android 14) or higher
- We target API 35 (Android 15) — compliant

Verify Flutter + all plugins support API 35:
- [ ] `flutter doctor` shows no issues
- [ ] `slavesdk2.1.8.aar` (MyPOS) compatible with API 35 — verify
- [ ] All `android/` directories in plugins: no `targetSdkVersion` override lower than 35

---

## 9. Internal / Closed Testing Plan

### 9.1 Internal Testing (< 10 devices)

Before pilot APK distribution:

| Test | Method | Pass Criteria |
|------|--------|--------------|
| Cold start < 4s | Manual on physical tablet | App opens, PIN screen in < 4s |
| Full order flow | Manual | Order → payment → receipt in < 3 min |
| Receipt print (Bluetooth) | Physical printer | Correct format, 5s max |
| Receipt print (WiFi) | Physical printer | Correct format, 3s max |
| Offline full shift | Airplane mode | Complete shift without crash |
| Payment terminal | Wallee or MyPOS device | Transaction completes and receipt prints |
| Shift close Z-report | Manual | Correct totals, prints |
| KDS displays order | Two tablets | Ticket appears within 2s |
| Crash test | StressTest order mode | 200 orders without crash |
| Backup / restore | Manual | Restore exact data after reinstall |

### 9.2 Pre-Pilot Restaurant Checklist

Walk through with pilot restaurant manager before go-live:
- [ ] Restaurant settings configured (name, address, UID, MWST number)
- [ ] Tax profiles set up (Swiss MWST: 8.1%, 2.6%, 3.8%)
- [ ] Menu imported (categories, products, modifiers, prices)
- [ ] Staff users created with PINs assigned
- [ ] Tables and floor plan configured
- [ ] Printers tested (receipt + kitchen ticket)
- [ ] Payment terminals tested (Wallee/MyPOS)
- [ ] KDS tablet set up (if using)
- [ ] Backup procedure explained to manager
- [ ] Emergency contact number for support

---

## 10. Release Procedure (Manual — Pre-CI/CD)

Until CI/CD is set up (post-pilot), follow this manual procedure:

### Pre-Release
1. Update version in `pubspec.yaml` (versionName + versionCode)
2. Update `CHANGELOG.md` with release notes
3. Run all tests: `flutter test`
4. Fix any failing tests
5. Run `flutter analyze` — zero warnings in release-blockers

### Build
6. `flutter build appbundle --release --obfuscate --split-debug-info=build/debug-info`
7. Verify AAB output exists and is signed
8. Archive the AAB with `CHANGELOG.md` entry as documentation

### Distribution (Pilot Phase)
9. Upload to Play Console internal track OR send APK directly
10. Install on test tablet: verify app opens correctly
11. Run smoke test: one complete order cycle
12. Deliver to pilot restaurant with changelog

### Post-Release
13. Monitor for crash reports (manually check with pilot contact for first 48 hours)
14. Keep previous APK archived for rollback

---

## 11. CI/CD Plan (To Implement in Phase 2)

Minimum GitHub Actions pipeline:

```yaml
name: Build and Test

on:
  push:
    branches: [main, release/*]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: 'stable'
          channel: 'stable'
      - run: flutter pub get
        working-directory: apps/pos
      - run: flutter analyze
        working-directory: apps/pos
      - run: flutter test
        working-directory: apps/pos

  build:
    needs: test
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
      - run: flutter pub get
        working-directory: apps/pos
      - run: |
          echo "${{ secrets.KEYSTORE_BASE64 }}" | base64 --decode > android/app/gastrocore-release.jks
          echo "storePassword=${{ secrets.STORE_PASSWORD }}" > android/key.properties
          echo "keyPassword=${{ secrets.KEY_PASSWORD }}" >> android/key.properties
          echo "keyAlias=${{ secrets.KEY_ALIAS }}" >> android/key.properties
          echo "storeFile=gastrocore-release.jks" >> android/key.properties
        working-directory: apps/pos
      - run: flutter build appbundle --release
        working-directory: apps/pos
      - uses: actions/upload-artifact@v4
        with:
          name: release-aab
          path: apps/pos/build/app/outputs/bundle/release/app-release.aab
```

Keystore is stored as base64-encoded GitHub Secret. Never in the repository.

---

## 12. Rollback Procedure

If a release causes critical issues:
1. Halt rollout in Play Console (if phased rollout)
2. Roll back in Play Console to previous version
3. For sideloaded pilot: send previous APK directly
4. Notify affected restaurants immediately
5. Fix in hotfix branch → PATCH version bump → expedited release

**Minimum rollback time target:** < 1 hour for pilot, < 4 hours for Play production.
