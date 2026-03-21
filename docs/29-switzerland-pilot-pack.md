# 29 - Switzerland Pilot Pack

> **Document Status:** Authoritative | **Last Updated:** 2026-03-20
>
> Everything needed for GastroCore to operate legally and correctly in Switzerland.

---

## 1. Switzerland Is the First Market

Swiss pilot is the priority. Germany fiscal pack (doc 30) begins only after Swiss pilot is validated.

**Why Switzerland first:**
- Home market for the team
- No mandatory fiscal signing hardware (unlike Germany's TSE)
- VAT complexity exists but is manageable without external certification
- Swiss restaurant owners in German-speaking regions are the target beachhead

---

## 2. Swiss Tax System (MWST / TVA / IVA)

Switzerland uses a multi-rate VAT system called MWST (Mehrwertsteuer).

### 2.1 Current Rates (effective January 2024)

| Rate | Name | Applies To |
|------|------|-----------|
| 8.1% | Standard rate | Alcohol, most beverages, restaurant dine-in service |
| 2.6% | Reduced rate | Food (non-alcoholic), non-alcoholic beverages for takeaway |
| 3.8% | Special rate | Accommodation services (hotel, B&B) |

**Critical restaurant rule:** The same product (e.g., a coffee or a sandwich) is taxed at **different rates** depending on whether it is consumed on-premises (dine-in) or taken away.

| Scenario | Rate |
|----------|------|
| Coffee consumed at the table | 8.1% |
| Coffee to go (takeaway) | 2.6% |
| Alcohol (beer, wine) — always | 8.1% |
| Food items (excluding alcohol) — dine-in | 8.1% |
| Food items (excluding alcohol) — takeaway | 2.6% |
| Accommodation | 3.8% |

**Existing code:** Tax profiles are in the DB seed. `SwissReceiptBuilder` handles multi-rate breakdowns. The `FareEngine` exists for rate resolution. **Missing:** the dine-in/takeaway toggle wired into the POS order flow.

### 2.2 Future Rate Change Support

Swiss VAT rates change via federal referendum. The last change was January 2024 (7.7% → 8.1%). The system must support:
- Tax profiles with `effective_from` date
- Admin can configure upcoming rate change in advance
- On the effective date, new orders use new rates automatically
- Historical orders remain at the rate active at time of sale (immutable)

**DB support:** `tax_profiles` table has `effective_from` column. Verify `FareEngine` uses it.

---

## 3. Dine-In vs Takeaway Toggle

This is the most important Swiss-specific feature to implement before pilot.

### 3.1 Toggle Location

- **Order level:** Single toggle for the entire order — applies to all items
- Default: dine-in (most orders in a sit-down restaurant are dine-in)
- Toggle visible in POS order screen, top bar area (not buried in settings)

### 3.2 Tax Resolution Logic

```dart
// In FareEngine:
TaxProfile resolveTaxProfile(Product product, OrderType orderType) {
  final isDineIn = orderType == OrderType.dineIn;
  final profile = product.taxProfileId;

  // If product is in alcohol category: always 8.1%
  if (product.category.isAlcohol) return taxProfile(rate: 0.081);

  // Food/non-alcoholic beverages:
  if (isDineIn) return taxProfile(rate: 0.081);  // service tax
  else return taxProfile(rate: 0.026);            // reduced rate

  // Accommodation items: always 3.8%
  if (product.category.isAccommodation) return taxProfile(rate: 0.038);
}
```

The toggle must be accessible to the cashier/waiter without going into settings. A single prominent toggle or a per-order order-type selection covers this.

### 3.3 Mixed Order Handling

A single order can have items at different rates (alcohol at 8.1%, food at 2.6% in takeaway mode). The receipt and the till report must break down VAT by rate:

```
Subtotal (8.1% MWST):  CHF 8.40
MWST 8.1%:             CHF 0.68
Subtotal (2.6% MWST):  CHF 12.50
MWST 2.6%:             CHF 0.32
─────────────────────────────────
Total:                 CHF 21.22
```

`SwissReceiptBuilder` already produces this breakdown — the tax resolution just needs to be wired correctly from the toggle.

---

## 4. 5-Rappen Rounding

Switzerland abolished the 1-Rappen and 2-Rappen coins. Cash payments must be rounded to the nearest CHF 0.05.

### 4.1 Rounding Rules

| Payment | Rounding |
|---------|---------|
| Cash | Round total to nearest CHF 0.05 |
| Card (Visa, MC, Maestro) | Exact amount — no rounding |
| TWINT | Exact amount — no rounding |
| Voucher | Exact amount |

### 4.2 Rounding Implementation

```dart
// In Money class or PaymentScreen:
int roundToFiveRappen(int cents) {
  // Round to nearest 5 cents
  final remainder = cents % 5;
  if (remainder < 3) return cents - remainder;
  return cents + (5 - remainder);
}
```

Rounding difference is tracked:
- `payments` table: a rounding line item (`type = 'rounding'`) records the delta
- Receipt shows: "Rounding: -CHF 0.02" or "+CHF 0.03" explicitly
- Shift report: rounding differences summed separately (not mixed with revenue)

**Unit tests** for rounding are in `SwissReceiptBuilder` tests. Verify they cover the payment screen path too.

---

## 5. Swiss Receipt Requirements

A valid Swiss receipt must contain:

| Field | Required | Notes |
|-------|---------|-------|
| Business name | ✅ | |
| Business address | ✅ | |
| UID (Unternehmens-ID) | ✅ | Format: CHE-XXX.XXX.XXX |
| MWST registration number | ✅ | Same as UID for most businesses |
| Date and time | ✅ | |
| Receipt/order number | ✅ | Sequential |
| Items with individual prices | ✅ | |
| MWST breakdown by rate | ✅ | Separate line per rate |
| Total amount | ✅ | |
| Payment method | ✅ | Cash / card / TWINT |
| 5-Rappen rounding line | If cash | Show explicitly |

**All of this is implemented in `SwissReceiptBuilder`**. The receipt just needs the restaurant's UID and MWST number from Settings.

---

## 6. Settings Required for Swiss Compliance

Add to `RestaurantSettings` / Settings screen:

| Setting | Field Name | Validation |
|---------|-----------|------------|
| Unternehmens-ID (UID) | `uid_number` | Format: CHE-XXX.XXX.XXX or CHExxx.xxx.xxx |
| MWST registration number | `mwst_number` | Same as UID usually |
| Business full address | `business_address` | Multiline |
| Currency | `currency` | Default: CHF (locked for Swiss) |
| Cash rounding | `cash_rounding_enabled` | Default: true for Switzerland |
| Tax mode | `default_order_type` | Dine-in or Takeaway as default |

These appear in the onboarding wizard (first-run setup).

---

## 7. Swiss QR-Bill (On-Demand Invoicing)

QR-bills are required for **formal B2B invoices** in Switzerland. They are NOT required for restaurant consumer receipts.

### 7.1 When Is a QR-Bill Needed?

- Corporate catering invoices
- Business customer requests a formal invoice (e.g., for expense reimbursement)
- Monthly tab for business accounts

### 7.2 QR-Bill Format

Swiss QR-bill (Zahlungsteil + Empfangsschein) based on ISO 20022:

```
Required fields:
- Account type: IBAN (CH XX XXXX XXXX XXXX XXXX X) or QR-IBAN
- Creditor: restaurant name + address
- Debtor: customer name + address (optional for restaurants)
- Amount: CHF XX.XX
- Currency: CHF
- Reference: QR-Referenz (27 digits) or Creditor Reference
- Additional information: invoice number, date
```

### 7.3 Implementation

Use the `epc_qr_code` or `swiss_qr_bill` Dart package (verify availability) OR generate the QR code payload manually following SIX Group specs.

**Scope for pilot:** On-demand only. Staff triggers "Print Invoice" from order screen, enters customer details, generates A4 invoice PDF with QR-bill section. Not automated.

**Defer:** Automated monthly billing, QR-bill for every transaction, customer email delivery.

---

## 8. Payment Terminal Integration for Switzerland

### 8.1 Already Implemented

| Terminal | Status | Notes |
|---------|--------|-------|
| Wallee LTI | Complete | TCP port 50000, XML framing — standard Swiss payment gateway |
| MyPOS WiFi | Complete | TCP port 60180, SlaveSDK — TWINT support |
| TWINT via MyPOS | Complete | CHF-only, mobile payment |

### 8.2 SIX / Worldline (Future)

SIX Group is the dominant Swiss payment terminal provider. Integration with SIX terminals is deferred post-pilot. Many Swiss restaurants already have their own SIX terminal under a separate acquiring contract — GastroCore can operate alongside it (cash/manual card tracking) without direct integration.

**For pilot:** Wallee + MyPOS covers the majority of pilot restaurant payment needs. SIX integration is Phase 3–4.

### 8.3 Cash Handling

5-Rappen rounding only on cash. All other payment methods process exact amounts. Cash movements tracked in `cash_movements` table. Opening float set at shift open.

---

## 9. Swiss Accounting Handoff (Minimum)

Switzerland does not mandate a specific accounting software for restaurants. The obligation is to keep proper records for 10 years.

For v1, the accounting handoff is:
1. Daily CSV export from GastroCore: shift summary, revenue by tax rate, payment method breakdown
2. Period export: all transactions in date range as CSV (for accountant/bookkeeper)
3. The custom backoffice (team's own infrastructure) consumes these exports

**No live bridge required.** Export is sufficient for the accountant to post the journal entries.

### 9.1 Minimum Export Fields

Daily summary CSV:
```
date, shift_id, gross_revenue, mwst_8_1_base, mwst_8_1_amount, mwst_2_6_base,
mwst_2_6_amount, mwst_3_8_base, mwst_3_8_amount, cash_payments, card_payments,
twint_payments, voids_total, rounding_total, net_revenue
```

Transaction CSV (for accountant):
```
receipt_number, date_time, table, waiter, order_type, items_subtotal, mwst_amount,
mwst_rate, total, payment_method, shift_id
```

---

## 10. Switzerland Pilot Pack — Implementation Checklist

### Phase 1 (Pilot Unblock)

- [ ] Dine-in / Takeaway toggle in POS order screen
- [ ] FareEngine reads toggle → resolves correct tax rate
- [ ] 5-Rappen rounding enforced at cash payment screen
- [ ] Rounding delta recorded as payment line item
- [ ] Receipt shows rounding line when applicable
- [ ] Restaurant UID and MWST number in Settings
- [ ] SwissReceiptBuilder prints UID and MWST number

### Phase 3 (Swiss Pilot Hardening)

- [ ] Tax rate effective dates: admin can set future rate
- [ ] MWST validation: warn if UID format is invalid
- [ ] Daily CSV export: shift summary in Swiss accounting format
- [ ] Period transaction CSV export
- [ ] QR-bill generation for on-demand invoices
- [ ] Cash drawer open on cash payment confirmation
- [ ] Reprint receipt by order number

### Deferred

- [ ] SIX payment terminal integration
- [ ] Automated QR-bill for every transaction
- [ ] MWST return preparation report (Abrechnungsformular)
- [ ] PostFinance payment integration

---

## 11. Success Criteria for Swiss Pilot

- [ ] Coffee dine-in: receipt shows 8.1% MWST
- [ ] Coffee takeaway: receipt shows 2.6% MWST
- [ ] Cash CHF 17.23 rounds to CHF 17.25; rounding shows on receipt
- [ ] Card CHF 17.23 processes exactly CHF 17.23
- [ ] Receipt includes restaurant UID and MWST number
- [ ] Restaurant owner can export daily CSV for their accountant
- [ ] System operates without internet for full service day
- [ ] Pilot restaurant owner validates: "I can hand this receipt to a Swiss customer without embarrassment"
