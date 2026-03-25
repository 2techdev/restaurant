# 25 — Play Distribution and Monetization

> **Document Status:** Authoritative | **Last Updated:** 2026-03-24
>
> Updated: removed `lan_sync` from license token (replaced with `multi_device`).
> myPOS confirmed as primary payment terminal.

---

## 1. Decision: Distribution Strategy

### Options Evaluated

| Option | Description | Verdict |
|--------|-------------|---------|
| A: Public Play Store + Play Billing | Free app on Play, in-app subscription via Google Play Billing | Rejected |
| B: Direct B2B invoicing + APK sideload | Send signed APK directly to restaurant owners, invoice monthly | Partial — for pilot only |
| C: Play Store (free app) + server-side license | App on Play Store, subscription managed via our own license server | **Selected** |

### Recommendation: Option C (Hybrid)

**App distribution:** Google Play Store (free to install, no trial lock)
**License management:** Server-side via GastroCore license service
**Payment collection:** Direct B2B invoice (bank transfer, SEPA) — no Play Billing
**Billing platform (v2):** Add Payrexx (Swiss) or similar after 10+ customers

**Rationale:**

1. Play Store distribution gives discoverability, trust signal, and auto-update
2. Server-side licensing means Google never touches subscription revenue
3. Restaurant customers in DACH expect bank transfer or SEPA invoice, not in-app payment
4. We avoid Google's 15–30% revenue cut on B2B subscriptions
5. Direct invoicing is standard B2B SaaS in the restaurant tech sector

---

## 2. Distribution Phases

### Phase 0–1 (Now — Pilot): APK Sideload

**Method:** Manual APK installation on pilot devices
- Generate signed APK: `flutter build apk --release`
- Install via USB or direct download link
- Maximum 3 pilot restaurants

**Requirements:**
- Android device: enable "Install from unknown sources" once
- Instructions provided to restaurant owner during onboarding

### Phase 2–3 (Pilot Validation): Play Internal Testing

**Method:** Google Play Console — Internal Test Track (up to 100 testers)
- App NOT publicly visible
- Share via test link or add tester emails
- Auto-updates work

**Requirements:**
- Google Play Developer account (EUR 25 one-time)
- Signed AAB: `flutter build appbundle --release`
- `targetSdk 35` (required for Play submission)
- Privacy policy URL (hosted at gastrocore.ch/privacy)
- Data safety declaration

### Phase 4+ (Commercial Launch): Play Production

**Method:** Play Store public listing
- Phased rollout: 10% → 50% → 100%
- App description in German (primary) and English
- Screenshots from real restaurant

---

## 3. Monetization Model

### 3.1 Subscription Tiers

| Tier | Monthly CHF | Annual CHF | Devices | Key Features |
|------|------------|------------|---------|-------------|
| **Starter** | 49 | 490 (save 2 months) | 1 device | Core POS, cash + 1 terminal, shifts, receipts, offline |
| **Professional** | 79 | 790 | Up to 5 | + KDS, cloud sync, multi-device, Swiss compliance, reports |
| **Enterprise** | 149 | 1,490 | Unlimited | + Multi-branch, API, custom backoffice export |

**Pricing rationale:**
- Starter CHF 49: below Lightspeed (CHF 119+), competitive with Loyverse Pro
- Professional CHF 79: strong value; covers 80% of restaurant use cases
- Enterprise CHF 149: priced for 2–5 branch operators, not chains

### 3.2 Annual Offline License

For restaurants that want **zero cloud dependency**:

- Annual license fee: CHF 490 (Starter) / CHF 790 (Professional)
- License token: Ed25519-signed JWT, validated locally — no internet required
- Renewal: new token sent by email before expiry
- Grace period: 90 days after expiry (features continue, renewal banner shown)
- Post-grace: app enters "receipt-only mode"

**Receipt-only mode:**
- Can open shift, take orders, process payments, print receipts ✅
- Cannot access: KDS, multi-device, reports, settings changes ❌
- Business never locked out mid-service due to billing

### 3.3 License Expiry Behavior

| Scenario | Behavior |
|----------|----------|
| License valid, device offline | Full operation — validated locally |
| License expired 0–90 days, offline | Full operation + renewal banner |
| License expired 90+ days, offline | Receipt-only mode |
| License expired 90+ days, reconnected | If renewed: full restore on next license fetch. If not: receipt-only continues. |

---

## 4. Feature Flag Model

### 4.1 License Token Structure

```json
{
  "tenant_id": "uuid-v7",
  "plan": "professional",
  "issued_at": "2026-03-24T00:00:00Z",
  "expires_at": "2027-03-24T00:00:00Z",
  "device_limit": 5,
  "features": {
    "kds": true,
    "multi_device": true,
    "cloud_sync": true,
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

**Note:** `lan_sync` feature flag removed. Replaced with `multi_device` (which requires cloud sync).

Token is Ed25519-signed. Flutter app verifies signature using bundled public key. Cannot be forged without private key.

### 4.2 Feature Gating in Flutter

```dart
// Gate pattern (not yet wired in feature code — see doc 22 GAP-03):
if (ref.read(licenseProvider).hasFeature(Feature.kds)) {
  // Show KDS navigation item
} else {
  // Show upgrade prompt
}
```

Gate points:
- KDS navigation entry (Professional)
- Multi-device settings (Professional)
- Cloud sync settings (Professional)
- Multi-branch settings (Enterprise)
- API access (Enterprise)

### 4.3 Freemium / Demo Mode

- App installed from Play: runs in "Demo Mode" until a license is loaded
- Demo mode: full functionality, but max 5 orders per shift, watermark on receipts
- License activation: scan QR code containing license token OR enter key manually
- License key format: `GC-XXXX-XXXX-XXXX-XXXX` (human-readable 4×4 groups)
- Trial license: 30-day full Professional trial, no credit card required

---

## 5. Payment Collection

**v1 (pilot phase):** Manual invoicing
- PDF invoice sent by email
- Bank transfer (IBAN, SEPA)
- Monthly or annual
- Swiss: CHF to IBAN at a Swiss bank

**v2 (after 10+ customers):** Payrexx or Stripe integration
- Card-on-file subscription
- Automatic monthly/annual billing
- Self-service upgrade/downgrade portal
- Payrexx preferred (Swiss company, lower fees for CHF, supports TWINT for subscription)

**Not using:**
- Google Play Billing (revenue share unacceptable for B2B)
- Apple App Store (iOS not targeted in v1)
- PayPal (not standard B2B in DACH)

---

## 6. Play Store Requirements Checklist

### Technical Requirements

- [ ] `targetSdk 35` (required for new apps on Play)
- [ ] `minSdk 26` (Android 8.0 — covers modern tablets)
- [ ] 64-bit builds only (AAB with arm64-v8a)
- [ ] App signing with upload keystore
- [ ] No `android:requestLegacyExternalStorage` (scoped storage required)
- [ ] USB device filter declared in `AndroidManifest.xml` (already present)
- [ ] Bluetooth permissions declared
- [ ] No cleartext HTTP in production (`android:usesCleartextTraffic="false"` globally)
- [ ] Network security config: HTTPS only (no LAN cleartext exceptions needed)

### Store Listing Requirements

- [ ] App icon: 512×512 PNG, no transparency
- [ ] Feature graphic: 1024×500 PNG
- [ ] Screenshots: phone (min 2), tablet (min 1)
- [ ] Short description: 80 chars — "Offline-first restaurant POS for Switzerland and Germany"
- [ ] Full description: 4000 chars (German primary, English)
- [ ] Privacy policy URL (live HTTPS)
- [ ] Data safety section:
  - No personal customer data collected ✅
  - Staff names + hashed PINs stored locally ✅
  - Transaction data: local + cloud backup if subscribed ✅
  - No location data ✅
  - No advertising ID ✅
- [ ] Content rating questionnaire
- [ ] Category: Business / Productivity

### Privacy Policy Requirements (GDPR + nDSG)

- Data collected: staff names, hashed PINs, transaction records
- Data location: local device (SQLite), cloud backup if subscribed (opt-in)
- Data retention: configurable, default 7 years (Swiss accounting requirement)
- Data deletion: available on account termination
- Contact: privacy@gastrocore.ch

---

## 7. Versioning Strategy

### Version Numbers

Format: `MAJOR.MINOR.PATCH+BUILD`

| Component | Meaning | Increment rule |
|-----------|---------|---------------|
| MAJOR | Breaking schema change | On migration requiring user action |
| MINOR | New feature | On each phase gate completion |
| PATCH | Bug fix | On hotfix releases |
| BUILD | Auto-increment | On every CI/CD build |

Current: `0.1.0+1` → First pilot APK: `1.0.0+1000`

### Release Tracks

| Track | Audience | Criteria |
|-------|----------|---------|
| Internal (0–100) | Team + pilot restaurants | Passes tests + manual smoke test |
| Closed Beta | 10–50 restaurants | Phase gate passed |
| Open Beta | Play Store, "beta" badge | 30 days stable in closed beta |
| Production | All Play users | No critical bugs in 2 weeks open beta |

---

## 8. Anti-Piracy Approach

Low investment in DRM. The DACH B2B restaurant market is small and professional. Piracy risk is low.

**Practical measures:**
1. Cloud features (sync, reports, dashboard) require valid license — cracked offline version has limited appeal
2. Ed25519 signature on license token — cannot forge without private key
3. Device limit enforced server-side
4. Dart code obfuscation: `--obfuscate --split-debug-info=...`
5. Root detection: warn on rooted device (don't block — kiosk mode sometimes needs root)

**Not implemented:** Certificate pinning, hardware attestation, Play Integrity API — complexity without proportionate protection in this market.

---

## 9. myPOS as Primary Terminal — Monetization Note

myPOS provides their own acquiring service. For restaurants using myPOS terminals, card processing fees go directly to myPOS (not through GastroCore). This is the correct model for B2B restaurant POS — GastroCore earns on subscription, not on transaction volume.

Wallee integration is available for restaurants with existing acquiring contracts. The hardware abstraction layer supports both with zero switching cost in the app.
