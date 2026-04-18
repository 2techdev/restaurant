# Boss App — Backlog

**Owner role:** Restaurant owner / manager (remote, mobile).
**Read-only:** no order taking, no menu edits.
**Connectivity:** Online-only (no local SQLite).
**Platforms:** Android first, iOS in same codebase.

## Unblock dependencies

Boss cannot start until these are live in production:

| Dep | Source | Why |
|-----|--------|-----|
| JWT auth + device registration | Phase 3 / Epic 7 (G-01, G-02) | Owner login |
| Sync upload + download | Phase 3 / Epic 7 (G-04, G-05) | Data must reach cloud from POS |
| Aggregated reports API | Phase 3 / Epic 7 (G-09) | Revenue / top products queries |
| Cloud license + feature flags | Phase 3 / Epic 7 (G-08) | Boss is a Professional-tier feature |
| Web Dashboard minimum | Phase 4 / Epic 9 (W-01..W-07) | Reuse same API surface |

If the pilot restaurant asks for remote visibility before Phase 4 is ready, a cheaper option is a read-only view of the existing Web Dashboard on mobile browsers — not a native app.

## MVP scope (v1)

Target: 3–4 person-weeks once unblocked.

### Screens
- [ ] Login (email + password → JWT).
- [ ] Dashboard Home: today's revenue, order count, average ticket, covers.
- [ ] Sales chart: hourly (today) / daily (this week) / daily (this month).
- [ ] Top products (today / this week).
- [ ] Order feed (live stream via WebSocket or 10s polling).
- [ ] Alerts inbox (shift opened, shift closed, high void rate, low stock if tracked).
- [ ] Settings (notification preferences, branch picker for multi-branch).

### Shared packages used
`core_models`, `core_theme`, `core_auth`. No `core_database`, no `core_sync`, no `core_printing`.

### Platform features
- [ ] Push notifications: FCM for Android, APNs for iOS. Topics: `tenant_{id}_shift`, `tenant_{id}_alerts`.
- [ ] Pull-to-refresh everywhere.
- [ ] Offline banner when disconnected (no local cache — just a banner).
- [ ] Biometric unlock (optional, post-MVP).

## Out of scope for v1

- Menu CRUD (Dashboard does this).
- Staff management (Dashboard does this).
- Multi-branch comparison screen (v2).
- Loyalty program view (v2+).
- Direct messaging to staff (v3).
- Kitchen prep time analytics (v2).

## Open questions (resolve before Phase 5 starts)

1. Which chart library? `fl_chart` is default across the codebase — confirm it renders acceptably on low-end Android phones.
2. Do we want a web version of Boss, or is the Dashboard good enough for desktop? The doc says Phone. Keeping it phone-only is simpler.
3. Alert thresholds: hardcoded or per-tenant configurable in Settings? Default to hardcoded for v1.
4. Which auth scope: tenant-admin only, or per-branch managers too? Start with tenant-admin, add branch-manager scope in v2.

## Non-goals

- Do not re-invent POS flows on mobile. If an action needs a POS, it stays on the POS.
- Do not embed a WebView of the Dashboard. If we want Dashboard on mobile, make the Dashboard responsive — don't wrap it.
