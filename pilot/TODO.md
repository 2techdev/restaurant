# Pilot v1 Launch — TODO

Last updated: 2026-05-01

Yapı: kategori başlıkları, her madde checkbox. Done olanlar `- [x]`, pending `- [ ]`.

## ✅ Tamamlananlar (özet)

### Backend (Go)
- [x] Multi-tenant Postgres schema (org + tenant + user + admin_users)
- [x] JWT auth (HS256 + Bearer + X-Tenant-ID middleware)
- [x] Menu CRUD endpoints
- [x] Menu sync (snapshot, version, publish — `/api/v1/menu/*`)
- [x] HQ logic (organizations + memberships + master_menu_versions + menu_policies)
- [x] Migration 015 — devices (POS pairing, `pos_devices` tablosu + bcrypt key hash)
- [x] Migration 016 — promotions/feedback/suppliers/notifications
- [x] Migration 018 — Swiss VAT 2024 oranlarına güncelleme (8.1 / 2.6 / 3.8)
- [x] Audit log endpoint (`/api/v1/audit-log` — filter + cursor pagination)
- [x] Reports: top-sellers / hourly / mwst / export
- [x] Device pairing endpoint'leri (`POST/GET/DELETE /api/v1/me/devices`)
- [x] Middleware menu/version+snapshot bypass fix (X-API-Key auth handler'a ulaşır)

### Backoffice (Next.js 15 + App Router)
- [x] Login + i18n (5 dil bayrak switcher)
- [x] Dashboard (KPI + 7-day chart + top sellers)
- [x] Menu CRUD (kategoriler, ürünler, modifier groups read-only, publish history)
- [x] Orders (active + history + refunds + filters)
- [x] Reports (revenue, top-sellers, hourly, MWST, CSV export)
- [x] Customers + Loyalty + Feedback
- [x] Inventory + Suppliers + Reorder
- [x] Users + Roles & Permissions + Activity log
- [x] Restaurant Mgmt (opening-hours, tax-profiles, payment-methods, devices)
- [x] HQ master menu products + publish history + menu-policies
- [x] HQ aggregate reports (comparison, by-location)
- [x] Organization (info, billing, plan)
- [x] Settings (integrations, audit log)
- [x] Promotions (happy-hour in-memory, discounts, campaigns)
- [x] Receipt templates editor (in-memory + live preview, backend integration TBD)
- [x] Sidebar collapsible groups (14 group × ~56 sub-item, manual override fix)
- [x] Token paleti + JetBrains Mono + StatusBadge + Command Palette (⌘K)
- [x] Production deploy (https://backoffice.gastrocore.ch)

### POS (Flutter Android)
- [x] Pair flow (admin login → device API key, manuel kopyalama yok)
- [x] Menu sync (cloud pull, diff preview, transactional apply)
- [x] M1-M7 pack (modifier wireup, settings POS back, multi-guest seat, temp tables, single Senden, hide description, tile scale)
- [x] Tile scale 5 preset (XS/S/M/L/XL) + slider + autoFit
- [x] Center name on product tiles
- [x] Schema v20 migration
- [x] Audit enum 37
- [x] Production API endpoint (api.gastrocore.ch)
- [x] APK build pipeline (jolly-final lineage)
- [x] Pilot APK: `pilot/app-pos-release.apk` (85.13 MB · sha256 5ec4126c… · POS Modifier UI 2026-05-11)
- [x] **LAN-first networking v2 — paylaşılan module + Kiosk wire** (2026-05-11) — `PeerRegistry` (StateNotifier, all discovered peers sorted server-first, role rozetiyle Settings'te liste), `ConnectionStrategy` (idle→connected→reconnecting→cooldown state machine, 5s/30s back-off, snapshots stream), NetworkLocator genişletildi (manualOverride priority 1 + tenantFilter + onPeersDiscovered callback + wall-clock 04:00 cron DST-safe + nextReprobeAt). Settings pane'inde manuel IP input (SharedPreferences persist), peer listesi, sonraki tarama saati. 3 boot wire (Waiter+KDS+Kiosk). +22 unit test pass. APK'lar: `pilot/app-kds-release-lanfirst-v2-20260509.apk` (62.50 MB · ae3e0190…), `pilot/app-waiter-release-lanfirst-v2-20260509.apk` (63.06 MB · 86c5967b…). WS client ConnectionStrategy ile henüz bağlanmadı (mevcut reconnect loop kalıyor); server-side mDNS broadcaster eksik (her boot cloud fallback). Detay: `pilot/DEPLOY_LOG_2026-05-09.md`.
- [x] **LAN-first networking v1 (Waiter + KDS)** (2026-05-11) — mDNS discovery (`_gastrocore._tcp`) + HTTP /health probe + 24h re-probe + cloud fallback. NetworkLocator paylaşılan servis (`lib/core/network/`), Riverpod state notifier, Settings'te "Bağlantı Durumu" pane (yeşil "LAN bağlı: 192.168.x.x" / turuncu "Bulut fallback" pill + manuel "Şimdi yenile"). AndroidManifest'e `CHANGE_WIFI_MULTICAST_STATE` eklendi. main_waiter + main_kds boot path locator override ediyor. 8 unit test pass. APK'lar: `pilot/app-kds-release-lanfirst-20260509.apk` (62.50 MB · 44855881…), `pilot/app-waiter-release-lanfirst-20260509.apk` (63.06 MB · b57902a8…). Server-side mDNS broadcaster sonraki sprint (locator şu an LAN'da peer bulmuyor, cloud'a düşüyor). Detay: `pilot/DEPLOY_LOG_2026-05-09.md`.
- [x] **Garson App MVP (Waiter flavor)** (2026-05-11) — Önceki keşif: `apps/pos/` flavor `waiter` (com.gastrocore.waiter, `lib/main_waiter.dart`, 3-tab shell) **zaten tam MVP** (login, masa planı, menü browser, sipariş + mutfağa gönder, aktif siparişler). Bu turda iki gap kapatıldı: (a) tüm operatör-gören metinler TR'ye çevrildi (6 dosya: order/tables/menu/active_orders/login/bottom_nav), (b) `WaiterReadyListener` yeni widget — 15s polling, `waiterActiveOrdersProvider` invalidate, status transitionı → `TicketStatus.ready` yakalayınca floating "Sipariş #X hazır!" banner. +3 widget test pass (first-snapshot baseline, transition fires once, ready→served→ready re-arms). Pilot APK: `pilot/app-waiter-release-20260509.apk` (62.94 MB · sha256 39271880…). Detay: `pilot/DEPLOY_LOG_2026-05-09.md`.
- [x] **POS Modifier Management UI** (2026-05-11) — Menü Yönetimi'ne 4. tab "Atamalar" eklendi (`ProductModifierAssignmentPanel`, ~480 satır): ürün seç → atanmış modifier gruplar (sıra rozeti + çıkar) + unassigned dropdown ile ekle. Mevcut `ModifierManagementPanel` tam TR localize edildi (Grup CRUD + Opsiyon CRUD + delete confirm + meta badges). Repository `linkModifierGroupToProduct/unlinkModifierGroupFromProduct` zaten vardı; +3 regression test (isolation, sibling-safe unlink, re-link round-trip). Detay: `pilot/DEPLOY_LOG_2026-05-09.md`.
- [x] **POS Multi-tenant runtime switcher** wire-up tamam (5/6 madde — schema v23 user_tenant_assignments + ActiveTenantNotifier override main.dart + Settings tenantSwitcher tile flag-gated + Pin-login post-login modal + SyncApiClient `X-Tenant-ID`. i18n ARB deferred — paralel agent çakışmasını önlemek için TR hardcoded). Default `multiTenantSwitcherEnabled = false` → pilot davranışı değişmez. 17 yeni unit test pass. Detay: `pilot/DEPLOY_LOG_2026-05-09.md`.
- [x] **POS Linked Items overlay** read-only — schema v24 (`products.is_popular_online` + `allergen_info` JSONB-string), `LinkedItemsOverlayTab` widget + `showLinkedItemsOverlaySheet(...)`, admin panel `_ProductGridCard` cloud icon trigger, banner + tooltip ("gastro.2hub.ch'te yönetilir"). Cloud Postgres karşılığı paralel agent migration 026.

### DevOps
- [x] Hetzner CPX22 sunucu (88.99.190.108, NBG1, Ubuntu 24.04)
- [x] Cloudflare DNS (api/ws/backoffice/gastrocore.ch)
- [x] Caddy auto-SSL (Let's Encrypt) + reverse proxy
- [x] Docker compose (Postgres 16 + Redis 7)
- [x] Backend systemd unit (`gastrocore.service`) + binary deploy
- [x] Backoffice systemd unit (`backoffice.service`) + standalone deploy
- [x] Demo seed (3 tenants: Pizzeria Da Mario / Sushi Zen / Burger House — 75 ürün, 7 günlük sipariş geçmişi)
- [x] Admin user (admin@gastrocore.ch / 123456)
- [x] Backup pattern (binary + tar + schema dump)

### Doküman
- [x] DEVELOPER_RESTAURANT.md (POS handoff)
- [x] DEVELOPER_GASTRO2HUB.md (gastro2hub handoff)
- [x] DEVELOPER_BACKOFFICE.md (Next.js handoff)
- [x] DESIGN_BRIEF.md (3359 satır, designer'a verildi — 8 wireframe HTML dahil)
- [x] DEPLOY_MAP.md (operations runbook)

## 🔄 Devam ediyor

- [x] Sidebar collapsible bug (manual override fix — son turda merge edildi)
- [x] KDV %7.7 → %8.1 / %2.5 → %2.6 düzeltme (frontend label + migration 018)
- [x] Modifier groups full CRUD (backend POST/PUT/DELETE + product assignment + UI live mutations — D Strategy Phase 2, 2026-05-09)
- [ ] POS Cihazları auth bug ("Invalid or expired token" — JWT 8h expire, silent refresh yok)
- [ ] Fast Sale flag-based fix (mevcut sales screen + fastSaleMode flag)
- [ ] Ürün ana dil + opsiyonel çeviriler (tenant primary_language + name_translations JSONB)
- [ ] Audit + printer templates dispatch (audit running)

## 📝 Yakında

### Printer entegrasyonu (POS embedded)
- [ ] Receipt templates Postgres tablosu (migration 020)
- [ ] Backend CRUD endpoints (`/api/v1/restaurant/receipt-templates`)
- [ ] Backoffice template editor backend wire (şu an localStorage iskele)
- [ ] CH MWST default şablon (UID-Nummer + IBAN + 5-rappen rounding)
- [ ] POS ESC/POS engine (template render + bytes)
- [ ] POS TCP/9100 transport
- [ ] POS printer settings UI (ekle/sil/test print)
- [ ] Auto-print on payment

### Payment entegrasyonu (Service App üzerinden)
- [ ] POS `ServiceAppClient` HTTP wrapper
- [ ] Settings → Service App URL
- [ ] Mevcut payment akışı service'e yönlendir (Cash/Card/TWINT)
- [ ] Service App down fallback (Cash-only)

### R2 görsel upload
- [ ] R2 credentials (kullanıcıdan bekleniyor)
- [ ] Backend `/uploads/image` endpoint (S3 SDK)
- [ ] Backoffice ImageUploader component (file picker + preview + progress)
- [ ] Mevcut foto URL field'larını uploader ile değiştir
- [ ] Mobile gallery picker (HTML5 capture)

### POS UX iyileştirmeleri
- [ ] Mode toggle (Tisch ↔ Fast Sale) topbar
- [ ] Lieferung müşteri form (ad/tel/adres)
- [ ] Order type fiyat değişimi (3-fiyat schema)
- [ ] Z raporu basma
- [ ] Vardiya açılış/kapanış akışı
- [ ] Operatör PIN login (vardiya bazlı)

### Backoffice eksikler
- [ ] DE/EN/FR/IT i18n eksik sayfalar (Agent C 16 sayfa + son 5 sayfa için)
- [ ] Mobile drawer (responsive sidebar < 768px)
- [ ] WebSocket real-time orders (şu an polling 10s)
- [ ] 2FA TOTP setup
- [ ] Audit log entity_type select (autocomplete)
- [ ] JWT silent refresh middleware (8h expire sonrası user manual re-login yerine)
- [ ] Tenant switcher 50+ restoran arama + favoriler

### Backend
- [ ] `happy_hour_rules` tablosu + endpoint
- [ ] `master_menu_versions` listing endpoint
- [x] Modifier groups POST/PUT/DELETE (split endpoint family `/api/v1/menu/modifiers/groups`, `/options`, product assignment — 2026-05-09 D Strategy Phase 2)
- [ ] Stripe webhook handler
- [ ] Fiskaly TSE entegrasyonu (DE müşteriler için)
- [ ] Cron `pg_dump` (günlük backup → Hetzner Storage Box)
- [ ] Per-tenant plan limit enforcement
- [ ] Refresh token akışı (`/auth/token/refresh` mevcut, backoffice kullanmıyor)

### Pilot launch hazırlığı
- [ ] Domain: admin.2tech.ch retire kararı (Cloudflare)
- [ ] Tablet pilot deployments (3 demo restoran fiziksel test)
- [ ] Customer onboarding flow (yeni restoran ekleme wizard)
- [ ] Müşteri eğitim materyali (kısa video / PDF)
- [ ] Pricing tiers (Basic / Pro / Enterprise) Stripe entegrasyonu
- [ ] SLA / uptime monitoring (Uptime Kuma veya benzeri)
- [ ] Error tracking (Sentry)
- [ ] Analytics (Plausible / PostHog)

## 🚀 İleride (v0.2+)

### Backoffice — ödeme yöntemleri yönetimi (post-Cuma demo)

> Pilot demo Cuma'sında POS hard-coded BAR + KARTE ile çalışıyor. Demo
> sonrası faz olarak backoffice'ten yönetilebilir liste yapılacak.

- [ ] Backend: `payment_methods` tablosu + migration (`name, icon, type:
  cash|card|digital|voucher, is_active, sort_order, tenant_id`)
- [ ] Backend: `GET/POST/PUT/DELETE /api/v1/admin/payment-methods` CRUD
- [ ] Backend: seed default 2 metod (BAR cash, KARTE card)
- [ ] Backoffice: `/[locale]/payment-methods` sayfası (CRUD + drag-reorder)
- [ ] Backoffice: hook `useCreatePaymentMethod` / `useUpdatePaymentMethod`
- [ ] POS: cloud sync `payment_methods` Drift tablosuna yansıt
- [ ] POS: hızlı satış ekranındaki BAR/KARTE chip'leri seed'den render
  (mevcut `_PayChip` widget'ı listeden besleyecek; cash flow'u
  `type=cash` flag'ine bağla)
- [ ] POS: yeni metodlar için icon set genişlet (TWINT/Postcard/Voucher)

Effort: ~2 gün (1 gün backend + 1 gün backoffice + UI; POS sync wiring
zaten mevcut sync_queue altyapısı üzerinden gider).

- [ ] Customer Display (CFD) — ikinci ekran müşteri tutarı
- [~] Reservation entegrasyonu (gastro2hub + backoffice) — D Strategy
  - Aşama 1 (magic-link menu import): **POS Go canlı, Reservation canlı, E2E ✓** (2026-05-09 — `POST /api/v1/menu/import-from-token` cents fix + name_translations seed)
  - Aşama 3 (POS-core push pipeline): **POS tarafı 88'de canlı** (2026-05-11, migration 027, push handler + auto-trigger + retry cron 5min/backoff/max5 + backoffice `/settings/menu-source` toggle). Reservation `/api/gastrocore/menu/sync` receiver kodu hazır ama **178 deploy bekliyor (akşam 22:00+)** — E2E o zaman.
  - Aşama 4 (overlay sync Reservation→POS): **POS receiver canlı** (`PATCH /api/v1/menu/overlay/products/{id}`), Reservation producer (`src/lib/gastrocore-overlay-client.ts`) deploy bekliyor.
- [ ] Self-checkout kiosk modu
- [ ] Mobile app (kasiyer iOS/Android — POS Lite)
- [ ] Boss app (sahip mobile — Phase 5, Flutter)
- [ ] AI-powered upsell suggestions
- [ ] Voice ordering (drive-through scenario)
- [ ] Multi-currency (şu an CHF hardcoded)
- [ ] Multi-restaurant single ticket (delivery aggregator)
- [ ] White-label / custom domain (tenant başına)
- [ ] Public API + webhooks (üçüncü-taraf entegrasyon)
- [ ] App marketplace

## ⚠️ Bilinen sorunlar (TBD)

- [ ] DE/EN/FR/IT i18n eksiklikleri (Agent C son sayfaları + son 5 placeholder fix)
- [ ] Receipt template backend endpoint'leri eksik (in-memory localStorage iskele)
- [ ] Happy hour backend tablosu yok (in-memory localStorage iskele)
- [x] Modifier groups CRUD backend (D Strategy Phase 2, 2026-05-09 — read-only banner kaldırıldı)
- [x] **F1 Super Admin Impersonation** (2026-05-09) — End-to-end CANLI. Server: migration 024, 3 endpoint (`POST /api/v1/admin/impersonate`, `/exit`, `GET /admin/tenants`), 9/9 unit test PASS, image `gastrocore-server:f1-20260509-003313`. Backoffice: `/[locale]/admin/tenants` page + 3 API proxy + ImpersonationBanner + lib/auth+cookies+api-types patches + 5-lang i18n (TR/DE/EN/FR/IT), atomic commit `22f789c` paralel-agent revert döngüsünü kırdı. PM2 reload `gastro-backoffice` 01:20 CEST, smoke 7/7 PASS. End-to-end: super admin login → /admin/tenants → "Login as User" → 15dk impersonation cookie → banner → exit. DB seed: `superadmin@gastrocore.ch is_super_admin=TRUE`. Detay: `pilot/DEPLOY_LOG_2026-05-09.md`.
- [ ] JWT 8h expire → user manual re-login (silent refresh middleware yok)
- [ ] Pre-existing 42 POS test fail (DB schema v7→v20 stale, seed data)
- [ ] Worktree dirs Windows file lock (manual cleanup gerek — `gallant-lichterman-b9de55`, `objective-davinci-0015df`)
- [ ] Master menu version listing endpoint TBD
- [ ] DESIGN_BRIEF.md eski VAT referansları (line 736, 1030, 1397, 1647-1648, 2017 — koda etki etmiyor)
- [ ] Pilot DB'de `tax_profiles` boş (0 row) — demo seed prod'a hiç çalıştırılmamış; gerçek kullanım başlayınca seed atılmalı
- [ ] HQ tenant picker pair screen'de manuel UUID girişi (autocomplete `/me/tenants` v0.2)
- [ ] secure_storage entegrasyonu POS'ta yok (API key SharedPreferences plain JSON)
