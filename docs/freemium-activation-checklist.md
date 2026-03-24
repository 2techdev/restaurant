# Freemium Activation Checklist — GastroCore POS Free Tier

**Audit date:** 2026-03-24
**Scope:** `apps/pos` — single-restaurant, offline, no license token

---

## Summary

The free tier licensing system (`lib/features/licensing/`) is architecturally sound and works without any license token — the app defaults to `LicenseTier.free` automatically when no active row exists in `license_tokens`. The feature gate widgets correctly block PRO/ENT features and show upgrade prompts.

**However**, 4 issues prevented a restaurant from actually using the free version. All 4 have been fixed in this session.

---

## Feature Flag System (lib/features/licensing/) — PASS

| Check | Result |
|---|---|
| `LicenseTier.free` is default when no token present | ✅ Works — `licenseTierProvider` returns `free` when `currentLicenseProvider` is null |
| Free features gated correctly | ✅ `basicPos`, `singleDevice`, `limitedMenu`, `basicReports` all require `LicenseTier.free` |
| PRO/ENT features blocked without token | ✅ `FeatureGate` shows `LockedFeaturePlaceholder` with upgrade prompt |
| Token validation offline | ✅ Ed25519 public key embedded, no network call required |
| Grace period (7 days after expiry) | ✅ `LicenseEntity.isInGracePeriod` correct |
| `FeatureFlagService` accessible synchronously | ✅ `featureFlagServiceProvider` wraps sync `licenseTierProvider` |

---

## Free Tier Feature Coverage

The following operations are FREE and work offline with no license:

| Operation | Gating | Status |
|---|---|---|
| Basic POS ordering | `AppFeature.basicPos` (free) | ✅ Free |
| Table management | via `basicPos` (free) | ✅ Free |
| Cash payment | via `basicPos` (free) | ✅ Free |
| Receipt preview + print | via `basicPos` (free) | ✅ Free |
| Shift open/close | not gated | ✅ Free |
| Day close | not gated | ✅ Free |
| PIN staff login | not gated | ✅ Free |
| Menu up to 50 items | `AppFeature.limitedMenu` (free) | ✅ Free |
| Basic reports | `AppFeature.basicReports` (free) | ✅ Free |

---

## Issues Found and Fixed

### ISSUE 1 — BLOCKER: Brand auth gate prevents offline first launch

**Severity:** Critical — app unusable without this fix

**Problem:**
`app.dart` wires up the GoRouter with `authReader` pointing to `brandAuthProvider`. On a fresh install with no stored session, `isAuthenticated = false`, so the router immediately redirects every route to `/brand-login`. The brand login screen requires a working internet connection to authenticate against `pos.2tech.ch`. A restaurant in pure offline free mode had no way to proceed.

**Root cause:**
`lib/features/brand_auth/presentation/providers/brand_auth_provider.dart` → `BrandAuthNotifier.restoreSession()` returns `false` on first launch (no stored context). The router then enforces a redirect to `/brand-login` for all non-public routes.

**Fix applied:**
- `brand_auth_provider.dart`: Added `loginAsLocalDemo()` method that creates a synthetic `StoreContext` with `isOnlineMode: false` and sets `isInitialized: true`. No network call. Cloud sync stays disabled.
- `brand_login_screen.dart`: Added **"Offline / Demo-Modus"** outlined button below the login button. Tapping it calls `loginAsLocalDemo()` and navigates directly to `/login` (PIN screen).

**Files changed:**
- `lib/features/brand_auth/presentation/providers/brand_auth_provider.dart`
- `lib/features/brand_auth/presentation/screens/brand_login_screen.dart`

---

### ISSUE 2 — MAJOR: Payment screen doesn't record payment data

**Severity:** Major — payments complete visually but no financial data is stored

**Problem:**
`PaymentScreen._onCompletePayment()` only called `orderRepository.updateTicketStatus(ticketId, completed)`. It never called `PaymentRepositoryImpl.processPayment()`. As a result:
- No `Bill` row was created
- No `Payment` row was created
- Payment method (cash/card) was not stored
- Tendered amount and change were not stored
- Shift payment breakdowns showed CHF 0 for all closed tickets
- Revenue reports contained no data

Additionally, `paymentRepositoryProvider` did not exist — `PaymentRepositoryImpl` had no Riverpod provider.

**Fix applied:**
- `refund_provider.dart`: Added `paymentRepositoryProvider` (alongside the existing `refundRepositoryProvider`).
- `payment_screen.dart`: Rewrote `_onCompletePayment()` to call `paymentRepo.processPayment()` with ticket ID, tenant ID, mapped `PaymentMethod`, `_grandTotal`, tendered amount, and the logged-in user's name. `processPayment()` atomically creates the bill, inserts the payment row, and closes the ticket in a single DB transaction.

**Files changed:**
- `lib/features/payments/presentation/providers/refund_provider.dart`
- `lib/features/payments/presentation/screens/payment_screen.dart`

---

### ISSUE 3 — UX: Turkish Lira symbol (₺) used throughout Swiss app

**Severity:** Medium — cosmetically broken for Swiss market

**Problem:**
`\u20BA` (Turkish Lira ₺) was used as the currency symbol in:
- `payment_screen.dart` — order summary, totals, change display, completion screen
- `receipt_preview_screen.dart` — all price lines, subtotal, tax, total, discount

The demo restaurant is "Demo Restaurant Zürich" operating with Swiss VAT rates (8.1%/3.8%/2.6%), so ₺ was incorrect.

**Fix applied:**
Replaced all `'\u20BA` with `'CHF` in both files (replace_all pass). Two remaining interpolated instances (`'Para Ustu: \u20BA...'` and `'-\u20BA...'`) were fixed individually.

**Files changed:**
- `lib/features/payments/presentation/screens/payment_screen.dart`
- `lib/features/orders/presentation/screens/receipt_preview_screen.dart`

---

### ISSUE 4 — UX: Receipt shows raw UUID instead of waiter name

**Severity:** Low — cosmetically broken receipt

**Problem:**
`receipt_preview_screen.dart` displayed:
```dart
ticket.waiterId != null ? 'Garson: ${ticket.waiterId}' : ''
```
`ticket.waiterId` is a UUID (e.g. `3f8a2b1c-...`), not a human name. `TicketEntity` already has a `cashierName` field populated from the seeded users.

**Fix applied:**
Changed to use `ticket.cashierName` with German label "Bedient:":
```dart
ticket.cashierName != null ? 'Bedient: ${ticket.cashierName}' : ''
```

**Files changed:**
- `lib/features/orders/presentation/screens/receipt_preview_screen.dart`

---

## Demo Data — PASS

`SeedData.seedIfEmpty()` runs on every cold start. On a fresh install it seeds:

| Data | Count | Status |
|---|---|---|
| Tenant "Demo Restaurant Zürich" | 1 | ✅ |
| Staff users with hashed PINs | 5 | ✅ |
| Menu categories | 5 | ✅ |
| Products | ~40 | ✅ (within 50-item free limit) |
| Modifier groups | multiple | ✅ |
| Restaurant floors | 2 | ✅ |
| Tables | 20+ | ✅ |
| Swiss VAT profiles (8.1% / 3.8% / 2.6%) | 3 | ✅ |

No issues found with seed data.

---

## Full Flow Verification (post-fix)

| Step | Expected | Notes |
|---|---|---|
| **App start** | Runs seed if DB empty, pre-warms license cache, initializes ProviderScope | ✅ |
| **Brand login** | Shows "Offline / Demo-Modus" button | ✅ Fixed |
| **PIN login** | Staff grid + PIN pad | ✅ Users loaded from seed |
| **Shift open** | Opens shift if none active | ✅ |
| **Order** | Add items, assign table | ✅ Free `basicPos` feature |
| **Payment (cash)** | Numpad entry, change calculation, "Complete" button | ✅ Fixed — bill + payment row created |
| **Receipt** | CHF prices, restaurant name from DB, staff name (not UUID) | ✅ All fixed |
| **Shift close** | Calculates totals from recorded payments | ✅ Now works correctly |
| **Day close** | Aggregates all shifts | ✅ |

---

## Remaining Known Issues (not fixed — out of scope)

| Issue | Severity | Notes |
|---|---|---|
| Mixed Turkish labels in payment/receipt screens ("Odeme Tamamlandi", "TOPLAM", "Afiyet Olsun", etc.) | Cosmetic | Language is inconsistent but non-blocking. Full i18n via `AppLocalizations` is the correct fix — tracked in backlog. |
| `webSocketSyncClientProvider` connects to `localhost:8080` on every startup | Low | Fails silently in offline mode — no crash, no UI impact. |
| Card/split payment path not tested end-to-end | Low | `_PaymentMethod.creditCard` maps to `PaymentMethod.creditCard` but hardware terminal providers throw `UnimplementedError` — expected for free tier (cash only). |
| `receipt_preview_screen.dart` top bar shows "Precision.POS" logo | Cosmetic | Should be "GastroCore". Legacy placeholder. |
