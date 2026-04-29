# GastroCore Backoffice (Next.js 15)

Pilot restoran zincirleri için backoffice — eski Flutter Web (`apps/dashboard`) yerine geçer.
Eski dashboard pilot transition süresince paralel kalıyor; yeni feature'lar burada.

## Stack

- **Next.js 15** (App Router, RSC, TypeScript strict)
- **Tailwind CSS** + **shadcn/ui** primitives
- **TanStack Query** (data fetch + cache + invalidation)
- **TanStack Table** (orders/menu listesi)
- **React Hook Form + Zod** (form + validation)
- **Recharts** (dashboard grafikleri)
- **next-intl** (TR/DE/EN/FR/IT — TR/DE öncelikli, diğerleri full)
- **next-themes** (default dark)
- **Vitest + RTL** (smoke testleri)

## Geliştirme

```bash
cd apps/backoffice
cp .env.example .env.local
# .env.local'da NEXT_PUBLIC_API_URL ve API_BASE_URL'i kontrol et

# dependencies (Windows'ta pnpm önerilir, npm da olur):
pnpm install   # ya da: npm install

pnpm dev       # → http://localhost:3001
```

Dev sırasında backend'e doğrudan istek yerine **`/api/proxy/*`** kullanılır
(httpOnly cookie güvenliği). Cookie tarayıcıda görünmez; Next.js route handler'lar
backend'e iletir.

## Build

```bash
pnpm build
pnpm start
```

`next.config.ts`'te `output: "standalone"` aktif — Docker image küçük kalır.

## Test

```bash
pnpm test           # tek seferlik
pnpm test:watch     # izleme modu
```

Smoke testleri `tests/` altında:
- `login-form.test.tsx` — form validation, submit
- `category-form.test.tsx` — renk + emoji + active toggle
- `auth-roles.test.ts` — role guard helpers, JWT expire
- `utils.test.ts` — CHF formatter, chf↔cents

## Yapı

```
apps/backoffice/
├── app/
│   ├── [locale]/
│   │   ├── (auth)/login/         # giriş ekranı
│   │   ├── (dashboard)/
│   │   │   ├── dashboard/        # KPI + 7 day chart + top sellers
│   │   │   ├── menu/             # tabs: kategoriler / ürünler / modifier'lar
│   │   │   ├── orders/           # liste + filtre + detay (polling 10s)
│   │   │   ├── reports/          # ciro / top / mwst placeholder
│   │   │   ├── settings/         # tz + dil + placeholder
│   │   │   └── organization/     # HQ — restoran listesi + master menu + aggregate
│   │   └── layout.tsx
│   ├── api/
│   │   ├── auth/{login,logout,tenant}/  # cookie set/clear
│   │   └── proxy/[...path]/      # Bearer + X-Tenant-ID injecte eden generic proxy
│   ├── layout.tsx
│   └── globals.css
├── components/
│   ├── ui/                       # shadcn primitives (button, card, dialog, table, …)
│   ├── shell/                    # sidebar, topbar, tenant-switcher, language-switcher
│   ├── menu/                     # category/product/modifier formları + publish button
│   ├── orders/                   # orders tablosu + detay dialog
│   ├── dashboard/                # revenue chart + top sellers tablosu
│   ├── settings/                 # settings formu
│   └── hq/                       # location compare chart
├── lib/
│   ├── api.ts                    # backend fetch (server-side)
│   ├── api-client.ts             # browser → /api/proxy
│   ├── api-types.ts              # Go backend tipleriyle eş tipler
│   ├── auth.ts                   # cookie session, role helpers, JWT exp
│   ├── server-data.ts            # RSC fetcher'ları
│   ├── i18n/                     # next-intl konfig
│   └── utils.ts                  # cn, formatChf, datetime
├── messages/                     # tr/de/en/fr/it.json
├── tests/                        # vitest smoke testleri
├── middleware.ts                 # auth gate + locale
├── Dockerfile                    # multi-stage standalone
├── next.config.ts
├── tailwind.config.ts
└── package.json
```

## Auth akışı

1. `/login` → email + password → `POST /api/auth/login`
2. Next.js route handler → backend `POST /api/v1/auth/admin/login`
3. Response: `{access_token, refresh_token, user{role, organization_id, store_ids}}`
4. Cookie'ler set:
   - `bo_token` (httpOnly, 1 gün) — JWT
   - `bo_refresh` (httpOnly, 7 gün)
   - `bo_user` (httpOnly, base64 JSON)
   - `bo_tenant` (sameSite, 7 gün) — aktif tenant
5. `middleware.ts` her request'te token kontrol eder
6. Logout: `POST /api/auth/logout` → tüm cookie'ler silinir

## Role'lar

| Role | Kapsam |
|------|--------|
| `HQ_ADMIN` | Tüm sistem; HQ menüsü, tüm restoranlar, aggregate raporlar |
| `HQ_MANAGER` | HQ menü, restoranlar (read+limited write), aggregate |
| `RESTAURANT_MANAGER` | Tek restoran: menü, sipariş, rapor, ayarlar |
| `RESTAURANT_STAFF` | Tek restoran read-only (menü düzenleyemez) |
| `POS_OPERATOR` | Sadece login + dashboard read |

`lib/auth.ts` helper'ları: `canManageMenu`, `canManageHq`, `isHqAdmin`, vs.

## HQ menu kilidi

Master menüden gelen ürünler 3 mod:

- `FLEXIBLE` — restoran tam düzenleyebilir (default).
- `PRICE_LOCKED` — sadece fiyat alanları kilitli; restoran açıklama/kategori değiştirebilir.
- `FULLY_LOCKED` — hiçbir alan düzenlenemez. Form opacity + tooltip "HQ tarafından kilitli".

Backend tarafında `menu_policies` tablosu eklenince `MenuProduct.policy_lock` doldurulur.
UI buna hazır.

## Backend kontratları

### Auth
- `POST /api/v1/auth/admin/login` → `AdminLoginResponse`
- `POST /api/v1/auth/token/refresh`

### Menu (her istek `X-Tenant-ID` ister)
- `GET/POST /api/v1/menu/categories` · `PUT/DELETE /api/v1/menu/categories/{id}`
- `GET/POST /api/v1/menu/products` · `PUT/DELETE /api/v1/menu/products/{id}`
- `GET /api/v1/menu/modifiers` (POST/PUT/DELETE eklenecek — paralel task)
- `POST /api/v1/menu/publish/{tenantId}` ← **bu task'ta gerçek değil; menu snapshot endpoint'i paralel taskta ekleniyor**
- `GET /api/v1/menu/snapshots?limit=5` (publish geçmişi)

### Dashboard / Reports / Orders
- `GET /api/v1/dashboard/stats`
- `GET /api/v1/dashboard/revenue?days=7`
- `GET /api/v1/orders?from=&to=&status=`
- `GET /api/v1/reports/products?days=30&limit=10`

### HQ
- `GET /api/v1/admin/stores` (tüm restoranlar, HQ_ADMIN)
- `GET /api/v1/admin/dashboard` (aggregate)

## Deploy

`deploy/HETZNER_DEPLOY.md` runbook'a bakın.

Kısa özet:

```bash
docker build -t gastrocore-backoffice .
docker run -d --name backoffice -p 127.0.0.1:3001:3001 \
  --env-file .env.production gastrocore-backoffice
```

nginx ya da Caddy reverse proxy ile `https://backoffice.gastrocore.ch`.

## Bilinen kısıtlar (pilot v1)

- WebSocket (canlı sipariş) yok — orders 10sn polling
- File upload yok — fotoğraf URL field
- Settings full değil — placeholder + 3 alan
- Reports MWST raporu placeholder
- HQ menu lock policy backend tabloları henüz yok — UI hazır
- RBAC sadece UI tarafında; backend role enforcement TBD
