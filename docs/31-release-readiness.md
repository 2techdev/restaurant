# 31 — Release Readiness

> **Document Status:** Authoritative | **Last Updated:** 2026-03-24
>
> Checklist for each release milestone: pilot APK, Play internal testing, Play production.
> Updated: network security config simplified — no LAN cleartext exceptions needed.

---

## 1. Release Tracks and Requirements

| Track | Audience | Requirements |
|-------|----------|-------------|
| **Pilot APK** | 1–3 pilot restaurants, sideloaded | Signing, functional test, backup plan |
| **Play Internal** | Team + 100 testers | Full Play submission requirements |
| **Play Closed Beta** | 10–50 restaurants | Store listing, privacy policy, data safety |
| **Play Production** | Public | All of the above + 30 days stable in closed beta |

---

## 2. Android Keystore and Signing

### 2.1 Release Keystore

The release keystore (`gastrocore-release.jks`) is referenced in `android/app/build.gradle.kts`. Before any release:

- [ ] Verify `gastrocore-release.jks` exists and is not corrupted
- [ ] Verify `key.properties` exists with `storePassword`, `keyAlias`, `keyPassword`, `storeFile`
- [ ] Store keystore in **3 separate secure locations** (password manager, encrypted drive, offline backup)
- [ ] Document key alias and password in secure vault (Bitwarden, 1Password, etc.)
- [ ] **NEVER commit `key.properties` or the JKS to git** — verify `.gitignore` excludes them

**Warning:** If the release keystore is lost, the app must be re-published under a new package name (existing installations cannot be updated). Treat the keystore as more critical than the codebase.

### 2.2 Play Upload Key (Separate from Release Key)

For Google Play App Signing (recommended):
- Upload key: used to sign AAB before upload
- Release key: stored by Google Play, used to re-sign the final APK
- If upload key is compromised: can request reset via Play Console
- Enroll in Play App Signing when creating the app in Play Console

### 2.3 Build Verification

```bash
# Release build:
flutter build appbundle --release --obfuscate --split-debug-info=build/debug-info

# Verify output exists:
ls -la build/app/outputs/bundle/release/app-release.aab

# Verify signing:
jarsigner -verify -verbose build/app/outputs/bundle/release/app-release.aab
```

---

## 3. Android Build Configuration Checklist

File: `apps/pos/android/app/build.gradle.kts`

- [ ] `namespace = "com.gastrocore.gastrocore_pos"` — confirm app ID
- [ ] `targetSdk = 35` — required for Play Store submissions
- [ ] `minSdk = 26` — Android 8.0 minimum
- [ ] `compileSdk = 35`
- [ ] `versionCode` — auto-increment or manually set before each release
- [ ] `versionName` — matches `pubspec.yaml` version field
- [ ] Java 11: `sourceCompatibility = JavaVersion.VERSION_11`
- [ ] `buildTypes.release.minifyEnabled = true` — code shrinking
- [ ] `buildTypes.release.shrinkResources = true` — resource shrinking
- [ ] Obfuscation flags in release build command

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
- **MINOR** (x.1.x): New feature (each phase gate = MINOR bump)
- **PATCH** (x.x.1): Bug fix, no new features

### 4.2 First Release

Current: `0.1.0+1`
First pilot APK: `1.0.0+1000`
First Play Internal: `1.0.0+1001` (next build)

---

## 5. Permissions Checklist (AndroidManifest.xml)

- [ ] `BLUETOOTH` + `BLUETOOTH_ADMIN` + `BLUETOOTH_CONNECT` + `BLUETOOTH_SCAN` — for printer
- [ ] `ACCESS_FINE_LOCATION` or `ACCESS_COARSE_LOCATION` — required by Android for BT scanning (declare in data safety: not used for location)
- [ ] `INTERNET` + `ACCESS_NETWORK_STATE` — for cloud sync and terminal communication
- [ ] `USB_PERMISSION` via `UsbManager` — for USB printers (USB filter XML exists)
- [ ] `WAKE_LOCK` — prevent tablet sleeping during service
- [ ] `RECEIVE_BOOT_COMPLETED` (optional) — auto-start on tablet power-on

**Data safety note:** Location permission is technically required for Bluetooth scanning by Android API but GastroCore does NOT use location data. Declare this in Play data safety form.

---

## 6. Network Security Config

For production: all traffic must be HTTPS. No LAN cleartext exceptions needed (no LAN sync in architecture).

`android/app/src/main/res/xml/network_security_config.xml`:
```xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <!-- All traffic must be HTTPS — no cleartext allowed -->
    <base-config cleartextTrafficPermitted="false" />
</network-security-config>
```

`android/app/src/main/AndroidManifest.xml`:
```xml
<application
    android:networkSecurityConfig="@xml/network_security_config"
    android:usesCleartextTraffic="false"
    ...>
```

**Note:** Previous version of this document included LAN IP range cleartext exceptions. These are removed because LAN sync is not in the architecture. All device-to-device communication goes through the cloud hub over HTTPS.

**Exception for payment terminals:** myPOS SlaveSDK communicates via TCP on the local network — this is handled by the AAR library directly, not by the Android HTTP stack. No `network_security_config` exception required.

---

## 7. Play Store Listing Requirements

### 7.1 App Metadata

- [ ] App name: "GastroCore POS" (≤ 30 chars)
- [ ] Short description: "Offline-first restaurant POS for Switzerland and Germany" (≤ 80 chars)
- [ ] Full description (≤ 4000 chars) — German primary, English
- [ ] App icon: 512×512 PNG, no transparency
- [ ] Feature graphic: 1024×500 PNG
- [ ] Phone screenshots: min 2 (use Android emulator at phone resolution)
- [ ] Tablet screenshots: min 1 (10" tablet)
- [ ] Category: Business
- [ ] Tags: restaurant, POS, Kasse, offline, tablet, Schweiz

### 7.2 Privacy Policy

A live privacy policy URL is mandatory for Play Store submission.

Minimum content (GDPR + Swiss nDSG compliant):
- Data controller identity and contact email
- What data is collected: staff names, hashed PINs, transaction data
- Purpose: restaurant operations, reporting
- Data storage: local device (SQLite) + cloud if subscribed
- Retention: 7–10 years for accounting records
- User rights: access, deletion, portability
- Data sharing: no third-party sharing (except Fiskaly for German fiscal when applicable)
- Contact: privacy@gastrocore.ch

Existing file: `docs/legal/privacy-policy.html` — review and update for v1.

### 7.3 Data Safety Declaration

| Data Type | Collected | Shared | Optional |
|-----------|---------|--------|---------|
| Name (staff) | Yes | No | No |
| Financial info (transactions) | Yes | No (cloud backup opt-in) | Yes |
| Location | No | No | — |
| Device ID | Yes (sync) | No | No |

---

## 8. Target SDK Compliance

- From August 2024: all new Play apps must target API 34 or higher
- GastroCore targets API 35 — compliant
- Verify: `flutter doctor` shows no issues
- Verify: `slavesdk2.1.8.aar` (myPOS) compatible with API 35
- Verify: no plugin overrides `targetSdkVersion` below 35

---

## 9. Internal / Closed Testing Plan

### 9.1 Pre-Pilot Internal Testing

| Test | Method | Pass Criteria |
|------|--------|--------------|
| Cold start | Manual on physical tablet | PIN screen in < 4s |
| Full order flow | Manual | Order → payment → receipt in < 3 minutes |
| Receipt print (Bluetooth) | Physical printer | Correct format, < 5s |
| Receipt print (WiFi) | Physical printer | Correct format, < 3s |
| Offline full shift | Airplane mode | Complete shift without crash |
| Payment terminal (myPOS) | Physical terminal | TWINT + card transactions complete |
| Shift close Z-report | Manual | Correct totals, prints |
| KDS displays real order | Same device | Ticket appears within 2s |
| Backup / restore | Manual | Restore exact data after reinstall |
| Swiss VAT: dine-in | Manual | Receipt shows 8.1% MWST |
| Swiss VAT: takeaway | Manual | Receipt shows 2.6% MWST |
| 5-Rappen rounding | Manual | CHF 17.23 cash → CHF 17.25 |

### 9.2 Pre-Pilot Restaurant Checklist

Walk through with pilot restaurant manager before go-live:
- [ ] Restaurant settings configured (name, address, UID, MWST number)
- [ ] Tax profiles set up (Swiss MWST: 8.1%, 2.6%, 3.8%)
- [ ] Menu imported (categories, products, modifiers, prices)
- [ ] Staff users created with PINs
- [ ] Tables and floor plan configured
- [ ] Receipt and kitchen ticket printers tested
- [ ] Payment terminal tested (myPOS: card + TWINT)
- [ ] KDS set up on same tablet (or printed fallback confirmed)
- [ ] Backup procedure explained to manager
- [ ] Emergency support contact number given

---

## 10. Release Procedure (Manual — Pre-CI/CD)

### Pre-Release
1. Update version in `pubspec.yaml` (`versionName+versionCode`)
2. Update `CHANGELOG.md` with release notes
3. Run: `flutter test` — fix any failures
4. Run: `flutter analyze` — zero release-blocking warnings

### Build
5. `flutter build appbundle --release --obfuscate --split-debug-info=build/debug-info`
6. Verify AAB output exists and is signed
7. Archive AAB with changelog entry

### Distribution (Pilot Phase)
8. Upload to Play Console internal track OR send signed APK directly
9. Install on test tablet: verify app opens
10. Smoke test: one complete order → payment → receipt → kitchen ticket
11. Deliver to pilot restaurant with changelog summary

### Post-Release
12. Monitor first 48 hours: check with pilot contact daily
13. Keep previous APK archived for rollback

---

## 11. CI/CD Plan (Implement in Phase 2)

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
      - name: Decode keystore
        run: |
          echo "${{ secrets.KEYSTORE_BASE64 }}" | base64 --decode > android/app/gastrocore-release.jks
          echo "storePassword=${{ secrets.STORE_PASSWORD }}" > android/key.properties
          echo "keyPassword=${{ secrets.KEY_PASSWORD }}" >> android/key.properties
          echo "keyAlias=${{ secrets.KEY_ALIAS }}" >> android/key.properties
          echo "storeFile=gastrocore-release.jks" >> android/key.properties
        working-directory: apps/pos
      - run: flutter build appbundle --release --obfuscate --split-debug-info=build/debug-info
        working-directory: apps/pos
      - uses: actions/upload-artifact@v4
        with:
          name: release-aab
          path: apps/pos/build/app/outputs/bundle/release/app-release.aab
```

Keystore stored as base64-encoded GitHub Secret. Never in the repository.

---

## 12. Rollback Procedure

1. Halt rollout in Play Console (if phased)
2. Roll back to previous version in Play Console
3. For sideloaded pilot: send previous APK directly
4. Notify affected restaurants immediately
5. Fix in hotfix branch → PATCH version bump → expedited release

**Target rollback time:** < 1 hour for pilot, < 4 hours for Play production.
