# 30 — Germany Fiscal Pack v1

> **Document Status:** Authoritative | **Last Updated:** 2026-03-24
>
> **DEPENDENCY:** Cloud sync (Phase 2) must be stable in production before starting this phase.
> Germany fiscal requires internet for Fiskaly TSE API calls.
> **Do not start this phase before the Swiss pilot has 30+ days of stable operation and 5+ paying customers.**

---

## 1. German Fiscal Law Overview

### 1.1 KassenSichV (Kassensicherungsverordnung)

Since 1 January 2020, all electronic cash registers in Germany must:
- Be equipped with a **certified Technical Security Device (TSE)**
- Sign every transaction cryptographically
- Issue receipts with TSE signature data
- Be capable of generating **DSFinV-K** compliant exports

**Non-compliance:** Fine up to EUR 25,000 per violation. Cannot legally operate a cash register in Germany without TSE.

### 1.2 DSFinV-K (Digitale Schnittstelle der Finanzverwaltung für Kassensysteme)

Standardized XML/CSV export required by German tax authorities on demand (e.g., during a tax audit).

### 1.3 GoBD (Grundsätze zur ordnungsmäßigen Führung und Aufbewahrung von Büchern)

Requirements for proper bookkeeping:
- Immutable transaction log ✅ (already implemented via ADR-010)
- Sequential numbering without gaps (must be verified)
- 10-year retention of tax-relevant records

---

## 2. Our Approach: Cloud TSE via Fiskaly

**Decision (ADR-008, confirmed):** Use Fiskaly SIGN DE v2 (cloud TSE) rather than hardware TSE dongles.

**Why Fiskaly:**
- BSI-certified (Bundesamt für Sicherheit in der Informationstechnik)
- No hardware to manage or fail
- REST API — integrates cleanly into Go cloud backend
- Handles TSE lifecycle management

**Fiskaly products used:**
- `SIGN DE v2`: Cloud TSE for signing transactions
- `SUBMIT DE`: DSFinV-K export generation (managed service)

---

## 3. Transaction Model

### 3.1 Terminology Mapping

| GastroCore Term | German Term | Fiskaly Term |
|----------------|-------------|-------------|
| Order / Ticket | Bestellung | — |
| Fiscal transaction | Kassiervorgang | `transaction` |
| Receipt | Beleg/Kassenbon | `receipt` |
| TSE signature | TSE-Signatur | `signature` |
| Order line | Belegposition | `lineItem` |

### 3.2 Transaction Lifecycle

Every payment (bill close) in Germany requires a Fiskaly transaction:

```
1. Payment initiated on POS
          ↓
2. Start TSE transaction:
   POST /api/v1/tse/{tse_id}/tx
   { "type": "KASSENUMSATZ", "client_id": "device-id", "state": "ACTIVE" }
          ↓
3. POS collects payment (cash/card/etc.)
          ↓
4. Finish TSE transaction:
   PUT /api/v1/tse/{tse_id}/tx/{tx_id}
   { "state": "FINISHED",
     "schema": { "standard_v1": { "receipt": { ... line_items ... }}}}
          ↓
5. Receive TSE response:
   { "signature": "...", "counter": 42, "serial_number": "...",
     "certificate_serial_number": "...", "time_start": "...", "time_end": "..." }
          ↓
6. Store TSE response in receipt record
          ↓
7. Print receipt with TSE fields and QR code
```

### 3.3 Offline Queue for Fiscal Signing

When POS is offline (no internet), Fiskaly cannot be reached:

1. POS takes order and payment offline — writes to local SQLite as normal
2. Receipt marked: `fiscal_status = 'pending_signature'`
3. Receipt printed with "OFFLINE - Signatur ausstehend" notice
4. When internet returns: background process batch-signs pending receipts via Fiskaly
5. Signed receipts: `fiscal_status = 'signed'`; customer can request updated receipt

**Alert thresholds:**
- > 100 unsigned receipts: alert owner
- > 500 unsigned receipts: legal risk — recommend 4G router backup
- Recommend: 4G/LTE router as internet backup for all German restaurants

---

## 4. German Receipt Format

A compliant German receipt must include:

```
[RESTAURANT NAME]
[ADDRESS]
[STEUERNUMMER or USt-IdNr.]
────────────────────────────────
[DATE] [TIME]
[RECEIPT NUMBER]

POSITIONEN:
[QTY] [ITEM NAME]     [PRICE]
...

────────────────────────────────
GESAMT:                [TOTAL]
davon MwSt. 19%:       [TAX]
davon MwSt. 7%:        [TAX]

ZAHLUNGSART: [CASH/CARD]
BETRAG:                [AMOUNT]

────────────────────────────────
TSE-Informationen:
TSE-Signatur: [BASE64 TRUNCATED]
TSE-Start: [ISO8601]
TSE-Ende:  [ISO8601]
Seriennr.: [SERIAL]
Sig.zähler: [COUNTER]
Transaktion.: [TX_ID]

[QR CODE — Kassenbeleg-V1 format]
────────────────────────────────
```

---

## 5. German VAT Rates

| Rate | Applies To |
|------|-----------|
| 19% | Standard (alcohol, most beverages, dine-in service) |
| 7% | Reduced (food for takeaway, non-alcoholic beverages takeaway) |

Same dine-in vs takeaway distinction as Switzerland but with different rates. The `order_type_rules` table and `FareEngine` handle the German country pack via `country_pack = 'germany'` setting.

---

## 6. Fiskaly Transaction Payload

```json
{
  "schema": {
    "standard_v1": {
      "receipt": {
        "receipt_type": "RECEIPT",
        "amounts_per_vat_id": [
          {
            "vat_definition_export_id": 1,
            "incl_vat": 1190,
            "excl_vat": 1000,
            "vat": 190
          }
        ],
        "amounts_per_payment_type": [
          {
            "payment_type": "CASH",
            "amount": 1190,
            "currency_code": "EUR"
          }
        ],
        "line_items": [
          {
            "business_case": { "type": "SALE" },
            "name": "Schnitzel",
            "amount_per_unit": 1190,
            "quantity": 1,
            "tax_rate_applicable": 0.19
          }
        ]
      }
    }
  }
}
```

Amounts in **EUR cents**. GastroCore's integer-cents money model maps directly.

---

## 7. Split Bill and Table Merge

**Split bill:** Each split portion generates its own Fiskaly transaction. Each portion gets its own receipt with unique TSE signature. Original ticket marked as split; each sub-bill references original.

**Table merge:** Merged order = one ticket = one Fiskaly transaction. All items from both tables in transaction line items. Audit trail shows merge event before final transaction.

---

## 8. Failure Handling

| Failure Scenario | Response |
|-----------------|---------|
| Fiskaly API timeout (> 5s) | Add to offline queue; print with "Signatur ausstehend" |
| Fiskaly 4xx error | Log; alert on dashboard; attempt re-sign |
| Fiskaly 5xx error | Retry exponential backoff; max 10 retries; then offline queue |
| TSE quota exhausted | Alert immediately; contact Fiskaly |
| Internet down | Offline queue (section 3.3) |

**Critical rule:** GastroCore NEVER blocks a completed payment waiting for Fiskaly. Payment always succeeds first. Fiscal signing is async post-payment.

---

## 9. DSFinV-K Export

| File | Contents |
|------|---------|
| `transactions.csv` | All transactions with amounts, timestamps, TSE data |
| `transactions_tse.csv` | TSE signature data per transaction |
| `cash_point_closing.csv` | Daily Z-report data |
| `data_payment.csv` | Payment method details |
| `items.csv` | Line items per transaction |
| `vat.csv` | VAT definitions |
| `cash_register.csv` | Register metadata |

**Implementation:** Use Fiskaly `SUBMIT DE` managed service (offloads complex CSV generation to Fiskaly).

**Trigger:** Cloud dashboard → "Export DSFinV-K" for date range → download ZIP.

---

## 10. Audit / Archive Requirements

GoBD requires tax-relevant records for **10 years**.

GastroCore approach:
- All transactions immutable in SQLite (local) and PostgreSQL (cloud)
- TSE response JSON stored in `receipts` table
- DSFinV-K stored in cloud after generation
- Data retention policy: 10+ years for fiscal data
- Account deletion: fiscal data archived, not deleted

---

## 11. Germany Pack Prerequisites

Do not start this phase until:
- [ ] Cloud sync (Phase 2) is stable in production
- [ ] Swiss pilot has ≥ 30 days of stable operation
- [ ] Swiss pilot has ≥ 5 paying customers
- [ ] Fiskaly account created; SIGN DE v2 sandbox access confirmed
- [ ] German tax advisor consulted on edge cases
- [ ] German payment terminal availability confirmed (myPOS supports girocard via Maestro)

---

## 12. Germany Pack Implementation Checklist

### Go Backend: Fiskaly Client (`internal/fiscal/`)

- [ ] Fiskaly HTTP client with API key auth
- [ ] TSE initialization: create TSE unit
- [ ] Start transaction: `POST /api/v1/tse/{tse_id}/tx`
- [ ] Finish transaction: `PUT /api/v1/tse/{tse_id}/tx/{tx_id}`
- [ ] Store TSE response in PostgreSQL `receipts` table
- [ ] Retry logic for Fiskaly failures
- [ ] Offline queue: process pending signatures on reconnect

### Flutter: German Fiscal Flow

- [ ] Country pack detection: `country_pack == 'germany'`
- [ ] After payment confirmation: call Go fiscal endpoint (async, non-blocking)
- [ ] Poll for fiscal status: update receipt when signed
- [ ] "Signatur ausstehend" shown on receipt if offline
- [ ] German receipt builder with TSE fields and QR code
- [ ] German VAT rates (19%, 7%) in tax profiles

### Cloud Dashboard

- [ ] DSFinV-K export button with date range selector
- [ ] Unsigned receipts count alert (warn if > 50)
- [ ] Fiscal signing error log

### Compliance Validation

- [ ] 1000-transaction online test: all signed
- [ ] Offline test: batch-signed within 60s of reconnect
- [ ] DSFinV-K export passes BSI validation tool
- [ ] Receipt QR code verifiable with Fiskaly tool
- [ ] Audit log has no gaps in sequential numbering

---

## 13. What Can Be Deferred in v1

| Item | Reason |
|------|--------|
| Hardware TSE dongle support | Fiskaly cloud is certified and simpler |
| Multiple TSE providers | Fiskaly sufficient; adapter layer prepared |
| Real-time DSFinV-K (continuous) | Batch/on-demand is legally sufficient |
| Finanzamt registration automation | Manual notification is acceptable |
| girocard (EC-Karte) certification | myPOS handles card processing |

---

## 14. Success Criteria for Germany Fiscal Pack v1

- [ ] Every transaction signed by Fiskaly within 5s (online)
- [ ] Offline transactions batch-signed within 60s of reconnect
- [ ] DSFinV-K export passes BSI validation tool
- [ ] Receipt contains all legally required TSE fields and QR code
- [ ] Zero fiscal signing failures in 500-transaction test
- [ ] Audit log proves GoBD compliance (no gaps, immutable, sequential)
- [ ] First German restaurant completes a full day of legally compliant sales
