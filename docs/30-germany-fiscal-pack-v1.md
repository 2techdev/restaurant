# 30 - Germany Fiscal Pack v1

> **Document Status:** Authoritative | **Last Updated:** 2026-03-20
>
> **DEPENDENCY:** Cloud sync (Phase 4) must be stable before starting this phase.
> Germany fiscal requires internet connectivity for Fiskaly TSE API calls.
> Do not start this phase before the Swiss pilot is generating stable revenue.

---

## 1. German Fiscal Law Overview

### 1.1 KassenSichV (Kassensicherungsverordnung)

Since 1 January 2020, all electronic cash registers in Germany must:
- Be equipped with a **certified Technical Security Device (TSE)**
- Sign every transaction cryptographically
- Issue receipts with TSE signature data
- Be capable of generating **DSFinV-K** compliant exports

**Non-compliance:** Fine up to EUR 25,000 per violation. Cannot legally operate a cash register in Germany without TSE certification.

### 1.2 DSFinV-K (Digitale Schnittstelle der Finanzverwaltung für Kassensysteme)

A standardized XML/CSV export format required by German tax authorities. Must be produceable on demand (e.g., for a tax audit).

### 1.3 GoBD (Grundsätze zur ordnungsmäßigen Führung und Aufbewahrung von Büchern)

Principles for proper bookkeeping. Relevant requirements:
- Immutable transaction log (already implemented via ADR-010)
- Sequential numbering without gaps (must be verified)
- 10-year retention of tax-relevant records

---

## 2. Our Approach: Cloud TSE via Fiskaly

**Decision (ADR-008, confirmed):** Use Fiskaly SIGN DE v2 (cloud TSE) rather than hardware TSE dongles.

**Why Fiskaly:**
- Certified by BSI (Bundesamt für Sicherheit in der Informationstechnik)
- No hardware to manage or fail
- REST API — integrates cleanly into Go cloud backend
- Handles TSE lifecycle management (initialization, re-initialization, export)

**Fiskaly products:**
- `SIGN DE v2`: Cloud TSE for signing transactions
- `SUBMIT DE`: DSFinV-K export generation (optional managed service)

---

## 3. Transaction Model

### 3.1 German-Specific Terminology

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
7. Print receipt with TSE QR code
```

### 3.3 Offline Queue for Fiscal Signing

When POS is offline (no internet), Fiskaly cannot be reached. GastroCore uses the "offline order + online fiscal finalization" model:

1. POS takes order and payment offline — writes to local SQLite as normal
2. Receipt marked as `fiscal_status: 'pending_signature'`
3. Receipt printed with "OFFLINE - Signatur ausstehend" notice
4. When internet returns: background process batch-signs pending receipts via Fiskaly
5. Signed receipts get `fiscal_status: 'signed'`; receipt updated in DB
6. Customer can request updated receipt with signature (rare case)

**Offline queue capacity:** Alert owner when > 100 unsigned receipts. Alert at > 500 (legal risk zone). Recommend 4G router as internet backup for German restaurants.

---

## 4. Receipt with TSE Data

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

[QR CODE containing TSE verification data]
────────────────────────────────
```

The QR code payload follows the Kassenbeleg-V1 format (can be verified with BSI test tools).

---

## 5. German VAT Rates

| Rate | Applies To |
|------|-----------|
| 19% | Standard (alcohol, most beverages, service) |
| 7% | Reduced (food for takeaway, non-alcoholic beverages) |

Same dine-in vs. takeaway distinction as Switzerland but with different rates. The `order_type_rules` table and `FareEngine` must handle the German country pack.

**Country detection:** A setting `country_pack` (values: `none`, `switzerland`, `germany`) controls which tax rules and receipt format apply. This drives the country pack behavior at runtime.

---

## 6. Table/Session Linkage

Fiskaly requires transaction data to include business context:

```json
{
  "schema": {
    "standard_v1": {
      "receipt": {
        "receipt_type": "RECEIPT",
        "amounts_per_vat_id": [
          { "vat_definition_export_id": 1, "incl_vat": 1190, "excl_vat": 1000, "vat": 190 }
        ],
        "amounts_per_payment_type": [
          { "payment_type": "CASH", "amount": 1190, "currency_code": "EUR" }
        ],
        "line_items": [
          { "business_case": { "type": "SALE" }, "name": "Schnitzel", "amount_per_unit": 1190, "quantity": 1, "tax_rate_applicable": 0.19 }
        ]
      }
    }
  }
}
```

The GastroCore `Ticket` entity maps cleanly to this structure. Amounts must be in **EUR cents**.

---

## 7. Split Bill Handling

When a table bill is split:
- Each split portion generates its own Fiskaly transaction
- Each portion gets its own receipt with unique TSE signature
- The original ticket is marked as split; each sub-bill references the original

No partial transactions — each payment completion = one complete Fiskaly transaction.

---

## 8. Table Merge Handling

When two tables are merged:
- The merged order becomes one ticket
- One Fiskaly transaction for the merged total
- Individual items from both tables appear in the transaction line items
- Audit trail shows merge event before the final transaction

---

## 9. Failure Handling

| Failure Scenario | Response |
|-----------------|---------|
| Fiskaly API timeout (> 5s) | Add to offline queue; print receipt with "Signatur ausstehend" |
| Fiskaly returns error (4xx) | Log error; alert on dashboard; attempt re-sign with corrected data |
| Fiskaly returns 5xx | Retry with exponential backoff; max 10 retries; then offline queue |
| TSE quota exhausted | Alert immediately; contact Fiskaly; cannot sign until resolved |
| Internet down | Offline queue (see section 3.3) |
| Device offline during finalization | Queue in sync_queue; cloud signs when device reconnects |

**Critical rule:** GastroCore NEVER blocks a completed payment waiting for Fiskaly. Payment always succeeds first. Fiscal signing is an async post-payment step.

---

## 10. DSFinV-K Export

DSFinV-K is a structured export required for tax audits. It consists of multiple CSV files:

| File | Contents |
|------|---------|
| `transactions.csv` | All transactions with amounts, timestamps, TSE data |
| `transactions_tse.csv` | TSE signature data per transaction |
| `cash_point_closing.csv` | Daily Z-report data |
| `data_payment.csv` | Payment method details |
| `items.csv` | Line items per transaction |
| `vat.csv` | VAT definitions |
| `cash_register.csv` | Register metadata |
| `business_cases.csv` | Business case codes |

**Implementation:** Use Fiskaly's `SUBMIT DE` service (managed DSFinV-K generation) OR generate manually from PostgreSQL.

**For v1:** Use `SUBMIT DE` managed service if available in our Fiskaly contract. This offloads the complex CSV generation to Fiskaly.

**Export trigger:** Available in cloud dashboard → "Export DSFinV-K" for date range → downloads ZIP.

---

## 11. Audit/Archive Requirements

Under GoBD, tax-relevant records must be retained for **10 years** and be available for inspection.

GastroCore approach:
- All transactions immutable in SQLite (local) and PostgreSQL (cloud)
- Fiscal signatures stored in `receipts` table with full TSE response JSON
- DSFinV-K export stored in cloud after generation (idempotent regeneration available)
- Data retention policy in cloud: 10+ years for fiscal data
- Deletion of tenant account: fiscal data archived, not deleted, for 10 years

---

## 12. What Can Be Deferred in v1

| Deferred Feature | Reason |
|-----------------|--------|
| Hardware TSE dongle support | Fiskaly cloud TSE is certified and simpler |
| Multiple TSE providers | Fiskaly is sufficient; adapter layer prepared for future |
| Real-time DSFinV-K (continuous export) | Batch/on-demand export is legally sufficient |
| Automatic fiscal audit preparation | Manual download from dashboard is sufficient |
| German payment terminals (girocard EC-Karte certification) | Start with card terminal that supports existing payment SDK |
| Registration with Finanzamt (mandatory since 2024) | Notification procedure — must research current state, may automate later |

---

## 13. Germany Pack Implementation Checklist

### Pre-requisites (must be done before starting)
- [ ] Cloud sync (Phase 4) is stable and in production
- [ ] Swiss pilot has at least 30 days of stable operation
- [ ] Fiskaly account created; SIGN DE v2 sandbox access confirmed
- [ ] German tax advisor consulted on edge cases

### Go Backend: Fiskaly Client
- [ ] Fiskaly HTTP client in `internal/fiscal/` module
- [ ] TSE initialization: POST /api/v1/tse (create TSE unit)
- [ ] Start transaction: POST /api/v1/tse/{tse_id}/tx
- [ ] Finish transaction: PUT /api/v1/tse/{tse_id}/tx/{tx_id}
- [ ] Store TSE response in PostgreSQL
- [ ] Retry logic for Fiskaly API failures
- [ ] Offline queue: process pending signatures on reconnect

### Flutter: Fiscal Flow
- [ ] Country pack detection: `country_pack == 'germany'`
- [ ] After payment confirmation: call Go fiscal endpoint (async, non-blocking)
- [ ] Poll for fiscal status: update receipt when signed
- [ ] "Signatur ausstehend" on receipt if offline
- [ ] German receipt format with TSE fields and QR code

### Cloud Dashboard
- [ ] DSFinV-K export trigger button with date range selector
- [ ] Unsigned receipts count indicator (alert if > 50)
- [ ] Fiscal signing error log

### Compliance Validation
- [ ] Every transaction signed in 1000-transaction test (online)
- [ ] Offline transactions signed within 60s of reconnect (in batch test)
- [ ] DSFinV-K export passes BSI validation tool
- [ ] Receipt QR code verifiable with Fiskaly verification tool
- [ ] Audit log has no gaps in sequential numbering

---

## 14. Success Criteria for Germany Fiscal Pack v1

- [ ] Every transaction signed by Fiskaly within 5s (online)
- [ ] Offline transactions batch-signed within 60s of reconnect
- [ ] DSFinV-K export passes validation tool
- [ ] Receipt contains all legally required TSE fields
- [ ] Zero fiscal signing failures in 500-transaction test
- [ ] Audit log proves GoBD compliance (no gaps, immutable, sequential)
- [ ] At least one German restaurant completes a full day of legally compliant sales
