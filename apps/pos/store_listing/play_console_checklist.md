# GastroCore POS – Google Play Console Submission Checklist

**Package:** com.gastrocore.gastrocore_pos
**Version:** 0.1.0 (versionCode: 1)
**Developer:** 2Tech GmbH
**Contact:** developer@2tech.ch
**Privacy Policy:** https://gastrocore.ch/privacy

---

## 1. App Category & Details

| Field | Value |
|---|---|
| **Category** | Business |
| **Sub-category** | Productivity |
| **Contact email** | developer@2tech.ch |
| **Website** | https://gastrocore.ch |
| **Privacy Policy URL** | https://gastrocore.ch/privacy |

---

## 2. Content Rating Questionnaire

### IARC / Google Play Rating

Answer the following in the Play Console under **Policy → App content → Content rating**:

| Question | Answer |
|---|---|
| Does the app contain violence? | No |
| Does the app contain sexual content? | No |
| Does the app contain profanity or crude language? | No |
| Does the app contain controlled substances? | No |
| Does the app simulate gambling? | No |
| Does the app share user location? | No |
| Does the app allow users to interact with each other? | No |
| Is the app a news app? | No |
| Is this a government app? | No |

**Expected rating:** Everyone (E) / PEGI 3 / USK 0

---

## 3. Target Audience

| Field | Value |
|---|---|
| **Primary audience** | Adults (18+) |
| **Target users** | Restaurant owners, managers, waitstaff |
| **Is this app directed at children?** | No |
| **Does the app collect data from users under 13?** | No |

> In Play Console: **Policy → App content → Target audience** → Select "18 and over"

---

## 4. Data Safety Form

Complete under **Policy → App content → Data safety**

### 4.1 Data Collected

| Data Type | Collected? | Shared with 3rd parties? | Encrypted? | User can delete? | Purpose |
|---|---|---|---|---|---|
| Name (staff name) | Yes | No | Yes (local DB) | Yes | App functionality |
| PIN / credentials | Yes | No | Yes (hashed) | Yes | Authentication |
| Order/transaction data | Yes | No | Yes (local DB) | Yes | App functionality |
| Device identifiers | No | — | — | — | — |
| Location | No | — | — | — | — |
| Payment card data | No* | — | — | — | — |
| Photos/media | No | — | — | — | — |
| Contacts | No | — | — | — | — |

> *Card payment data is handled entirely by Wallee/MyPOS terminals — GastroCore never sees or stores raw card data.

### 4.2 Data Safety Answers

- **Does your app collect or share any of the required user data types?** → Yes (staff names, transaction records)
- **Is all of the user data collected by your app encrypted in transit?** → Yes (HTTPS for sync, local SQLite encrypted)
- **Do you provide a way for users to request that their data is deleted?** → Yes (via Settings → Data Management → Delete all data)
- **Is your app's data collection required (users cannot opt out)?** → Yes, for core functionality (orders must be stored)

### 4.3 Data Practices

- Data is **not** sold to third parties
- Data is **not** used for advertising or marketing
- Data is used solely for app functionality (order management, reporting)
- Sync to cloud (if enabled) uses encrypted HTTPS connections

---

## 5. App Permissions Justification

Document for Play Console review. Under **Policy → App content → Permissions**

| Permission | Reason |
|---|---|
| `INTERNET` | Sync orders/menu with backend server (optional cloud sync) |
| `ACCESS_NETWORK_STATE` | Detect connectivity for offline/online mode switching |
| `ACCESS_WIFI_STATE` | Discover network printers and payment terminals on LAN |
| `BLUETOOTH_CONNECT` | Connect to Bluetooth receipt printers and card terminals |
| `BLUETOOTH_SCAN` | Discover nearby Bluetooth printers and payment devices |
| `BLUETOOTH` / `BLUETOOTH_ADMIN` | Legacy Bluetooth support (Android ≤ 11) |
| `CAMERA` | Future: barcode/QR scanning for products and TWINT |
| `WRITE_EXTERNAL_STORAGE` | Backup export on Android ≤ 9 |
| `READ_EXTERNAL_STORAGE` | Backup import on Android ≤ 12 |
| `WAKE_LOCK` | Prevent screen sleep during active service (kiosk mode) |
| `RECEIVE_BOOT_COMPLETED` | Reserved, currently disabled — future kiosk auto-start |

---

## 6. Store Listing Assets Checklist

### Screenshots (1080×1920 recommended, min 320px, max 3840px)
- [ ] `screenshot_pos.html` → POS order screen (open in browser, screenshot at 1080×1920)
- [ ] `screenshot_kds.html` → Kitchen Display System
- [ ] `screenshot_tables.html` → Table management floor plan
- [ ] `screenshot_reports.html` → Reports & dashboard
- [ ] `screenshot_payments.html` → Payment screen

> **Note:** Minimum 2 screenshots required. Maximum 8. Recommended: all 5.

### Feature Graphic (exactly 1024×500)
- [ ] `feature_graphic.html` → Open in browser at 1024×500, screenshot

### App Icon (512×512 PNG, no alpha)
- [ ] Export a 512×512 version of the app icon for Play Console upload
- Current mipmap icons exist in `android/app/src/main/res/mipmap-*/ic_launcher.png`
- Create hi-res 512×512 version for Play Console separately

### Short Promo Video (optional)
- [ ] 30–120 second screen recording of key features (optional but recommended)

---

## 7. Release Setup

### Release Track Recommendation
1. **Internal testing** (upload first AAB, test on real devices)
2. **Closed testing (Alpha)** — invite 10–20 restaurant testers
3. **Open testing (Beta)** — broader audience
4. **Production** — full rollout

### Build Requirements
- Upload format: **Android App Bundle (.aab)** (not APK)
- Target API: **35** (Android 15) ✅ already set
- Min API: per `flutter.minSdkVersion` (Flutter 3.35 default = 21)
- Signing: Release keystore configured in `android/key.properties` ✅

### Build Command
```bash
cd apps/pos
flutter build appbundle --release
# Output: build/app/outputs/bundle/release/app-release.aab
```

---

## 8. Pre-launch Checklist

- [ ] `android:label` in AndroidManifest.xml set to `"GastroCore POS"` (not `"gastrocore_pos"`)
- [ ] `versionCode` incremented for each upload (current: 1)
- [ ] `versionName` matches semantic version (current: 0.1.0)
- [ ] ProGuard rules configured (`android/app/proguard-rules.pro`)
- [ ] Release build tested on physical Android device
- [ ] All 4 locales tested: DE, FR, IT, EN
- [ ] Payment flows tested end-to-end (Wallee/MyPOS sandbox)
- [ ] TWINT payment tested
- [ ] Offline mode tested (airplane mode)
- [ ] Z-report generation tested
- [ ] Privacy policy page live at https://gastrocore.ch/privacy
- [ ] App icon reviewed (no transparent background for Play Store hi-res)

---

## 9. Post-submission

- **Review time:** Typically 3–7 days for new apps
- **Common rejection reasons:**
  - Missing privacy policy (ensure URL is live)
  - Screenshots don't match app functionality
  - Permissions not justified
  - App crashes on test devices (check pre-launch report)
- **Monitor:** Play Console → Android vitals for crashes after launch
