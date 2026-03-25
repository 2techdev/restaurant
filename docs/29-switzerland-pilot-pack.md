# 29 — Switzerland Pilot Pack

> **Document Status:** Authoritative | **Last Updated:** 2026-03-24
>
> Everything needed for GastroCore to operate legally and correctly in Switzerland.
> Updated: myPOS confirmed as primary terminal; cloud sync is the multi-device path.

---

## 1. Switzerland Is the First Market

Swiss pilot is the priority. Germany fiscal pack (doc 30) begins only after Swiss pilot is validated.

**Why Switzerland first:**
- Home market for the team — direct access to pilot restaurants
- No mandatory fiscal signing hardware (unlike Germany's TSE requirement)
- VAT complexity is manageable without external certification
- German-speaking Swiss restaurants are the target beachhead
- myPOS supports TWINT natively — Switzerland's dominant mobile payment method

---

## 2. Swiss Tax System (MWST / TVA / IVA)

Switzerland uses a multi-rate VAT system called MWST (Mehrwertsteuer).

### 2.1 Current Rates (effective January 2024)

| Rate | Name | Applies To |
|------|------|-----------|
| 8.1% | Standard rate | Alcohol, most beverages, restaurant dine-in service |
| 2.6% | Reduced rate | Food (non-alcoholic), non-alcoholic beverages for takeaway |
| 3.8% | Special rate | Accommodation services (hotel, B&B) |

**Critical restaurant rule:** The same product is taxed at **different rates** depending on dine-in vs takeaway consumption.

| Scenario | Rate |
|----------|------|
| Coffee consumed at table | 8.1% |
| Coffee to go (takeaway) | 2.6% |
| Alcohol (beer, wine) — always | 8.1% |
| Food — dine-in | 8.1% |
| Food — takeaway | 2.6% |
| Accommodation | 3.8% |

**Existing code:** Swiss MWST rates are in DB seed. `SwissReceiptBuilder` produces multi-rate breakdowns. `FareEngine` handles rate resolution.

**Missing (GAP-04):** The dine-in/takeaway toggle is not surfaced in the POS order flow.

### 2.2 Future Rate Change Support

Swiss VAT rates change via federal referendum (last change: January 2024, 7.7% → 8.1%).

**Support required:**
- Tax profiles with `effective_from` date (column exists in `tax_profiles` table)
- Admin sets future rate change in advance with activation date
- On effective date: new orders use new rates automatically
- Historical orders: remain at rate active at time of sale (immutable)

---

## 3. Dine-In vs Takeaway Toggle

This is the most important Swiss-specific feature to implement before pilot.

### 3.1 Toggle Location

- **Order level:** Single toggle for the entire order
- Default: dine-in (most orders in a sit-down restaurant)
- Visible in POS order screen, top bar area — not buried in settings

### 3.2 Tax Resolution Logic

```dart
// In FareEngine:
TaxProfile resolveTaxProfile(Product product, OrderType orderType) {
  // Alcohol: always standard rate regardless of order type
  if (product.category.isAlcohol) return taxProfile(rate: 0.081);

  // Accommodation: always accommodation rate
  if (product.category.isAccommodation) return taxProfile(rate: 0.038);

  // Food and non-alcoholic beverages: rate depends on order type
  if (orderType == OrderType.dineIn) return taxProfile(rate: 0.081);
  return taxProfile(rate: 0.026); // takeaway
}
```

### 3.3 Mixed Order Handling

A single order can have items at different rates. Receipt and till report must break down VAT by rate:

```
Subtotal (8.1% MWST):   CHF  8.40
MWST 8.1%:              CHF  0.68
Subtotal (2.6% MWST):   CHF 12.50
MWST 2.6%:              CHF  0.32
────────────────────────────────
Total:                  CHF 21.22
```

`SwissReceiptBuilder` already produces this breakdown. The toggle just needs to be wired.

---

## 4. 5-Rappen Rounding

Switzerland abolished the 1-Rappen and 2-Rappen coins. Cash payments must round to nearest CHF 0.05.

### 4.1 Rounding Rules

| Payment Method | Rounding |
|----------------|---------|
| Cash | Round to nearest CHF 0.05 |
| Card (Visa, MC, Maestro, PostFinance) | Exact amount |
| TWINT | Exact amount |
| Voucher | Exact amount |

### 4.2 Rounding Implementation

```dart
// In Money class:
int roundToFiveRappen(int cents) {
  final remainder = cents % 5;
  if (remainder < 3) return cents - remainder;
  return cents + (5 - remainder);
}
```

**Tracking:**
- `payments` table: rounding line item (`type = 'rounding'`) records the delta
- Receipt shows: "Rundung: -CHF 0.02" or "+CHF 0.03" explicitly
- Shift report: rounding differences summed separately (not mixed with revenue)

---

## 5. Swiss Receipt Requirements

A valid Swiss receipt must contain:

| Field | Required | Status in Code |
|-------|---------|----------------|
| Business name | ✅ | In settings → receipt |
| Business address | ✅ | In settings → receipt |
| UID (CHE-XXX.XXX.XXX) | ✅ | Settings field exists; save path incomplete |
| MWST registration number | ✅ | Same as UID for most businesses |
| Date and time | ✅ | SwissReceiptBuilder |
| Receipt/order number (sequential) | ✅ | |
| Items with individual prices | ✅ | |
| MWST breakdown by rate | ✅ | SwissReceiptBuilder: multi-rate |
| Total amount | ✅ | |
| Payment method | ✅ | Cash / card / TWINT |
| 5-Rappen rounding line (cash only) | ✅ | When applicable |

**All fields are implemented in `SwissReceiptBuilder`** — the receipt just needs the UID and MWST number to persist from settings (GAP-06 fix).

---

## 6. Settings Required for Swiss Compliance

| Setting | Field | Validation |
|---------|-------|------------|
| Unternehmens-ID (UID) | `uid_number` | Format: CHE-XXX.XXX.XXX |
| MWST registration number | `mwst_number` | Usually same as UID |
| Business full address | `business_address` | Multiline |
| Currency | `currency` | Default: CHF (locked for Swiss) |
| Cash rounding | `cash_rounding_enabled` | Default: true |
| Default order type | `default_order_type` | Dine-in or Takeaway |

These appear in the onboarding wizard (first-run setup).

---

## 7. Payment Terminal Integration for Switzerland

### 7.1 Implemented and Ready

| Terminal | Status | Notes |
|---------|--------|-------|
| **myPOS WiFi** | ✅ Complete | TCP port 60180, SlaveSDK AAR bundled, TWINT support — **primary terminal** |
| **Wallee LTI** | ✅ Complete | TCP port 50000, XML framing — secondary option |
| TWINT (via myPOS) | ✅ Complete | CHF-only, Switzerland's dominant mobile payment |

Both bridges need **field validation on real hardware** before pilot. The implementations are code-complete; integration testing on actual terminals is required.

### 7.2 SIX / Worldline (Future)

SIX Group is the dominant Swiss payment terminal provider. Integration deferred post-pilot. Many Swiss restaurants already have their own SIX terminal — GastroCore can operate alongside it (cash/manual card tracking) without direct integration.

### 7.3 Cash Handling

5-Rappen rounding applies only to cash. All other methods process exact amounts. Cash movements tracked in `cash_movements` table with opening float at shift open.

---

## 8. Swiss Accounting Handoff

Switzerland does not mandate specific accounting software for restaurants. The obligation is to keep proper records for 10 years.

**v1 accounting handoff:**
1. Daily CSV export from GastroCore: shift summary, revenue by tax rate, payment method breakdown
2. Period export: all transactions in date range as CSV (for accountant)
3. Custom backoffice (team's own infrastructure) consumes these exports via pull API

**No live bridge required.** Export is sufficient for an accountant to post journal entries.

### 8.1 Minimum Daily CSV Fields

```
date, shift_id, gross_revenue, mwst_8_1_base, mwst_8_1_amount, mwst_2_6_base,
mwst_2_6_amount, mwst_3_8_base, mwst_3_8_amount, cash_payments, card_payments,
twint_payments, voids_total, rounding_total, net_revenue
```

### 8.2 Transaction CSV Fields (for accountant)

```
receipt_number, date_time, table, waiter, order_type, items_subtotal, mwst_amount,
mwst_rate, total, payment_method, shift_id
```

---

## 9. Swiss QR-Bill (On-Demand Invoicing)

QR-bills are required for **formal B2B invoices** in Switzerland. NOT required for restaurant consumer receipts.

**When needed:**
- Corporate catering invoices
- Business customer expense reimbursement
- Monthly tab for business accounts

**Format:** Swiss QR-bill (Zahlungsteil + Empfangsschein), ISO 20022:
- IBAN (CH format) — restaurant's bank account
- Creditor: restaurant name + address
- Amount: CHF
- Reference: QR-Referenz or Creditor Reference
- Additional info: invoice number, date

**Implementation scope for pilot:** On-demand only. Staff triggers "Print Invoice" from order screen, enters customer details, generates A4 invoice with QR-bill section.

**Deferred:** Automated QR-bill for every transaction, customer email delivery, monthly automated invoicing.

---

## 10. Switzerland Pilot Pack — Implementation Checklist

### Phase 1 (Pilot Unblock) — Required Before First Pilot

- [ ] Dine-in / Takeaway toggle in POS order screen
- [ ] FareEngine reads toggle → resolves correct tax rate
- [ ] 5-Rappen rounding enforced at cash payment screen
- [ ] Rounding delta recorded as payment line item
- [ ] Receipt shows rounding line when cash payment
- [ ] Restaurant UID and MWST number fields in Settings (save working)
- [ ] `SwissReceiptBuilder` uses UID and MWST number from settings

### Phase 3 (Swiss Pilot Hardening)

- [ ] Tax rate effective dates: admin sets future rate with activation date
- [ ] UID format validation: warn if CHE-XXX.XXX.XXX format invalid
- [ ] Daily CSV export to device Downloads (shift summary format)
- [ ] Period transaction CSV export
- [ ] QR-bill generation for on-demand B2B invoices
- [ ] Cash drawer opens on cash payment confirmation
- [ ] Reprint receipt by order number

### Deferred

- [ ] SIX/Worldline payment terminal integration
- [ ] Automated QR-bill for every transaction
- [ ] MWST return preparation report (Abrechnungsformular)
- [ ] PostFinance integration
- [ ] Payrexx subscription billing

---

## 11. Success Criteria for Swiss Pilot

- [ ] Coffee dine-in: receipt shows 8.1% MWST
- [ ] Coffee takeaway: receipt shows 2.6% MWST
- [ ] Alcohol (beer/wine): always 8.1% regardless of order type
- [ ] Cash CHF 17.23 rounds to CHF 17.25; rounding shown on receipt
- [ ] Card CHF 17.23 processes exactly CHF 17.23
- [ ] Receipt includes restaurant UID and MWST number
- [ ] Restaurant owner can export daily CSV for accountant
- [ ] Full service day runs without internet connectivity
- [ ] myPOS TWINT transaction completes end-to-end
- [ ] Pilot restaurant owner validates: "I can give this receipt to a Swiss customer without embarrassment"
