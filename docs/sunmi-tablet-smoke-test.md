# Sunmi Tablet Smoke-Test Checklist — Waiter App (Sprint 2)

**Target hardware:** Sunmi V2s Pro / M2 Max (Android 11+, 800×1280 portrait).
**Build:** `flutter build apk --release --flavor waiter` (or the default APK if
no flavor is set).
**Tester role:** waiter for the fine-dining pilot (Swiss 4-top / 6-top service).

This is the physical-device smoke test for Sprint 2. The items below cover
the golden paths that are most at risk of breaking on a real tablet versus the
desktop dev emulator: thermal printer, USB-OTG peripherals, offline
connectivity, and touch interaction on a 7–8" screen.

Run the full pass **once per release candidate**. Record pass/fail beside each
item with a short note. Anything red blocks the pilot deploy.

---

## 0. Install & cold start

| # | Step | Expected | Result |
|---|------|----------|--------|
| 0.1 | Connect tablet via USB, enable ADB debugging, run `adb install -r build/app/outputs/flutter-apk/app-release.apk` | APK installs without signature conflict | ☐ |
| 0.2 | Open the app from the launcher | Cold-start under 4 s, no white flash | ☐ |
| 0.3 | Log in as the seeded waiter user | Lands on waiter home (tables grid) | ☐ |
| 0.4 | Rotate the tablet | Portrait only — orientation locked | ☐ |

## 1. Table → ticket → quick-add (golden path)

| # | Step | Expected | Result |
|---|------|----------|--------|
| 1.1 | Tap a free 4-top | Table dialog opens, "Start order" enabled | ☐ |
| 1.2 | Set guest count to 4, start order | Menu screen opens, draft ticket created | ☐ |
| 1.3 | Tap 3 products to quick-add (one per gang) | Each add shows a toast, running total updates | ☐ |
| 1.4 | Seat selector visible with "Shared" + Seat 1..4 | Chips render in one horizontal row, no wrap | ☐ |
| 1.5 | Pick "Seat 2", add one more product | Order list shows the new item with a Seat-2 badge | ☐ |

## 2. Gang (Kurs) flow

| # | Step | Expected | Result |
|---|------|----------|--------|
| 2.1 | Switch to Order tab | Items grouped by Gang 1 / 2 / 3 | ☐ |
| 2.2 | Fire Gang 1 only | Gang 1 becomes "Sent", others unchanged | ☐ |
| 2.3 | From KDS (separate device / emulator), bump a Gang-1 item to ready | Waiter screen updates within ~1 s without pull-to-refresh; per-gang badge flips to "Ready · serve" | ☐ |
| 2.4 | Tap "Mark served" on Gang 1 | Items go to served state; badge disappears | ☐ |

## 3. Offline queue

| # | Step | Expected | Result |
|---|------|----------|--------|
| 3.1 | Turn on airplane mode | Orange offline banner appears at top | ☐ |
| 3.2 | Add 3 more items to the ticket | Adds succeed locally; UI responsive | ☐ |
| 3.3 | Fire Gang 2 while offline | Status transitions locally, outbox pill shows pending count | ☐ |
| 3.4 | Turn airplane mode off | Banner clears; "Sync now" fires automatically; pending count goes to 0 within ~5 s | ☐ |

## 4. Service calls (waiter → POS)

| # | Step | Expected | Result |
|---|------|----------|--------|
| 4.1 | Tap the bell icon in the waiter app bar | Sheet opens with Water / Bread / Manager / Cleanup / Other | ☐ |
| 4.2 | Raise a "Water" call | Sheet closes, confirmation toast | ☐ |
| 4.3 | On the POS/admin device, open Home | Bell in header shows red "1" badge | ☐ |
| 4.4 | Tap the badge, Ack the call on the POS | Status flips to Acknowledged (grey) | ☐ |
| 4.5 | Tap "Done" on the POS | Sheet auto-closes (last call), badge disappears | ☐ |

## 5. Billing & split

| # | Step | Expected | Result |
|---|------|----------|--------|
| 5.1 | From the Order tab, tap "Request bill" | Ticket enters billRequested; totals locked | ☐ |
| 5.2 | Hand off to cashier device — split by seat | Each seat's subtotal matches what was tagged on the waiter side | ☐ |

## 6. Thermal printer (if connected)

| # | Step | Expected | Result |
|---|------|----------|--------|
| 6.1 | Plug the ESC/POS USB printer into the Sunmi OTG port | Android grants USB permission | ☐ |
| 6.2 | From Settings → Printer, run "Test print" | Page prints with the logo + "GastroCore test" header | ☐ |
| 6.3 | Fire Gang 1 with a printer-bound kitchen station | Kitchen ticket prints with items + gang number + seat numbers | ☐ |
| 6.4 | Finalize the ticket in cash | Receipt prints with tax breakdown, MWST lines, tenant logo | ☐ |

If no printer is available at the pilot site, mark 6.x as **N/A** and log a
follow-up to retest once hardware arrives.

## 7. Camera / QR (if present)

| # | Step | Expected | Result |
|---|------|----------|--------|
| 7.1 | From the tables screen, scan a table QR code | Opens that table's ticket directly | ☐ |
| 7.2 | From Settings → Activation, scan a license QR | Tier lifts from Free to the scanned tier | ☐ |

N/A for Sunmi V2s (no rear camera) — skip and note the model in the row.

## 8. Battery & thermals (endurance)

| # | Step | Expected | Result |
|---|------|----------|--------|
| 8.1 | Leave the app open on the tables screen for 2 h at 50% brightness | Battery drain ≤ 20 %, chassis warm not hot | ☐ |
| 8.2 | After 2 h, run steps 1.1 → 1.5 again | No visible lag, no dropped gestures | ☐ |

---

## Reporting template

Paste into the pilot-rollout issue:

```
Device: Sunmi V2s Pro · Android 11 · APK <git-sha>
Tested by: <name> · <date>
Environment: <pilot tenant name>

Section 0: PASS
Section 1: PASS
Section 2: PASS (KDS sync measured ~600 ms)
Section 3: PASS
Section 4: PASS
Section 5: PASS
Section 6: N/A (no printer on site yet)
Section 7: N/A (no camera on V2s)
Section 8: PASS (17 % drain / 2 h)

Blockers: <none | list>
Follow-ups: <tickets filed>
```
