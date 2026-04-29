# Backoffice (Next.js 15) — Developer Handoff

Pilot için yeni backoffice. Eski Flutter Web (`apps/dashboard`) paralel kalıyor —
yeni feature'lar burada.

## Hızlı başlangıç

```bash
cd apps/backoffice
cp .env.example .env.local
pnpm install
pnpm dev   # http://localhost:3001
```

Default `NEXT_PUBLIC_API_URL=https://api.2hub.ch/api/v1`. Local backend için
`http://localhost:8080/api/v1`.

## Stack özeti

Next.js 15 (App Router) + Tailwind + shadcn/ui + TanStack Query + Recharts + next-intl + Zod.
Detay: `apps/backoffice/README.md`.

## Auth akışı

1. `POST /api/auth/login` (Next.js route handler)
2. Backend `POST /api/v1/auth/admin/login` çağrılır
3. JWT + refresh token httpOnly cookie'ye yazılır
4. Sonraki istekler `/api/proxy/*` üzerinden gider — proxy `Authorization: Bearer` ve `X-Tenant-ID` ekler

Cookie'ler:
- `bo_token` (httpOnly, 1 gün)
- `bo_refresh` (httpOnly, 7 gün)
- `bo_user` (httpOnly, base64 JSON)
- `bo_tenant` (sameSite, 7 gün — aktif tenant)

## Roller

`HQ_ADMIN`, `HQ_MANAGER`, `RESTAURANT_MANAGER`, `RESTAURANT_STAFF`, `POS_OPERATOR`.
Helper: `lib/auth.ts` → `canManageMenu`, `canManageHq`, `isHqAdmin` …

UI sidebar'ı role'e göre HQ bölümünü gösterir/gizler. Menu ürünlerinde
`policy_lock` (FLEXIBLE | PRICE_LOCKED | FULLY_LOCKED) alanı var — kilitli ürünler
restoran yöneticisinde form disable edilir.

## Önemli route'lar

| URL | Sayfa |
|-----|-------|
| `/{locale}/login` | Login |
| `/{locale}/dashboard` | KPI + 7d chart + top sellers |
| `/{locale}/menu` | Kategori/ürün/modifier tabs + POS'a Yayınla |
| `/{locale}/orders` | Sipariş listesi (10s polling) + filter + detay |
| `/{locale}/reports` | Ciro / top / mwst (placeholder) |
| `/{locale}/settings` | TZ + dil (placeholder) |
| `/{locale}/organization/restaurants` | HQ — restoran listesi |
| `/{locale}/organization/menu` | HQ master menu |
| `/{locale}/organization/reports` | HQ aggregate |

`{locale}` ∈ {tr, de, en, fr, it}. Default `tr`.

## Backend kontratları

| Endpoint | Notlar |
|----------|--------|
| `POST /auth/admin/login` | `{email, password}` → `AdminLoginResponse` |
| `POST /auth/token/refresh` | `{refresh_token}` → yeni token |
| `GET/POST /menu/categories` | Tenant scoped |
| `PUT/DELETE /menu/categories/{id}` | |
| `GET/POST /menu/products` | |
| `PUT/DELETE /menu/products/{id}` | |
| `GET /menu/modifiers` | POST/PUT/DELETE backend'de eklenecek (paralel task) |
| `POST /menu/publish/{tenantId}` | Menu snapshot — **paralel task ekliyor** |
| `GET /menu/snapshots?limit=5` | Publish geçmişi — yeni endpoint |
| `GET /dashboard/stats` | KPI |
| `GET /dashboard/revenue?days=7` | Chart data |
| `GET /orders?from=&to=&status=` | Sipariş listesi |
| `GET /reports/products?days=30&limit=10` | Top sellers |
| `GET /admin/stores` | HQ tenant listesi |
| `GET /admin/dashboard` | HQ aggregate |

Her istek `X-Tenant-ID` (tenant scoped) header'ı ister. Login response'taki
`organization_id` (HQ) ya da `store_ids[0]` initial olarak yazılır.

## Menu publish

`POST /api/v1/menu/publish/{tenantId}` → `{version: number}` döner.
UI'da AlertDialog ile onay → toast "Versiyon N POS'a yayınlandı".
Geçmiş Sheet panelde son 5 versiyon listelenir.

> Pilot v1: Backend tarafında snapshot endpoint'i paralel task'ta ekleniyor.
> Kontrat: `tenant_id`, `version`, `published_at`, `published_by`, `category_count`,
> `product_count`. Bu yapı `lib/api-types.ts`'te `MenuSnapshotInfo` tipinde.

## HQ kilitleri

`MenuProduct.policy_lock`:

| Değer | Davranış |
|-------|----------|
| `undefined` / `FLEXIBLE` | Tam düzenlenebilir |
| `PRICE_LOCKED` | Sadece fiyat alanları disabled |
| `FULLY_LOCKED` | Tüm form opacity-60 + pointer-events-none, "HQ Kilitli" badge |

Backend'de `menu_policies(orgId, productId, lockType)` tablosu eklenecek.

## Test çalıştır

```bash
pnpm test
```

`tests/` altında 4 dosya:
- `auth-roles.test.ts` — role helper'ları + JWT expire
- `utils.test.ts` — CHF formatter
- `login-form.test.tsx` — login validation + submit
- `category-form.test.tsx` — kategori CRUD form

## Deploy

`deploy/HETZNER_DEPLOY.md` runbook (Docker + nginx/Caddy).

Servisler:
- Container: `backoffice` → port 3001 (localhost)
- Reverse proxy: `backoffice.gastrocore.ch` → 3001
- Backend: `https://api.2hub.ch/api/v1`

## Mevcut sorular / TBD

1. **Menu snapshot endpoint** — paralel task `local_f868a3fa` ekliyor; tip `MenuSnapshotInfo`.
2. **HQ tabloları** — `organizations`, `organization_memberships`, `menu_policies` migration'ları (backend task).
3. **WebSocket** — pilot v1'de yok, polling 10s yeterli.
4. **File upload** — fotoğraf URL field, upload API entegrasyonu sonra.
5. **RBAC backend enforcement** — şu an UI tarafında; backend role kontrolü gerekli.

## Diğer doc'lar

- `pilot/DEVELOPER_RESTAURANT.md` — POS Flutter uygulama
- `pilot/DEVELOPER_GASTRO2HUB.md` — Go backend
- `apps/backoffice/README.md` — bu projenin teknik README'si
