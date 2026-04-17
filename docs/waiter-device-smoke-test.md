# Waiter Device Smoke-Test Checklist — Waiter App (Sprint 2)

**Target form factor:** 7–10" tablet in portrait, used by a single waiter on
the floor.
**Build:** `flutter build apk --release` (Android) or `flutter build ios
--release` (iOS) — use the default flavor unless a hardware-specific one has
been configured by the time this runs.
**Tester role:** waiter for the fine-dining pilot (Swiss 4-top / 6-top service).

This is the physical-device smoke test for Sprint 2. The items below cover
the golden paths that are most at risk of breaking on a real device versus the
desktop dev emulator: thermal printer, external peripherals, offline
connectivity, and touch interaction on a 7–10" screen.

Run the full pass **once per release candidate**. Record pass/fail beside each
item with a short note. Anything red blocks the pilot deploy.

---

## Prerequisites

- **Device choice is still open.** The pilot has not yet committed to a
  specific tablet (Android generic tablet / iPad / a dedicated POS tablet are
  all on the table). This checklist is deliberately hardware-agnostic — any
  step that depends on a specific peripheral is marked `(if available)` and
  can be filled in as **N/A** with a follow-up ticket once hardware arrives.
- A working Wi-Fi network the device can join, plus a way to disable
  connectivity at will (airplane mode / router toggle) for the offline tests.
- The seeded pilot tenant on the backend, with at least one waiter user and
  a small product catalog mapped to 2–3 kitchen gangs.

---

## 0. Install & cold start

| # | Step | Expected | Result |
|---|------|----------|--------|
| 0.1 | Install the build on the device: **Android** — enable ADB, `adb install -r build/app/outputs/flutter-apk/app-release.apk`; **iOS** — distribute the IPA via TestFlight and accept the invite | App installs without signature conflict | ☐ |
| 0.2 | Open the app from the launcher / home screen | Cold-start under 4 s, no white flash | ☐ |
| 0.3 | Log in as the seeded waiter user | Lands on waiter home (tables grid) | ☐ |
| 0.4 | Rotate the device | Portrait only — orientation locked | ☐ |

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

Connection path depends on the chosen printer — Bluetooth (most generic
tablets), TCP/LAN (counter-mount printers), or USB-OTG (only on Android
tablets with the right port/cable).

| # | Step | Expected | Result |
|---|------|----------|--------|
| 6.1 | Pair / connect the ESC/POS thermal printer (Bluetooth, TCP, or USB-OTG) | OS grants the connection; device appears in Settings → Printer | ☐ |
| 6.2 | From Settings → Printer, run "Test print" | Page prints with the logo + "GastroCore test" header | ☐ |
| 6.3 | Fire Gang 1 with a printer-bound kitchen station | Kitchen ticket prints with items + gang number + seat numbers | ☐ |
| 6.4 | Finalize the ticket in cash | Receipt prints with tax breakdown, MWST lines, tenant logo | ☐ |

If no printer is available at the pilot site (or the chosen tablet doesn't
support the intended connection path), mark 6.x as **N/A** and log a
follow-up to retest once hardware arrives.

## 7. Camera / QR (if present)

| # | Step | Expected | Result |
|---|------|----------|--------|
| 7.1 | From the tables screen, scan a table QR code | Opens that table's ticket directly | ☐ |
| 7.2 | From Settings → Activation, scan a license QR | Tier lifts from Free to the scanned tier | ☐ |

If the chosen device has no rear camera (some dedicated POS tablets), mark
these **N/A** and note the model on the row.

## 8. Battery & thermals (endurance)

| # | Step | Expected | Result |
|---|------|----------|--------|
| 8.1 | Leave the app open on the tables screen for 2 h at 50% brightness | Battery drain ≤ 20 %, chassis warm not hot | ☐ |
| 8.2 | After 2 h, run steps 1.1 → 1.5 again | No visible lag, no dropped gestures | ☐ |

---

## Reporting template

Paste into the pilot-rollout issue:

```
Device: <make/model> · <OS version> · build <git-sha>
Tested by: <name> · <date>
Environment: <pilot tenant name>

Section 0: PASS
Section 1: PASS
Section 2: PASS (KDS sync measured ~600 ms)
Section 3: PASS
Section 4: PASS
Section 5: PASS
Section 6: N/A (no printer on site yet)
Section 7: N/A (no rear camera on this model)
Section 8: PASS (17 % drain / 2 h)

Blockers: <none | list>
Follow-ups: <tickets filed>
```
