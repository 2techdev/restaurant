# Waiter Device Smoke-Test Checklist — Waiter App (Sprint 2)

**Target form factor:** Android tablet, 7–10" screen, portrait, used by a
single waiter on the floor.
**Build:** `flutter build apk --release` → `build/app/outputs/flutter-apk/
app-release.apk` (rename to `app-pos-release.apk` for distribution).
**Tester role:** waiter for the fine-dining pilot (Swiss 4-top / 6-top service).

This is the physical-device smoke test for Sprint 2. The items below cover
the golden paths that are most at risk of breaking on a real device versus the
desktop dev emulator: thermal printer, Bluetooth/TCP peripherals, offline
connectivity, and touch interaction on a 7–10" screen.

Run the full pass **once per release candidate**. Record pass/fail beside each
item with a short note. Anything red blocks the pilot deploy.

---

## Prerequisites

- **Target device: Android tablet** — 7–10" screen, **Android 10+** (API 29+),
  USB debugging enabled in Developer Options, "Install unknown apps" allowed
  for the Files app if sideloading. iOS is **out of scope** for the pilot
  (confirmed 2026-04-18).
- **Recommended test devices** (mainstream, no dedicated POS hardware
  required): Samsung Galaxy Tab A8, Lenovo Tab M10, Huawei MatePad, or any
  comparable mid-range Android tablet in the same size class.
- Working Wi-Fi network the device can join, plus a way to disable
  connectivity at will (airplane mode) for the offline tests.
- Seeded pilot tenant on the backend, with at least one waiter user and a
  small product catalog mapped to 2–3 kitchen gangs.

---

## 0. Install & cold start

| # | Step | Expected | Result |
|---|------|----------|--------|
| 0.1 | Install the build: **ADB** — `adb install -r app-pos-release.apk`, or **sideload** — copy the APK to the tablet, open it from Files, tap to install (accept the "Install unknown apps" prompt for Files if prompted) | App installs without signature conflict | ☐ |
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

## 6. Thermal printer (if available)

Mainstream Android tablets use either **Bluetooth** (pair the ESC/POS printer
in Android Settings first) or **TCP/IP** (static LAN IP for a counter-mount
printer). USB-OTG is not assumed on generic tablets.

| # | Step | Expected | Result |
|---|------|----------|--------|
| 6.1 | Connect the ESC/POS printer: **Bluetooth** — pair in Android Settings → Bluetooth, then select in app Settings → Printer; **TCP/IP** — enter the printer's LAN IP and port in Settings → Printer | Android grants the connection; the printer shows as "connected" in Settings → Printer | ☐ |
| 6.2 | From Settings → Printer, run "Test print" | Page prints with the logo + "GastroCore test" header | ☐ |
| 6.3 | Fire Gang 1 with a printer-bound kitchen station | Kitchen ticket prints with items + gang number + seat numbers | ☐ |
| 6.4 | Finalize the ticket in cash | Receipt prints with tax breakdown, MWST lines, tenant logo | ☐ |

If no printer is available at the pilot site, mark 6.x as **N/A** and log a
follow-up to retest once hardware arrives.

## 7. Camera / QR

Android camera2 API path — all three recommended test tablets (Tab A8, Tab
M10, MatePad) have rear cameras, so this section should be exercised.

| # | Step | Expected | Result |
|---|------|----------|--------|
| 7.1 | First launch of a camera screen — Android prompts for CAMERA permission | Permission dialog appears; granting it reveals the preview | ☐ |
| 7.2 | From the tables screen, scan a table QR code | Opens that table's ticket directly | ☐ |
| 7.3 | From Settings → Activation, scan a license QR | Tier lifts from Free to the scanned tier | ☐ |

## 8. Endurance (2 h)

Combines battery drain, screen-timeout behavior, and offline-queue resilience
— the three things that break between "demo on desk" and "real floor shift".

| # | Step | Expected | Result |
|---|------|----------|--------|
| 8.1 | Start with battery at 100 %, brightness 50 %, screen timeout set to 5 min in Android Settings → Display | Baseline captured | ☐ |
| 8.2 | Leave the app on the tables screen for 2 h. Let the screen time out; wake it with the power button every ~15 min; add one item to a live ticket each wake | App resumes instantly, no re-login required, added items persist across sleeps | ☐ |
| 8.3 | Around minute 60, turn airplane mode on for 15 min, add 3 items, fire a gang | Offline banner appears; outbox pill grows to 4 pending | ☐ |
| 8.4 | Turn airplane mode off | Banner clears; pending count drains to 0 within ~10 s | ☐ |
| 8.5 | At minute 120, check battery and temperature | Battery drain ≤ 30 % from start; chassis warm, not hot | ☐ |
| 8.6 | Re-run steps 1.1 → 1.5 | No visible lag, no dropped gestures | ☐ |

---

## Reporting template

Paste into the pilot-rollout issue:

```
Device: <make/model> · Android <version> · APK <git-sha>
Tested by: <name> · <date>
Environment: <pilot tenant name>

Section 0: PASS
Section 1: PASS
Section 2: PASS (KDS sync measured ~600 ms)
Section 3: PASS
Section 4: PASS
Section 5: PASS
Section 6: N/A (no printer on site yet)
Section 7: PASS
Section 8: PASS (22 % drain / 2 h, reconnect drain 8 s)

Blockers: <none | list>
Follow-ups: <tickets filed>
```
