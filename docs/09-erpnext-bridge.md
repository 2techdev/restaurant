# ERPNext Bridge

> **Document Status:** DEFERRED — NOT PLANNED FOR V1 | **Last Updated:** 2026-03-20
>
> ⚠️ **ARCHITECTURE DECISION: ERPNext integration has been permanently removed from GastroCore.**
>
> The team is building their own accounting/backoffice infrastructure. ERPNext integration
> adds complexity (version pinning, API fragility, GPL risk) with zero benefit given this
> decision.
>
> **What replaces this:**
> The GastroCore Cloud Hub exposes a generic **Export API** (CSV/JSON) that the team's
> custom backoffice consumes on its own schedule. There is no live bridge; the export
> is pull-based and loosely coupled.
>
> See doc 23 (Architecture Freeze, FRZ-02) for the formal decision record.
> See doc 32 (Implementation Backlog, DEF items) for what is deferred.

---

## Decision Log

| Date | Decision | Reason |
|------|----------|--------|
| 2026-03-20 | ERPNext bridge removed permanently | Team builds own backoffice infrastructure; ERPNext adds GPL risk and API fragility with no benefit |

---

## What the Custom Backoffice Export Looks Like Instead

The Cloud Hub provides lightweight export endpoints:

```
GET /api/v1/export/daily-summary?date=2026-03-20
  → CSV: date, gross_revenue, vat_breakdown, payment_methods

GET /api/v1/export/transactions?from=2026-03-01&to=2026-03-20
  → CSV: all transactions with receipt numbers, amounts, taxes

GET /api/v1/export/shifts?from=2026-03-01&to=2026-03-20
  → CSV: shift summaries with cash counts
```

The custom backoffice project (separate from GastroCore) polls these endpoints and posts journal entries to its own accounting system.

---

## Original Content

The original ERPNext bridge design content (master data sync, transaction posting,
stock sync, ERPNext downtime handling) is preserved in git history and available
if the architecture decision is ever revisited.

Current decision: it will not be revisited in v1 or v2.

---

*All references to "ERPNext Bridge" in other documents should be understood as "Custom Backoffice Export API".*
