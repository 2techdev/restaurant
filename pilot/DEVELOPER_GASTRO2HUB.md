# gastro.2hub.ch — Developer Handoff (Online Sipariş Sistemi)

> **Hedef okuyucu:** Projeye yeni giren bir Claude oturumu veya developer.
> Bu dosya **self-contained**'dir; başka bir dosya okumadan online sipariş modülünde üretken olabilmeniz için yeterli bağlam verir.
>
> **Tarih:** 2026-04-24
> **Durum:** 🟢 Production — canlı (gastro.2hub.ch + tenant custom domain'ler)
>
> **ÖNEMLİ — Kapsam netliği:**
> Kullanıcı kararı ile: **online sipariş (gastro.2hub.ch)**, **rezervasyon** ve **POS (GastroCore)** ÜÇ AYRI ÜRÜN olarak ele alınıyor. Fakat kodda ŞU AN online sipariş + rezervasyon **birleşik bir Next.js uygulamasında** (`E:\Project\reservation\`) — iki domain ile yayında:
> - `gastro.2hub.ch` (online sipariş odaklı — bu dosyanın konusu)
> - `reservation.2pos.ch` (rezervasyon + kardeş subdomain)
>
> Bu dosya online sipariş modülünü tek başına anlatır. Rezervasyon için bkz. `DEVELOPER_RESERVATION.md`. POS için bkz. `DEVELOPER_RESTAURANT.md`.

---

## 0. TL;DR — İlk 60 Saniye

Online sipariş modülü **zaten canlı**: Next.js 15 + Prisma 6 + Postgres + Redis + Cloudflare R2, Hetzner `178.104.137.75`, PM2 app `reservation` port **3001**, primary domain `gastro.2hub.ch`, Sunmi V2s Flutter POS (`mobile/` aynı repo).

```bash
# 1. Ana repo
cd E:/Project/reservation

# 2. Bağımlılıklar
npm install
npx prisma generate

# 3. Dev server
npm run dev           # localhost:3000

# 4. Flutter POS (Sunmi V2s) build
cd mobile
flutter build apk --release    # build/app/outputs/flutter-apk/app-release.apk

# 5. Web deploy (git YOK — SFTP/tar)
python deploy_test.py           # önce test (LAN 192.168.1.134)
# kullanıcı onayı
python deploy_hetzner.py        # sonra canlı
```

**Üç altın kural:**
1. **Git YOK.** Repo versiyon kontrolsüz. Deploy = `.next/standalone` + `public/` + `prisma/` + env → SFTP+tar → PM2 restart. Yerel build canonik.
2. **Yeni iş önce TEST'e, sonra canlıya.** 2026-04-19'dan itibaren zorunlu. Test: `192.168.1.134` LAN. Canlı: Hetzner `178.104.137.75`.
3. **`mobile/` (Sunmi Flutter POS) dokunulmazdı, 2026-04-19'dan sonra renk/font token'ları ESNETİLDİ** (user kural güncellemesi). Mantık değişiklikleri hâlâ dokunulmaz — onlar Sunmi-özel.

---

## 1. Proje Kimliği

- **Ürün:** Çok-kiracılı online sipariş (2POS / 2PAY) — takeaway + delivery, posta kodu bazlı teslim bölgeleri, canlı sipariş akışı (SSE), Sunmi V2s termal yazıcı entegrasyonu.
- **Mevcut repo:** `E:\Project\reservation\` (hem online sipariş hem rezervasyon bu repo'da).
- **Primary domain:** `gastro.2hub.ch`
- **Secondary:** `reservation.2pos.ch` + tenant custom domain'leri (`pizzeriapalazzo.ch`, `restaurant-aspendos.ch`, ...).
- **Teknoloji:** Next.js 15 (App Router, RSC, `output: "standalone"`) / React 19 / TypeScript strict / Prisma 6.19.2 / PostgreSQL / Redis (ioredis) / Cloudflare R2 / nodemailer SMTP / web-push / sharp.
- **Process:** PM2, app adı `reservation` (evet, aynı process — tek Next.js app), port **3001**, max-memory restart 500M.
- **Dil:** DE default + FR + EN + IT. TR henüz yok (POS tarafında eklendi).
- **Pazar:** İsviçre (MWST 2.6%, CH DSG).
- **Tenant'lar (prod):** aspendos, demo-restaurant, dunia, frohsinn, pizzeria-palazzo, restaurant-test (+ migration ile tane değişir).

---

## 2. Kaynaklar ve Yollar

Aynı bilgisayarda çalışıyorsan aşağıdaki yolları doğrudan `Read` tool ile açabilirsin.

### 2.1 Online Sipariş Repo (MEVCUT, CANLI)

| Ne | Yol |
|----|-----|
| **Ana repo** | `E:\Project\reservation\` |
| **Prisma schema (632 satır)** | `E:\Project\reservation\prisma\schema.prisma` |
| **Middleware (rate limit + custom domain + JWT)** | `E:\Project\reservation\src\middleware.ts` |
| **Auth (OWNER/ADMIN + customer)** | `E:\Project\reservation\src\lib\auth.ts` |
| **Cache / SSE pub-sub** | `E:\Project\reservation\src\lib\cache.ts` |
| **R2/S3 helper** | `E:\Project\reservation\src\lib\s3.ts` |
| **Sipariş form (müşteri)** | `E:\Project\reservation\src\app\(public)\[slug]\order\page.tsx` |
| **Sipariş API (create)** | `E:\Project\reservation\src\app\api\public\[slug]\order\route.ts` |
| **Sipariş SSE stream** | `E:\Project\reservation\src\app\api\orders\stream\route.ts` |
| **Ödeme API (Stripe TODO)** | `E:\Project\reservation\src\app\api\public\[slug]\order\[orderId]\payment\route.ts` |
| **Mail template'leri** | `E:\Project\reservation\src\lib\email-templates\*.ts` |
| **Desktop ordering UI (yeni 2026-04-18)** | `E:\Project\reservation\src\components\order\desktop\*` |
| **Brand tokens (desktop)** | `E:\Project\reservation\src\lib\brand-tokens.ts` |
| **Flutter POS (Sunmi)** | `E:\Project\reservation\mobile\` |
| **PM2 config** | `E:\Project\reservation\ecosystem.hetzner.config.js` |
| **Nginx vhost** | `E:\Project\reservation\nginx\*.conf` |
| **Proje dokümanı indeksi** | `E:\Project\reservation\CLAUDE.md` |
| **Branch bazlı dokümanlar** | `E:\Project\reservation\.claude\docs\01..13.md` |
| **DEVLOG** | `E:\Project\reservation\DEVLOG.md` |
| **Deploy Checklist** | `E:\Project\reservation\DEPLOY_CHECKLIST.md` |
| **Mobile App Spec** | `E:\Project\reservation\MOBILE_APP_SPEC.md` |

### 2.2 POS Tarafı (GastroCore köprüsü)

| Ne | Yol |
|----|-----|
| **POS monorepo kökü** | `E:\Project\Restaurant\` |
| **POS pilot worktree** | `E:\Project\Restaurant\.claude\worktrees\jolly-final\` |
| **POS handoff dosyası** | `E:\Project\Restaurant\pilot\DEVELOPER_RESTAURANT.md` |
| **POS pilot APK** | `E:\Project\Restaurant\pilot\app-pos-release.apk` |

**POS kılavuzundan online sipariş için okunması gereken klasörler:**

| Klasör | Neden önemli |
|--------|--------------|
| `E:\Project\Restaurant\.claude\worktrees\jolly-final\docs\developer-kilavuzu\02-features\menu\` | POS'un `products`/`categories` yapısı, sold-out toggle, combo/set menü — web kataloğu buradan feed |
| `...\docs\developer-kilavuzu\02-features\orders\` | `OrderType.dineIn/takeaway/delivery`, gang dispatch — online sipariş POS'a takeaway/delivery ticket olarak düşecek |
| `...\docs\developer-kilavuzu\02-features\customer\` | POS `customer` entity, loyalty — web müşteri kaydıyla eşleşme |
| `...\docs\developer-kilavuzu\02-features\payment\` | Mixed tender, Wallee, storno refund — web ödeme / POS reconciliation |
| `...\docs\developer-kilavuzu\03-swiss-compliance\` | MWST 2.6/3.8/8.1, audit log, Z-seal |

**POS kılavuzu kök:** `E:\Project\Restaurant\.claude\worktrees\jolly-final\docs\developer-kilavuzu\`

### 2.3 Obsidian Vault — Canonical Planlama Notları

User'ın kişisel planlama notları (reservation + ordering birleşik):

| Not | Yol |
|-----|-----|
| **Ana note (harita, 870 satır)** | `C:\Users\kasim\Documents\2tech\2tech\Projects\Reservation.md` |
| **Changelog (tüm deploy'lar)** | `C:\Users\kasim\Documents\2tech\2tech\Projects\Reservation - Changelog.md` |
| **Deploy Runbook** | `C:\Users\kasim\Documents\2tech\2tech\Projects\Reservation - Deploy Runbook.md` |
| **Son Session Report** | `C:\Users\kasim\Documents\2tech\2tech\Projects\Reservation - Session Report 2026-04-18_19.md` |

### 2.4 Claude Oturum Yolları

| Ne | Yol |
|----|-----|
| **Memory dizini** (auto-memory) | `C:\Users\kasim\.claude\projects\E--Project-Restaurant\memory\` |
| **Uploads** (screenshot vb.) | `C:\Users\kasim\AppData\Roaming\Claude\local-agent-mode-sessions\<session-id>\agent\local_ditto_<id>\uploads\` |

### 2.5 Obsidian Senkron Skill

`E:\Project\reservation\.claude\skills\sync-to-obsidian\SKILL.md` — web repo'su için Obsidian'ı güncel tutan skill.

---

## 3. Topoloji — İki Hedef

### 3.1 Production (Hetzner)

| Alan | Değer |
|------|-------|
| Host | `178.104.137.75` |
| Domain'ler | `gastro.2hub.ch`, `reservation.2pos.ch`, custom tenant domain'ler |
| DB | **Docker Postgres** (`reservation_db`, user `reservation_user`) |
| Redis | **Docker** (`gastrocore-redis:6379`, auth'lu) |
| PM2 | app `reservation`, port 3001, 500M max, log `/home/tech/logs/reservation-{out,error}-0.log` |
| Deploy | `python deploy_hetzner.py` |
| Backup | `/home/tech/backups/` altında tar.gz |

### 3.2 Test / Internal (LAN)

| Alan | Değer |
|------|-------|
| Host | `192.168.1.134` (`2techrust`) |
| Domain | `reservation.2pos.ch` (bu host nginx → 127.0.0.1:3001) |
| DB | **Native Postgres 16.13** (`localhost:5432`) |
| Yan Docker | `gastrocore-db:5433`, `gastrocore-redis:6379`, `techhub-minio`, `alpiva-tools` |
| Deploy | `python deploy_test.py` |

**Kritik:** İki DB **tamamen izole**. Test, Hetzner'dan DB çekmiyor.

---

## 4. Data Modeli — Online Siparişe Dokunanlar

**Kaynak:** `prisma/schema.prisma` (632 satır, 20+ model). Tam dökümün POS handoff dışı; burada ordering-relevant modeller.

### 4.1 Enum'lar

| Enum | Değerler |
|------|----------|
| `OrderType` | `TAKEAWAY`, `DELIVERY` |
| `OrderStatus` | `PENDING`, `CONFIRMED`, `PREPARING`, `READY`, `DELIVERED`, `CANCELLED` |
| `PaymentMethod` | `CASH_ON_DELIVERY`, `CASH_ON_PICKUP`, `CARD_ONLINE`, `TWINT` |
| `PaymentStatus` | `UNPAID`, `PAID`, `REFUNDED` |
| `PriceType` | `STANDARD`, `TAKEAWAY`, `DELIVERY` |
| `ExtraType` | `SINGLE` (radio), `MULTI` (checkbox) |
| `LoyaltyTransactionType` | `EARNED`, `REDEEMED` |

### 4.2 Ana modeller

- **`Order`** — sipariş başlığı. `orderNumber` (restoran başına advisory-lock ile serialize), `orderType`, `status`, müşteri bilgileri, `deliveryAddress/City/postalCode`, `subtotal/taxAmount/totalAmount` (Decimal), `discountPercent` (Float), `discountAmount` (Decimal), `deliveryFee`, `paymentMethod/Status`, `stripeSessionId`, `estimatedMinutes`, `scheduledFor`, `customerId?`.
- **`OrderItem`** — sepet kalemi. `productName`, `productId?`, `quantity`, `unitPrice`, `totalPrice`, `priceType`, `extras` Json (`[{optionId,optionName,groupName,price}]`), `note`.
- **`MenuCategory`** — kategori, `sortOrder`, `isActive`.
- **`MenuItem`** — **3 fiyat:** `priceStandard`, `priceTakeaway?`, `priceDelivery?`. `isAvailable`, `isPopular`, `hasVariants`, `allergenInfo` Json.
- **`ProductVariant`** — ürün varyantı (ör. "büyük"), `price` Decimal(10,2).
- **`ExtraGroup`** / **`ExtraOption`** — ekstra seçim grupları (SINGLE/MULTI), category & item junction tabloları.
- **`Customer`** — online sipariş müşterisi. `(email, restaurantId)` unique, `password` (bcrypt varsayımı), totalOrders, totalSpent, segment.
- **`DeliveryZone`** — posta kodu bazlı. `(postalCode, restaurantId)` unique, `deliveryFee`, `minOrderAmount`, `estimatedTime`.
- **`LoyaltyProgram`** / **`LoyaltyAccount`** / **`LoyaltyTransaction`** — sadakat.
- **`ComboMenu`** / **`ComboMenuGroup`** / **`ComboMenuGroupItem`** — kombo/set menü.
- **`MenuUpsellConfig`** / **`MenuUpsellStep`** — "Menü yap?" upsell akışı.
- **`Campaign`** — kampanya + kupon (happy hour dahil, `happyHourStart/End/Days`), `discountType/Value`, `maxUses`.
- **`PushSubscription`** — browser push (VAPID).
- **`GroupOrder`** / **`GroupOrderParticipant`** — link paylaşımlı grup sipariş.
- **`SystemSettings`** — global singleton (SMTP fallback).

### 4.3 `Restaurant`'tan ordering alanları

`orderingEnabled`, `acceptDelivery`, `acceptTakeaway`, `minPrepTimeMinutes`, `maxPrepTimeMinutes`, `onlineHoursMode` (BUSINESS/CUSTOM/SPLIT), `onlineHours/pickupHours/deliveryHours` Json, `autoDiscountEnabled/Percent/Message`, `surpriseMenuEnabled/Budgets`, `preorderEnabled/MaxDays`, `isOnlineOrderEnabled`, `onlinePaymentEnabled`, `stripeAccountId`, `twintMerchantId`, `orderNotificationEmail`, `orderAutoAccept`.

### 4.4 Migration geçmişi (9 tane, son güncellemeye kadar)

1. `20260219063013_init`
2. `20260402000000_add_reservation_enabled`
3. `20260403000000_add_online_ordering`
4. `20260403100000_menu_string_names_extras`
5. `20260407000000_add_is_online_order_enabled`
6. `20260408000000_add_has_variants`
7. `20260408100000_add_product_variant_system_settings`
8. **`20260416000000_add_gastrocore_integration`** — `Restaurant.gastrocoreTenantId` + `gastrocoreApiUrl` (POS köprüsü — §8)
9. **`20260416100000_add_seo_score`** — `Restaurant.seoScore`

### 4.5 Index'ler

Order: `(restaurantId, status)`, `(restaurantId, createdAt)`. Customer: `(email, restaurantId)` unique, `restaurantId`. Campaign: `(restaurantId, code)`. Toplam 17 index (DEVLOG 2026-04-04).

---

## 5. Online Sipariş Flow — Golden Path

```
Müşteri → /[slug]/order (veya customDomain/order → middleware rewrite)
  ├── Menü listele (GET /api/public/[slug]/menu, Redis 5dk cache, key menu:${slug})
  ├── Extra / modifier seç
  ├── Sepet + upsell + combo
  ├── Checkout: müşteri bilgileri, delivery adresi (DELIVERY ise PLZ check)
  │   POST /api/public/[slug]/check-delivery  → zone + fee + minOrder
  └── Ödeme yöntemi: CASH_ON_PICKUP / CASH_ON_DELIVERY / CARD_ONLINE (Stripe TODO) / TWINT
  ↓
POST /api/public/[slug]/order
  ├── zod validate (validators.ts → orderSchema)
  ├── rate limit middleware 5/dk IP + global 100/dk
  ├── advisory_xact_lock ile orderNumber serialize (race guard)
  ├── Order + OrderItem[] create (Decimal subtotal/tax/total)
  ├── publishEvent('new-orders:${restaurantId}', order) → Redis pub/sub
  └── sendOrderCustomer + sendOrderOwner mail
  ↓
SSE /api/orders/stream
  ├── Dashboard /dashboard/orders (OWNER): realtime alarm + queue
  └── Sunmi V2s Flutter POS (mobile/): audio alarm + fiş bas
  ↓
OWNER action: PATCH /api/orders/[id]/status
  ├── PENDING → CONFIRMED (ASAP prep süresi veya scheduledFor saati)
  ├── CONFIRMED → PREPARING → READY → DELIVERED
  └── sendStatusUpdate mail
  ↓
(POS tarafı — şu an manuel): Sipariş POS'ta takeaway/delivery ticket'ı olarak oluşturulmalı — otomatik wire-up YOK, §8.2'ye bak
```

**Teklif / scheduledFor:**
- ASAP: `scheduledFor == null`, Sunmi `_handleAccept` → `showWaitTimePicker` → 15–60 dk → CONFIRMED
- Ön sipariş: `scheduledFor != null` (Lieferzeit / Abholzeit), Sunmi `_showScheduledConfirmDialog` → saat göster, süre sorma (fix 2026-04-17)

**Delivery zone:** `POST /api/public/[slug]/check-delivery` with `{postalCode}` → `DeliveryZone` (postalCode + restaurantId unique).

---

## 6. API Endpoint'leri — Online Siparişe Dokunanlar

### Public (`/api/public/[slug]/*`)

| Method | Endpoint | Açıklama |
|--------|----------|----------|
| GET | `/api/public/[slug]` | Restoran bilgileri (CDN-normalize) |
| GET | `/api/public/[slug]/menu` | Public menü (kategori, item, extras, variant). Redis 5dk TTL |
| GET | `/api/public/[slug]/combos` | Kombo menüler |
| GET | `/api/public/[slug]/menu-upsell` | Upsell config |
| POST | `/api/public/[slug]/order` | **Sipariş oluştur** (5/dk IP limit) |
| GET | `/api/public/[slug]/order/[orderId]` | Sipariş detay |
| POST | `/api/public/[slug]/order/[orderId]/payment` | Ödeme (**TODO Stripe**) |
| PATCH | `/api/public/[slug]/order/[orderId]/status` | Müşteri statü çek |
| GET | `/api/public/[slug]/delivery-zones` | Zone listesi |
| POST | `/api/public/[slug]/check-delivery` | PLZ teslim edilebilirlik |
| GET | `/api/public/[slug]/campaigns/active` | Aktif kampanyalar |
| POST | `/api/public/[slug]/campaigns/apply` | Kupon uygula |
| POST | `/api/public/[slug]/push/subscribe` | Web push abone |
| GET | `/api/public/[slug]/surprise` | Sürpriz menü |
| — | `/api/public/[slug]/auth/{login,register,me,last-order}` | Customer auth (CUSTOMER_JWT_SECRET) |
| — | `/api/public/[slug]/loyalty/account` | Müşteri sadakat |
| — | `/api/public/[slug]/group-order/[code]` | Grup sipariş share link |

### Sipariş yönetimi (OWNER/ADMIN)

| Method | Endpoint | Açıklama |
|--------|----------|----------|
| GET | `/api/orders` | Scope'lu sipariş listesi |
| PATCH | `/api/orders/[id]/status` | Durum güncelle |
| GET | `/api/orders/[id]/estimate` | Teslim süresi tahmini |
| GET | `/api/orders/stream` | **SSE** — dashboard + Sunmi mobile dinliyor |
| GET | `/api/orders/stats` | Günlük/haftalık/aylık |

### Menü / ekstra / zone

`/api/menu/{categories,items,variants,import}`, `/api/extras`, `/api/extras/[id]/{assign-category,assign-item}`, `/api/delivery-zones[/id][/bulk]`.

### Upload / health

`/api/upload` (R2), `/api/admin/upload`, `/api/health` (DB + Redis + latency), `/api/smtp-test`.

### Mobile (Sunmi)

`POST /api/auth/mobile/login` → Bearer token.

---

## 7. Sunmi V2s Flutter POS — Bestellung App (MOBILE/)

**Kaynak:** `E:\Project\reservation\mobile\`
**Cihaz:** Sunmi V2s (termal yazıcı + Android)
**Build:** `flutter build apk --release` → `mobile/build/app/outputs/flutter-apk/app-release.apk`
**Script:** `mobile/build_apk.bat`

### İletişim
- **Login:** `POST /api/auth/mobile/login` → Bearer token, `shared_preferences`'ta persist
- **Realtime:** `GET /api/orders/stream` (SSE, auto-reconnect, 15s polling yedek)
- **Status patch:** `PATCH /api/orders/[id]/status`
- **Sağlık:** `GET /api/health`

### Bağımlılıklar
`http`, `shared_preferences`, `audioplayers`, `sunmi_printer_plus` (termal), `connectivity_plus`, `wakelock_plus`, `vibration`.

### Dosya yapısı
```
mobile/lib/
├── main.dart                  — MaterialApp + WakelockPlus
├── config.dart                — API base URL
├── models/order.dart          — Order + OrderItem (scheduledFor dahil)
├── screens/
│   ├── login.dart
│   └── orders.dart            — 3 sekme: Neu / In Arbeit / Erledigt
├── services/
│   ├── api.dart               — HTTP Bearer
│   ├── printer.dart           — sunmi_printer_plus
│   ├── sse.dart               — SSE reconnect
│   └── sound.dart             — 13 alarm sesi yönetimi
└── widgets/
    ├── order_card.dart
    ├── order_detail.dart
    └── time_picker.dart
assets/audio/*.wav             — 13 alarm
```

### Sipariş kabul akışı (Lieferzeit fix 2026-04-17)
- **ASAP** (`scheduledFor == null`) → `_handleAccept` → `showWaitTimePicker` (15-60 dk) → CONFIRMED + fiş
- **Ön sipariş** (`scheduledFor != null`) → `_showScheduledConfirmDialog` (saati göster, süre SORMA) → CONFIRMED + fiş

### Lieferzeit görünümü
- Kart: 📅 ikonu + "Lieferzeit: 19:20 Uhr" (mor)
- Detay başlık: `scheduledFor` → gerçek saat (mor) / yoksa "Schnellstmöglich"
- Kabul dialog: saat onay ekranı açılır

### Diğer istemciler
- `mobile_mypos/` — MyPOS cihaz varyantı
- `reservation-tablet/` — tablet paketi
- **Aktif olan hangisi?** Sor — net değil.

### ADB kurulum
```bash
cd E:\Project\reservation\mobile
flutter build apk --release
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

> 💡 Windows'ta Dart dosyası yazarken bash heredoc yerine Python kullan (CLAUDE.md'de uyarı).

---

## 8. POS (GastroCore) Entegrasyonu — Mevcut ve Gelecek

### 8.1 Mevcut (başlamış — migration 8, 2026-04-16)

**Schema alanları (Restaurant modeline eklendi):**
```prisma
gastrocoreTenantId    String?     // örn. "pilot-zurich-001"
gastrocoreApiUrl      String?     // POS GastroCore Go backend endpoint
```

**Env değişkenleri (`.env.production.hetzner`):**
```env
GASTROCORE_API_URL       # POS backend REST
GASTROCORE_WS_URL        # POS websocket (sipariş event push?)
GASTROCORE_INTERNAL_SECRET  # HMAC shared secret (POS ↔ web)
```

**Proxy route:** `/api/gastrocore/[...path]` eklenmiş **olabilir** — **doğrula:**
```
Read: E:\Project\reservation\src\app\api\gastrocore\
```
Yoksa eklenecek; varsa wire-up'ı tamamla.

### 8.2 Hedef: online sipariş → POS ticket

Şu an online sipariş POS'ta **otomatik ticket yaratmıyor**. Manuel mapping:

| Online field | POS eşdeğeri |
|--------------|--------------|
| `Order.orderType = DELIVERY` | POS `OrderType.delivery` |
| `Order.orderType = TAKEAWAY` | POS `OrderType.takeaway` |
| `OrderItem[]` | POS ticket item'ları |
| `OrderItem.extras` (Json) | POS modifier seçimleri |
| `Order.customerId` | POS `Customer` entity (email eşleşme) |
| `Order.paymentStatus = PAID` | POS ticket `status: paid`, payment tender kaydı |
| `Order.scheduledFor` | POS ticket'ta notlar / ön sipariş alanı |

**Gereken (POS tarafında):**
- POS'a REST API / webhook endpoint'leri (şu an yok)
- `OnlineOrderEntity` POS tarafında — online sipariş sistemiyle web siparişi arasındaki köprü
- POS'ta `AuditAction.onlineOrderReceived/Accepted/Fulfilled/Cancelled`
- POS tarafında kitchen dispatch (gang) online için de etkin

### 8.3 POS ↔ web arası karar matrisi

| Soru | Olasılık A | Olasılık B |
|------|-----------|-----------|
| Sipariş senkronu nasıl? | Web push POS'a (webhook) | POS pull web'den (polling) |
| Ödeme provider | Wallee **paylaşımlı** — tek reconciliation | Stripe **ayrı** — günlük reconciliation job |
| Menü source-of-truth | **POS** (web okur) | **Web** (POS okur) |
| Customer source-of-truth | **Email anahtar**, her iki taraf kendi kaydı + link | **Merkezi** CRM |
| Audit | POS audit table (canonical) | Web ayrı log |

**Önerilen default (kullanıcı onayıyla):**
- Web → POS push (webhook, HMAC imzalı, DLQ backed)
- Ödeme **Wallee paylaşımlı**
- Menü **POS canonical**, web cache
- Customer email anahtar, iki tarafta ayrı kayıt, link
- Audit POS canonical, web push

---

## 9. Middleware & Custom Domain Routing

**Kaynak:** `src/middleware.ts` (207 satır)

### 9.1 Boru hattı
1. **Rate limit:** auth/login 10/dk, order POST 5/dk, genel 100/dk. In-memory `Map`, 60s cleanup. **Cluster-safe değil.**
2. **Internal host check:** `["localhost","127.0.0.1","reservation.2pos.ch","gastro.2hub.ch","2hub.ch"]`
3. **Custom domain rewrite:** `hostname` → `getSlugForDomain()` (5dk cache fetch to `${NEXT_PUBLIC_BASE_URL}/api/restaurants?customDomain=X`).
   - `/` → root self
   - `/order`, `/order/...` → `/[slug]/order...`
   - `/daily-menu`, `/datenschutz`, `/impressum` → `/website/[slug]/...`
   - Diğer → `/order` redirect fallback
4. **Auth guard** (`/dashboard`, `/admin`): `auth-token` cookie / `Bearer` header → `jose verify` → role check. `/admin` = ADMIN only, `/dashboard` = OWNER|ADMIN.
5. **matcher:** `/dashboard/:path*`, `/admin/:path*`, `(?!api|_next|static|uploads|favicon\\.ico).*`.

### 9.2 Tuzaklar
- `NEXT_PUBLIC_BASE_URL` yanlış → domain resolver fetch çöker → custom domain sessizce fail.
- Rate limit cluster-safe değil (PM2 multi-worker'da worker başına Map).
- Domain cache TTL 5dk — yeni custom domain atandığında gecikme.
- `www.` otomatik strip.

---

## 10. Ödeme Entegrasyonu — Mevcut Durum

| Yöntem | Durum |
|--------|-------|
| `CASH_ON_PICKUP`, `CASH_ON_DELIVERY` | ✅ Çalışıyor |
| `CARD_ONLINE` (Stripe Connect) | ⚠️ **TODO:** `src/app/api/public/[slug]/order/[orderId]/payment/route.ts:56` — şema alanları var (`stripeAccountId`, `stripeSessionId`), kod TODO |
| `TWINT` | ⚠️ `twintMerchantId` alan hazır, entegrasyon **TBD** |

**Stripe ekleme planı (`payment/route.ts:56`):**
1. Stripe Connect (`stripeAccountId` per restaurant)
2. Create checkout session
3. Webhook: `/api/stripe/webhook` → ödeme succeeded → Order.paymentStatus = PAID → publishEvent

---

## 11. Cache & Realtime (Redis + SSE)

**Kaynak:** `src/lib/cache.ts` (93 satır)

- Redis yoksa **no-op** sessiz (opsiyonel sistem).
- Default TTL: **300s** (menü cache).
- `publishEvent('new-orders:${restaurantId}', data)` — sipariş oluştuğunda.
- `/api/orders/stream` — SSE route, `createSubscriber()` ile bağlantı açar, client disconnect'te cleanup.
- Dashboard (`/dashboard/orders`) + Sunmi mobile Flutter dinler. Yeni sipariş → alarm + termal fiş.

---

## 12. Entegrasyonlar

| Servis | Amaç | Konfig |
|--------|------|--------|
| **Cloudflare R2** | Tüm görseller. Bucket `gastrocore`, CDN `https://cdn.2hub.ch` | `S3_ENDPOINT/ACCESS_KEY/SECRET_KEY/BUCKET/PUBLIC_URL` → `src/lib/s3.ts` |
| **PostgreSQL** | Ana DB | `DATABASE_URL` |
| **Redis (ioredis)** | Menü cache 5dk + SSE pub/sub | `REDIS_URL` → `src/lib/cache.ts` |
| **SMTP (nodemailer)** | Sipariş + rezervasyon mail | `SMTP_HOST/PORT/USER/PASS/FROM`; 2026 pilotta `mail.2pos.ch` (reservation@ + order@ iki account) → `src/lib/email.ts` + `order-email.ts`. Fallback: `SystemSettings` DB. |
| **Web Push (VAPID)** | Browser push | `VAPID_PUBLIC_KEY/PRIVATE_KEY/SUBJECT` |
| **Stripe** | CARD_ONLINE | **Tam bağlı değil** — payment route'da TODO |
| **TWINT** | CH mobile | `twintMerchantId` alan hazır; integration TBD |
| **Sunmi V2s POS** | Termal fiş + alarm | Flutter `mobile/` Bearer + SSE |
| **PM2** | Process manager | `ecosystem.hetzner.config.js` — port 3001, 500M |
| **Nginx** | Reverse proxy + SSL + custom domain | `nginx/*.conf` |
| **GastroCore (POS)** | Köprü — migration 8 | `GASTROCORE_API_URL/WS_URL/INTERNAL_SECRET` |

---

## 13. Environment Değişkenleri (Kritik)

```env
# === Core ===
DATABASE_URL
JWT_SECRET                  # OWNER/ADMIN (jose, HS256, 7d)
CUSTOMER_JWT_SECRET         # Customer (jsonwebtoken) — ayrı!
NEXT_PUBLIC_BASE_URL        # örn https://gastro.2hub.ch
PORT                        # 3001 PM2 override

# === Redis ===
REDIS_URL                   # ioredis, auth: VeiroHjoE... (prod)

# === SMTP ===
SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS, SMTP_FROM
# Prod: mail.2pos.ch, reservation@/order@ ayrı account

# === R2 ===
S3_ENDPOINT, S3_ACCESS_KEY, S3_SECRET_KEY, S3_BUCKET, S3_PUBLIC_URL

# === Push (VAPID) ===
VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, VAPID_SUBJECT

# === GastroCore (POS köprüsü) ===
GASTROCORE_API_URL
GASTROCORE_WS_URL
GASTROCORE_INTERNAL_SECRET
```

Test için `.env.production.test`, prod için `.env.production.hetzner` — deploy scripti **dosya yoksa abort**, fallback yok.

---

## 14. Deploy — Detay

Runbook tam: `C:\Users\kasim\Documents\2tech\2tech\Projects\Reservation - Deploy Runbook.md`.

### 14.1 Prod (Hetzner)

```bash
cd E:\Project\reservation
rm -rf .next && npm run build
ls .next/standalone/server.js   # VAR olmalı

python deploy_hetzner.py
# Alternatif: python deploy_hetzner_tar.py (optimize)
```

Script akışı:
1. `.next/standalone` + `public` + `prisma` + `package.json` + `ecosystem.hetzner.config.js` tar'lar
2. SFTP → `/home/tech/reservation/`
3. SSH → `npx prisma migrate deploy` + `pm2 restart reservation`
4. `pm2 logs reservation --lines 50`

### 14.2 Test (LAN)

```bash
cd E:\Project\reservation
rm -rf .next && npm run build
python deploy_test.py
```

Script:
1. `/home/tech/backups/` altına tar.gz snapshot
2. `.next/standalone` + `.next/static` + `public/` + `prisma/` + `node_modules/{.prisma,@prisma}` + `.env.production.test` → `/home/tech/reservation_standalone/`
3. `npx prisma@6.19.2 generate && migrate deploy`
4. `pm2 stop/delete && pm2 start ecosystem.config.js && pm2 save`
5. `curl http://localhost:3001/ + pm2 logs --lines 10`

### 14.3 Promote (Test → Prod)

1. Test smoke OK (PM2 online, HTTP 200, Prisma auth temiz, feature doğru)
2. Kullanıcı onayı
3. Prod backup: `ssh tech@178.104.137.75 "tar czf /home/tech/backups/reservation_standalone_pre_<slug>_$(date +%Y%m%d_%H%M%S).tar.gz ..."`
4. DB migration varsa test'te uygulananla aynısını prod'a + snapshot
5. `python deploy_hetzner.py`
6. Prod smoke: `curl https://gastro.2hub.ch/aspendos/order` (200), `/api/public/<slug>` primaryColor/flag, PM2 logs
7. Changelog entry → Obsidian + `/dashboard/wiki/release-notes` (şu an hardcoded)
8. Rollback: prod tar.gz + DB snapshot hazır mı

### 14.4 Smoke komutları

```bash
# Prod
curl -I https://gastro.2hub.ch/aspendos/order
curl -I https://gastro.2hub.ch/demo-restaurant/order
curl -s https://gastro.2hub.ch/api/public/aspendos | grep -oE '"primaryColor":"#[0-9a-fA-F]+"'

# Test (LAN)
curl -I http://192.168.1.134:3001/aspendos/order

# Log tarama (test)
ssh tech@192.168.1.134 "pm2 logs reservation --lines 30 --nostream --err" \
  | grep -vE '(Server Action "x"|Redis.*default.*password)'
# "Failed to find Server Action" = eski client bundle cache, deploy sonrası geçici, normal
```

---

## 15. i18n

**Kaynak:** `src/lib/i18n.ts` (public), `src/lib/dashboard-i18n.ts` (dashboard)
- Diller: `de` (default), `fr`, `en`, `it`
- `Restaurant.language` alanı her tenant için
- Helper: `t(lang, key)`, `getDateLocale(lang)` (de-CH/fr-CH/en-US/it-CH), `getStatusLabel`, `getStatusColor`
- JSON i18n alanları: `tagline`, `aboutText`, `allergenInfo`, `menuData.*.category`, `menuData.*.items.*.name/description`, `GalleryImage.caption` — hepsi `Record<lang, string>`

**Yeni dil eklemek için:**
1. `src/lib/i18n.ts` → `Lang` type + `LANGUAGE_OPTIONS` + tüm çeviri nesnesi + `getDateLocale()`
2. `src/lib/dashboard-i18n.ts` aynı şekilde
3. Email template'leri i18n key kullanıyor, otomatik
4. Website JSON alanları (`tagline`, `aboutText`) restoran admin'leri manuel ekler

---

## 16. Güvenlik & Bilinen Riskler

### ✅ Mevcut korumalar
- Rate limiting (auth 10/dk, order 5/dk, genel 100/dk)
- In-memory Map 60s cleanup (memory leak önlendi)
- JWT secret env-only, prod Secure cookie
- Customer token email çıkarıldı (DEVLOG)
- CSS injection: `primaryColor` regex validate (`website/[slug]/page.tsx`)
- JSON-LD XSS: `</script>` → `<\/script>` escape
- `orderNumber` race condition: `prisma.$transaction` + `pg_advisory_xact_lock`
- OWNER scope filter: dashboard endpoint'lerinde `where: { restaurantId: session.restaurantId }`
- Delivery zone duplicate query kaldırıldı (DEVLOG)

### ⚠️ Riskler
- **Rate limiter cluster-safe değil** — Redis'e taşınmalı (`src/lib/cache.ts` zaten var, INCR+EXPIRE pattern)
- **CUSTOMER_JWT_SECRET** eksikse customer login sessizce çöker (`auth.ts:81`)
- **`TODO: Stripe entegrasyonu`** — payment endpoint production-ready değil (`payment/route.ts:56`)
- **Newsletter backend yok** — sadece UI (`website-newsletter.tsx:27` TODO)
- **Customer şifre alan adı `password`** — bcrypt varsayımı, alan adı hash ima etmiyor; doğrula
- **Decimal/Float karışımı** — `subtotal/tax/total` Decimal, `discountPercent/autoDiscountPercent` Float; hesaplamada dikkat

---

## 17. Teknik Borç & TODO

| Yer | TODO |
|-----|------|
| `src/app/api/public/[slug]/order/[orderId]/payment/route.ts:56` | **Stripe entegrasyonu** |
| `src/app/website/[slug]/components/website-newsletter.tsx:27` | E-posta servisi |
| PM2 cluster tutarsızlığı | Eski notlar 4 worker, mevcut `ecosystem.hetzner.config.js` tek worker/500M — doğrula |
| `scripts/` altında 54 Python | one-off `check_*`, `fix_*` — temizlenmeli |
| `mobile_mypos/`, `reservation-tablet/` | Aktif mi belirsiz — sor |
| `md/` klasörü | İçerik araştır, güncel doküman taşı |
| Campaign.discountType | String (enum değil) — legacy değerler olabilir |
| Customer.password alan adı | Hash mi? doğrula |
| `md/DEPLOY_PLAN.md:9` | "Test DB: SSH tunnel Hetzner localhost:5433" yazıyor; artık native Postgres — **stale** |
| `NEXT_PUBLIC_BASE_URL` test env'inde `gastro.2hub.ch` | Canonical link'ler prod'a işaret — smoke karışıklığı riski |
| `dashboard/wiki/release-notes` | Hardcoded array, her entry build+deploy — F5 skill planlı |

---

## 18. Güncelleme Haritası — "X'i değiştirmek istersen..."

### 🔸 Sipariş akışı / ödeme yöntemi
1. Oku: `.claude/docs/05-order.md`
2. Form: `src/app/(public)/[slug]/order/page.tsx`
3. API: `src/app/api/public/[slug]/order/route.ts`
4. Status güncelleme: `src/app/api/orders/[id]/status/route.ts`
5. SSE: `src/app/api/orders/stream/route.ts` + `src/lib/cache.ts`
6. Stripe ekle: `payment/route.ts:56` TODO'dan başla

### 🔸 Menü yapısı (yeni fiyat tipi / variant şekli)
1. Şema: `prisma/schema.prisma` (`MenuItem`, `ProductVariant`, `PriceType`)
2. Migration
3. API: `src/app/api/menu/{categories,items,variants}/route.ts`
4. Public API: `src/app/api/public/[slug]/menu/route.ts` (`normalizeImageUrl`!)
5. Dashboard UI: `src/app/dashboard/menu/page.tsx`
6. Public UI: `src/app/(public)/[slug]/order/page.tsx`

### 🔸 Custom domain ekleme
1. DB: `Restaurant.customDomain` (dashboard → settings)
2. Nginx: `nginx/<domain>.conf` vhost + SSL
3. DNS: domain → `178.104.137.75`
4. Cache: `getSlugForDomain` 5dk sonra çözer
5. **`INTERNAL_HOSTS`'a ekleme** (internal olsaydı); müşteri domain'i olduğu için eklenmez

### 🔸 E-posta şablonu
1. Template: `src/lib/email-templates/*.ts`
2. Sender: `src/lib/email.ts` veya `order-email.ts`
3. i18n key'leri 4 dile de ekle
4. Test: `/api/smtp-test`
5. SMTP fallback: `/admin/settings` → `SystemSettings`

### 🔸 Rate limit Redis'e taşıma
1. `src/middleware.ts:12-32` + `src/app/api/public/[slug]/reserve/route.ts:11`
2. `src/lib/cache.ts` zaten Redis — `INCR` + `EXPIRE`
3. Cluster-safe olunca middleware `setInterval` cleanup kaldır

### 🔸 Yeni dil ekleme
Bkz. §15.

---

## 19. Sormadan Dokunma / Bozma

- `orderNumber` advisory lock (`pg_advisory_xact_lock`) — race condition koruması
- Middleware `domainCache` Map referansı
- `TAX_RATE = 0.026` — İsviçre KDV, yasal sabit (`src/lib/constants.ts:2`)
- `normalizeImageUrl()` — menu + restaurant + website API çağrıları; kaldırılırsa `/uploads/` path'leri 404
- `INTERNAL_HOSTS` listesi (`middleware.ts:85`) — prod DNS yönlendirmesi bozulur

---

## 20. Yeni Claude İçin "İlk Adımlar"

1. **Bu dosyayı okudun.** İyi.
2. **Kardeş dosyalar (sıra ile):**
   - `E:\Project\Restaurant\pilot\DEVELOPER_RESERVATION.md` (rezervasyon — aynı repo)
   - `E:\Project\Restaurant\pilot\DEVELOPER_RESTAURANT.md` (POS — ayrı monorepo)
3. **Obsidian notları:**
   ```
   Read: C:\Users\kasim\Documents\2tech\2tech\Projects\Reservation.md
   Read: C:\Users\kasim\Documents\2tech\2tech\Projects\Reservation - Changelog.md
   Read: C:\Users\kasim\Documents\2tech\2tech\Projects\Reservation - Deploy Runbook.md
   Read: C:\Users\kasim\Documents\2tech\2tech\Projects\Reservation - Session Report 2026-04-18_19.md
   ```
4. **Repo:** `cd E:/Project/reservation`
5. **Repo içi okuma sırası:**
   ```
   Read: E:\Project\reservation\CLAUDE.md                           # modüler doküman indeksi
   Read: E:\Project\reservation\DEVLOG.md                           # kararlar + kronoloji
   Read: E:\Project\reservation\.claude\docs\01-database.md
   Read: E:\Project\reservation\.claude\docs\05-order.md            # ordering branch
   Read: E:\Project\reservation\.claude\docs\13-cdn-storage.md
   Read: E:\Project\reservation\prisma\schema.prisma                # 632 satır
   Read: E:\Project\reservation\src\middleware.ts                   # rate limit + domain + JWT
   Read: E:\Project\reservation\src\lib\{auth,cache,s3,validators,constants}.ts
   Read: E:\Project\reservation\src\app\api\public\[slug]\order\route.ts
   Read: E:\Project\reservation\src\app\api\orders\stream\route.ts
   Read: E:\Project\reservation\src\app\(public)\[slug]\order\page.tsx
   ```
6. **Ortamı hazırla:**
   ```bash
   npm install
   npx prisma generate
   npm run dev
   ```
7. **Sunmi POS dokunacaksan:**
   ```
   Read: E:\Project\reservation\mobile\lib\main.dart
   Read: E:\Project\reservation\mobile\lib\screens\orders.dart
   Read: E:\Project\reservation\MOBILE_APP_SPEC.md
   ```
8. **Deploy kuralı:** önce `python deploy_test.py` (LAN) → smoke → kullanıcı onayı → `python deploy_hetzner.py` (canlı).

### Sık tuzaklar
- **Git YOK:** `git log/diff` çalışmaz. Yerel değişiklik = canonical.
- **Rate limit in-memory:** Dev'de limit'e takılırsan PM2/process restart.
- **Dev server açıkken `npm run build`:** `.next/standalone` overwrite → deploy bozulur. Build öncesi dev'i durdur.
- **`.env.production.*` dosyaları:** secret dolu, yanlış hedefe = Prisma auth error + PM2 crash.
- **Windows'ta Dart dosyası:** bash heredoc yerine Python kullan.
- **Redis no-auth warning:** uyarı, zararsız.
- **"Failed to find Server Action":** eski client cache, deploy sonrası 1-2 dk sürer, normal.

---

## 21. Dosya Referansı Hızlı Kart

| İş | Dosya |
|----|-------|
| Global prisma singleton | `src/lib/prisma.ts` |
| OWNER/ADMIN JWT | `src/lib/auth.ts` (signToken, verifyToken, getSession) |
| Customer JWT | `src/lib/auth.ts` (getCustomerIdFromRequest, `CUSTOMER_JWT_SECRET`) |
| Rate limit | `src/middleware.ts:12-110` + `src/app/api/public/[slug]/reserve/route.ts:11` |
| Custom domain rewrite | `src/middleware.ts:53-155` |
| Redis client | `src/lib/cache.ts` |
| SSE channel | `new-orders:${restaurantId}` |
| R2/S3 upload | `src/lib/s3.ts` |
| Image URL normalize | `src/lib/image.ts` |
| Slot generation | `src/lib/slots.ts` |
| Working hours normalize | `src/lib/constants.ts:60` |
| Zod şemaları | `src/lib/validators.ts` |
| Tax rate | `src/lib/constants.ts:2` (TAX_RATE = 0.026) |
| SMTP sender | `src/lib/email.ts`, `order-email.ts` |
| i18n public | `src/lib/i18n.ts` |
| i18n dashboard | `src/lib/dashboard-i18n.ts` |
| SEO | `src/lib/seo/{metadata,schema,image}.ts` |
| Prisma schema | `prisma/schema.prisma` |
| PM2 config | `ecosystem.hetzner.config.js` |
| Next config | `next.config.ts` |
| Dockerfile | `Dockerfile` |
| Nginx | `nginx/*.conf` |
| Brand tokens (desktop) | `src/lib/brand-tokens.ts` |
| Desktop hero/category/card | `src/components/order/desktop/*` |

---

## 22. Koordinat — 3 Dosyalı Ekosistem

Bu dosya **online sipariş tarafı**. İlgili dosyalar:

| Dosya | Kapsam |
|-------|--------|
| `E:\Project\Restaurant\pilot\DEVELOPER_RESTAURANT.md` | **POS (GastroCore)** — Flutter, jolly-final worktree, pilot APK |
| `E:\Project\Restaurant\pilot\DEVELOPER_GASTRO2HUB.md` | **Online sipariş** — Next.js, `E:\Project\reservation\`, bu dosya |
| `E:\Project\Restaurant\pilot\DEVELOPER_RESERVATION.md` | **Rezervasyon** — Next.js, aynı repo `E:\Project\reservation\` |

**Not:** Online sipariş ve rezervasyon şu an **tek Next.js uygulaması** (ortak Prisma, middleware, auth, deploy, repo, PM2 process). Kullanıcı bunları **mantıksal olarak ayrı ürün** olarak konumlandırıyor. Ayrı repo'ya split kararı şu an yok; mevcut birleşik yapı korunmakta.

---

**Son güncelleme:** 2026-04-24. Mevcut canlı sistem temel alındı. Schema değiştirilirse §4, endpoint eklenirse §6, entegrasyon wire-up tamamlandığında §8 güncellenmeli.


---

## §M5 Cloud-Master Menu Sync — TAŞINDI

> **Güncellendi: 2026-04-29 (yeniden hedefleme).** Bu bölümün gastro2hub
> tarafındaki implementasyonu **revert edildi**. Cloud-master menü kayıt
> kaynağı artık **`api.2hub.ch` (Go backend, `Restaurant/server`)**.
> gastro2hub artık menü-sync için ne yazıcı ne okuyucu — eklenen tüm
> dosyalar (admin/menu sayfaları, `/api/menu/{snapshot,version,publish,api-key}/`
> route'ları, `lib/menu-snapshot.ts`, `lib/pos-api-key.ts`,
> `lib/tenant-scope.ts`, MenuVersion modeli, MenuCategory.color/iconEmoji
> alanları, "POS'a Yayınla" butonu, /admin/menu sidebar linki) kaldırıldı
> veya 410 Gone stub'larına dönüştürüldü.
>
> POS'un yeni hedefi:
> `https://api.2hub.ch/api/v1/menu/{version|snapshot|publish}/:tenantId`.
> Kontrat şekli (CONTRACT.md, schemaVersion 1) aynı — dosya
> `Restaurant/server/docs/menu-sync/CONTRACT.md`'ye taşındı,
> tek değişen URL prefix'i ve auth tarafı.
>
> `Restaurant.gastrocoreApiUrl` alanı schema'da kalıyor; içerik artık
> POS Go backend URL'i (`https://api.2hub.ch`) için kullanılıyor —
> menü-sync hedef noktası buradan okunabilir.
>
> **Yeni Next.js backoffice (admin paneli)** — `apps/backoffice/` altında
> pilot için ayağa kaldırıldı. Handoff: [`pilot/DEVELOPER_BACKOFFICE.md`](DEVELOPER_BACKOFFICE.md).
> Backoffice api.2hub.ch'in tüm endpoint'lerini tüketiyor (auth, menu CRUD,
> orders, dashboard, reports, HQ aggregate). Bu repo (gastro2hub) **yalnızca rezervasyon ve online
> ordering bileşenlerini** barındırıyor; menü ne yazılır, ne okunur.
>
> **Why moved:** Go backend zaten POS'un offline-first sync mekanizması
> için authoritative — menü-sync'in onunla aynı yerde olması JWT/auth/
> WebSocket altyapısının tekrar inşasını engelledi. gastro2hub'a ikinci
> bir menü authority'si koymak çift kaynak doğuracaktı.
>
> Aşağıda korunan eski metin **tarihsel referans** içindir; canlı kod
> bu davranışın hiçbirini barındırmıyor.

### Eski endpoint hattının durumu (revert sonrası)

`/api/menu/{snapshot|version|publish|api-key}/[tenantId]/route.ts` ve
`/api/admin/menu-sync/tenants/route.ts` dosyaları 410 Gone döndüren
neutral stub'lara dönüştürüldü. Var olan `/api/menu/categories`,
`/api/menu/items`, `/api/extras` route'ları **owner-only** davranışına
geri çevrildi (admin restaurantId body alanı ve `tenant-scope.ts`
yardımcısı kaldırıldı). Mevcut kategori/ürün/extra CRUD'u —
rezervasyon + online ordering tarafı için — aynen çalışıyor.

---

### TARİHSEL: gastro2hub menu-sync (artık geçersiz)

> Eklendi: 2026-04-29. gastro2hub menü için tek kayıt kaynağıdır;
> POS clientları yayınlanmış snapshot'ı çeker. İlgili kod
> `src/lib/menu-snapshot.ts`, `src/lib/pos-api-key.ts`, ve
> `src/app/api/menu/{snapshot,publish,version,api-key}/[tenantId]/`.

### Prisma değişiklikleri (migration `20260429000000_add_menu_version_and_color`)

```
Restaurant
  + posApiKey         String? @unique         -- bcrypt hash (prod) veya plaintext (dev)
  + menuVersionCurrent Int    @default(0)     -- aktif yayınlanmış sürüm

MenuCategory
  + color     String?                          -- hex #RRGGBB, POS tile rengi
  + iconEmoji String?                          -- POS tile emoji

MenuVersion (yeni model)
  id           cuid
  restaurantId FK Restaurant
  version      int           -- @@unique([restaurantId, version])
  snapshot     Json          -- contract'a uygun envelope (CONTRACT.md)
  publishedAt  DateTime
  publishedBy  String?       -- user id
```

### Endpoint'ler

| Method | Yol                                  | Auth         | İşlev |
|--------|--------------------------------------|--------------|-------|
| GET    | `/api/menu/version/:tenantId`        | API key      | Lightweight — sürüm + tarih |
| GET    | `/api/menu/snapshot/:tenantId?since=N` | API key    | Fu