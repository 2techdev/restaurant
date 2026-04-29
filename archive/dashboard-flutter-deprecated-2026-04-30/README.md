# Flutter Web Dashboard (DEPRECATED 2026-04-30)

This is the original Flutter Web backoffice (`apps/dashboard/`). Replaced
by [`apps/backoffice/`](../../apps/backoffice/) — a Next.js 15 + App Router
+ next-intl + Tailwind/shadcn rewrite.

## Status

- **Production replacement**: https://backoffice.gastrocore.ch (Next.js, served via Caddy on Hetzner)
- **Deprecated host**: https://admin.2tech.ch (Cloudflare Pages, Flutter Web build)
  - DNS retire is pending — see Cloudflare panel: Pages project must be paused/removed and `admin.2tech.ch` CNAME unset.
- **Archive date**: 2026-04-30
- **Last release tag**: `gastrocore_dashboard 1.0.0-beta.1+1`

## Why archived rather than deleted

Kept in-tree for diff reference until the Cloudflare/DNS retire is finished.
Once `admin.2tech.ch` returns NXDOMAIN, this folder can be `git rm -rf`'d
and recovered from history if needed.

## CI

`.github/workflows/deploy-backoffice.yml` was switched to **manual-only**
(`workflow_dispatch`), so it no longer auto-builds on `apps/dashboard/**`
pushes. Trigger from the Actions tab if you need a one-off Cloudflare push.

## What replaced what

| Flutter Web (this folder) | Next.js replacement (`apps/backoffice/`) |
| --- | --- |
| Riverpod state mgmt | React Server Components + tRPC-style client fetch |
| `flutter_localizations` + ARB | `next-intl` + JSON catalogs (de/tr/en/fr/it) |
| Material 3 widgets | Tailwind + shadcn/ui primitives |
| `flutter build web` → CF Pages | `next build` → Caddy reverse-proxy on Hetzner |

See `apps/backoffice/DESIGN_BRIEF.md` for the rewrite scope.
