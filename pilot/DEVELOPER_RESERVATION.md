# Reservation System — Developer Handoff (Masa Rezervasyonu — Ayrı Proje)

> **Hedef okuyucu:** Projeye yeni giren bir Claude oturumu veya developer.
> Bu dosya **self-contained**'dir; başka bir dosya okumadan rezervasyon sisteminde üretken olabilmeniz için yeterli bağlam verir.
>
> **Tarih:** 2026-04-24
>
> **ÖNEMLİ — Kapsam netliği:**
> Kullanıcı kararı ile: **rezervasyon**, **online sipariş (gastro.2hub.ch)** ve **POS (GastroCore)** ÜÇ AYRI ÜRÜN olarak ele alınıyor. Fakat kodda ŞU AN rezervasyon + online sipariş **birleşik bir Next.js uygulamasında** (`E:\Project\reservation\`) — iki domain ile yayında:
> - `gastro.2hub.ch` (online sipariş odaklı)
> - `reservation.2pos.ch` (rezervasyon + kardeş subdomain)
>
> Bu dosya rezervasyon modülünü tek başına anlatır. Online sipariş için bkz. `DEVELOPER_GASTRO2HUB.md`. POS için bkz. `DEVELOPER_RESTAURANT.md`.

---

## 0. TL;DR — İlk 60 Saniye

Rezervasyon modülü **zaten canlı**: Next.js 15 + Prisma 6 + Postgres + Redis, Hetzner `178.104.137.75`, PM2 app `reservation` port **3001**, domain **`reservation.2pos.ch`** (ikincil) + tenant custom domain'ler.

```bash
# 1. Ana repo
cd E:/Project/reservation

# 2. Bağımlılıklar
npm install
npx prisma generate

# 3. Dev server
npm run dev           # localhost:3000 (prod 3001)

# 4. Prisma
npx prisma migrate dev        # dev'de yeni migration
npx prisma studio             # görsel DB

# 5. Deploy (git YOK — SFTP/tar tabanlı)
python deploy_test.py          # önce test'e (LAN 192.168.1.134)
# kullanıcı onayı
python deploy_hetzner.py       # sonra canlıya
```

**Üç altın kural:**
1. **Git YOK.** Repo versiyon kontrolsüz. Deploy = `.next/standalone` + `public/` + `prisma/` + env → SFTP+tar → PM2 restart. Lokal build canonik.
2. **Yeni iş önce TEST'e, sonra canlıya.** 2026-04-19'dan itibaren zorunlu. Test: `192.168.1.134` LAN. Canlı: Hetzner `178.104.137.75`. İki script kasten ayrı.
3. **Hetzner'e dokunmak kısıtlı.** Deploy script'i dışında SSH bile yasak (bazı oturumlarda) — sadece public HTTP smoke.

---

## 1. Proje Kimliği

- **Ürün:** Çok-kiracılı masa rezervasyon sistemi — bir Next.js uygulaması, her restoran kendi slug'ı (`reservation.2pos.ch/pizzeria-palazzo`) veya custom domain'iyle yayında.
- **Mevcut repo:** `E:\Project\reservation\` (aynı repo hem rezervasyon hem online sipariş barındırıyor).
- **Primary domain (rezervasyon odaklı):** `reservation.2pos.ch`
- **Teknoloji:** Next.js 15 (App Router, RSC, standalone) / React 19 / TypeScript strict / Prisma 6.19.2 / PostgreSQL / Redis (ioredis) / Cloudflare R2 / nodemailer SMTP.
- **Process:** PM2, app adı `reservation`, port **3001**, max-memory restart 500M, log `/home/tech/logs/reservation-{out,error}-0.log`.
- **Dil:** DE default + FR + EN + IT. TR rezervasyon tarafında henüz yok (POS'ta eklendi — bkz. POS handoff `d855d00`).
- **Pazar:** İsviçre (CH DSG + MWST 2.6%).
- **Durum:** 🟢 Production (çok tenant, pilot restoranlar: aspendos, demo-restaurant, dunia, frohsinn, pizzeria-palazzo, restaurant-test).

---

## 2. Kaynaklar ve Yollar

Aynı bilgisayarda çalışıyorsan aşağıdaki yolları doğrudan `Read` tool ile açabilirsin.

### 2.1 Reservation + Online Sipariş Monorepo (MEVCUT)

| Ne | Yol |
|----|-----|
| **Ana repo** | `E:\Project\reservation\` |
| **Prisma schema (632 satır)** | `E:\Project\reservation\prisma\schema.prisma` |
| **Middleware (rate limit + custom domain)** | `E:\Project\reservation\src\middleware.ts` |
| **Auth (JWT + customer)** | `E:\Project\reservation\src\lib\auth.ts` |
| **Rezervasyon slot algoritması** | `E:\Project\reservation\src\lib\slots.ts` |
| **Rezervasyon form** | `E:\Project\reservation\src\components\reservation\reservation-form.tsx` |
| **Rezervasyon API** | `E:\Project\reservation\src\app\api\public\[slug]\reserve\route.ts` |
| **Rezervasyon email template** | `E:\Project\reservation\src\lib\email-templates\reservation-*.ts` |
| **PM2 config** | `E:\Project\reservation\ecosystem.hetzner.config.js` |
| **Nginx vhost** | `E:\Project\reservation\nginx\reservation.2pos.ch.conf` |
| **CLAUDE.md (modüler doküman indeksi)** | `E:\Project\reservation\CLAUDE.md` |
| **Proje dokümantasyonu** | `E:\Project\reservation\.claude\docs\01..13.md` |
| **Deploy scripti (prod)** | `E:\Project\reservation\deploy_hetzner.py` |
| **Deploy scripti (test)** | `E:\Project\reservation\deploy_test.py` |

### 2.2 POS Tarafı (entegrasyon noktası — GastroCore)

| Ne | Yol |
|----|-----|
| **POS monorepo kökü** | `E:\Project\Restaurant\` |
| **POS pilot worktree** | `E:\Project\Restaurant\.claude\worktrees\jolly-final\` |
| **POS handoff dosyası** | `E:\Project\Restaurant\pilot\DEVELOPER_RESTAURANT.md` |
| **POS pilot APK** | `E:\Project\Restaurant\pilot\app-pos-release.apk` |

**POS kılavuzundan rezervasyon için okunması gereken klasörler:**

| Klasör | Neden önemli |
|--------|--------------|
| `E:\Project\Restaurant\.claude\worktrees\jolly-final\docs\developer-kilavuzu\02-features\customer\` | POS'un `customer` entity'si — rezervasyon müşteri linki buraya eşlenecek |
| `...\docs\developer-kilavuzu\02-features\orders\` | Table/ticket lifecycle — rezervasyon onayı POS masasını "reserved" işaretleyecek |
| `...\docs\developer-kilavuzu\03-swiss-compliance\` | MWST + audit retention — rezervasyon deposit refund kayıtlı olmalı |
| `...\docs\developer-kilavuzu\05-kararlar-ve-bilinmesi-gerekenler\tenant-switcher-ertelendi.md` | Multi-tenant runtime switcher kararı |

**POS kılavuzu kök:** `E:\Project\Restaurant\.claude\worktrees\jolly-final\docs\developer-kilavuzu\`

### 2.3 Obsidian Vault — Canonical Reservation Notları

User'ın kişisel planlama notları (projede aktif olarak tutulan):

| Not | Yol |
|-----|-----|
| **Ana note (harita)** | `C:\Users\kasim\Documents\2tech\2tech\Projects\Reservation.md` |
| **Changelog** | `C:\Users\kasim\Documents\2tech\2tech\Projects\Reservation - Changelog.md` |
| **Deploy Runbook** | `C:\Users\kasim\Documents\2tech\2tech\Projects\Reservation - Deploy Runbook.md` |
| **Son Session Report** | `C:\Users\kasim\Documents\2tech\2tech\Projects\Reservation - Session Report 2026-04-18_19.md` |

POS kılavuzu mirror'ı da burada (`...\2tech\2tech\Projects\POS Developer Kılavuzu\`) — rezervasyon için ayrılmış bir vault klasörü yok; yukarıdaki dört not canonical.

### 2.4 Claude Oturum Yolları

| Ne | Yol |
|----|-----|
| **Memory dizini** (auto-memory) | `C:\Users\kasim\.claude\projects\E--Project-Restaurant\memory\` |
| **Uploads** (screenshot vb.) | `C:\Users\kasim\AppData\Roaming\Claude\local-agent-mode-sessions\<session-id>\agent\local_ditto_<id>\uploads\` |

### 2.5 Otomatik Obsidian Senkron Skill

`E:\Project\reservation\.claude\skills\sync-to-obsidian\SKILL.md` — rezervasyon projesinin Obsidian not'larını güncel tutmak için skill.

---

## 3. Topoloji — İki Hedef

### 3.1 Production (Hetzner)

| Alan | Değer |
|------|-------|
| Host | `178.104.137.75` |
| Erişim | `ssh tech@178.104.137.75` |
| Domain'ler | `gastro.2hub.ch`, `reservation.2pos.ch`, tenant custom domain'ler |
| DB | **Docker Postgres** container (`reservation_db`, user `reservation_user`) |
| Yan servisler (Docker) | `gastrocore-db:5433`, `gastrocore-redis:6379`, `techhub-minio`, `alpiva-tools` |
| Process | PM2 `reservation`, port 3001 |
| Deploy scripti | `deploy_hetzner.py` |

### 3.2 Test / Internal (LAN)

| Alan | Değer |
|------|-------|
| Host | `192.168.1.134` (`2techrust`) |
| Erişim | `ssh tech@192.168.1.134` |
| Domain | `reservation.2pos.ch` (bu host nginx → 127.0.0.1:3001) |
| DB | **Native Postgres 16.13** (`localhost:5432`, db `reservation`, user `reservation`) |
| Yan servisler | Yukarıdaki Docker servislerinin tümü aynı host'ta |
| Deploy scripti | `deploy_test.py` |

**Kritik:** İki ortamın DB'si **tamamen izole**. Test Hetzner'dan DB çekmiyor; kendi native Postgres'ini kullanıyor.

---

## 4. Data Modeli — Rezervasyona Dokunanlar

**Kaynak:** `prisma/schema.prisma` (632 satır, 20+ model).

### 4.1 `Reservation` modeli

```prisma
model Reservation {
  id             String    @id @default(cuid())
  restaurantId   String
  date           DateTime  @db.Date
  time           String                        // "19:30" HH:MM
  guestCount     Int
  customerName   String
  customerEmail  String
  customerPhone  String
  notes          String?
  status         ReservationStatus             // PENDING/CONFIRMED/CANCELLED/REJECTED
  createdAt      DateTime  @default(now())
  updatedAt      DateTime  @updatedAt
  restaurant     Restaurant @relation(fields: [restaurantId], references: [id])

  @@index([restaurantId, date])
  @@index([restaurantId, status])
  @@index([date])
}

enum ReservationStatus { PENDING, CONFIRMED, CANCELLED, REJECTED }
```

**Not:** Mevcut model **no-show** status'ü içermiyor (PENDING/CONFIRMED/CANCELLED/REJECTED sadece). No-show eklemek istiyorsan enum genişlet + migration.

**Not:** Mevcut model **depozito alanı içermiyor**. Deposit/no-show fee politikası uygulanacaksa `depositAmount`, `depositPaid`, `depositRefunded` alanları eklenmeli.

**Not:** Mevcut model **tableId bağlantısı içermiyor**. Masa ataması ayrı entity yok — `Restaurant.maxCapacity` / `timeSlotInterval` üzerinden kapasiteye göre slot verilir, ama "X masası Y kişiye bu saatte rezerve" detayı kayıtlı değil.

### 4.2 `Restaurant`'tan rezervasyon-relevant alanlar

```prisma
model Restaurant {
  slug                String    @unique
  customDomain        String?   @unique
  workingHours        Json                   // {mon:{open:"...", close:"..."}, ...}
  maxCapacity         Int                    // toplam kapasite
  timeSlotInterval    Int                    // dakika (varsayılan 30)
  language            String                 // de/fr/en/it
  reservationEnabled  Boolean                // master switch
  // ... website, ordering, gastrocore vb. alanları
  reservations        Reservation[]
}
```

`workingHours` normalize helper: `src/lib/constants.ts:60` `normalizeDaySchedule`.

### 4.3 Slot Algoritması

`src/lib/slots.ts`:
- `generateTimeSlots(workingHours, date, interval)` → gün için tüm olası slot'lar (string array).
- `getAvailableSlots(restaurantId, date)` → o gün için kapasitesi dolmamış slot'lar.

Kapasite filtresi: aynı tarih+saat dilimindeki CONFIRMED+PENDING rezervasyonların `guestCount` toplamı `maxCapacity`'yi geçemez. **Yanlış yorumlama = overbooking** — bölüme bakmadan değiştirme.

### 4.4 Email Template'leri

`src/lib/email-templates/`:
- `reservation-customer.ts` — müşteri onay maili
- `reservation-owner.ts` — restoran sahibine bildirim
- Status update'ler için varyantlar

Sender: `src/lib/email.ts` → `sendReservationPending`, `sendOwnerNotification`, `sendReservationStatusUpdate`.
SMTP: `SMTP_HOST/PORT/USER/PASS/FROM` env (default `reservation@2pos.ch`). Fallback: `SystemSettings` DB singleton.

---

## 5. Rezervasyon Flow — Golden Path

```
Müşteri → /[slug] (landing, 4 adımlı form)
  ├── step 1: date (calendar-picker)
  ├── step 2: time (GET /api/public/[slug]/available-slots?date=YYYY-MM-DD)
  ├── step 3: guestCount (1..maxCapacity)
  └── step 4: customerName + customerEmail + customerPhone + notes
  ↓
POST /api/public/[slug]/reserve
  ├── zod validate (src/lib/validators.ts → reservationSchema)
  ├── rate limit: IP başına saatlik 5 rezervasyon (ayrı Map, reserve/route.ts:11)
  ├── create Reservation(status=PENDING)
  └── sendReservationPending(customer) + sendOwnerNotification(owner)
  ↓
/[slug]/confirmation?id=<reservationId>  (onay sayfası)
```

**OWNER akışı:** dashboard `/dashboard/reservations` → PENDING listesi → onayla/reddet → `PUT /api/reservations/[id]` → status update → müşteriye mail.

**Takvim widget'ı:** `src/components/reservation/calendar-picker.tsx` — `react-day-picker` tabanlı. `date-fns` ile lokal. Dil = `Restaurant.language`.

**4 adımlı form:** `src/components/reservation/reservation-form.tsx` + step state management sayfa level'da.

---

## 6. API Endpoint'leri — Rezervasyona Dokunanlar

### Public (`/api/public/[slug]/*`)

| Method | Endpoint | Açıklama |
|--------|----------|----------|
| GET | `/api/public/[slug]` | Restoran bilgileri (cached) |
| GET | `/api/public/[slug]/available-slots?date=YYYY-MM-DD` | Kapasite-filtreli slot listesi |
| POST | `/api/public/[slug]/reserve` | **Rezervasyon oluştur** (PENDING). Rate limit: IP/saat 5. |
| GET | `/api/public/[slug]/reservation/[id]` | Müşteri detay (token'sız, id ile) |

### Admin / Owner

| Method | Endpoint | Açıklama |
|--------|----------|----------|
| GET | `/api/reservations` | List (scope: OWNER'ın restaurantId'si) |
| PUT | `/api/reservations/[id]` | Status güncelle (PENDING → CONFIRMED / REJECTED / CANCELLED) |

---

## 7. Auth Modeli

**Kaynak:** `src/lib/auth.ts`.

| Kavram | Değer |
|--------|-------|
| OWNER/ADMIN JWT lib | `jose` (edge-safe, middleware kullanıyor) |
| Customer JWT lib | `jsonwebtoken` (server) |
| Algorithm | HS256 |
| TTL | 7 gün |
| Cookie | `auth-token` (httpOnly, SameSite=Lax, Secure prod) |
| Bearer | `Authorization: Bearer ...` (mobile Sunmi için) |
| Secrets | `JWT_SECRET` + `CUSTOMER_JWT_SECRET` (ayrı!) |

**Müşteri rezervasyonu login-less:** rezervasyon formu token istemez; email + telefon girerek kayıt oluşturur. Customer account sistemi `/api/public/[slug]/auth/*` altında var ama **rezervasyon akışında zorunlu değil**.

---

## 8. İsviçre Compliance

- **MWST:** `src/lib/constants.ts:2` → `TAX_RATE = 0.026` (İsviçre KDV, yasal sabit). Rezervasyon için doğrudan uygulanmaz (hizmet ücreti yok şu an), ama deposit alındığında gerekir.
- **CH DSG (GDPR):** Müşteri email/telefon saklanıyor. Silme/anonymise politikası **henüz yok** — eklenmeli. POS tarafında var (`80f277b`), aynı mantık rezervasyon'a da uygulanmalı.
- **Audit log:** Rezervasyon için **structured log yok** — `src/lib/logger.ts` JSON logger var, ama POS-tarzı audit tablosu yok. Deposit refund / no-show fee yapılırsa audit gerekli olacak.

---

## 9. POS Entegrasyonu — Mevcut ve Gelecek

### 9.1 Mevcut (2026-04-16)

Migration `20260416000000_add_gastrocore_integration` ile `Restaurant` modeline eklenen alanlar:
- `gastrocoreTenantId` (String?) — POS tenant eşleşme anahtarı (örn. `pilot-zurich-001`)
- `gastrocoreApiUrl` (String?) — POS'un GastroCore Go backend endpoint'i

Env değişkenleri (`.env.production.hetzner`):
```env
GASTROCORE_API_URL=<POS backend URL>
GASTROCORE_WS_URL=<POS websocket URL>
GASTROCORE_INTERNAL_SECRET=<POS ↔ reservation HMAC>
```

Muhtemelen `/api/gastrocore/[...path]` proxy route'u eklenmiş (**doğrula**: `E:\Project\reservation\src\app\api\gastrocore\` klasörü var mı bak).

### 9.2 Hedef: Rezervasyon ↔ POS masa senkronizasyonu

Şu an **yok**. Planlama gerekir:

| Olay | Beklenen davranış |
|------|-------------------|
| Rezervasyon CONFIRMED olduğunda | POS masa planında masa "reserved" işaretli olmalı |
| Rezervasyon zamanı geldiğinde | Masa POS'ta "occupied" / "open" yapılabilmeli (otomatik veya tek tuş) |
| No-show | Masa release edilmeli + audit log |
| Müşteri SEATED | POS'ta ticket rezervasyonla link'li olmalı (customer_id + reservation_id) |

### 9.3 POS tarafında EKLENMESİ GEREKENLER

POS (`DEVELOPER_RESTAURANT.md` §5'te feature matrisi) şu an **rezervasyon entity'si barındırmıyor**. Aşağıdakiler gerekir:

```dart
// apps/pos/lib/features/reservations/domain/entities/reservation_entity.dart
class ReservationEntity {
  final String id;                         // reservation sisteminden gelen cuid
  final String tenantId;                   // 'pilot-zurich-001'
  final String? tableId;                   // atandığında doldurulur
  final String? customerId;                // POS customer ile link
  final DateTime dateTime;
  final int partySize;
  final Duration duration;                 // varsayılan 90 dk
  final ReservationStatus status;          // pending/confirmed/seated/noShow/cancelled
  final int depositCents;                  // 0 = deposit yok
  final String? notes;
  final DateTime createdAt;
  final String source;                     // 'web' / 'phone' / 'walkin'
}

enum ReservationStatus { pending, confirmed, seated, noShow, cancelled }
```

Schema v19 migration gerekecek (POS'un şu anki schema'sı v18).

Yeni AuditAction enum değerleri (POS audit):
- `reservationCreated`
- `reservationConfirmed`
- `reservationSeated`
- `reservationNoShow`
- `reservationCancelled`

POS tarafında REST/webhook endpoint'i (henüz yok):
- `POST /api/v1/reservations` (reservation sisteminden push)
- `PATCH /api/v1/reservations/:id/status`
- `GET /api/v1/tables/availability?ts=...` (reservation sistemi kullansın)

---

## 10. MVP Scope Önerisi — Rezervasyon "Ayrı Proje" Olursa

Kullanıcı rezervasyonu gerçekten ayrı bir codebase'e çekmek isterse (mevcut tek repo'yu split), MVP scope:

**İçeride:**
1. Çok tenant (slug + custom domain) — mevcut repo'dan taşı
2. 4 adımlı form + calendar-picker + slot algoritması
3. Email template'leri (4 dil: DE/FR/EN/IT)
4. Dashboard: OWNER rezervasyon listesi + onay/iptal
5. Rate limiting (IP/saat 5) + zod validation
6. POS webhook push (`gastrocoreTenantId` üzerinden)
7. CH DSG müşteri silme endpoint'i

**Dışarıda (v2):**
- Deposit + no-show fee
- SMS hatırlatıcı (Twilio/MessageBird)
- Recurring rezervasyon
- Masa-özel atama UI (POS floor plan üzerinden)
- Waitlist

---

## 11. Açık Kararlar / Kullanıcıdan Beklenenler

Bunlar finalize edilmeden kod değişikliği / split yapılamaz:

| # | Karar | Seçenekler | Not |
|---|-------|------------|-----|
| 1 | **Split etme stratejisi** | Monorepo içinde modül izolasyonu / ayrı repo çıkarma / mevcut durum sürdür | Öneri: **mevcut durum sürdür**, rezervasyonu ayrı bir folder'a (örn. `src/features/reservation/`) izole et ama DB paylaşmaya devam et |
| 2 | **No-show status** | Enum'a ekle / ayrı flag | Öneri: `ReservationStatus`'e `NO_SHOW` ekle, migration |
| 3 | **Deposit / fee** | Alınacak mı? | Policy kararı — CH pazarında bazı restoranlar uyguluyor |
| 4 | **POS masa atama** | Web tarafı seçer / POS tarafı seçer / otomatik | Öneri: **POS tarafı** (floor plan olan yerde atama), web sadece "masa 4 kişilik var mı?" sorgular |
| 5 | **Reminder kanalı** | SMS / email / push | Email mevcut. SMS provider seçimi açık |
| 6 | **Recurring** | Şimdi / v2 | v2 (MVP değil) |
| 7 | **Table entity** | Web DB'de / POS DB'de | Öneri: **POS DB canonical**, web rezervasyon POS'tan tableId çekip cache'ler |
| 8 | **GastroCore proxy route** | `/api/gastrocore/[...path]` zaten var mı? | **Doğrula.** Yoksa ekle. |
| 9 | **Customer dedupe** | Web customer = POS customer aynı kayıt mı? | Öneri: email+telefon anahtar, eşleşince link |
| 10 | **Audit mirror** | POS audit tablosuna yaz / web ayrı | Öneri: POS'a HMAC-signed push (tek gerçeklik merkezi) |

---

## 12. Güvenlik / Bilinen Riskler — Rezervasyon Tarafı

### Var olan korumalar
- Rate limit: middleware 100/dk genel + `reserve/route.ts:11` IP/saat 5 (ayrı Map)
- Zod validation
- OWNER scope filter (dashboard endpoint'lerinde `where: { restaurantId: session.restaurantId }`)
- JWT secret env-only

### Riskler / iyileştirilmeli
- **Rate limiter in-memory** — PM2 multi-worker'da worker'lar arası paylaşılmaz, Redis'e taşınmalı (`src/lib/cache.ts` zaten Redis var, `INCR` + `EXPIRE` pattern)
- **Customer şifre alanı** `password` ismi — bcrypt olduğu varsayılıyor ama field adı hash ima etmiyor; doğrula (POS'ta `passwordHash` açık isim)
- **CH DSG silme endpoint'i yok** — eklenmeli
- **No-show takibi yok** — rezervasyonun gerçekleşip gerçekleşmediği izlenmiyor
- **`NEXT_PUBLIC_BASE_URL`** yanlışsa middleware `getSlugForDomain` fetch çöker → custom domain sessizce fail (bkz. `src/middleware.ts:62`)

---

## 13. Deploy — Rezervasyon Kapsamı

Tam deploy runbook için: `C:\Users\kasim\Documents\2tech\2tech\Projects\Reservation - Deploy Runbook.md`. Özet:

### 13.1 Prod (Hetzner)

```bash
cd E:\Project\reservation
rm -rf .next && npm run build    # dev server kapalıyken
ls .next/standalone/server.js    # VAR olmalı

python deploy_hetzner.py
# → tar bundle SFTP → ssh → prisma migrate deploy → pm2 restart reservation
```

### 13.2 Test (LAN)

```bash
cd E:\Project\reservation
rm -rf .next && npm run build
python deploy_test.py
# → pre-deploy backup tar.gz → SFTP → pm2 stop/delete/start → curl localhost:3001
```

Gerekli env: `.env.production.hetzner` (prod için), `.env.production.test` (test için). Dosya yoksa script **abort**; fallback yok.

### 13.3 Smoke

```bash
# Prod
curl -I https://reservation.2pos.ch/aspendos
curl -s https://gastro.2hub.ch/api/public/aspendos | grep -oE '"primaryColor":"#[0-9a-fA-F]+"'

# Test
curl -I http://192.168.1.134:3001/aspendos
```

---

## 14. Bilinen Teknik Borç

| Alan | Sorun | Kaynak |
|------|-------|--------|
| Git YOK | Version control eksik. Her deploy SFTP+tar. | Obsidian Reservation.md bölüm 4 |
| 30+ `fix_hetzner_*.py` | 2026-04-17 debug turundan artan one-off scriptler | temizlik adayı |
| `md/DEPLOY_PLAN.md:9` | "Test DB: SSH tunnel" yazıyor, artık native Postgres'e değişti | doküman stale |
| `.env.production` | Eski repo kopyası, hardcoded SMTP pass — hiçbir script okumuyor | silinebilir |
| `dashboard/wiki/release-notes` | Hardcoded array, her entry için build+deploy | F5 skill otomatikleştirecek (planlanıyor) |
| Stripe TODO | `payment/route.ts:56` production-ready değil — **ordering tarafı**, rezervasyon deposit alacaksa da gerekli | **açık** |
| `mobile_mypos/`, `reservation-tablet/` | Aktif mi belirsiz | sor |

---

## 15. Yeni Claude İçin "İlk Adımlar" Kılavuzu

1. **Bu dosyayı okudun.** İyi.
2. **Kardeş dosyaları oku (sıra ile):**
   - `E:\Project\Restaurant\pilot\DEVELOPER_GASTRO2HUB.md` (online sipariş — aynı repo)
   - `E:\Project\Restaurant\pilot\DEVELOPER_RESTAURANT.md` (POS — ayrı monorepo)
3. **Obsidian notlarına bak:**
   ```
   Read tool: C:\Users\kasim\Documents\2tech\2tech\Projects\Reservation.md
   Read tool: C:\Users\kasim\Documents\2tech\2tech\Projects\Reservation - Changelog.md
   Read tool: C:\Users\kasim\Documents\2tech\2tech\Projects\Reservation - Deploy Runbook.md
   Read tool: C:\Users\kasim\Documents\2tech\2tech\Projects\Reservation - Session Report 2026-04-18_19.md
   ```
4. **Repo'ya gir:**
   ```bash
   cd E:/Project/reservation
   ```
5. **Repo içi doküman okuma sırası:**
   ```
   Read: E:\Project\reservation\CLAUDE.md
   Read: E:\Project\reservation\.claude\docs\04-reservation.md      # rezervasyon branch'i
   Read: E:\Project\reservation\.claude\docs\01-database.md         # DB yapısı
   Read: E:\Project\reservation\prisma\schema.prisma                # 632 satır
   Read: E:\Project\reservation\src\middleware.ts                   # rate limit + domain
   Read: E:\Project\reservation\src\lib\slots.ts                    # kapasite algoritması
   Read: E:\Project\reservation\src\lib\validators.ts               # reservationSchema
   Read: E:\Project\reservation\src\components\reservation\reservation-form.tsx
   Read: E:\Project\reservation\src\app\api\public\[slug]\reserve\route.ts
   ```
6. **Ortamı hazırla:**
   ```bash
   npm install
   npx prisma generate
   npm run dev
   ```
7. **Test hedefine deploy kuralı:**
   - Önce `python deploy_test.py` (LAN)
   - Smoke geç (curl + browser)
   - Kullanıcı onayı al
   - Sonra `python deploy_hetzner.py` (canlı)

### Hata payı — sık tuzaklar

- **Git YOK:** `git log` veya `git diff` çalışmaz. Local changes = canonical. Yedek yoksa kayıp risk.
- **Rate limit in-memory:** Development'ta limit'e takılırsan PM2 restart / process restart.
- **`.env.production.*` dosyaları secret dolu:** Yanlış env'i yanlış hedefe göndermek = Prisma auth error → PM2 crash.
- **Dev server açıkken `npm run build`:** `.next/standalone` overwrite olur → deploy bozulur. Build öncesi dev server'ı durdur.
- **Migration yazarken:** Önce test hedefinde `npx prisma migrate dev`, sonra prod'a `deploy_hetzner.py` içinde otomatik `migrate deploy`.

---

## 16. Koordinat — 3 Dosyalı Ekosistem

Bu dosya **rezervasyon tarafı**. İlgili dosyalar:

| Dosya | Kapsam |
|-------|--------|
| `E:\Project\Restaurant\pilot\DEVELOPER_RESTAURANT.md` | **POS (GastroCore)** — Flutter, jolly-final worktree, pilot APK |
| `E:\Project\Restaurant\pilot\DEVELOPER_GASTRO2HUB.md` | **Online sipariş (gastro.2hub.ch)** — Next.js, aynı repo `E:\Project\reservation\` |
| `E:\Project\Restaurant\pilot\DEVELOPER_RESERVATION.md` | **Rezervasyon** — Next.js, aynı repo `E:\Project\reservation\`, bu dosya |

**Not:** "Rezervasyon" ve "online sipariş" şu an kodda **tek Next.js uygulamasında** (ortak Prisma schema, ortak middleware, ortak auth, ortak deploy). Kullanıcı bunları **mantıksal olarak ayrı ürünler** olarak konumlandırıyor — gerçekten ayrı repo'ya split kararı §11'de açık tutuldu.

---

**Son güncelleme:** 2026-04-24. Mevcut canlı sistem temel alındı. Schema değiştirilirse §4, endpoint eklenirse §6 güncellenmeli.
