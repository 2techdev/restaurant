# Payment terminals — Wallee & myPOS

Operator and support guide for the two hardware gateways integrated with
GastroCore POS for the Swiss pilot (`backoffice.gastrocore.ch`). All amounts
in this document are in Swiss Francs (CHF); TWINT is always CHF.

---

## 1. Supported gateways

| Gateway | Connection    | Port  | Supports                       | Notes                        |
| ------- | ------------- | ----- | ------------------------------ | ---------------------------- |
| Wallee  | TCP / LTI 2.52| 50000 | Card (chip, contactless, swipe)| Primary card provider        |
| myPOS   | TCP / SlaveSDK| 60180 | Card + **TWINT**               | TWINT exclusive; card fallback |

TWINT is only available on myPOS. Card payments route to Wallee first and fall
back to myPOS automatically if Wallee is unreachable. See
`apps/pos/lib/features/payments/data/hardware/payment_engine.dart`.

---

## 2. One-time setup

### 2.1 Wallee terminal

1. Mount the terminal, power it up, connect it to the restaurant LAN (same
   subnet as the POS tablet).
2. On the terminal, enable **LTI 2.52** in the operator menu:
   `Menu → Setup → Interface → LTI → Enable`.
3. Note the terminal's LAN IP address (e.g. `192.168.1.100`) and the `posId`
   assigned to this POS in the Wallee back office.
4. Keep the default TCP port **50000** unless your network requires otherwise.

### 2.2 myPOS Sigma terminal

1. Mount the terminal and power it up.
2. Connect it to the restaurant WiFi (**WiFi only** — USB and Bluetooth are
   not supported by this integration).
3. Enable the SlaveSDK: `Menu → Settings → SlaveSDK → Enabled`.
4. Note the terminal's WiFi IP address (e.g. `192.168.1.101`). Keep the
   default TCP port **60180**.

### 2.3 POS configuration

Open the POS → **Settings → Payment terminal**. Choose the active gateway and
enter the IP / port / POS identifier from above. Values persist in
`SharedPreferences` and are picked up live by `walleeConfigProvider` and
`myposConfigProvider` (see
`apps/pos/lib/features/payments/providers/hardware_payment_providers.dart`).

If the active gateway is set to **None**, the Kredi / Banka buttons fall back
to a DB-only path so operators can still close tickets manually.

---

## 3. Cashier flow

1. Tap **Kredi** or **Banka** on the payment screen.
2. Tap **Ödemeyi Tamamla** — a fullscreen overlay appears:
   - *"Connecting to terminal…"* (< 1 s)
   - *"Tap or insert card on the terminal below…"* (customer action)
3. The customer taps / inserts / swipes. The terminal displays approval.
4. On **approved**, the ticket is closed automatically and the receipt
   screen opens after ~2 s.
5. On **declined**, **cancelled**, **failed**, or **30 s timeout**, an
   error banner appears at the bottom and the cashier may retry.

**Cancel during payment.** The overlay shows a *Cancel Payment* button that
invokes `PaymentEngine.cancelPayment()` — it reaches the terminal and aborts
the in-flight transaction.

---

## 4. What gets persisted

Every approved terminal payment writes to the `payments` table (schema v9+)
with:

| Column                 | Source (HardwarePaymentResult)   | Example        |
| ---------------------- | -------------------------------- | -------------- |
| `terminal_transaction_id` | `transactionId` (RRN / LTI ref) | `000000123456` |
| `auth_code`            | `authCode` (ep2AuthCode)         | `A12B34`       |
| `masked_pan`           | `cardNumber`                     | `411111******1111` |
| `card_type`            | `cardType`                       | `Mastercard`   |
| `entry_method`         | `entryMethod`                    | `CHIP`         |
| `terminal_id`          | `terminalId` (ep2TrmId)          | `TRM0001`      |
| `terminal_provider`    | Engine-assigned                  | `Wallee` or `MyPOS` |

These feed the Swiss Z-report and end-of-day reconciliation.

---

## 5. Test cards & TWINT

### 5.1 Wallee test cards (LTI sandbox)

| Scheme      | Number              | CVV | Expected  |
| ----------- | ------------------- | --- | --------- |
| Visa        | 4111 1111 1111 1111 | 123 | Approved  |
| Mastercard  | 5555 5555 5555 4444 | 123 | Approved  |
| Visa        | 4000 0000 0000 0002 | 123 | Declined  |

Use the PIN `0000` when prompted.

### 5.2 myPOS test cards

Check the myPOS merchant portal for the card numbers attached to your test
account — they rotate periodically. The TWINT sandbox uses a test app
(TWINT Sandbox) that customers can install on a second phone.

### 5.3 TWINT flow

1. Cashier taps **Kredi** (TWINT is routed via myPOS internally when the
   customer selects the QR option on the terminal). For kiosk-initiated
   TWINT, use the dedicated TWINT button in
   `features/kiosk/presentation/screens/kiosk_payment_screen.dart`.
2. Terminal displays a QR code.
3. Customer scans with the TWINT app and confirms.
4. Terminal returns approved — same persistence path as cards.

TWINT is CHF-only; the engine rejects non-CHF TWINT requests at the
`MyPosPaymentProvider` layer.

---

## 6. Troubleshooting

| Symptom                                              | Likely cause                                          | Fix                                                                                                   |
| ---------------------------------------------------- | ----------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| "Terminal unavailable. Please try again."            | Terminal off, wrong IP, different subnet              | Check IP in Settings → Payment terminal; ping the IP from the POS device                              |
| "Terminal did not respond within 30 seconds."        | Network congestion, terminal hung mid-transaction     | Power-cycle the terminal; re-check LAN/WiFi                                                           |
| Payment approved but POS stuck on "Closing ticket…"  | DB write failed after terminal approval               | Do **not** retry — the customer's card has been charged. Call support to reconcile via `terminal_transaction_id` |
| TWINT option missing on kiosk                        | Active gateway is Wallee, or myPOS currency ≠ CHF     | Switch active gateway to MyPOS or add MyPOS as fallback                                               |
| Duplicate payment rows                               | Cashier tapped "Ödemeyi Tamamla" twice during overlay | Overlay blocks duplicate taps; if row exists, remove via `DELETE FROM payments WHERE id=?` and audit |

---

## 7. Files involved

- `apps/pos/lib/features/payments/data/hardware/payment_engine.dart` — routing + fallback
- `apps/pos/lib/features/payments/data/hardware/wallee/` — Wallee LTI client
- `apps/pos/lib/features/payments/data/hardware/mypos/` — myPOS SlaveSDK bridge
- `apps/pos/lib/features/payments/providers/hardware_payment_providers.dart` — Riverpod wiring from settings
- `apps/pos/lib/features/payments/presentation/screens/payment_screen.dart` — cashier flow (`_processTerminalPayment`)
- `apps/pos/lib/features/kiosk/presentation/screens/kiosk_payment_screen.dart` — self-serve flow
- `apps/pos/lib/core/database/tables/payments.dart` — terminal-response schema (v9)

---

## 8. Reference

- Wallee LTI Reference Manual 2.52 (Wallee developer portal)
- myPOS SlaveSDK Integration Guide 2.1.8 (myPOS developer portal)
- EP2 field dictionary (authCode, trxRefNum, ep2TrmId) — shared by both gateways
