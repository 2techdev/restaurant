# 25 - Play Distribution and Monetization

> **Document Status:** Authoritative | **Last Updated:** 2026-03-20

---

## 1. Decision: Distribution Strategy

### Options Evaluated

| Option | Description | Verdict |
|--------|-------------|---------|
| A: Public Play Store + Play Billing | Free app on Play, in-app subscription via Google Play Billing API | Rejected |
| B: Direct B2B invoicing + APK sideload | Send signed APK directly to restaurant owners, invoice monthly | Partial — for pilot only |
| C: Play Store (free app) + server-side license | App on Play Store, subscription managed via our own license server | **Selected** |

### Recommendation: Option C (Hybrid)

**App distribution:** Google Play Store (free to install, no trial lock)
**License management:** Server-side via GastroCore license service
**Payment collection:** Direct B2B invoice (bank transfer, SEPA, or Stripe/Payrexx)
**No Play Billing:** Google's 15–30% cut on B2B subscriptions is unacceptable at CHF 49–149/month price point

**Rationale:**

1. Play Store distribution gives discoverability, trust signal, and auto-update
2. Server-side licensing means Google never touches subscription revenue
3. Restaurant customers expect bank transfer or invoice — not in-app payment via Play
4. We avoid App Store vs Play Store payment policy complexity
5. Direct invoicing is standard B2B SaaS for restaurant tech in DACH region

---

## 2. Distribution Tiers

### Phase 0–1 (Now — Pilot): APK Sideload / Internal Testing

**Method:** Manual APK installation on pilot devices
- Generate signed APK: `flutter build apk --release`
- Install via USB or email attachment
- Only 2–3 pilot restaurants

**Requirements:**
- Android device: enable "Install from unknown sources" once
- Instructions provided to restaurant owner during onboarding

### Phase 2–3 (Pilot Validation): Play Internal / Closed Testing

**Method:** Google Play Console — Internal Test Track (up to 100 testers)
- App NOT publicly visible
- Share via test link or add tester emails
- Allows testing Play distribution path without public exposure
- Auto-updates work

**Requirements:**
- Google Play Developer account (EUR 25 one-time fee)
- Signed AAB: `flutter build appbundle --release`
- Target SDK 35 (required for Play submission)
- Privacy policy URL (hosted at gastrocore.ch/privacy or similar)
- Data safety declaration

### Phase 4+ (Commercial Launch): Play Production

**Method:** Play Store public listing
- Phased rollout: 10% → 50% → 100%
- App description in German (primary) and English
- Screenshots from real restaurant (no demo screenshots at launch)

---

## 3. Monetization Model

### 3.1 Subscription Tiers

| Tier | Monthly CHF | Annual CHF | Devices | Key Features |
|------|------------|------------|---------|-------------|
| **Starter** | 49 | 490 (2 months free) | 1 device, 1 branch | Core POS, cash + 1 terminal, shifts, receipts, offline |
| **Professional** | 79 | 790 | Up to 5 devices | + KDS, LAN sync, multi-device, Swiss compliance, reports |
| **Enterprise** | 149 | 1,490 | Unlimited | + Cloud sync, multi-branch, API, custom backoffice export |

**Pricing rationale:**
- Starter CHF 49: below Lightspeed (CHF 119+), comparable to Loyverse Pro
- Professional CHF 79: strong value vs. competitors requiring hardware bundles
- Enterprise CHF 149: priced for 2–5 branch operators, not chains

### 3.2 Annual Offline License

For restaurants that want **zero cloud dependency**:

- Annual license fee: CHF 490 (Starter) / CHF 790 (Professional)
- License token generated offline: Ed25519 signed JWT
- Token contains: tenant_id, plan, features, expiry date, device limit
- Validated locally on device — no internet required
- Renewal: send new token by email before expiry
- Grace period: 90 days after expiry (features continue, warning shown)
- Post-grace: app enters "receipt-only mode" (can still process sales, but reports/KDS locked)

**Receipt-only mode definition:**
- Can open shift, take orders, process payments, print receipts ✅
- Cannot access: KDS, multi-device, reports, settings changes ❌
- This prevents business disruption if owner forgets to renew during service

### 3.3 What Happens if License Expires While Offline

| Scenario | Behavior |
|----------|----------|
| License valid, device offline | Full operation — license validated locally |
| License expired 0–90 days, device offline | Full operation + renewal banner on home screen |
| License expired 90+ days, device offline | Receipt-only mode — orders + payments work, nothing else |
| License expired 90+ days, reconnected | If renewed on server: full restore on next license fetch. If not: receipt-only continues. |

This design means **a restaurant can never be locked out mid-service** due to a billing issue. Revenue protection comes first.

---

## 4. Feature Flag Model

### 4.1 License Token Structure

```json
{
  "tenant_id": "uuid-v7",
  "plan": "professional",
  "issued_at": "2026-03-20T00:00:00Z",
  "expires_at": "2027-03-20T00:00:00Z",
  "device_limit": 5,
  "features": {
    "kds": true,
    "lan_sync": true,
    "cloud_sync": false,
    "multi_branch": false,
    "custom_backoffice_export": false,
    "germany_fiscal": false,
    "switzerland_pack": true,
    "api_access": false,
    "max_products": 500,
    "max_users": 20
  }
}
```

Token is Ed25519-signed. Flutter app verifies signature using bundled public key. Cannot be forged without private key.

### 4.2 Feature Gating in Flutter

```dart
// Usage pattern (not yet implemented — see GAP-03):
if (licenseProvider.hasFeature(Feature.kds)) {
  // Show KDS navigation item
}
```

Gate points:
- Navigation item visibility
- Screen entry guard (redirect to upgrade prompt if not licensed)
- API calls that require tier (cloud sync requires cloud_sync flag)

### 4.3 Freemium / Demo Mode

- App installed from Play: runs in "Demo Mode" until a license is loaded
- Demo mode: full functionality, but max 5 orders per shift, watermark on receipts
- License activation: scan QR code containing license token OR enter license key manually
- License key format: `GC-XXXX-XXXX-XXXX-XXXX` (human-readable 4×4 groups)

---

## 5. Payment Collection

**v1 (pilot phase):** Manual invoicing
- PDF invoice sent by email
- Bank transfer (IBAN, SEPA)
- Monthly or annual

**v2 (after 10+ customers):** Stripe or Payrexx integration
- Card-on-file subscription
- Automatic monthly/annual billing
- Self-service upgrade/downgrade portal

**Not using:**
- Google Play Billing (revenue share unacceptable)
- Apple App Store (iOS not targeted in v1)
- PayPal (not standard B2B in DACH)

---

## 6. Play Store Requirements Checklist

### Technical Requirements

- [ ] `targetSdk 35` (required for new apps from Aug 2024)
- [ ] `minSdk 26` (Android 8.0 — covers 99%+ of modern tablets)
- [ ] 64-bit builds only (AAB with arm64-v8a)
- [ ] App signing with upload keystore (separate from release keystore)
- [ ] No `android:requestLegacyExternalStorage` (scoped storage required)
- [ ] USB device filter declared in `AndroidManifest.xml` (already exists)
- [ ] Bluetooth permissions declared (for printer)
- [ ] No cleartext HTTP in production (enforce `android:usesCleartextTraffic="false"`)
- [ ] Network security config for LAN discovery exceptions

### Store Listing Requirements

- [ ] App icon: 512×512 PNG, no alpha
- [ ] Feature graphic: 1024×500 PNG
- [ ] Screenshots: phone (minimum 2), tablet (minimum 1)
- [ ] Short description: 80 characters max
- [ ] Full description: 4000 characters max (in German + English)
- [ ] Privacy policy URL (must be live HTTPS URL)
- [ ] Data safety section completed:
  - No personal data collected from customers ✅
  - Staff PIN stored locally (not shared) ✅
  - Cloud sync: anonymized transaction data ✅
  - No location data ✅
  - No advertising ID ✅
- [ ] Content rating questionnaire completed
- [ ] Category: Business / Productivity

### Privacy Policy Requirements (GDPR + nDSG)

Minimum required declarations:
- Data collected: staff names, hashed PINs, transaction records
- Data location: local device (SQLite), cloud backup if subscribed
- Data retention: configurable, default 7 years (Swiss accounting requirement)
- Data deletion: available on account termination
- Contact: data protection officer email

---

## 7. Versioning Strategy

### Version Numbers

Format: `MAJOR.MINOR.PATCH+BUILD`

| Component | Meaning | Increment rule |
|-----------|---------|---------------|
| MAJOR | Breaking schema change | On migration that requires user action |
| MINOR | New feature | On each phase gate completion |
| PATCH | Bug fix | On hotfix releases |
| BUILD | Auto-increment | On every CI/CD build |

Current: `0.1.0+1` → First pilot release: `1.0.0+N`

### Release Tracks

| Track | Audience | Criteria |
|-------|----------|---------|
| Internal (0–100) | Team + pilot restaurants | Any build that passes tests |
| Closed Beta | 10–50 trusted restaurants | Phase gate passed |
| Open Beta | Play Store visible, "beta" badge | 30 days stable in closed beta |
| Production | All Play Store users | No critical bugs in 2 weeks open beta |

---

## 8. Anti-Piracy Approach

**Not worth over-investing in DRM.** The DACH B2B restaurant market is small and professional. Piracy risk is low.

**Practical measures:**
1. Cloud features (sync, reports, dashboard) require valid license → cracked local-only version has limited appeal
2. Ed25519 signature on license token — cannot forge without private key
3. Device limit enforced server-side
4. Dart code obfuscation: `flutter build appbundle --obfuscate --split-debug-info=...`
5. Root detection: warn if rooted device (not block — restaurant owners sometimes root for kiosk mode)

**Not implemented:** Certificate pinning, hardware attestation, Play Integrity API. These add complexity without proportionate protection in this market.
