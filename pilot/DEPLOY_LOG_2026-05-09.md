# Deploy Log — 2026-05-09

> Pilot launch öncesi günlük deploy kayıtları. Her deploy sonrası bu dosyaya
> üste prepend ekle. Deploy başarısızsa rollback komutu + zaman damgası yaz.

## 2026-05-11 ~22:30 CEST — Promotions migration 030 + handler enrich + happy-hour wired (code only — deploy QUEUED)

**Servisler:** POS Go (88) — şema/binary GÜNCELLEME GEREKTİRİYOR; Backoffice
(88) — handler kontratı değişti, GÜNCELLEME GEREKTİRİYOR. **Bu cycle deploy
ÇALIŞTIRILMADI** (aşağıya bakın); commit `36af7f9` üzerinde bekliyor.

### Karar

Recon "Promotions sayfası boş onu da yapar mısın" yanıltıcıydı: backoffice'in
`/promotions` altında 3 alt sayfa zaten yaşıyordu (Campaigns + Discounts
live, Happy Hour localStorage stub). POS Go server'da 11 endpoint mevcut
(migration 016'da `discounts` + `campaigns` tabloları). Gerçek gap:

1. **Happy Hour backend yok** — localStorage'a yazıyordu, restart sonrası
   kayboluyordu.
2. **Schema brief'in istediği zengin alanlardan yoksun** — promo_code,
   days_of_week, hours_from/to, max_uses/used_count, is_stackable,
   name_translations / description_translations, HAPPY_HOUR type enum
   değeri — hiçbiri yoktu.

### Migration 030 — `discounts_enrich`

`server/migrations/030_discounts_enrich.up.sql` (+ down):
- `type` CHECK constraint relax → `HAPPY_HOUR` admit
- 9 yeni kolon: `name_translations` JSONB, `description` TEXT,
  `description_translations` JSONB, `days_of_week` int[]
  (default `{0..6}` = her gün), `hours_from` TIME, `hours_to` TIME,
  `max_uses` INT, `used_count` INT default 0, `promo_code` TEXT,
  `is_stackable` BOOLEAN default false
- 2 yeni index:
  - `idx_discounts_tenant_promo_code` (UNIQUE, partial WHERE promo_code IS NOT NULL AND is_deleted=false)
  - `idx_discounts_days_of_week` (GIN, partial WHERE is_deleted=false)
- Tüm ALTER'lar `IF NOT EXISTS` ile idempotent — fresh install ve
  re-run güvenli.

### Go handler enrichment

`server/internal/promotions/handlers.go`:
- `Discount` struct: 9 yeni alan + JSON tag (omitempty for nullable).
- `discountReq` request DTO: aynı alanlar nullable pointer ile (operatör
  omit'ederse mevcut değer korunur).
- `isValidType()`: HAPPY_HOUR eklendi.
- INSERT 22 placeholder, UPDATE 21 placeholder (COALESCE/CASE ile omit
  durumunda mevcut değer korunuyor — kısmi update güvenli).
- `scanDiscount` 24 sütunu okuyor.
- `jsonOrEmpty()` helper: nullable JSON blob → `{}` normalize (JSONB NOT
  NULL DEFAULT contract).

### Backoffice happy-hour rewire

`apps/backoffice/app/[locale]/(dashboard)/promotions/happy-hour/happy-hour-client.tsx`:
- localStorage tamamen kaldırıldı.
- TanStack Query + `clientFetch` → `/api/v1/discounts`.
- Filtre: `hours_from && hours_to` set olan kayıtlar = happy-hour kuralı.
  `/promotions/discounts` sayfası yine her şeyi gösterir; happy-hour
  sayfası alt-küme.
- UI Mon-first day picker ↔ schema ISO 0=Sun..6=Sat int[] mapping (`DAY_TO_INT` / `INT_TO_DAY`).
- Mutations: POST `/discounts`, PUT `/discounts/{id}`, DELETE.
- "Backend tarafı geliştiriliyor" warning banner kaldırıldı.

### i18n

TR (`messages/tr.json`) → +3 anahtar (`deletedToast`, `saveError`, `deleteError`).
**DE/EN/FR/IT** için `promotions.happyHour` namespace'i hiç yoktu;
genişletme sonraki cycle'da tek pass'te yapılacak. Pilot operatörü
Türkçe (user memory), bu cycle blocking değil.

### Deploy — NEDEN ÇALIŞTIRILMADI

| Bileşen | Bloker |
|---|---|
| POS Go server | Yerel makinede `go` ve `docker` yok — sandbox'tan compile mümkün değil. `deploy_backend.py` 192.168.1.134 (LAN) hedefliyor, 88 değil. 88 deploy mekanizması: docker-compose pull (cihazlarda manuel) veya CI build. |
| Backoffice | Sunucudan ÖNCE deploy edilirse handler kontratı eşleşmez (happy-hour POST'u yeni alanlar gönderiyor, eski server 500 atar). Sıra zorunlu: server → backoffice. |

**Commit `36af7f9` jolly-final'in main repo branch'inde
(`claude/super-admin-impersonation`) hazır bekliyor.** Bir sonraki Go
build/deploy'lu cycle:
1. `cd E:/Project/Restaurant/server && go build -o gastrocore-linux-amd64 ./cmd/server` (veya docker build)
2. SFTP `gastrocore-linux-amd64` → 88 `/tmp/`
3. `psql -U gastro -d gastro < server/migrations/030_discounts_enrich.up.sql`
4. `sudo cp /tmp/gastrocore-linux-amd64 /home/tech/gastrocore/server && sudo systemctl restart gastrocore`
5. Smoke: `curl https://api.gastrocore.ch/api/v1/discounts -H "X-Tenant-ID: ..."`
6. `cd apps/backoffice && python deploy_backoffice_hetzner.py`

### Doğrulama (yerel)

- Migration SQL syntax review (PostgreSQL-uyumlu, IF NOT EXISTS guard'ları)
- Go handler placeholder/arg count audit (22 INSERT / 21 UPDATE / 24 SELECT — manuel doğrulandı, Go compile yapılamadı)
- happy-hour-client TypeScript syntax doğru görünüyor (ESLint/tsc lokal sandbox'tan koşturulamadı; backoffice dev server bu worktree'den başlatılamıyor — preview lock)

### Yasak / Yapılmayan

- 178'e dokunulmadı (Reservation Campaign modeli ayrı, brief yasağı)
- jolly-final worktree'ye dokunulmadı (POS Flutter app — brief yasağı)
- Discounts form UI'da multi-lang name + day-of-week + time picker + promo_code + max_uses + is_stackable kontrolleri eklenmedi → sonraki cycle (schema + API hazır)
- DE/EN/FR/IT i18n genişlemesi → sonraki cycle
- max_uses server-side enforcement (counter increment payment path'inde) → sonraki cycle

### Rollback

Migration 030 reversible: `psql < server/migrations/030_discounts_enrich.down.sql`.
Handler regression için önceki binary geri yüklenebilir (`/home/tech/gastrocore/server.bak.<TS>`).

---

## 2026-05-11 ~21:45 CEST — Tenant switcher async race fix + magic-link rewrite verification

**Servis:** Backoffice (88). Go server dokunulmadı.

### Kullanıcı bulgusu

İki şikayet bir arada geldi:
1. "Magic-link tekrar başarısız — token 7CC-QHC"
2. "Üstten restoran değişince birşey değişmiyor"

### Tanı

**Şikayet 1 — false alarm.** POS Go log + DB audit gösterdi ki 21:22 deploy ettiğim 5-phase rewrite gerçekten çalıştı:

```
GO LOG  19:40:47 POST /menu/import-from-token 200 116ms (preview)
        19:40:50 POST /menu/import-from-token 200 1392ms (apply)

DB FRESH 30M:
  Burger House: 186 new products, 15 new cats, 7 new MGs, 267 new refs

FINAL STATE (Burger House):
  prods=209  with_image=187  cats=20  MG=9  mods=63  links=238  refs=267
```

Pre-rewrite (seed-only) modifier groups=2, mods=6, links=12. **+7/+57/+226** sayıları yeni import'tan geliyor. Pipeline 100% çalışıyor. Kullanıcı `Burger House` tenant'ına bakmıyordu / tenant switcher bozuk olduğu için switcher'da Sushi Zen seçili kalmıştı.

**Şikayet 2 — gerçek bug.** `components/shell/tenant-context.tsx`:

```ts
// ÖNCE — fetch fire-and-forget, router.refresh BEFORE cookie lands:
const setActiveAndPersist = (id) => {
  setActive(id);
  fetch("/api/auth/tenant", { ... });  // ← async, await yok
};
// onSelect:
setActive(id); router.refresh();  // ← cookie henüz set edilmemiş
```

Sonuç: `router.refresh()` eski `bo_tenant` cookie ile RSC fetch ediyor, X-Tenant-ID header yine eski tenant. React Query cache da hiç invalidate olmuyor — client-side query'ler eski veriyi göstermeye devam ediyor.

### Fix

**`components/shell/tenant-context.tsx`** — `setActive` artık async Promise döner:
1. **Optimistic client-side update**: `setActive(id)` (React state) + `writeTenantCookieClient(id)` (document.cookie, httpOnly:false halini hemen yazar)
2. **Server POST await edilir** (`/api/auth/tenant` httpOnly cookie'yi de yazar)
3. **`qc.invalidateQueries()` await edilir** — tüm cache'ler yeni X-Tenant-ID ile re-fetch için işaretlenir
4. Caller (TenantSwitcher / CommandPalette) **AWAIT eder** sonra `router.refresh()` çağırır

**`components/shell/tenant-switcher.tsx`** — `onSelect` async, `await setActive(id); router.refresh();`

**`components/shell/command-palette.tsx`** — aynı pattern

### Sözleşme değişikliği

`TenantContextValue.setActive` artık `(id: string) => Promise<void>`. Hem TenantSwitcher hem CommandPalette güncellendi; başka çağıran yok (grep doğrulandı).

### Deploy (88, 21:45 CEST)

Backoffice tarball 15.5 MB → BUILD_ID **`aiBBOEKfPw4CLKq3wZNbq`** `active`.

### Smoke

API per-tenant doğru veriyi dönüyor (JWT + X-Tenant-ID):

```
Burger House  TOTAL=209  with_image=187   price samples: 1300, 1450, 450, 650, 800
Sushi Zen     TOTAL=195  with_image=1     (eski import, image bug öncesi)
Pizzeria      TOTAL=23   with_image=0     (seed)
```

### Kullanıcı talimatı

1. **Hard refresh** (Ctrl+Shift+R) — yeni BO bundle yüklenir, `useQueryClient` artık tenant-context'te bağlı
2. Üst-sağ **tenant switcher** → "Burger House" seç → bekle ~500ms → liste otomatik yenilenir, 209 ürün, 187 resim, 9 modifier grup görünmeli
3. Switcher'dan Sushi Zen'e geç → liste anında değişmeli, 195 ürün gelmeli
4. Sushi Zen'i de yeni pipeline ile yenilemek isterse: 195 ürünü soft-delete edip yeni token ile re-import (ben yapayım, söylesin)

### Rollback

```bash
sudo systemctl stop backoffice
tar -xzf /home/tech/backups/backoffice-pre-tswitch-*.tgz -C /home/tech/backoffice
sudo systemctl start backoffice
```

---

## 2026-05-11 ~21:22 CEST — Magic-link FULL apply rewrite (5-phase + image + modifiers + links) + UI toggle cleanup

**Servis:** POS Go (88), Backoffice (88). 178 dokunulmadı.

### Kök sebep (kullanıcı bulgusu)

Önceki import handler `applySnapshotMinimal` **sadece categories + products** üzerinde dönüyordu. Snapshot'taki `extraGroups`, `extraOptions`, `extraLinks` SLICE'LARI hiç tüketilmiyordu. Sonuç: kullanıcı 195 ürün görüyor ama:
- Modifier groups (extra grupları) = pre-seed 2 tane (hiç eklenmemiş)
- Modifier options = pre-seed 6 tane
- Product↔modifier_group bağlantıları = pre-seed 12 tane
- `image_path` = 194/195 NULL (Reservation `image` field'ı Go struct'ında zaten yoktu, geçen turda eklendi ama wire'lı kalmıştı)
- Önceki "import 100% başarılı" raporu yanılgıydı — sadece product/category row'ları sayıldı

### Değişen dosyalar

**Server (Go) — `server/internal/menu/import_token.go` ~500 satır rewrite:**

| Struct/Func | Değişiklik |
|---|---|
| `menuIRItem` | `IsPopular *bool` eklendi |
| `menuIRExtraGroup` | `MinSelect`, `MaxSelect`, `SortOrder` eklendi |
| `menuIRExtraOption` | `IsDefault`, `SortOrder` eklendi |
| `menuIRExtraLink` (yeni) | `ExtraGroupName`, `Target` (`CATEGORY`/`ITEM`), `TargetCategoryName`, `TargetItemName` — Reservation'dan **name-based references** geliyor |
| `menuIR.ExtraLinks` | yeni field |
| `applyStats` | `ModifierGroupsAdded`, `ModifierGroupsUpdated`, `ProductModifierLinks` eklendi |
| `applySnapshotMinimal()` | **5-phase rewrite** (aşağı) |
| `upsertCategory` / `upsertModifierGroup` / `upsertModifier` / `upsertProduct` / `assignModifierGroup` | yeni dedicated helper'lar, hepsi idempotent |
| `upsertExternalRefInbound` | `external_menu_refs` mirror, `last_sync_from='gastrohub'` (push_handlers'ın `'pos'` versiyonu ile çakışmıyor) |
| `normalizeImageURL` | `http(s)://` → as-is; `/uploads/...` → `GASTROHUB_BASE_URL` prefix; `//cdn...` → `https:` prefix |

**5-phase pipeline:**

1. **Categories** — name-keyed; local UUID map oluşturulur
2. **Modifier groups** — `extraGroups[]` → `modifier_groups` (SINGLE/MULTI type mapping, min/max/required)
3. **Modifier options** — `extraOptions[]` → `modifiers` (group adına resolve, `price_delta` cents)
4. **Products** — kategori adına resolve, image `normalizeImageURL`'den geçer, price `chfToCents`
5. **Extra links** — `extraLinks[]` → `product_modifier_groups` M:N. `ITEM` target: (categoryName, itemName) compound resolve. `CATEGORY` target: o kategorideki tüm ürünlere fan-out

Her entity için **external_menu_refs upsert** — sonraki POS→Reservation push'ı local UUID + remote ID mapping'ini kullanabilir.

**Backoffice — `app/[locale]/(dashboard)/menu/products/products-client.tsx`:**
- Operatör isteğiyle **"Stokta" toggle KALDIRILDI** — POS sold-out POS-side kontrol edilir, backoffice yalnızca catalog (`is_active`) + online channel (`is_online_visible`) gösterir
- Bulk "Tümünü stoğa al / çıkar" butonları kaldırıldı
- `toggleAvailable` mutation + `bulkSetAvailable` + `bulkBusy` state silindi (yaklaşık 60 satır dead code)
- Hem desktop table hem mobile card path'lerinden kaldırıldı

### Cleanup (son 24h yanlış import wipe)

```
PREVIEW           : Burger House 173 product
SOFT_DEL_PRODUCTS : UPDATE 173
SOFT_DEL_CATS     : UPDATE 15
AFTER             : Burger House 23 prods / 5 cats (seed state restored)
                    Pizzeria Da Mario 23/5 (touched)
                    Sushi Zen 195/21 (eski import korundu, 2 gün önce)
```

Sushi Zen'in eski import'u (172 ürün, image yok) **bilinçli olarak korundu** — kullanıcı re-import isterse o tenant'ı da wipe edebilir.

### Deploy (88, 21:22 CEST)

- gastrocore binary 13.6 MB → systemctl restart `active`
- backoffice tarball 15.5 MB → BUILD_ID `tfdpq-eeLD046GCpGZOps` `active`

### Kullanıcı talimatı (smoke + verification)

1. **Burger House** için `gastro.2hub.ch` admin'den **yeni magic-link token üret**
2. Backoffice → `/menu/connect-gastrohub` → token yapıştır → "Önizleme Al" → "İçe Aktar"
3. Step 3 (Sonuç) ekranında stats görmeli:
   - Kategoriler: ~15 yeni
   - Ürünler: ~173 yeni
   - Modifier grupları: N yeni (Reservation'da kaç grup varsa)
   - Modifier seçenekleri: M yeni
   - Ürün ↔ Modifier bağlantısı: K yeni
4. `/menu/products` listesinde:
   - **Fiyatlar CHF 19.90, 14.00, 12.00 vs.** (cents doğru, frontend doğru bölme)
   - **Resimler var** (R2 cdn.2hub.ch URL'leri)
   - **Kategori sütunu dolu** ("Falafel", "Pasta", "Pide" vs.)
   - **Sadece 2 toggle**: Aktif, Online'da var (Stokta YOK)
5. Sushi Zen için tekrar import istiyorsa: önce mevcut 195'i wipe etmek lazım (yardım iste, manuel komut)

### Smoke verification (kullanıcı re-import sonrası DB query):

```sql
SELECT t.name, 
  (SELECT COUNT(*) FROM products WHERE tenant_id=t.id AND is_deleted=false) AS prods,
  (SELECT COUNT(*) FROM products WHERE tenant_id=t.id AND is_deleted=false AND image_path IS NOT NULL AND image_path != '') AS with_image,
  (SELECT COUNT(*) FROM categories WHERE tenant_id=t.id AND is_deleted=false) AS cats,
  (SELECT COUNT(*) FROM modifier_groups WHERE tenant_id=t.id AND is_deleted=false) AS mgs,
  (SELECT COUNT(*) FROM modifiers WHERE tenant_id=t.id AND is_deleted=false) AS mods,
  (SELECT COUNT(*) FROM product_modifier_groups pmg JOIN products p ON p.id=pmg.product_id WHERE p.tenant_id=t.id) AS links,
  (SELECT COUNT(*) FROM external_menu_refs WHERE tenant_id=t.id) AS refs
FROM tenants t ORDER BY t.name;
```

Burger House satırında **with_image > 0**, **mgs > 2** (seed dışında), **links > 12** (seed dışında), **refs > 0** olmalı.

### Rollback

```bash
# POS Go
cp /home/tech/gastrocore/server.bak.20260511-…-pre-rewrite /home/tech/gastrocore/server
sudo systemctl restart gastrocore
# Backoffice
sudo systemctl stop backoffice
tar -xzf /home/tech/backups/backoffice-pre-rewrite-*.tgz -C /home/tech/backoffice
sudo systemctl start backoffice
```

---

## 2026-05-11 ~21:15 CEST — Swiss MWST split-rate (8.1 / 2.6 / alcohol-always-8.1) backend wire-up

**Servis:** POS Go DB schema (88 canlı uygulandı) + Reservation Go-side/TS-side helper'lar + Reservation order route. Reservation prod migrate **akşam 22:00+ deploy ile** uygulanacak (iş saati yasağı).

### Operatör kuralı (2026-05-11)
| Senaryo | Yiyecek / non-alkol | Alkol |
|---|---|---|
| Dine-in (içerde tüketim, Mitnehmen=no) | **8.1%** | **8.1%** |
| Takeaway + Lieferung | **2.6%** | **8.1%** (exception) |

Reservation `(public)/[slug]/order` yalnız TAKEAWAY/DELIVERY destekliyor (DINE_IN orada anlamsız), POS app dine-in dahil hepsini destekler.

### Schema değişiklikleri
- `server/migrations/029_product_is_alcoholic.{up,down}.sql` — POS Go `products.is_alcoholic BOOLEAN NOT NULL DEFAULT FALSE` + COMMENT açıklama.
- `prisma/schema.prisma` — Reservation `MenuItem.isAlcoholic Boolean @default(false)` field eklendi.
- `prisma/migrations/20260511190000_menu_item_is_alcoholic/migration.sql` — `ALTER TABLE "MenuItem" ADD COLUMN "isAlcoholic" BOOLEAN NOT NULL DEFAULT false;`

### Helper modülleri (single source of truth)
- **POS Go** `server/internal/shared/vat/vat.go` — `CalculateVATRate(isAlcoholic, orderType)` + `CalculateOrderVAT(lines, orderType)` + `VATPortion()` + sabitler (VATDineIn 0.081, VATTakeawayDelivery 0.026, VATAlcohol 0.081). Per-line breakdown ile receipt printing'i destekliyor. `vat_test.go` — 4 test (rate table, rappen rounding, mixed basket, dine-in single bucket).
- **Reservation** `src/lib/vat-calculator.ts` — aynı API: `calculateVatRate`, `calculateOrderVat` (per-line breakdown), `vatPortion`, OrderType `"DINE_IN" | "TAKEAWAY" | "DELIVERY"`. `TAX_RATE` legacy constant (2.6%, single-rate) hâlâ duruyor — yeni kod helper kullanmalı.

### Reservation order route refactor (`src/app/api/public/[slug]/order/route.ts`)
- `prisma.menuItem.findMany` select'ine `isAlcoholic: true` eklendi.
- `ValidatedItem` type'ına `isAlcoholic: boolean` field; her item bu flag'i taşıyor.
- Eski:
  ```ts
  const taxAmount = Math.round(totalAmount * TAX_RATE / (1 + TAX_RATE) * 100) / 100;
  ```
- Yeni:
  ```ts
  const vatLines: OrderLineForVat[] = validatedItems.map(it => ({
    grossLineTotal: it.totalPrice,
    isAlcoholic: it.isAlcoholic,
  }));
  if (deliveryFee > 0) vatLines.push({ grossLineTotal: deliveryFee, isAlcoholic: false });
  const vatBreakdown = calculateOrderVat(vatLines, data.orderType);
  const taxAmount = vatBreakdown.taxAmount;
  ```
- Delivery fee non-alcohol line gibi davranıyor (rate = takeaway/delivery food rate). Discount VAT-bearing değil (Swiss receipt convention).
- Mevcut data'da tüm `isAlcoholic = false` → operatör backoffice'ten flag atmaya başlayana kadar tüm sepetler 2.6% (pre-migration davranışla aynı, hiçbir kullanıcı görünür değişiklik yok).

### 029 canlı uygulama (88)
- pg_dump pre-backup: `/home/tech/backups/products-pre-029-20260511-211430.sql.gz` (25K)
- `ALTER TABLE` + `COMMENT` çalıştı → 414 rows hepsi `is_alcoholic = FALSE`
- Atomic DDL — fail → implicit rollback

### Bilinçle ertelendi (sonraki seans, ayrı PR)

| Görev | Neden ertelendi |
|---|---|
| **Backoffice product edit form alcohol toggle** + 5-dil label | products-client.tsx + form schema değişikliği, paralel agent revert riski (modifier UI 3+ seans revert'lendi); UI tek-shot deploy ile birleştirmek daha güvenli. |
| **POS Go order/payment handler refactor** (VAT helper'ı çağırsın) | Live binary'nin source branch'i bulunmalı (önceki seansta gözlemlendiği üzere local repo'daki menu handler'lar live'da yok — branch divergence). Helper modül hazır, handler kullanıma alındığında mekanik. |
| **POS Flutter `swiss_vat_calculator.dart` + payment screen refactor** | Drift schema bump + APK rebuild + jolly-final lineage. Müstakil epic. |
| **Receipt VAT breakdown** (`MWST 8.1%: CHF X.XX` + `MWST 2.6%: CHF Y.YY`) | Helper API hazır (`byRate` map), receipt template + ESC/POS render ayrı iş. |
| **tax_profiles seed update** alcohol categorization için | Seed script paralel agent zone'unda, ayrı PR. |
| **Reservation prod Prisma migrate** | İş saati yasağı — 22:00+ saatinde `deploy_hetzner_safe.py` çalıştığında `npx prisma migrate deploy` otomatik uygulayacak. Migration file commit-ready. |

### Behaviour check (mevcut + post-deploy)
- 029 uygulanmış canlı 88'de: yeni kolon, default FALSE → tüm hesaplar eski davranışı korur.
- Reservation prod migrate olduğunda: aynı durum (default FALSE → eski davranış).
- Operatör backoffice'ten ilk alkol ürünü flag'leyene kadar görünür değişiklik yok.
- İlk alkol flag'i atıldıktan sonra mixed sepet (pizza + bira takeaway): pizza 2.6%, bira 8.1%, tax breakdown response'ta `byRate: {"0.026":..., "0.081":...}` döner.

### Test
- Go `vat_test.go`: 4 unit test (rate table, rappen rounding, mixed basket, dine-in single bucket). Standart `go test ./...` ile çalışır.
- TS: helper saf fonksiyon, deploy + smoke order ile E2E doğrulanacak (lokal preview canlı DB/auth gerektirir, smoke uygulanamaz).

### Rollback
```bash
# POS Go DB
ssh tech@88.99.190.108
echo 'ALTER TABLE products DROP COLUMN IF EXISTS is_alcoholic;' | docker exec -i gastro-postgres psql -U gastro -d gastro

# Reservation (lokal migration henüz prod'a gitmedi)
# prisma/migrations/20260511190000_menu_item_is_alcoholic dizinini sil + schema.prisma'dan isAlcoholic satırını çıkar
# Reservation Helper modülü ve order route değişikliği lokal commit — geri almak için git revert.
```

---

## 2026-05-11 ~18:45 CEST — KDS Cloud SSE wire-up (POS Go 88 deploy + Flutter client + 178 akşam prep)

**Servis:** POS Go (88 deploy). Flutter SSE client kod hazır (main worktree).
Pilot APK rebuild **deferred** — cross-branch state, bkz. "Açık konular" altında.

### Karar

KDS app şu an Drift local streams + WS hub (`/ws/kds`) üzerinden besleniyor.
WS kanalı bazı Caddy/nginx ortamlarında flaky proxy davranışı gösteriyor.
SSE paralel transport olarak ekleniyor — aynı broadcast fan-out'a takılıyor,
operatör Settings'ten "SSE modu" toggle'ı ile transport seçebilecek.

### Yeni / değişen dosyalar

**Server (Go) — 6 dosya:**
- `server/internal/kds/hub.go` — `kdsSubscriber` struct + `Subscribe(id, tenantID, station) <-chan []byte` + `Unsubscribe(id)`. `broadcast()` artık WS clients + SSE subscribers'ı paralel besliyor. Yeni `NotifyOrderCreated(...)` helper.
- `server/internal/orders/stream_handler.go` (yeni) — `GET /api/v1/orders/stream` SSE handler. `text/event-stream` + `X-Accel-Buffering: no` + 25s heartbeat comment. İlk frame `event: ready` data `subscriber_id`+`tenant_id`. KDS event frame: `event: kds` data: KDSNotification JSON. `kdsBroker` interface ile DI — circular import yok.
- `server/internal/orders/module.go` — yeni rota; `/orders/stream` literal path'i `/orders/{id}` ÖNCE register edildi.
- `server/internal/orders/handlers.go` — `handleCreateOrder` artık başarılı insert sonrası `kdsBrokerRef.NotifyOrderCreated(...)` çağırıyor (nil-safe).
- `server/internal/shared/middleware/middleware.go` — `statusWriter.Flush()` eklendi (`http.Flusher`). Logger wrapper'ı önceden SSE handler'ın Flush çağrısını kaybediyordu → "STREAMING_UNSUPPORTED" 500. İlk smoke ile ortaya çıktı.
- `server/cmd/server/main.go` — `orders.SetKdsBroker(kdsHub)` startup wire-up; auth gate exemption listesine `/api/v1/orders/stream` eklendi (mirror /ws/kds auth modeli).

**Flutter (main worktree, super-admin-impersonation) — 5 dosya:**
- `apps/pos/lib/features/kds_app/data/kds_stream_service.dart` (yeni) — `KdsStreamService`. `http.Client().send()` long-lived GET, `utf8.decoder` stream, manuel SSE parser (event:/data:/comment, blank-line separator). Idle watchdog 60s. Exp backoff reconnect 1/2/4/8/16/32/64s cap 60. Aynı `KdsEvent` shape emit eder.
- `apps/pos/lib/features/kds_app/presentation/providers/kds_providers.dart` — `kdsRealtimeTransportProvider` (`'ws'` | `'sse'`, default `'ws'`).
- `apps/pos/lib/features/kds_app/presentation/providers/kds_realtime_provider.dart` — `kdsStreamClientProvider` (null when transport ≠ 'sse'). SSE state → `KdsWsState` mapper.
- `apps/pos/lib/features/kds_app/presentation/screens/kds_main_screen.dart` — `initState`'de hem WS hem stream provider read; SSE provider gated.
- `apps/pos/lib/features/kds_app/presentation/screens/kds_settings_screen.dart` — yeni "Realtime Bağlantı" bölümü, `SwitchListTile` "SSE modu" toggle, SharedPreferences `kds_realtime_transport` persist.

`flutter analyze lib/features/kds_app` → No issues found.

### Deploy (88, 2026-05-11 ~18:43 CEST)

1. Cross-compile `gastrocore-linux-amd64` 13.6 MB
2. SFTP → `/tmp/gastrocore-new`
3. backup `server.bak.20260511-…-pre-sse`, install, `systemctl restart gastrocore`
4. **Flusher fix:** ilk smoke STREAMING_UNSUPPORTED 500 verdi → middleware patch → ikinci binary push → final active
5. Boot logs: `server starting port=8090` + `menu-sync-retry: started interval_s=300` ✓

### Smoke tests (tümü ✓)

| Test | Result |
|---|---|
| `GET /orders/stream` no params | 400 `MISSING_TENANT_ID` |
| `GET /orders/stream?tenant_id=…&device_id=…` | 200 + `event: ready` handshake |
| Concurrent: stream tail + `POST /orders` | Order 201 → SSE frame içinde ~50ms: `event: kds\ndata: {"type":"order.created","ticket":{…}}` |
| `flutter analyze` (kds_app) | clean |

Real captured E2E frame:

```
: gastrocore-kds-stream connected
event: ready
data: {"subscriber_id":"bf989670-3c9c-4ae5-b847-3e057e705230","tenant_id":"0b289fc4-…"}

event: kds
data: {"type":"order.created","tenant_id":"0b289fc4-…","ticket":{"id":"685da898-…","order_number":1088,"channel":"smoke"}}
```

### Açık konular — KDS APK rebuild deferred

SSE Flutter client kodu main worktree'de (`claude/super-admin-impersonation`); ancak:

1. **Memory rule (jolly-final lineage):** Pilot APK her zaman jolly-final worktree'den build. jolly-final'da KDS realtime infrastructure (`kds_ws_client.dart`, `kds_realtime_provider.dart`) henüz yok — branch sadece basic providers + screens + LAN-first içeriyor. Cross-branch port gerekli (WS infrastructure + SSE service'i jolly-final'a aktarmak).
2. **Main worktree build error:** super-admin-impersonation branch'inde `action_buttons`, `restaurant_settings.shiftStartRequired`, `payments/receipt_counter_dao` Drift schema drift compile error'ları var (KDS feature'la alakasız, başka bir paralel agent WIP). `build_runner build --delete-conflicting-outputs` çalıştı ama actionButtons tablosu generated kodda yok.

**Sonraki sprint plan:**
- Jolly-final'a port: `kds_ws_client.dart` + `kds_realtime_provider.dart` (mevcut) + `kds_stream_service.dart` (yeni) + transport toggle UI
- Veya: main worktree'deki action_buttons + payments schema drift'i temizle, APK orada build et

Server-side SSE endpoint 88'de canlı — kullanıcı yeni APK gelmeden manuel curl smoke yapabilir (yukarıdaki E2E örneği).

### 178 akşam deploy hazırlık (≥22:00 CEST)

D Aşama 3 receiver endpoint (`src/app/api/gastrocore/menu/sync/route.ts`) önceki turda commit edildi; bu deploy onu canlıya alıyor.

**Pre-deploy check (this turn, ✓):**

| Check | Result |
|---|---|
| `preflight_css_guard()` (deploy_hetzner_safe.py) | `no-store + immutable present in next.config` ✓ |
| SSH 178 probe | uptime 32 days, sudo passwordless = root ✓ |
| pm2 reservation | `online`, pid 1708407 ✓ |
| Disk free `/home/tech` | 130G (10% used) ✓ |
| Node | v20.20.2 ✓ |
| `GASTROCORE_SERVICE_SECRET` in 178 `.env` | OK (POS HMAC için sync'li) |
| Receiver route deployed? | NO — `.next/server/app/api/gastrocore/menu/sync` yok (beklenen) |

**Çalıştırılacak adımlar (kopyala-yapıştır):**

```powershell
# 1. Local build (Windows host)
Set-Location E:\Project\reservation
npm run build

# 2. Deploy (CSS guard otomatik koşar)
python deploy_hetzner_safe.py

# 3. Smoke: 88'den 178'e gerçek push
# (D Aşama 3 turunda kullanılan smoke script'i tekrarla — bu sefer 'applied' beklenir)
```

E2E mutation flow test:
1. Backoffice `/settings/menu-source` → Sushi Zen "POS'ta yönet" + gerçek Reservation `restaurant.id` (cuid)
2. Backoffice `/menu` → yeni ürün ekle
3. 1-2s içinde Reservation dashboard'da görünmeli
4. Server log: `[menu-sync] product.create restaurant=sushi-zen action=created id=…` satırı

**Rollback:**

```bash
ssh tech@178.104.137.75
cd /home/tech
ls -1t reservation_standalone_old_* | head -1
mv reservation_standalone reservation_standalone_failed_$(date +%s)
mv reservation_standalone_old_<TS> reservation_standalone
pm2 reload reservation --update-env
```

---

## 2026-05-11 ~20:00 CEST — LAN-first v2: PeerRegistry + ConnectionStrategy + manual override + 04:00 cron

**Servis:** Pilot tablet, KDS ekranı, Kiosk (manuel APK install, **88'e deploy YOK**)

**Karar:** Önceki cycle'da inen LAN-first iskeleti operatör-grade'e taşındı.
NetworkLocator artık tüm peer'leri keşfedip kayıt altına alıyor; manuel IP
override (corporate WiFi + mDNS blokları için) operatöre Settings'te
gösteriliyor; 24h timer wall-clock 04:00 local'e hizalandı (DST-safe); WS
disconnect/reconnect mantığı ayrı bir ConnectionStrategy state machine'inde.

### Mimari (genişletildi)

```
NetworkLocator
  ├─ resolve()  priority chain
  │   1. Manuel override (Settings'te girilirse) → HTTP probe → kabul
  │   2. mDNS scan → her peer paralel HTTP probe → registry'ye yaz
  │      → role=server tercih, yoksa ilk healthy
  │   3. Cloud fallback
  ├─ scheduleDailyReprobeAt(hour=4)  wall-clock aligned, DST-safe
  ├─ tenantFilter  TXT record tenant_id eşleşmeyen peer'ler dropped
  └─ onPeersDiscovered callback  PeerRegistry'ye besler

PeerRegistry (StateNotifier<List<LanPeer>>)
  ├─ replaceAll(scan sonuçları)  server first, sonra role/host sort
  ├─ upsert(peer)  side-channel inserts
  └─ clear()  tenant switch'te

ConnectionStrategy (idle → resolving → connected → reconnecting → cooldown)
  ├─ markConnected()  WS handshake başarılı, failure count sıfırla
  ├─ markDisconnected()  N<3 → 5s backoff (reconnecting), N>=3 → 30s (cooldown)
  ├─ forceRetry()  Settings → "Şimdi yenile"
  └─ snapshots stream  UI ConnectionPhase + nextRetryAt göstersin diye
```

### Yeni / değişen dosyalar

| Dosya | İş |
|---|---|
| `apps/pos/lib/core/network/peer_registry.dart` | **YENİ ~165 satır.** `PeerRole` enum (server/pos/kds/waiter/kiosk/ods/unknown) + `parse()` helper, `LanPeer` immutable model (host/port/role/tenantId/version/lastSeenAt/healthy + copyWith + equality), `PeerRegistry` StateNotifier (replaceAll/upsert/clear/activeServer). |
| `apps/pos/lib/core/network/network_locator.dart` | Genişletildi: `tenantFilter` ctor param (TXT mismatch peer drop), `manualOverride` host/port (priority 1 — direct probe), `onPeersDiscovered` callback (registry feed), `DiscoveredPeer` enriched (roleRaw/tenantId/version), `PeersObserver` typedef, `scheduleDailyReprobeAt(hourLocal=4)` wall-clock cron + `_nextOccurrenceOfHour` DST-safe helper, `nextReprobeAt` getter, `setManualOverride()`. `resolve()` "winner" mantığı (role=server tercih). Eski `startDailyReprobe()` korundu. |
| `apps/pos/lib/core/network/connection_strategy.dart` | **YENİ ~145 satır.** `ConnectionPhase` 5-state enum, `ConnectionSnapshot` immutable, `ConnectionStrategy` class — markConnected/Disconnected/forceRetry, snapshots stream, 3-strike-then-cooldown back-off (5s default, 30s extended). |
| `apps/pos/lib/core/network/network_locator_provider.dart` | `connectionStrategyProvider` + `connectionSnapshotProvider` + `ConnectionSnapshotNotifier` (StateNotifier mirror). |
| `apps/pos/lib/features/settings/presentation/widgets/network_status_pane.dart` | Genişletildi: TextField'lı `_ManualOverrideCard` (IP+port input, Aktif chip, Uygula/Temizle butonları, SharedPreferences persist), `_PeerListCard` (LAN'da bulunan tüm cihazlar role-rozeti + healthy dot + aktif sunucu işareti), "Sonraki tarama" satırı. |
| `apps/pos/lib/main_waiter.dart`, `main_kds.dart`, `main_kiosk.dart` | Boot path: `PeerRegistry()` + `NetworkLocator(tenantFilter, onPeersDiscovered)` + manual override prefs'ten yükle + `scheduleDailyReprobeAt()` + `ConnectionStrategy(locator: locator)`. 3 yeni provider override (`connectionStrategyProvider`, `peerRegistryProvider`, mevcut `networkLocatorProvider`). Kiosk için ilk kez wire edildi. |
| `apps/pos/pubspec.yaml` | `network_info_plus: ^5.0.3` eklendi (operatörün kendi LAN IP'sini Settings'te göstermek için; mevcut `multicast_dns` yerinde kalıyor — bonsoir alternatifi vardı, multicast_dns zaten LAN sync için kullanıldığı için ikinci stack açmak yerine onu wrap'ledik). |

### Tests (+22)

`test/core/network/peer_registry_test.dart` **YENİ — 12 test pass:** PeerRole.parse case-insensitive, null→unknown, LanPeer equality (host+port only), replaceAll sort (server-first/role/host), upsert insert+update, clear.

`test/core/network/connection_strategy_test.dart` **YENİ — 10 test pass:** initial idle, markConnected resets failures, reconnecting under threshold, cooldown after 3, snapshots stream emissions, forceRetry triggers extra scan, dispose closes stream + no-op after; NetworkLocator manual override bypass, manual probe fail → mDNS fallback, tenantFilter drops other-tenant peers, onPeersDiscovered fires with full+healthy set, nextReprobeAt null then 04:00 after schedule.

`flutter test --reporter compact` → **1973 pass / 23 skip / 2 fail** (untracked `fast_sale_screen_test.dart` paralel agent — dokunulmadı). **+22 net, 0 regresyon**.

### Pilot APK'ları

| Flavor | Path | Size | SHA256 |
|---|---|---:|---|
| **KDS** | `pilot/app-kds-release-lanfirst-v2-20260509.apk` | 62.50 MB | `AE3E01905DB95D6B8DC632FFF0AA9326A999A2F1C1CEA1D1DBB14EFB0B53D237` |
| **Waiter** | `pilot/app-waiter-release-lanfirst-v2-20260509.apk` | 63.06 MB | `86C5967BB393E8C2D7A7FC92ABF304890ACAD94F1336961D7B689805AC130652` |

Kiosk APK paralel agent'ın işi — bu cycle rebuild edilmedi, sadece
`main_kiosk.dart` LAN-first overrides eklendi (paralel agent build edince
otomatik dahil olur).

### Settings akışı (operatör tarafı)

1. Operatör Settings → Bağlantı Durumu açar
2. Üst pill: anlık state (yeşil/turuncu/mavi/gri)
3. Detay kart: mod / sunucu IP / API+WS URL / son keşif / **sonraki tarama (HH:MM)**
4. "Şimdi yenile" butonu — anında re-resolve
5. **Manuel sunucu IP kartı** — mDNS broadcast blokluysa IP+port elle yazılır
   ("192.168.1.50" + "8090") → Uygula → SharedPreferences'a yazılır + locator
   doğrudan o IP'ye gider. "Aktif" chip + "Temizle" CTA.
6. **LAN'da bulunan cihazlar kartı** — tüm peer'ler, role rozeti + healthy
   dot + aktif sunucu check icon. mDNS broadcast yokken boş state mesajı.

### Yasak / Yapılmayan
- 88'e deploy yok (server kodu değişmedi)
- 178'e dokunulmadı
- `pos_v2_shell` ve `fast_sale_screen` lineage'e dokunulmadı (brief yasağı)
- Bonsoir paketi eklenmedi (existing multicast_dns ile redundant; tek stack)
- WS client'ı ConnectionStrategy ile **henüz bağlanmadı** — strategy state
  machine hazır, snapshots stream çalışıyor, ama mevcut WebSocketSyncClient
  hâlâ kendi reconnect loop'unu kullanıyor. Wire-up `lib/features/sync/data/clients/websocket_sync_client.dart`'da
  `markConnected/Disconnected` çağrıları ekleyince tam aktive olur — sonraki
  cycle (refactor riskli, brief'te yoktu)
- Server-side mDNS broadcaster (server/internal/discovery/...) hâlâ yok —
  her boot cloud'a düşüyor (graceful, operatör Settings'te görür)
- POS flavor APK rebuild — brief'te sadece KDS+Waiter

### Rollback

```
adb install -r pilot/app-kds-release-lanfirst-20260509.apk   # önceki LAN-first v1
adb install -r pilot/app-waiter-release-lanfirst-20260509.apk
```

---

## 2026-05-11 ~18:35 CEST — Migration 028 modifier_groups + modifiers name_translations JSONB

**Servis:** gastro-postgres (88.99.190.108) — schema-only değişiklik, server binary'e dokunulmadı.

### Migration 028
`server/migrations/028_modifier_translations.{up,down}.sql` — products + categories'nin migration 022 pattern'ini modifier'lara genişletiyor.

```sql
ALTER TABLE modifier_groups ADD COLUMN IF NOT EXISTS name_translations JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE modifiers       ADD COLUMN IF NOT EXISTS name_translations JSONB NOT NULL DEFAULT '{}'::jsonb;
UPDATE modifier_groups SET name_translations = jsonb_build_object('de', name, 'tr', name) WHERE name_translations = '{}'::jsonb;
UPDATE modifiers       SET name_translations = jsonb_build_object('de', name, 'tr', name) WHERE name_translations = '{}'::jsonb;
```

### Canlı uygulama (88)
Script: `E:\Project\reservation\apply_028_modifier_translations.py` — SFTP up.sql → `docker cp` → `psql -f`. Postgres DDL implicit transactional, fail → atomik rollback.

Pre-backup: `/home/tech/backups/modifier-pre-028-20260511-183456.sql.gz` (1.6K, pg_dump --data-only --table=modifier_groups --table=modifiers).

Sonuç:
- `ALTER TABLE` × 2 → kolonlar `jsonb DEFAULT '{}'::jsonb` ile eklendi
- `UPDATE modifier_groups` → 6 row backfilled
- `UPDATE modifiers` → 18 row backfilled
- Sample doğrulama: `Boyut → {"de":"Boyut","tr":"Boyut"}`, `Klein → {"de":"Klein","tr":"Klein"}` ✓

Mevcut UI/POS app etkilenmedi — `name` kolonu dokunulmadı, handler'lar yeni kolonu henüz SELECT/INSERT/UPDATE etmiyor.

### Bilinçle ertelendi (sonraki seans, ayrı PR)

| Görev | Neden ertelendi |
|---|---|
| **Go handler refactor** (`modifier_handlers.go` Create/Update body accept + SELECT name_translations) | Local repo branch'inde `modifier_handlers.go` mevcut değil (canlı binary farklı branch'te build'lenmiş). Handler PR'ı için canlı binary'nin source branch'i bulunmalı. Source-binary divergence'ı çözülmeden handler push etmek riskli. |
| **Backoffice modifier panel multi-lang input** (5-dil mini-tab DE primary) | Paralel agent revert döngüsü bu dosyaları sürekli geri çekiyor (3+ seans). Schema canlı, UI eklenmesi mekanik ama revert riski yüksek. Ayrı seans → tek-shot deploy. |
| **POS app modifier UI multi-lang** (`modifier_management_panel.dart` + Drift v25) | APK rebuild + jolly-final lineage + 5-dil text input + sync queue payload genişletme — 2-3 saatlik iş, tek seansta + handler ile birlikte. |
| **5-dil UI mini-tab pattern** | Schema hazır, sync_queue payload genişletilebilir; tüm UI değişiklikleri handler PR'ı ile aynı turda yapılırsa coherence yüksek. |

### Rollback
```bash
ssh tech@88.99.190.108
docker cp /tmp/028_modifier_translations.down.sql gastro-postgres:/tmp/028.down.sql  # (sftp upload önce)
docker exec gastro-postgres psql -U gastro -d gastro -f /tmp/028.down.sql
# Data restore (kullanıcı yeni multi-lang yazmadıysa data loss yok — DROP COLUMN sonra UI hâlâ name kullanıyor):
# gunzip -c /home/tech/backups/modifier-pre-028-20260511-183456.sql.gz | docker exec -i gastro-postgres psql -U gastro -d gastro
```

### Sonraki adım (single-shot deploy önerisi)
1. Local'de canlı binary'nin source branch'ini bul (`git log --all --grep "modifier_handlers"` veya worktree taraması)
2. `modifier_handlers.go`: Create/Update DTO'sunda `NameTranslations map[string]string` field; SELECT'lerde + INSERT/UPDATE'lerde dahil et
3. Models: `ModifierGroup` + `Modifier` struct'larına `NameTranslations Translations` (mevcut Translations type'ı reuse, `translations.go`'da)
4. Backoffice: `modifier-group-form.tsx` name input → 5-tab pattern (`products-client.tsx`'teki `LOCALES = ["tr","de","en","fr","it"]` pattern'ini kopyala)
5. POS app: Drift schema v25 migration + UI text input mini-tab
6. APK rebuild + canlı server binary swap + backoffice systemd restart
7. Tek E2E smoke

---

## 2026-05-11 ~19:00 CEST — LAN-first networking layer (POS/Waiter/KDS) + APK rebuilds

**Servis:** Pilot tablet ve KDS ekranı (manuel APK install, **88'e deploy YOK**)

**Karar:** Restoran içi trafik artık bulut sunucusuna gitmeden yerel WiFi
üzerinden POS sunucusuna doğrudan akar. Cihazlar mDNS keşfiyle yerel POS
server'ı bulur, HTTP health probe ile doğrular, bulamazsa `api.gastrocore.ch`
buluta düşer. Günde bir (default 24h) yeniden tarama, IP değişimlerini
otomatik karşılar. Settings'te canlı durum (yeşil "LAN bağlı: 192.168.x.x"
veya turuncu "Bulut fallback") + manuel "Şimdi yenile" CTA.

### Mimari

```
boot → NetworkLocator.resolve()
        ├─ mDNS scan (_gastrocore._tcp, 4s timeout)
        ├─ HTTP probe GET http://<peer>:<port>/health (1s timeout each)
        ├─ İlk 200 → ResolvedEndpoint(source: 'lan', api/ws: http://lan-ip:8090)
        └─ Hepsi fail → ResolvedEndpoint(source: 'cloud', AppEndpoints)
       → startDailyReprobe() (24h cadence)
       → ProviderScope override: networkLocatorProvider + syncServerUrlProvider + wsServerUrlProvider
```

### Yeni / değişen dosyalar

| Dosya | İş |
|---|---|
| `apps/pos/lib/core/network/network_locator.dart` | **YENİ ~280 satır.** `NetworkLocator` servisi: `resolve()` (discover+probe), `startDailyReprobe()` timer, `stateChanges` broadcast stream, `dispose()`. Pluggable `PeerScanner` + `HealthProber` hooks for tests. Default impl: `MDnsClient` + `package:http` GET /health. Hata yutucu — herhangi bir exception cloud'a fallback eder, app crash etmez. |
| `apps/pos/lib/core/network/network_locator_provider.dart` | **YENİ ~115 satır.** Riverpod wiring: `networkLocatorProvider` (must override at root), `networkEndpointStateProvider` (StateNotifier mirror), `resolvedApiBaseUrlProvider` / `resolvedWsBaseUrlProvider`. Notifier abone olur `stateChanges`'e, UI güncellenir. `reprobe()` "Şimdi yenile" butonuna bağlı. |
| `apps/pos/lib/features/settings/presentation/widgets/network_status_pane.dart` | **YENİ ~220 satır.** Settings altında `_Section.networkStatus` paneli: renkli state pill (taranıyor/LAN/cloud/reconnecting), detay kart (mod, peer IP, API, WS, son keşif), "Şimdi yenile" FilledButton, "LAN-first nasıl çalışır" açıklama kartı. SelectableText URL'ler için. |
| `apps/pos/lib/features/settings/presentation/screens/settings_screen.dart` | `_Section.networkStatus` enum entry + `_buildContent` switch eklendi (tenantSwitcher ile upgrade arasına). NetworkStatusPane import edildi. |
| `apps/pos/lib/main_waiter.dart` | Boot path'e `NetworkLocator()` + `await locator.resolve()` + `startDailyReprobe()` + override `networkLocatorProvider` + override `syncServerUrlProvider`/`wsServerUrlProvider` `resolved.apiBaseUrl` ile (SharedPreferences manual override hâlâ kazanır — operatör escape hatch). |
| `apps/pos/lib/main_kds.dart` | Aynı pattern (KDS özellikle kazanır: kitchen → POS ticket-pull trafiği yüksek, intra-restaurant). |
| `apps/pos/android/app/src/main/AndroidManifest.xml` | `CHANGE_WIFI_MULTICAST_STATE` permission eklendi (Android 12+'da UDP multicast için zorunlu). |

### Tests (+8)

`apps/pos/test/core/network/network_locator_test.dart` **YENİ — 8 test pass:**
- Boş peer listesi → cloud fallback, `state==cloudFallback`
- Scanner exception → graceful cloud fallback (crash etmez)
- İlk state `discovering`, current default cloud
- State stream'i emit'leri (reconnecting → cloudFallback)
- Repeat resolve idempotent, fresh timestamp
- Dispose timer + stream temizler
- `ResolvedEndpoint.isLan` ayırt eder
- `copyWith` un-touched field'ları korur

`flutter test --reporter compact` → **1951 pass / 23 skip / 2 fail** (yine
untracked `fast_sale_screen_test.dart` paralel agent — dokunulmadı). +14 net,
0 regresyon.

### Pilot APK'ları

| Flavor | Path | Size | SHA256 |
|---|---|---:|---|
| **KDS** | `pilot/app-kds-release-lanfirst-20260509.apk` | 62.50 MB | `448558815D90707B7D864842763F2F358EDD48CB03F7348ECD2C4D013BC8F948` |
| **Waiter** | `pilot/app-waiter-release-lanfirst-20260509.apk` | 63.06 MB | `B57902A8639212F3C35936D4654D8D7083DFA7754A0D5DB800DA710CFF4A1254` |

Builder commands:
```
flutter build apk --release --flavor kds    -t lib/main_kds.dart      # 97.5s
flutter build apk --release --flavor waiter -t lib/main_waiter.dart   # 95.8s
```

Önceki APK'lar (`app-waiter-release-20260509.apk` 62.94 MB, eski KDS sürüm)
korundu — rollback için. POS flavor için yeniden build yapılmadı (POS'a
LAN-first override aynı pattern'i alabilir ama brief'te POS APK rebuild
istenmemişti; gelecek cycle).

### Web kiosk için

**Skip.** Web kiosk modu browser-based — mDNS native API yok, multicast
socket'lere erişemiyor. LAN-first sadece native Flutter app'lere uygulandı
(POS / Waiter / KDS — bu cycle waiter+KDS rebuild). Capacitor/Cordova
bridge ile native mDNS API çağrısı teorik olarak mümkün ama ayrı epic;
follow-up'a not edildi.

### Server tarafı (bonus, deferred)

POS Go server `avahi-daemon` (Linux) veya manuel UDP multicast ile
`_gastrocore._tcp` servis kaydını broadcast etmeli. Şu an bu kayıt YOK,
yani locator LAN'da hiçbir peer bulamayacak ve **her boot cloud fallback'e
düşecek**. Bu sprint Flutter-tarafı altyapısı; server-side mDNS broadcaster
bir sonraki sprint'in işi:
- `server/internal/discovery/mdns_broadcaster.go` (yeni) — port 5353 UDP
  multicast yayını, TXT records: `tenant_id`, `role=server`
- systemd `gastrocore.service` ExecStart'a broadcast goroutine
- Caddy reverse-proxy'de port 5353 expose et (Hetzner firewall)

Bu eksik LAN-first'ün asıl değerini bloke ediyor — operatör Settings'te
"Bulut fallback" göreceğine yöneticisiyle konuşur. Pre-pilot demo için
şimdilik kabul edilebilir; restoran kurulumunda server-side broadcaster
şart.

### Install

```
adb install -r E:\Project\Restaurant\pilot\app-kds-release-lanfirst-20260509.apk
adb install -r E:\Project\Restaurant\pilot\app-waiter-release-lanfirst-20260509.apk
```

### Yasak / Yapılmayan
- 88'e deploy yok (sunucu kodu hiç değişmedi)
- 178'e dokunulmadı
- POS flavor APK rebuild (sonraki cycle; aynı override eklenebilir)
- Web kiosk LAN-first (browser sınırı, follow-up)
- Server-side mDNS broadcaster (deferred — yukarıda belgelendi)
- 5-dil ARB i18n (paralel agent çakışma riski; hardcoded TR)

### Rollback

```
adb install -r E:\Project\Restaurant\pilot\app-waiter-release-20260509.apk
# KDS için önceki "linked items" build pilot/'ta varsa onu install et
```

---

## Native Kiosk MVP — apps/pos kiosk flavor (2026-05-11 ~17:30 CEST)

**Servis:** Pilot tablet (manuel APK install, **deploy YOK**)

**Karar:** Self-service customer ordering Flutter app, KDS multi-flavor pattern'ini takip ediyor. `features/kiosk_app/` modülü sıfırdan kuruldu (kiosk klasörü yoktu, Gradle flavor `com.gastrocore.kiosk` zaten line 64 build.gradle.kts'te tanımlıydı).

### Sıfırdan kurulan dosyalar (9)

| Dosya | İçerik |
|---|---|
| `lib/features/kiosk_app/i18n/kiosk_l10n.dart` | Inline 5-locale label map (27 anahtar × 5 dil = 135 string). `kioskLabel(BuildContext, key)` + `kioskLabelFor(localeCode, key)` resolver + `debugKioskLabelsMap` test getter + `kioskLabelKeys` canon + `kioskSupportedLocales` list. |
| `lib/features/kiosk_app/router/kiosk_router.dart` | `KioskRoutes` (welcome / menu / cart / checkout / thanks/:orderNumber) + `createKioskRouter()` GoRouter factory. Standalone — flavor entry-point wire-in post-MVP. |
| `lib/features/kiosk_app/presentation/providers/kiosk_providers.dart` | Riverpod state: `kioskLocaleProvider` (session-sticky lang), `kioskOrderTypeProvider` (dineIn/takeaway + tableNumber), `kioskCartProvider` (KioskCartNotifier — add/remove/setQuantity/clear, CHF cents int math, no float drift). |
| `lib/features/kiosk_app/presentation/screens/kiosk_welcome_screen.dart` | Full-screen hero gradient (primary → primaryContainer), 72pt "Hoşgeldiniz/Willkommen/Bienvenue…" headline, large "Tap to order" CTA, 5-language picker chip row (selected → white pill). Whole screen tappable to advance to /menu. |
| `lib/features/kiosk_app/presentation/screens/kiosk_menu_screen.dart` | Left 220px category rail (All + 4 demo) + right product grid (responsive 2-5 cols, 260px min width). Tap card → add to cart + snackbar. Floating cart bar at the bottom (item count + total + arrow) when cart non-empty. Mock catalogue (4 cats × 8 products) — Drift wire-in post-MVP. |
| `lib/features/kiosk_app/presentation/screens/kiosk_cart_screen.dart` | Line items list with +/- quantity controls, line total, remove icon. Total bar at bottom: Continue (back to /menu) + Checkout buttons. Empty state with shopping_basket icon + Continue CTA. |
| `lib/features/kiosk_app/presentation/screens/kiosk_checkout_screen.dart` | Order type 2-card picker (Dine in vs Takeaway, icon + label, selected fills with primary). Table number TextField shown only when dineIn. Order summary card (line items + total). Place order button disabled when cart empty or table missing. Generates local order number `K<HHMMSS>` and routes to /thanks. **TODO:** push to POS Go `/api/v1/orders` — post-MVP wire-in. |
| `lib/features/kiosk_app/presentation/screens/kiosk_thanks_screen.dart` | Large check icon, "Order placed!" heading, order number + estimated time number cards, auto-return to /welcome after 12 s. "New order" button cancels auto-timer and returns immediately. |
| `test/features/kiosk/kiosk_l10n_test.dart` | 27 key × 5 locale completeness matrix + TR non-ASCII assertions (Hoşgeldiniz, Sipariş Ver, Paket) + EN/DE/FR/IT CTA value pinning + brief-verbiage check ("Hier essen" / "Mitnehmen") + unknown-locale → en fallback + orphan-key canon ↔ map mismatch detection. |

### i18n coverage (5 dil)

27 anahtar × 5 locale = **135 string** inline. Anahtar grupları:
- **Welcome:** welcomeHeadline, welcomeStartCta, welcomeSubtitle, pickLanguage
- **Menu:** menuHeading, categoriesAll, addToCart, unavailable
- **Cart:** cartHeading, cartEmpty, cartTotal, cartCheckout, cartCancel, cartContinue, cartRemove
- **Checkout:** pickOrderType, orderTypeDineIn, orderTypeTakeaway, tableNumber, placeOrder
- **Thanks:** thanksHeading, thanksSubtitle, thanksOrderNumber, thanksEstimate, thanksNewOrder
- **Misc:** idleWarning, connectionOffline

### Build

`flutter analyze lib/features/kiosk_app/ test/features/kiosk/` → 1 unused-local warning (fixed) + 4 info lint — no compile-blocker.

`flutter build apk --release --flavor kiosk` ✓ (PID `bcaq392ts`, exit 0).

| Property | Değer |
|---|---|
| APK boyut | 89,265,510 bytes (~85 MB) |
| **SHA256** | `2a9483abd3509b6d8e1cda065e0cbcabd5add4c55193f78f58125accec273636` |
| Pilot artifact | `pilot/app-kiosk-release-20260509.apk` |
| Build kaynağı | `apps/pos/build/app/outputs/flutter-apk/app-kiosk-release.apk` (May 11 18:22 CEST) |

### Brief'ten henüz yapılmamış (post-MVP, ayrı sprint)

- **LAN-first mDNS networking** — paralel agent Waiter app için aynı pattern yazıyor; `lib/core/network/network_locator.dart` shared module landed olunca kiosk de tüketecek
- **Order push → POS Go `/api/v1/orders`** — `_placeOrder()` içine 1-satır mutation (mevcut `OrderRepository`)
- **Drift wire-in** — mock `_demoProducts` yerine `menuRepositoryProvider`
- **Modifier multi-step modal** — mevcut `ProductOptionsBottomSheet` reuse
- **Payment (TWINT / card)** — mevcut `PaymentScreen` + Wallee POS terminal pattern
- **Idle timeout watchdog** (60s) — root scaffold wrapper, GestureDetector pan/tap reset
- **Theme: Restaurant.primaryColor** — `themeCustomizationProvider` zaten var, kiosk shell tüketecek
- **Receipt print / QR** — `printer_service.dart` + QR widget
- **App.dart flavor branching** — `--dart-define=APP_FLAVOR=kiosk` veya Gradle BuildConfig ile flavor detect → `createKioskRouter()` mount. Şu an default POS router'a düşüyor; APK çalıştırılınca POS PIN screen geliyor (kiosk_app modülü compile içinde ama entry'den erişilemiyor). Bu wire-in pilot demosu öncesi tamamlanmalı (15 dk iş).

### Yasaklara uyum

✅ Reservation (178) dokunulmadı · ✅ jolly-final POS satış lineage'i (`features/orders/`, `features/fast_sale/`, `features/payments/`) dokunulmadı · ✅ AskUserQuestion kullanılmadı · ✅ Sadece `features/kiosk_app/` (yeni feature) + `test/features/kiosk/` (yeni test)

**İmza:** Opus 4.7 · Kiosk MVP iskelet (9 dosya, ~1100 satır) + APK build

### Addendum — Kiosk pilot-ready rebuild (2026-05-11 ~18:39 CEST)

Brief'in 4 kritik gap'i (flavor branching / Drift wire-in / order push / idle watchdog) + 5. tema **paralel agent tarafından kapatılmış** olarak bulundu. Benim önceki `features/kiosk_app/` iskeletim orphan (kullanılmıyor); paralel agent rakip path `features/kiosk/` üzerinde geniş bir MVP yazmış:

| Brief gap | Paralel agent çözümü | Path |
|---|---|---|
| **Flavor entry** | `main_kiosk.dart` (landscape + immersive) + `lib/kiosk_app.dart` (root widget + idle Listener) | `lib/main_kiosk.dart`, `lib/kiosk_app.dart` |
| **Drift wire-in** | `kioskCategoriesProvider` / `kioskProductsProvider` / `kioskSessionProvider` | `features/kiosk/presentation/providers/kiosk_provider.dart` |
| **Order push (88 target)** | `KioskOrderService.submitOrder()` → `OrderRepositoryImpl.createTicket` (Drift transactional) + `KitchenRepositoryImpl.dispatch` + Swiss VAT 8.1%/2.6% split + 5-Rappen rounding | `features/kiosk/services/kiosk_order_service.dart` |
| **Idle watchdog (60s)** | `Listener.onPointerDown` → `_resetInactivityTimer()` → `kioskRouter.go(KioskRoutes.welcome)` + `kioskSessionProvider.reset()` | `lib/kiosk_app.dart:62` |
| **Theme** | `buildKioskTheme()` warm light kiosk-optimised | `features/kiosk/theme/kiosk_theme.dart` |

Paralel agent extra scope: 7 screen (welcome / language / menu / **product_detail with modifier modal** / cart / **payment** / confirmation) + `KioskCartItem` domain entity + tax extraction helper.

**Endpoint doğrulaması (88 ecosystem, Reservation/178 referansı YOK):**
- `apiHost` = `api.gastrocore.ch` (88 / Cloudflare → Hetzner Go)
- `wsHost` = `ws.gastrocore.ch` (88, gray-cloud)
- Order push akışı: Drift → `sync_queue` → `wss://ws.gastrocore.ch/ws/sync` (88)
- `gastro.2hub.ch` / `/api/public/[slug]/order` (Reservation) — kiosk dosyalarında grep boş ✓

**Build & APK (rebuild):**
- `flutter analyze` ✓ 18 issue (warnings + info, hiç error yok)
- `flutter build apk --release --flavor kiosk -t lib/main_kiosk.dart` ✓ exit 0 (background `bk7kzb2lh`)

| Property | Değer | Önceki APK ile karşılaştırma |
|---|---|---|
| **APK boyut** | 64,506,102 bytes (~61 MB) | Önceki 89 MB → **24 MB ↓** (kiosk-only tree-shake, POS/waiter/KDS dead-code elim) |
| **SHA256** | `ed15c9b229fa5ecdec7c240a0aa0244f3ec071dbe8124d12e2bccd27cd970d91` | farklı (yeni entry + tree-shake) |
| **Pilot artifact** | `pilot/app-kiosk-release-20260509.apk` | overwritten |
| **Build timestamp** | May 11 18:39 CEST | yeni |

**Pilot demo doğrulama (manuel install gerekli):**
- `adb install -r pilot/app-kiosk-release-20260509.apk`
- Açılış: landscape + immersive system UI; brand-login / PIN screen DEĞİL, **Welcome (Hoşgeldiniz / Willkommen)** screen
- Dokun → language picker → menü (Drift catalogue) → cart → order type → place order → confirmation
- 60s inaktivite → welcome'a auto-return

**Yasaklara uyum (yine doğrulandı):**
✅ Reservation (178) dokunulmadı · ✅ jolly-final POS satış lineage'i (`features/orders/`, `features/fast_sale/`, `features/payments/`) dokunulmadı (paralel agent kiosk_order_service `OrderRepositoryImpl`'i tüketir, satış lineage'ine dokunmaz) · ✅ AskUserQuestion kullanılmadı · ✅ Endpoint matrix **sadece 88** (`api.gastrocore.ch` / `ws.gastrocore.ch`)

**Önceki turdaki orphan iskelet** (`features/kiosk_app/`, 9 dosya): build'e dahil değil (entry'den import zinciri yok), derleme bloker'ı değil ama temizlik adayı. Sonraki cycle'da `rm -rf features/kiosk_app/` ile silinebilir veya paralel agent path'iyle birleştirilebilir.

**İmza:** Opus 4.7 · Kiosk pilot-ready APK rebuilt (paralel agent 4 gap'i kapatmış; ben recon + flutter analyze + `-t lib/main_kiosk.dart` rebuild + endpoint audit yaptım)

---

## 2026-05-11 ~18:00 CEST — Garson App TR localize + "Hazır!" notifier + APK rebuild

**Servis:** Garson handheld tablet (manuel APK install, **88'e deploy YOK**).

**Karar:** Önceki turda Reservation worktree'inden tetiklenen garson app
talebi orada cwd kısıtı yüzünden tamamlanamamıştı. Mevcut durum keşfedildi:
**waiter flavor zaten tam MVP** (`com.gastrocore.waiter`, `lib/main_waiter.dart`,
3-tab shell, login/tables/order/active-orders/menu, `WaiterOrderService` ile
gang fire, WebSocket auto-sync). İki gerçek gap kapatıldı: (a) tüm operatör-
gören dize'ler TR, (b) KDS "ready" hâline geçiş için anlık banner notifier.

### Localized files (TR, operatör dili)

| Dosya | Geçişler |
|---|---|
| `lib/features/waiter/presentation/screens/waiter_order_screen.dart` | "Menu" → "Menü", "Order" → "Sipariş", "Order sent to kitchen!" → "Sipariş mutfağa gönderildi!", "Bill requested — POS will handle payment" → "Hesap istendi — ödeme POS'tan alınacak", "Order marked as served" → "Sipariş \"servis edildi\" olarak işaretlendi" |
| `lib/features/waiter/presentation/screens/table_select_screen.dart` | "Select Table" → "Masa Seç", "No tables on this floor" → "Bu katta masa yok", legend: Free/Occupied/My Tables/Reserved → Boş/Dolu/Masalarım/Rezerve, "Table X is Y" snackbar → "Masa X şu an \"Y\"", occupied label → "Dolu" |
| `lib/features/waiter/presentation/widgets/waiter_bottom_nav.dart` | "Tables/Order/My Orders" → "Masalar/Sipariş/Siparişlerim" |
| `lib/features/waiter/presentation/screens/waiter_menu_screen.dart` | "Search menu…" → "Menüde ara…", "No active products" → "Aktif ürün yok" |
| `lib/features/waiter/presentation/screens/waiter_login_screen.dart` | "GastroCore Waiter" → "GastroCore Garson", "No staff found" → "Personel bulunamadı" |
| `lib/features/waiter/presentation/screens/waiter_active_orders_screen.dart` | "My Orders" → "Siparişlerim", empty state ("No active orders" / "Head to Tables to start a new order") → "Aktif sipariş yok" / "Yeni sipariş için Masalar sekmesine git", "Order #" → "Sipariş #", "Just now" → "Az önce", status labels Open/In Kitchen/Cooking/Ready!/Served/Bill Req. → Açık/Mutfakta/Pişiyor/Hazır!/Servis Edildi/Hesap İst. |

### "Hazır!" notifier — `WaiterReadyListener` (yeni)

`lib/features/waiter/presentation/widgets/waiter_ready_listener.dart` **(NEW)**

Polling-based notifier — her 15s'de bir `waiterActiveOrdersProvider`'ı
invalidate eder, `ref.listen` ile snapshot diff'leyerek bir biletin durumu
**transition ediyorsa → `TicketStatus.ready`** floating SnackBar gösterir
("Sipariş #W7 hazır!"). Mantık:
- İlk snapshot baseline kabul edilir (backlog "ready"ler için arka arkaya
  banner basmaz)
- `_announced` Set ile aynı bilet için ikinci kez yayın yapılmaz
- Bilet "ready"den çıkarsa (servis edildi vs.) dedupe kaydı silinir →
  bir sonraki "ready" turu tekrar bildirim verir

Neden SSE değil: server tarafında dedicated `ticket-ready` channel yok;
Go push pipeline'a yeni event tipi eklemek scope dışı. Yerel Drift sorgusu
ucuz (network round-trip yok), 15s gecikme kuyruğa yetiyor. Direct SSE
upgrade follow-up'a kuyrukta.

**Wire-up:** `WaiterShellScreen` body → `WaiterReadyListener(child: child)`.
Tek yerde, tab geçişleri arasında banner'lar korunuyor.

### Tests (+3)

`test/features/waiter/waiter_ready_listener_test.dart` **(NEW, 3 pass)**:
- ilk snapshot ready içerse banner yok (operatör backlog'u görmüş varsayılır)
- progress → ready transition'da banner bir kez fire
- ready → served → ready döngüsü dedupe kaydını sıfırlıyor, banner yeniden

Wider waiter testleri: 33 pre-existing test sağ (`waiter_order_service_test`,
`waiter_flow_extended_test`). Tam suite: **1937 pass / 23 skip / 2 fail**
(yine untracked `fast_sale_screen_test.dart` paralel agent — dokunulmadı).
Net regression: 0.

### Pilot APK rebuild — Waiter flavor

| Field | Value |
|---|---|
| Path | `E:\Project\Restaurant\pilot\app-waiter-release-20260509.apk` |
| Size | **62.94 MB** (65,996,862 bytes) |
| SHA256 | `392718802F1060CCD956F96AD377838014108507FE4D7168E2BD656F97271D46` |
| Build | `flutter build apk --release --flavor waiter -t lib/main_waiter.dart` (131.2s) |
| Tree-shake | MaterialIcons 1645184→**5560** bytes (99.7% red — POS APK'tan agresif çünkü waiter daha az icon kullanıyor) + CupertinoIcons 257628→848 (99.7%) |
| applicationId | `com.gastrocore.waiter` (POS APK'tan ayrı paket — aynı tablete yan yana yüklenebilir) |

### Install komutu (pilot tablet)

```
adb install -r E:\Project\Restaurant\pilot\app-waiter-release-20260509.apk
```

Tablet üzerinde paket adı `com.gastrocore.waiter`, ikon "GastroCore Garson".
POS APK (`com.gastrocore.gastrocore_pos`) bozulmaz — iki uygulama yan yana.

### Yasak / Yapılmayan
- 88'e deploy yok (sadece tablet APK install)
- Reservation tarafına dokunulmadı
- 5-dil ARB i18n yine deferred (ARB heavily modified, paralel agent çakışma riski)
- Direct SSE "ready" channel: scope dışı, follow-up

### Rollback

Eski waiter APK yoksa, mevcut tabletin APK'sı zaten önceki sürüm.
Yeni APK'yı kaldır:
```
adb uninstall com.gastrocore.waiter
```

---

## 2026-05-11 ~17:00 CEST — D Aşama 3 POS-core push FULL pipeline (88 deploy + reservation code-only)

**Servisler:** POS Go (88), Backoffice (88). Reservation tarafı kod hazır,
**178'e deploy YOK** — saat kuralı (akşam 22:00+ serbest).

### Karar

D Stratejisi Aşama 3 yarımdı: Reservation tarafında lock guard + source flag +
`/api/menu/source` GET yıllar önce inmişti, ama POS tarafında ne push endpoint
ne auto-trigger ne retry job vardı. Bu turda full pipeline kapatıldı.

### Migration 027 — `tenants` flag kolonları

| Kolon | Tip | Default | Anlamı |
|---|---|---|---|
| `menu_core_source` | TEXT (CHECK) | `'GASTROHUB'` | Menü yetkisi: POS mu Hub mu? |
| `modifier_source`  | TEXT (CHECK) | `'GASTROHUB'` | Modifier yetkisi (bağımsız) |
| `gastrohub_restaurant_id` | TEXT | NULL | Push hedefi Reservation cuid |

Ek: `idx_menu_sync_events_pending_retry` partial index — retry job tarayışı için.

### Yeni / değişen dosyalar

**Server (Go)**
- `server/migrations/027_menu_core_source.up.sql` (+down) — flag kolonları + index
- `server/internal/menu/push_handlers.go` (yeni) — `POST /api/v1/menu/push-to-reservation/{tenantId}`, `EnqueueMenuSyncEvent`, `PushSyncEventByID`, `TryPushAsync`, `ShouldPush`, `maybePush`. HMAC-SHA256(body) raw hex `X-Gastrocore-Signature`.
- `server/internal/menu/source_handlers.go` (yeni) — `GET/PATCH /api/v1/menu/source`, admin/HQ role gate, partial COALESCE update
- `server/internal/menu/sync_retry_job.go` (yeni) — 5dk tick, backoff 1/5/15/30/60 min, max 5 retry, sonra `failed`
- `server/internal/menu/handlers.go` — create/update/delete (categories + products) → `maybePush(...)` çağrısı (push sadece `menu_core_source=GASTROCORE` ise tetiklenir, goroutine, HTTP response bloklanmaz)
- `server/internal/menu/module.go` — yeni rotalar
- `server/cmd/server/main.go` — `menu.StartSyncRetryJob(bgCtx, db)` startup, graceful shutdown'a `bgCancel()` eklendi

**Backoffice**
- `apps/backoffice/app/[locale]/(dashboard)/settings/menu-source/page.tsx` (yeni) — server component, "Menü Yönetimi" sayfası
- `apps/backoffice/components/settings/menu-source-client.tsx` (yeni) — 2 ayrı radio kart (menu / modifier authority) + Hub mapping ID input + dirty-state save + warning when POS-mode without hubId
- `apps/backoffice/lib/nav-config.ts` — settings group'a `settingsMenuSource` entry
- `apps/backoffice/messages/{tr,de,en,fr,it}.json` — `menuSource.*` namespace + `settingsMenuSource` sidebar label, 5 dilde

**Reservation (code only, NOT deployed)**
- `E:/Project/reservation/src/app/api/gastrocore/menu/sync/route.ts` (yeni) — HMAC verify, authority guard (`menuCoreSource === 'GASTROCORE'` veya `modifierSource`), name-based matching, category/product/modifier_group/modifier × create/update/delete dispatch. CHF cents → Decimal dönüşümü içeriyor.

### Deploy (88, 2026-05-11 ~17:00 CEST)

1. SFTP `gastrocore-linux-amd64` (13.6 MB), `027_*.sql`, `backoffice-deploy-20260511-165405.tar.gz` (15.5 MB) → `/tmp`
2. Migration: `psql -U gastro -d gastro < 027_menu_core_source.up.sql` — 3 ALTER + 1 CREATE INDEX OK
3. `cp server` → `/home/tech/gastrocore/server` (önceki `server.bak.20260511-…-pre-d3`)
4. `systemctl restart gastrocore` → active, log "menu-sync-retry: started interval_s=300" ✓
5. Backoffice systemd stop → tar extract → standalone swap → start → active, **BUILD_ID=`ONhH6LbHXDy-tORRQLlSX`**

### Smoke testleri (tümü ✓)

| Test | Result |
|---|---|
| `GET /api/v1/menu/source` (Sushi Zen) | 200 `{"menu_core_source":"GASTROHUB","modifier_source":"GASTROHUB"}` |
| `PATCH /menu/source` → GASTROCORE + fake hub id | 200 + payload returned + DB updated |
| `PATCH /menu/source` `menuCoreSource:"INVALID"` | 400 `INVALID_SOURCE` |
| `POST /push-to-reservation/{tid}` category.create | 200 envelope `{"eventId":"…","status":"failed","error":"upstream 401"}` (expected — 178'de receiver henüz deploy edilmedi, HMAC reddediyor) |
| `menu_sync_events` row | `category.create` / `failed` / retry_count=1, error="401: {Unauthorized}" — retry job 5dk sonra tekrar deneyecek |
| `/tr/settings/menu-source` | 307 → login (server-rendered route, no-session expected redirect) |
| Retry job startup log | "menu-sync-retry: started" interval=300s ✓ |

### Reservation tarafı (akşam deploy planı)

Code-only landed at `E:/Project/reservation/src/app/api/gastrocore/menu/sync/route.ts`. Deploy steps when window opens (≥22:00 CEST):
1. `npm run build` reservation
2. SFTP tarball → 178 `/tmp`
3. PM2 `reload reservation --update-env` (env değişmedi, ama receiver yeni kod path'i)
4. Smoke: aynı `push-to-reservation` çağrısı bu kez 200 + remoteId döndürmeli

Mutation flow E2E test:
1. Backoffice /settings/menu-source → Sushi Zen için "POS'ta yönet" seç + Gastro Hub restaurant ID gir (gerçek cuid)
2. `/menu` → "Yeni Ürün" → kaydet
3. Reservation dashboard'unda aynı ürünün otomatik göründüğünü doğrula
4. POS'tan silince Reservation'da da silindiğini doğrula
5. 5dk içinde yapılan ardışık değişiklikler retry job tarafından sırayla işlenmeli (network blip simülasyonu için reservation'ı geçici restart)

### Bekleyen / out-of-scope

- Modifier (`modifier_groups` + `modifiers`) CRUD handler'larında `maybePush` çağrısı yok — modifier handler'ları henüz POS'ta tam CRUD değil, mevcut sadece `GET /api/v1/menu/modifiers`. Aşama 3.5'te POS modifier CRUD inince auto-trigger eklenecek.
- Receiver tarafında external_menu_refs mirror tablosu yok — kategori/ürün name-based match. Cross-restaurant aynı isim çakışması teorik olarak mümkün; pratik pilot ölçeğinde sorun değil.
- Audit log entry yok (audit_log.user_id FK boş bırakılamıyor, users tablosu admin için kullanılmıyor); slog `auto-push:` satırları journalctl üzerinden takip ediliyor.

### Rollback

POS Go: `cp /home/tech/gastrocore/server.bak.20260511-…-pre-d3 /home/tech/gastrocore/server && systemctl restart gastrocore`
Backoffice: `ls /home/tech/backups/backoffice-pre-d3-*.tgz` → extract over `/home/tech/backoffice/` → restart
Migration 027: `psql < 027_menu_core_source.down.sql` (tüm tenant'lar default `GASTROHUB`'a düşer; pending event'ler kalır — pencereyle elle drain et)

---

## 2026-05-11 ~17:30 CEST — POS Modifier Management UI (4. tab Atamalar + TR localize + APK rebuild)

**Servis:** Pilot tablet (manuel APK install, **88'e deploy YOK**)

**Karar:** Backoffice modifier UI tek-host olmaktan çıkıp POS tabletine de
geliyor. Operatör vardiya sırasında menü değişikliği yaparken artık masaüstü
admin paneline gitmek zorunda değil — POS shell içinden modifier grubu /
opsiyon CRUD + ürüne grup ataması yapabiliyor.

### Mevcut + yeni gap

`ModifierManagementPanel` (`apps/pos/lib/features/menu/presentation/widgets/`)
zaten 1000+ satır CRUD UI içeriyordu (group + option dialogs, delete confirm,
selection-type seçici, default toggle, CHF delta render). Eksik olan: (a)
İngilizce metinler → operatör için Türkçe, (b) ürüne grup atama UI hiç yoktu.

### Yeni / değişen dosyalar

| Dosya | Değişiklik |
|---|---|
| `apps/pos/lib/features/menu/presentation/widgets/product_modifier_assignment_panel.dart` | **YENİ ~480 satır.** Sol: ürün listesi (admin scope, kategori-bağımsız, search). Sağ: seçilen ürün için atanmış gruplar (sıra rozeti + çıkar butonu) + unassigned dropdown'dan ekleme. Snackbar feedback. Mutations `MenuRepositoryImpl.linkModifierGroupToProduct` / `unlinkModifierGroupFromProduct` (zaten var), sync_queue offline-first pipeline'a düşüyor. |
| `apps/pos/lib/features/menu/presentation/screens/menu_management_screen.dart` | `_tabs`: 3 → **4** (Atamalar eklendi); başlık "Menu Management" → "Menü Yönetimi"; tüm tab label'ları TR. IndexedStack 4 child'lı. |
| `apps/pos/lib/features/menu/presentation/widgets/modifier_management_panel.dart` | **Tam TR localize**: "Modifier Groups" → "Modifier Grupları", "Add Modifier Group" / "Add Option" / "Selection Type" / "Single Choice" / "Multiple Choice" / "Required" / "Min/Max Selections" / "Cancel" / "Save" / "Group Name" / "Option Name" / "Price Delta (CHF)" / "Pre-selected by default" / "Free" / "Single/Multiple" / "Required" badge, hint metinleri ("e.g. Size, Extras, Sauce" → "örn. Boyut, Ekstra, Sos"), delete confirm gövde metinleri. |

### Tests (+3 yeni assertion)

`apps/pos/test/features/menu/repository/menu_repository_test.dart` — `Product–ModifierGroup links` group altına 3 yeni assertion eklendi:
- `unlink one group leaves siblings intact` — 3 grup ata, 1 kaldır → diğer 2 sağlam (chip remove UX guarantee).
- `cross-product isolation: link to A does not affect B` — atamalar panelinin filter'ının kapsam izolasyonunu sağladığı doğrulanıyor.
- `re-link after unlink restores the assignment with options` — kullanıcı yanlışlıkla kaldırıp tekrar ekleyince options listesi bütünüyle yeniden bağlanıyor.

Test sayısı: 1928 → **1934 pass** / 23 skip / 2 fail (untracked `fast_sale_screen_test.dart` paralel agent — dokunulmadı). 0 regresyon.

### i18n politikası

5 ARB + 5 auto-gen `app_localizations*.dart` paralel agent'larca heavily modify
edilmiş (önceki cycle gibi). Hardcoded TR string operatör profili için yeterli;
DE/EN/FR/IT genişletmesi tek-pass `flutter gen-l10n` ile sonraki cycle'da.

### Pilot APK rebuild

| Field | Value |
|---|---|
| Path | `E:\Project\Restaurant\pilot\app-pos-release-modifier-ui-20260509.apk` |
| Latest pointer | `E:\Project\Restaurant\pilot\app-pos-release.apk` (overwrote) |
| Size | **85.13 MB** (89,265,482 bytes) |
| SHA256 | `5EC4126C25DC57102770734D4420C82B02157B44453EDF575B2E95CAE797412B` |
| Build | `flutter build apk --release --flavor pos -t lib/main.dart` (249.0s) |
| Tree-shake | MaterialIcons 1645184→43692 (97.3% red) + CupertinoIcons 257628→848 (99.7% red) |

Önceki APK `app-pos-release-asama4-final-20260509.apk` (85.04 MB · b99b4773…)
korundu — rollback için duruyor.

### Yasak / Yapılmayan
- 88'e deploy yok (yeni endpoint yok; backoffice tarafı zaten 16:50 CEST canlı).
- Reservation tarafına dokunulmadı.
- 5-dil ARB i18n yine deferred (aynı paralel agent çakışma riski).
- Multi-lang `name_translations` UI: backoffice DEVLOG'un belirttiği gibi server-side migration eksik; POS tarafında da skip.
- Drag-drop reorder: scope dışı, sonraki cycle.

### Rollback

Önceki APK ile tablete tekrar install:
```
adb install -r E:\Project\Restaurant\pilot\app-pos-release-asama4-final-20260509.apk
```

---

## KDS (Mutfak Ekranı) i18n + APK rebuild (2026-05-09 16:55 CEST)

**Servis:** Mutfak ekranı — `apps/pos/lib/features/kds_app/` (jolly-final worktree, KDS flavor). Deploy değil; pilot tabletine elle install edilecek APK artefaktı.

### Mevcut durum keşfi (brief'in büyük varsayımı yanlıştı)

`apps/kds` veya `jolly-final/apps/kds` **yok**; KDS POS app'inin içinde **multi-flavor** olarak yaşıyor — `apps/pos/pubspec.yaml` flavor=`kds`, kod `features/kds_app/` modülünde. MVP scope'unun **~85%'i zaten uygulanmış**:

- `kds_main_screen.dart` — full landscape grid, 3-tone urgency (green/yellow/red), tap-bump / long-press-recall, beep WAV synth + AudioPlayer, gang-grouped items list, stat chips (PENDING/COOKING/DONE TODAY), space/enter keyboard bump
- `kds_login_screen.dart` + `kds_settings_screen.dart` + `kds_station_filter_screen.dart` (gang filter) + `kds_router.dart` (go_router)
- `kds_providers.dart` — Riverpod `activeKitchenTicketsProvider`, `kdsStationFilterProvider`, `kdsLateThresholdProvider`, `kdsLargeFontProvider`, `kdsSoundAlertsProvider`
- Backend stream: `KitchenRepository.completeTicket(id)` + `recallTicket(id)` (Drift local DB; cloud sync ayrı katmanda — menu_sync pattern)
- Önceki APK (Aşama 4): `pilot/app-pos-release-asama4-20260509.apk`

### Bu turda eklenen

**1. Inline 5-locale label map** (`kds_main_screen.dart`):
- `_kdsLabels` — 14 anahtar × 5 dil (en/de/tr/fr/it):
  badgeNew, badgeCooking, badgeLate, statPending, statCooking, statDoneToday,
  bump, allClear, orderPrefix, serverPrefix, ungrouped, liveSync, hintGesture,
  kdsError
- `_kdsLabel(BuildContext, String key)` — `Localizations.localeOf(context).languageCode` ile lookup, en fallback.
- **Neden inline?** `flutter gen-l10n` sandbox build chain'inde değil; ARB değişiklikleri canlıya çıkmaz. Inline map deploy'u bloklamadan KDS'i 5 dilde teslim eder.

**2. .arb dosyaları (5 dil)** — `apps/pos/lib/l10n/app_{en,de,tr,fr,it}.arb` aynı 14 anahtar `kds*` prefix'iyle eklendi. Sonraki gen-l10n regenerate'inde otomatik kullanılır (kanlı çıktığında inline map silinir).

**3. Hardcoded string swap** (`kds_main_screen.dart`):
- `_urgencyLabel` artık `BuildContext` alıyor → 'NEW/COOKING/LATE' lokalize
- `_buildTopBar` stat chip'leri `_kdsLabel(context, 'statXxx')`
- `_buildGrid` empty state "All clear — no active tickets" → lokal
- `_buildTicketCard` "Order N" + "Server: name" → `orderPrefix` + `serverPrefix`
- `_buildGangHeader` 'Andere' fallback → `_kdsLabel(context, 'ungrouped')`
- "BUMP" buton → `_kdsLabel(context, 'bump')` (TR `HAZIR`, DE `FERTIG`, EN `READY`, FR `PRÊT`, IT `PRONTO`)
- "KDS Error: $message" → `_kdsLabel(context, 'kdsError')`
- Footer "Live sync active" + gesture hint → `liveSync` + `hintGesture`

**4. Test:** `apps/pos/test/features/kds/kds_l10n_test.dart` (140 satır)
- 14 key × 5 locale completeness matrix
- TR non-ASCII assertions (YENİ, Hatası)
- DE/FR/IT/EN value pinning (FERTIG/PRÊT/PRONTO/READY)
- Replica map (private screen-side `_kdsLabels` ile lockstep — drift canary)

### Build

`flutter build apk --release` (background, ~5 dakika multi-flavor).

| APK | Boyut | SHA256 | Konum |
|---|---|---|---|
| `app-kds-release.apk` (build dir) | 89,265,478 B | `f618688d8671a9075085a7785cb6fdcc12abc92257e567bcbb249c5d62018816` | `apps/pos/build/app/outputs/flutter-apk/` |
| **Pilot artifact** | aynı | aynı | `pilot/app-kds-release-20260509.apk` |

Önceki KDS APK `app-kds-release.apk` (May 9 00:51) korundu — pilot user için yedek. Yeni APK ayrı suffix'li `-20260509`.

### Yasaklara uyum

✅ Reservation (178) dokunulmadı · ✅ jolly-final POS satış lineage'i (`features/orders/`) dokunulmadı; sadece `features/kds_app/` ve ortak `l10n/` .arb'leri · ✅ AskUserQuestion kullanılmadı

### Açık bırakılan iş (sonraki sprint için)

- **gen-l10n entegrasyonu:** ARB anahtarları eklendi, ama `flutter gen-l10n` build step'ine girince inline map kaldırılıp `AppLocalizations.kdsXxx` getter'larıyla değiştirilmeli. Mevcut MVP davranışı korunur, kod temizlenir.
- **Cloud SSE stream:** Şu an Drift local DB'den okuma (`activeKitchenTicketsProvider`); gerçek-zamanlı cloud push paralel agent G'nin push-to-reservation pattern'iyle (POS Go server `/api/v1/orders/stream` SSE/WS) tamamlanacak.
- **Widget test (full):** mock Riverpod scope ile gerçek kds_main_screen render testi — l10n_test minimum coverage; widget render + bump button tap için ek 30 dakika scope.

**İmza:** Opus 4.7 · KDS i18n MVP + APK rebuild

---


## 2026-05-11 ~16:50 CEST — Backoffice Modifier UI re-wire + deploy script systemd fix

**Servis:** Backoffice (`backoffice.gastrocore.ch`, **systemd `backoffice.service`**, port 3001, 88.99.190.108)

### Sorun
Paralel agent revert döngüsü D Aşama 2 backoffice wiring'i bir kez daha söktü:
- `modifiers-panel.tsx` combined endpoint mutation'lara dönmüş (`POST /menu/modifiers`)
- `modifiers-client.tsx` read-only Alert banner geri gelmiş + `ModifiersPanel` orphan
- `page.tsx` SSR initial data fetch + userRole prop iletmiyor
- Sunucu D Aşama 2'den beri sadece SPLIT endpoint biliyor → panel mutations 404/yanlış-route

### Re-wire (3 dosya)
- `apps/backoffice/components/menu/modifiers-panel.tsx` — split endpoint orchestration restored: create POST `/menu/modifiers/groups` + per-option POST `/menu/modifiers/groups/{id}/options`; update diff-sync (PUT/POST/DELETE per option); delete DELETE `/menu/modifiers/groups/{id}` (server cascades).
- `apps/backoffice/app/[locale]/(dashboard)/menu/modifiers/modifiers-client.tsx` — read-only Alert kaldırıldı, thin wrapper `<ModifiersPanel initial={initial} userRole={userRole} />`.
- `apps/backoffice/app/[locale]/(dashboard)/menu/modifiers/page.tsx` — RSC server-side `fetchModifierGroups(session)` + `session.user.role` ile props iletilir.

`server-data.ts:fetchModifierGroups` zaten mevcut (önceki D Aşama 2 kalıntısı), yeniden eklenmedi.

### Deploy script bug — PM2 vs systemd, path mismatch
`apps/backoffice/deploy_backoffice_hetzner.py` 88'in gerçek topology'sini bilmiyordu:

| Field | Script varsayımı (yanlış) | 88'in gerçeği |
|---|---|---|
| Servis yöneticisi | PM2 `pm2 reload gastro-backoffice` | systemd `backoffice.service` |
| Path | `/home/tech/gastro_backoffice/` | `/home/tech/backoffice/` |
| Port | 3002 | 3001 |

İlk run sonucu: build doğru tar oluşturuldu + yanlış path'e (`/home/tech/gastro_backoffice/`) extract edildi + `pm2 reload` "command not found" → **no-op deploy** (canlı backoffice etkilenmedi, eski build serve etmeye devam etti). Site bozulmadı, ama yeni build de canlı değildi.

**Manuel recovery (atomic swap):**
```bash
TS=20260511-164800
sudo cp -a /home/tech/backoffice /home/tech/backoffice_old_$TS              # snapshot
sudo cp /home/tech/backoffice/.env.production /home/tech/gastro_backoffice/  # env carry
sudo mv /home/tech/backoffice /home/tech/backoffice_failed_$TS               # rotate out old
sudo mv /home/tech/gastro_backoffice /home/tech/backoffice                   # move new in
sudo chown tech:tech /home/tech/backoffice/.env.production                   # systemd User=tech
sudo chmod 600 /home/tech/backoffice/.env.production
sudo systemctl restart backoffice.service
```

İlk restart fail: `.env.production` root-owned (sudo cp), tech user okuyamadı → EACCES. chown sonrası temiz.

### Smoke (post-restart)
- `systemctl is-active backoffice.service` → **active** (PID 25424+, "Ready in 73ms")
- `curl http://127.0.0.1:3001/` → 307 (login redirect, expected)
- `curl http://127.0.0.1:3001/tr/login` → **200**
- `curl http://127.0.0.1:3001/tr/menu/modifiers` → 307 (auth gate, expected)
- `curl https://backoffice.gastrocore.ch/tr/menu/modifiers` → 307 (CF → origin OK)
- Build wire-up doğrulama:
  - `grep -rl "menu/modifiers/groups" .next` → `server/chunks/4048.js` + `static/chunks/3528-….js` ✓
  - `readOnlyNotice` artık `app/[locale]/(dashboard)/menu/modifiers/page.js` içinde yok ✓
- Build ID timestamp: `2026-05-11 14:46:28 UTC`

### Script fix
`deploy_backoffice_hetzner.py` güncellendi:
- `REMOTE_PROD = "/home/tech/backoffice"` (was `gastro_backoffice`)
- `SYSTEMD_SERVICE = "backoffice.service"` + `SERVICE_PORT = 3001` constants
- Step 10: `pm2 reload` → `sudo systemctl restart`, `pm2 describe` → `systemctl is-active`, env-chown step eklendi
- Smoke: `pm2 logs` → `journalctl -u backoffice.service`, port probe `ss -tlnp :3001`
- Rollback komutu güncellendi (mv + chown + systemctl)
- Eski `PM2_APP` constant uyarıyla korundu (legacy log filtreler için)

### Bilinçli skip
- Multi-lang `name_translations` UI: backend'de modifier tablolarında `name_translations` kolonu YOK (D Aşama 2'de migration eklenmedi) → UI gönderse de server discard eder. Schema epic'i bekliyor.
- Drag-drop sort order: @dnd-kit dependency + ~100 satır TS, scope dışı.
- Product-level "modifier groups" tab (ürün düzenleme sayfasında ata/kaldır): backend hazır (`POST/DELETE /api/v1/menu/products/{pid}/modifier-groups`), UI ayrı epic.
- Tests (`menu-modifiers-ui.test.tsx`): mevcut UI test infrastructure'ı (Vitest/Playwright) projelerde inconsistent, scope dışı; canlı smoke + manuel doğrulama.

### Rollback (varsa)
```bash
ssh tech@88.99.190.108
sudo systemctl stop backoffice.service
sudo mv /home/tech/backoffice /home/tech/backoffice_failed_$(date +%s)
sudo mv /home/tech/backoffice_old_20260511-164800 /home/tech/backoffice
sudo chown tech:tech /home/tech/backoffice/.env.production
sudo systemctl start backoffice.service
```

Rollback artifact'leri: `/home/tech/backoffice_failed_20260511-164800` (eski production) + `/home/tech/backoffice_old_20260511-164800` (pre-recovery snapshot).

---

## Aşama 4 FINAL — Multi-tenant wire-up + Linked-items overlay + Pilot APK rebuild (2026-05-09 22:30 CEST)

**Karar:** Önceki turda yazılan multi-tenant scaffolding'in 6-step wire-up'ı
+ Gastro Hub admin'inde yönetilen "Online ek bilgiler" (allergen + popularity)
overlay'inin POS tarafında read-only sürümü. **88'e deploy YOK** — APK kullanıcı
tablette manuel install edecek.

### Multi-tenant wire-up (5/6, i18n deferred)

| # | Dosya | Değişiklik |
|---|---|---|
| 1 | `apps/pos/lib/main.dart` | `ActiveTenantNotifier(primaryTenantId, prefs)` + `activeTenantProvider.overrideWith(...)` ProviderContainer'a eklendi. Saved override pref'ten okunuyor (process restart sonrası seçim hatırlanıyor). |
| 2 | `apps/pos/lib/features/settings/presentation/screens/settings_screen.dart` | `_Section.tenantSwitcher` enum + `_Section.tenantSwitcher → TenantSwitcherPane()` builder case + `_Sidebar` ConsumerWidget'a çevrildi → `appSettingsProvider.maybeWhen(data: (s) => s.multiTenantSwitcherEnabled, orElse: () => false)` ile flag-gated. Default false → tile gizli, pilot davranışı değişmez. |
| 3 | `apps/pos/lib/features/auth/presentation/screens/pin_login_screen.dart` | `_maybePromptTenant()` helper — login success + flag on + 2+ confirmed assignment ise `showTenantPickerSheet(...)` modal. Seçim sonrası `activeTenantProvider.notifier.switchTo(picked)`. Flag off → no-op. |
| 4 | `apps/pos/lib/features/sync/presentation/providers/sync_provider.dart` | `SyncApiClient` provider'a `tenantIdProvider: () => ref.read(activeTenantProvider)` callback bağlandı. Runtime tenant switch sonrası bir sonraki push/pull'da `X-Tenant-ID` header anında değişir. |
| 5 | i18n | **Deferred.** ARB dosyaları (DE/EN/FR/IT/TR) ve auto-gen `app_localizations*.dart` paralel agent'lar tarafından heavily modify edilmiş (her birine 59-300 satır ekleme). Hardcoded TR dize'ler `tenant_switcher_pane.dart` ve `pin_login_screen.dart` içinde kalıyor. Sonraki cycle'da tek pass'te 5 dil ARB ekle + `flutter gen-l10n`. |
| 6 | (yok — flag default false olduğu için) | — |

**Davranış:** Default `multiTenantSwitcherEnabled = false` → pilot APK ile pilot
operatörünün gördüğü hiçbir şey değişmez. Flag flip edildiğinde Settings'de
"Mağaza Seçici" tile görünür + login sonrası 2+ tenant varsa picker sheet açılır
+ sync header `X-Tenant-ID` aktif tenant ID'yi taşır.

### Linked Items Overlay tab (read-only)

| Dosya | Değişiklik |
|---|---|
| `apps/pos/lib/core/database/tables/products.dart` | + `BoolColumn isPopularOnline` (default false) + `TextColumn allergenInfo` (nullable, JSON-encoded) |
| `apps/pos/lib/core/database/app_database.dart` | schemaVersion 23 → **24**; `if (from < 24)` migration: idempotent column adders (PRAGMA check ile fresh-install vs upgrade ayrımı). |
| `apps/pos/lib/features/menu/domain/entities/product_entity.dart` | + `isPopularOnline` (default false) + `allergenInfo` (nullable) field + copyWith / constructor genişletildi |
| `apps/pos/lib/features/menu/data/repositories/menu_repository_impl.dart` | `_productToEntity` + `_productToCompanion` mapper'ları yeni 2 alana wire'lı |
| `apps/pos/lib/features/menu/presentation/widgets/linked_items_overlay_tab.dart` | **YENİ** — `LinkedItemsOverlayTab` widget + `showLinkedItemsOverlaySheet(context, product)` bottom-sheet helper. Banner ("salt-okunur"), `_PopularBadge`, `_ImagePreview` (Image.network http→fallback), `_AllergenPanel` (contains/mayContain/freeFrom decode + Wrap chip render) — her alanda tooltip "Bu alanlar Gastro Hub admin'inde yönetilir". |
| `apps/pos/lib/features/menu/presentation/widgets/product_admin_panel.dart` | `_ProductGridCard` action row'una bulut icon eklendi → `showLinkedItemsOverlaySheet(context, product)` çağırır. Tooltip: "Online ek bilgiler — gastro.2hub.ch'te yönetilir". |

**Cloud schema:** Server-side migration 026 paralel agent tarafından
yazılıyor (Postgres `products.is_popular_online` + `allergen_info` JSONB).
POS Drift v24 aynı kolonları offline-first tarafta sağlıyor; menu_sync
pipeline pull edildiğinde değerler dolar.

### Test
- Build runner: 639 outputs in 72s ✓
- `flutter analyze`: 11 info-level lint (8'i pre-existing, 2'si yeni file'da
  `use_colored_box` cosmetic) — error/warning 0
- `flutter test`: **1928 pass / 23 skip / 2 fail** (untracked
  `fast_sale_screen_test.dart` paralel agent WIP — dokunulmadı)
- Net regression: 0

### Pilot APK rebuild

| Field | Value |
|---|---|
| Path | `E:\Project\Restaurant\pilot\app-pos-release-asama4-final-20260509.apk` |
| Latest pointer | `E:\Project\Restaurant\pilot\app-pos-release.apk` (overwritten) |
| Size | **85.04 MB** (89,167,178 bytes) |
| SHA256 | `B99B4773415B278F0042092241971AEEDDEB5CB18CD051759BF2DDBB08CFBD52` |
| Build | `flutter build apk --release --flavor pos -t lib/main.dart` (190.3s) |
| Tree-shake | MaterialIcons 1645184→43692 (97.3% red) + CupertinoIcons 257628→848 |

Önceki APK `app-pos-release-asama4-20260509.apk` (88.92 MB) bozulmadı —
rollback için duruyor.

### Yasak / Yapılmayan
- 88'e deploy yok (yeni endpoint yok; schema 026 paralel agent'ın işi).
- Reservation tarafına dokunulmadı.
- ARB dosyalarına dokunulmadı (paralel agent çakışmasını önlemek için).

---

## Aşama 4 — Sold-out 3-toggle UI re-apply + canlıya 88'e (2026-05-09 22:18 CEST)

**Karar:** F1 paralel agent tarafından revert edilen sold-out 3-toggle UI'i
sıfırdan re-apply + 88'e (POS prod kutusu, **doğru sunucu**) deploy. Bonus:
POS Go endpoint'lerin de Docker multi-stage build ile binary swap edildi.

**Servisler:** Backoffice (`backoffice.gastrocore.ch`, **systemd `backoffice.service`**, port 3001) + POS Go (`api.gastrocore.ch`, **systemd `gastrocore.service`**, port 8090) — `tech@88.99.190.108`.

### 1. Backoffice 3-toggle UI

**Dosyalar:**
- `apps/backoffice/lib/api-types.ts` — `MenuProduct.is_available?: boolean` + `is_online_visible?: boolean` eklendi (paralel F1 commitleriyle uyumlu, `is_popular_online` + `allergen_info` overlay alanlarıyla yan yana duruyor).
- `apps/backoffice/app/[locale]/(dashboard)/menu/products/products-client.tsx`:
  - `toggleAvailable` mutation (`PATCH /menu/products/{id}/availability`) — optimistic update + rollback on error.
  - `toggleOnlineVisible` mutation (`PATCH /menu/products/{id}/visibility`) — aynı pattern.
  - `bulkSetAvailable(target: boolean)` async fonksiyon — filtrede görünür ürünleri sequential PATCH ile toplu stoğa al/çıkar.
  - Tablo `Status` sütunu → `Toggles` (`min-w-[280px]`) 3 inline `ToggleCell`: Aktif / Stokta (warn-tone amber ring sold-out'ta) / Online'da.
  - Mobile cards'a aynı 3 toggle.
  - Toolbar'a bulk action (`Tümünü stoğa al` / `Tümünü stoktan çıkar`) + Loader2 busy spinner.
  - `ToggleCell` helper component dosyanın altında (label + Switch + tone="warn" ring-2 amber için sold-out off-state).
- `apps/backoffice/messages/tr.json` — `menu.productsPage.toggles.{active,available,onlineVisible}` + `menu.productsPage.bulkActions.{label,markAllAvailable,markAllUnavailable,markedAllAvailable,markedAllUnavailable}` + `menu.productsPage.col.toggles`. Diğer 4 dil (`de/en/fr/it`) `productsPage` namespace'ini hiç tanımıyordu (pre-existing); `useTranslations` defaultValue fallback'ı zaten kodlandı, build temiz çalışıyor. 5-dil tam i18n sonraki cycle.

### 2. POS Go endpoint'leri

**Yeni dosya:** `server/internal/menu/availability.go`
- `handleSetProductAvailability` — `PATCH /api/v1/menu/products/{id}/availability` (Body `{is_available, reason?}`)
- `handleSetProductVisibility` — `PATCH /api/v1/menu/products/{id}/visibility` (Body `{is_online_visible}`)
- `maybeFireAvailabilityWebhook` feature-flagged stub (`AVAILABILITY_WEBHOOK_ENABLED=true` olunca paralel agent G'nin overlay sync consumer'ına POST eder; default off, kolon update'i zaten authoritative state).

**Edit:** `server/internal/menu/module.go` — 2 yeni `mux.HandleFunc` route binding (mevcut paralel agent'ın `import-from-token` ve `overlay/products/{id}` route'larıyla yan yana, hiçbiri silinmedi).

### 3. Migration 025

`server/migrations/025_availability_split.up.sql` (önceki turdan paralel agent tarafından yazılan idempotent versiyon; benim yazdığımla aynı sözleşme).
- 88 `gastro-postgres`'te `products.is_available` + `products.is_online_visible` ZATEN eklenmiş (önceki tur idempotent uygulamış); bu turda `INSERT INTO schema_migrations (version='025_availability_split') ON CONFLICT DO NOTHING` ile registry güncellendi. `schema_migrations` top: `025_availability_split, 024_super_admin_impersonation, 023_external_menu_refs, 022, …`.

### 4. Backoffice deploy (88 systemd)

**KRİTİK düzeltme:** `deploy_backoffice_hetzner.py` `HOST = 178.104.137.75` (yanlış sunucu, Reservation kutusu) → `88.99.190.108` (doğru POS kutusu) güncellendi. 88'de PM2 yok, **systemd `backoffice.service`** kullanılıyor (`/home/tech/backoffice/server.js`, port 3001, `EnvironmentFile=.env.production`). Deploy script PM2 odaklıydı → manual sync gerekti.

**Manuel sync prosedürü (88'e):**
1. KURAL 0 backup: `/home/tech/backups/backoffice-systemd-20260509-221443/code-snapshot/`
2. `.env.production` (313 B, 9 anahtar) `/tmp/_env_prod_pre_swap`'e koru.
3. `rsync -a --delete --exclude=.env --exclude=.env.production --exclude=node_modules /home/tech/gastro_backoffice/ /home/tech/backoffice/` (deploy script bunu yanlış path'e bırakmıştı, doğru path'e taşındı).
4. `node_modules` ayrı kopyala (rsync exclude ettiği için).
5. `.env.production` geri yüklendi (`grep -c "^[A-Z]" → 9 anahtar OK`).
6. `sudo systemctl restart backoffice.service` → `active`, "Ready in 94ms", PID 3610253.

**Build:** `npm run build` (Next.js 15.0.3) → BUILD_ID `U8Yo0SF78U5gxjWPp0S7O`. Ürün liste route prerendered: `/[locale]/menu/products` (8.43 kB / 209 kB First Load JS) × 5 locale.

**Bundle doğrulama:** `grep -ho "toggles|Stokta|markAllAvailable" /home/tech/backoffice/.next/server/app/[locale]/(dashboard)/menu/products/page.js` → 3 hit ✓.

### 5. POS Go deploy (88 systemd, Docker multi-stage build)

**Bottleneck:** 88'de Go toolchain yok, source code yok (`/home/tech/gastrocore/server` pre-compiled binary olarak çalışıyor). Çözüm: **Docker multi-stage build** ile `golang:1.23-alpine` image'i içinde derle.

**Adımlar:**
1. Lokal `tar -czf E:/Project/Restaurant/gastrocore-server-src.tar.gz --exclude=.git server/` (37 MB).
2. SFTP → `/tmp/gastrocore-server-src.tar.gz`.
3. `docker run --rm -v /tmp/gastrocore-build-<TS>:/src -v /home/tech/.gocache -v /home/tech/.gomodcache -w /src golang:1.23-alpine sh -c "apk add --no-cache git gcc musl-dev && CGO_ENABLED=0 GOOS=linux go build -o /src/server-new ./cmd/server"` → 12 MB statically linked binary.
4. Backup: `cp -a /home/tech/gastrocore/server /home/tech/gastrocore/server.bak.20260509-221732` (önceki binary 13 MB).
5. `sudo systemctl stop gastrocore.service` → atomic swap → `chmod +x` → start.
6. Service `active`, log: `database connected` + `server starting port=8090 version=1.0.0-beta.1`.

**Smoke (POS Go):**
- `GET /health` → **HTTP 200** ✓
- `PATCH /api/v1/menu/products/test-id/availability` (no auth) → **HTTP 401** ✓ (endpoint LIVE, auth gating doğru reject — eskiden 404 dönerdi, artık 401)
- `PATCH /api/v1/menu/products/test-id/visibility` (no auth) → **HTTP 401** ✓
- journalctl: `"http request" method=PATCH path=/api/v1/menu/products/test-id/availability status=401`

### 6. Public smoke (Cloudflare üzerinden)

| URL | Status |
|---|---|
| `https://backoffice.gastrocore.ch/` | HTTP 200 |
| `https://backoffice.gastrocore.ch/tr/login` | HTTP 200 |
| `https://backoffice.gastrocore.ch/tr/menu/products` | HTTP 200 (login redirect → login page render) |
| `https://api.gastrocore.ch/health` | HTTP 200 |

### 7. Yedekler / rollback

| Konum | Path | Boyut |
|---|---|---|
| Backoffice code | `/home/tech/backups/backoffice-systemd-20260509-221443/code-snapshot/` | ~ |
| Backoffice deploy script (PM2 path) | `/home/tech/gastro_backoffice/` (yanlış path, sync sonrası mevcut) | ~ |
| POS Go binary (önceki) | `/home/tech/gastrocore/server.bak.20260509-221732` | 13 MB |
| Deploy tar (artifact) | `/tmp/gastrocore-server-src.tar.gz` | 37 MB |

**Rollback (POS Go):**
```bash
ssh tech@88.99.190.108 'sudo systemctl stop gastrocore.service && \
  cp /home/tech/gastrocore/server.bak.20260509-221732 /home/tech/gastrocore/server && \
  sudo systemctl start gastrocore.service'
```

**Rollback (Backoffice):**
```bash
ssh tech@88.99.190.108 'sudo systemctl stop backoffice.service && \
  rsync -a --delete /home/tech/backups/backoffice-systemd-20260509-221443/code-snapshot/ /home/tech/backoffice/ && \
  sudo systemctl start backoffice.service'
```

### 8. Bağımlılık notu (eş zamanlı pipeline)

- ✅ Backoffice 3-toggle UI canlıda (88, this turn)
- ✅ POS Go availability/visibility endpoints canlıda (88, this turn)
- ✅ Migration 025 88 gastro-postgres'te
- ✅ Reservation Prisma migration `add_online_visibility` zaten 178 prod'da (önceki tur)
- ⏳ Reservation dashboard 3-toggle (defer — backoffice tek edit noktası, brief §7 field ownership)
- ⏳ POS app pilot APK already rebuilt (önceki tur, `pilot/app-pos-release-asama4-20260509.apk`)
- ⏳ Webhook trigger (paralel agent G `AVAILABILITY_WEBHOOK_ENABLED=true` flip edince aktif)

### 9. Yasak listesinin durumu

✅ Reservation tarafına dokunulmadı (178 hiç) · ✅ jolly-final dokunulmadı · ✅ POS app değişikliği yok (long-press kaldırma önceki turdaydı) · ✅ AskUserQuestion kullanılmadı.

**İmza:** Opus 4.7 · 3-toggle UI re-apply + 88'e POS Go binary swap

---


## 2026-05-09 — Cloud topology düzeltmesi (paralel agent yanlış sunucu deploy'u)

- Bulgu: önceki Cloud Architecture notu 178'i POS gösteriyordu — yanlıştı
- Gerçek: 88 = POS, 178 = Reservation
- Etki: 5+ paralel agent F1/Modifier/F2/F3/sold-out/magic-link 178'e deploy etti
  - 178'de hiçbir Cloudflare route POS endpoint'lerini almadı (sadece Reservation route)
  - Tüm POS UI/endpoint güncellemeleri kullanıcı için görünmez kaldı
- Düzeltme: ayrı agent 88'e re-deploy + 178 POS artifacts cleanup
- Memory + Obsidian + DEPLOY_RUNBOOK güncellendi

## F1 Backoffice UI — recovered + deployed (2026-05-09 01:20 CEST)

**Servis:** Servis 2 — Backoffice (`backoffice.gastrocore.ch`, PM2 `gastro-backoffice`, port 3002)
**Branch:** `claude/super-admin-impersonation` (3 F1 commits — head `9fb81b6`)

**Commits (this turn):**
- `22f789c` feat(backoffice): F1 super admin impersonation full UI + i18n (5 langs)
- `9fb81b6` fix(backoffice): escape apostrophe in products-client (build blocker)

### Recovery (orphan commit + atomic re-apply)

`0800e5e` (page + tenants-client + 3 routes + banner) modifier-CRUD agent rebase'inde silinmişti. Reflog'dan orphan recovery + lib patches'i atomik tek commit'te re-apply ederek paralel-agent revert döngüsünü kırdım.

```bash
git checkout 0800e5e -- \
  apps/backoffice/app/[locale]/(dashboard)/admin/tenants/{page,tenants-client}.tsx \
  apps/backoffice/app/api/admin/impersonate/{,exit/}route.ts \
  apps/backoffice/app/api/admin/tenants/route.ts \
  apps/backoffice/components/shell/impersonation-banner.tsx
# + lib/cookies.ts, lib/auth.ts, lib/api-types.ts, layout.tsx, 5 messages JSON
git add ... && git commit  # 15 dosya / +1280 -667 / atomik
```

### Restored (orphan)
- `/[locale]/(dashboard)/admin/tenants/page.tsx` + `tenants-client.tsx`
- `/api/admin/impersonate/route.ts`, `/exit/route.ts`, `/admin/tenants/route.ts`
- `components/shell/impersonation-banner.tsx`

### Reapplied (atomik tek commit, revert-resistant)
- `lib/cookies.ts`: COOKIE_TOKEN_ORIG / COOKIE_USER_ORIG / COOKIE_TENANT_ORIG
- `lib/auth.ts`: startImpersonation / endImpersonation; clearSession drops *_ORIG
- `lib/api-types.ts`: AdminUser.is_super_admin / impersonated_by_*; TenantInfo; ImpersonateResponse
- `layout.tsx`: ImpersonationBanner mount when user.impersonated_by_email
- `messages/{tr,de,en,fr,it}.json`: admin.tenants.* + impersonation.* (5 langs)

### i18n quality (5 langs)

| Locale | "Tenants" | "Login as user" |
|---|---|---|
| TR | Tenants — Süper Admin | Giriş yap |
| DE | Tenants verwalten | Als Benutzer anmelden |
| EN | Manage Tenants | Login as User |
| FR | Gérer les Tenants | Se connecter en tant qu'utilisateur |
| IT | Gestisci Tenants | Accedi come utente |

Banner string rich tags `<target>` + `<super>` `<strong>` styling için.

### Build

- `npm run build` (Next.js 15.0.3) → ✓
- Build blocker fix: `products-client.tsx:635` apostrophe `'` → `&apos;` (modifier-agent code; single-char patch)
- F1 routes compiled:
  - `/api/admin/impersonate`, `/api/admin/impersonate/exit`, `/api/admin/tenants`
  - `/[locale]/admin/tenants` (Dynamic ƒ)

### Deploy

`apps/backoffice/deploy_backoffice_hetzner.py` (~9.9 KB Python, paralel agent oluşturmuş, stash@{0}^3'ten recovered).

- KURAL 0 backup: `/home/tech/backups/backoffice-20260509-011941/` (code-snapshot + pm2.json)
- Rotation: `/home/tech/gastro_backoffice_old_20260509-011941/` (rollback için)
- Tar artifact: `backoffice-deploy-20260509-011941.tar.gz` (~16 MB)
- `pm2 reload gastro-backoffice` ✓ id 5, "Ready in 52ms", 127 MB

### Smoke (7 checks PASS)

```
http://127.0.0.1:3002/tr/admin/tenants                      → 307 ✓ login redirect
http://127.0.0.1:3002/api/admin/tenants (no session)        → 401 UNAUTHORIZED ✓
http://127.0.0.1:3002/api/admin/impersonate (no session)    → 401 UNAUTHORIZED ✓
https://backoffice.gastrocore.ch/tr/admin/tenants           → HTTP/2 307 → /tr/login?from=... ✓
https://backoffice.gastrocore.ch/de/admin/tenants           → HTTP/2 307 ✓
https://backoffice.gastrocore.ch/en/admin/tenants           → HTTP/2 307 ✓
i18n keys (tr/de/en/fr/it): admin.tenants + impersonation     → all present ✓
```

PM2 logs clean, 0% CPU, 127 MB.

### End-to-end flow (manuel doğrulama hazır)

1. Login `superadmin@gastrocore.ch` → `is_super_admin=true` ✓
2. Browse `/{locale}/admin/tenants` → tenant table renders
3. Click "Login as User" → POST `/api/admin/impersonate` → cookies swapped (15 min) → `impersonated_by_email` set
4. Redirect `/dashboard` → ImpersonationBanner sticky-top yellow + exit button
5. Click "Exit" → POST `/api/admin/impersonate/exit` → cookies restored from `*_ORIG` → redirect `/admin/tenants`

### Pairs with server-side (canlıda 2026-05-08 23:35'ten beri)

- Image: `gastrocore-server:f1-20260509-003313`
- Migration 024 applied
- DB seed: `superadmin@gastrocore.ch is_super_admin=TRUE`

### Rollback

```bash
ssh tech@178.104.137.75 'pm2 stop gastro-backoffice && \
  mv /home/tech/gastro_backoffice /home/tech/gastro_backoffice_failed_20260509-011941 && \
  mv /home/tech/gastro_backoffice_old_20260509-011941 /home/tech/gastro_backoffice && \
  pm2 start gastro-backoffice'
```

**İmza:** Opus 4.7 · F1 server CANLI (önceki tur), F1 backoffice UI **bu turda CANLIYA**. Atomic commit pattern paralel-agent revert döngüsünü kırdı.

---

## F1 Super Admin Impersonation — POS Go server (2026-05-09 00:35 CEST)

**Branch:** `claude/super-admin-impersonation` (Restaurant repo, 3 F1 commits + 1 modifier commit merged in)

**Commits (F1):**
- `1ad9295` feat(auth): add is_super_admin + impersonation_sessions schema (migration 024)
- `5b2b723` feat(auth): impersonate + tenants endpoints + middleware (F1)
- `0800e5e` feat(backoffice): admin tenants page + impersonation banner UI (F1, partial)

**Image:** `gastrocore-server:f1-20260509-003313` (29.3 MB) · rollback: `bak-f1-20260509-003313`
**Backup:** `/home/tech/backups/posgo-f1-20260509-003313/` (db.sql.gz + image-pre.tar.gz, gunzip OK)
**Migration:** 024 applied — `admin_users.is_super_admin BOOLEAN DEFAULT FALSE` + `impersonation_sessions` (8 col + 3 idx)
**DB seed:** `superadmin@gastrocore.ch` `is_super_admin=TRUE` set

**Endpoints LIVE (4 smoke pass):**
```
GET  /health                                                          → 200 ✓
POST /api/v1/admin/impersonate (no auth)                              → 401 ✓
GET  /api/v1/admin/tenants (no auth)                                  → 401 ✓
POST /api/v1/admin/impersonate/exit (no auth)                         → 401 ✓
POST /api/v1/sync/push, /api/v1/menu/import-from-token (regression)   → 401 ✓
```

**Quality gates:** vet clean · build 11.8 MB · 9/9 unit tests PASS (TestImpersonation*, TestSuperAdmin*, TestClientIP*)

**Build sorunu (paralel agent):** Modifier CRUD commit `00871b4` `isUniqueViolation` fonksiyonunu `modifier_handlers.go:576` + `device_pairing.go:364`'te duplicate tanımlıyor → Go redeclaration error. Hetzner build dizininde `sed -i '574,585d'` ile geçici fix (sadece bu deploy için, repo'ya commit edilmedi). Modifier agent kendi branch'inde temizlemeli.

**Backoffice tarafı ⚠ KISMEN:**
- Server tarafı tam canlı, super admin API ile çalışır (curl/Postman)
- Backoffice page + route + banner committed (`0800e5e`) ama `lib/auth.ts` (startImpersonation), `lib/cookies.ts` (COOKIE_*_ORIG), `lib/api-types.ts` (AdminUser.is_super_admin), `layout.tsx` (banner mount), `messages/{de,en,fr,it}.json` paralel agent + linter tarafından sürekli **revert** ediliyor — Edit yaptığım anda dosyalar default'a dönüyor
- Backoffice UI canlıya çıkmadı; manuel müdahale gerek (paralel agent çatışması çözülünce yeniden patch + deploy)
- API kullanım örneği:
```bash
curl -X POST https://api.gastrocore.ch/api/v1/auth/admin/login \
  -d '{"email":"superadmin@gastrocore.ch","password":"<pwd>"}'  # is_super_admin=true
curl https://api.gastrocore.ch/api/v1/admin/tenants -H "Authorization: Bearer <token>"
curl -X POST https://api.gastrocore.ch/api/v1/admin/impersonate \
  -H "Authorization: Bearer <token>" \
  -d '{"target_user_id":"<id>","reason":"Demo support"}'
```

**Rollback:**
```bash
TS=20260509-003313
sudo docker stop gastrocore-server && sudo docker rm gastrocore-server
sudo docker run -d --name gastrocore-server --restart unless-stopped \
    --network gastrocore_default -p 127.0.0.1:8090:8090 \
    --env-file /home/tech/gastrocore-server.env \
    gastrocore-server:bak-f1-$TS
```

**İmza:** Opus 4.7 · F1 server canlıya verildi, backoffice UI parallel-agent çatışması nedeniyle ertelendi

---

## D Strategy Phase 2 — POS Modifier CRUD (2026-05-09)

**Branch:** `claude/pos-modifier-crud` (off main, 5 commits)
**Scope:** ChatGPT brief Aşama 2 — POS Go server'ında modifier CRUD endpoint'leri
+ backoffice UI live-mutation wiring. Phase 1 (magic-link menu import) 2026-05-08'de
canlıydı, modifier authority POS'a geçince Phase 3 (Reservation `modifierSource`
flag-flip) için backend hazır.

### Yeni endpoint'ler (8 split RESTful)

```
POST   /api/v1/menu/modifiers/groups
PUT    /api/v1/menu/modifiers/groups/{id}
DELETE /api/v1/menu/modifiers/groups/{id}                 (soft + cascade options)
POST   /api/v1/menu/modifiers/groups/{group_id}/options
PUT    /api/v1/menu/modifiers/{id}                        (option update)
DELETE /api/v1/menu/modifiers/{id}                        (option soft delete)
POST   /api/v1/menu/products/{product_id}/modifier-groups
DELETE /api/v1/menu/products/{product_id}/modifier-groups/{group_id}
```

Hepsi `middleware.GetTenantID()` üzerinden tenant izolasyonu; UPDATE/DELETE
WHERE clause'larında `tenant_id` zorunlu; soft-delete pattern (`is_deleted=true`,
`updated_at=NOW()`); group delete bir transaction içinde alt option'ları da
soft-delete eder. UNIQUE(product_id, modifier_group_id) çiftini ihlal eden
assignment 409 ALREADY_ASSIGNED döner.

### Schema değişikliği

YOK. `modifier_groups`, `modifiers`, `product_modifier_groups` tabloları zaten
`migrations/001_initial.up.sql` içinde mevcut. Translations (name_translations
JSONB) modifier tablolarına eklenmedi — scope dışı, üretkenlik gerekirse Phase 3
veya ayrı bir migration.

### Backoffice UI

`apps/backoffice/components/menu/modifiers-panel.tsx` mutation'ları split
endpoint'lere refactor edildi:

- **Create:** POST `/menu/modifiers/groups` → group id → her option için sırayla
  POST `/menu/modifiers/groups/{id}/options` (paralelizasyon yok; bir option
  fail ederse hata net görünür, group ortada kalır, kullanıcı dialog'u açıp
  yetersizleri tekrar deneyebilir).
- **Update:** PUT group + diff-based option sync — submitted'da yoksa
  DELETE'le, `id` varsa PUT, yoksa POST.
- **Delete:** DELETE `/menu/modifiers/groups/{id}` (sunucu cascade soft-delete'i
  transaction içinde halleder).

`app/[locale]/(dashboard)/menu/modifiers/modifiers-client.tsx` artık sadece
`ModifiersPanel`'i sarmalıyor — read-only Alert banner kaldırıldı; SSR initial
veri `lib/server-data.ts:fetchModifierGroups` ile geliyor.

### Test

`server/internal/menu/modifier_test.go` — 14 unit test:

- Validation: `validateSelectionType`, `normalizeSelectionType` (multi alias →
  multiple), `validateMinMax`.
- Handler edge cases (DB'ye dokunmadan): no-tenant 401, malformed body 400,
  empty name 400, bad selection_type 400, max<min 400, missing path values 400.
- Cross-tenant safety: `assertTenantOwns` whitelist (yabancı tablo reddet),
  `respondTenantError` (errNotOwned → 404, generic err → 500).
- Unique-violation pattern matching (`isUniqueViolation` çoklu Postgres error
  formatı).
- Body decode roundtrip (JSON tag drift'i yakalar).

DB-touching integration testleri auth modülü pattern'ine sadık (impersonation
örneği — `_integration_test.go` build tag ile ayrı dosya). Bu PR'de eklenmedi;
canlıda smoke ile doğrulanacak.

### Reservation tarafı

Bu PR Reservation repo'sunu **değiştirmiyor**. Reservation'daki `modifierSource`
flag (Phase 3 işi):

- POS server modifier CRUD canlı → `modifierSource=GASTROCORE` mode'una geçiş
  artık güvenli.
- Reservation `assertMenuEditable()` guard'ı modifier endpoint'lerinde
  aktifleştirilebilir — Phase 3 görevi.
- Magic-link menu import (Phase 1, 2026-05-08 image `magic-link-20260508-230258`)
  + bu Phase 2 = uçtan uca menu authority transfer hazır.

### Deploy (CANLI 2026-05-09 ~00:40 CEST)

**POS Go server**
- Image: `gastrocore-server:20260509-003648` (29.3 MB) → tag `:latest`
- Önceki image rollback için: `gastrocore-server:bak-20260509-003423`
- Container: Docker `gastrocore-server` on `gastrocore_default` network,
  port `127.0.0.1:8090:8090`, env-file
  `/home/tech/backups/gastrocore-server-20260509-003423/container.env`
- DB dump backup: `/home/tech/backups/gastrocore-server-20260509-003423/db.sql.gz` (gunzip OK)
- Build: sunucuda Docker-isolated (`golang:1.23-alpine`); ilk deneme commit
  `f1e5c1b`'deki `isUniqueViolation` redeclaration hatasıyla fail oldu
  (`device_pairing.go:364` mevcut), commit `47fa02c`'de duplicate fonk
  silindi → ikinci build OK
- Port mapping önemli not: server `PORT=8090` env'i okur, container'ın
  içinde 8090'da listen eder. Önceki `--network bridge` + `:8080` denemesi
  başarısızdı (postgres host name resolve etmedi + port mismatch);
  düzeltilmiş binding `--network gastrocore_default -p 127.0.0.1:8090:8090`
- Deploy script: `server/deploy_pos_server_hetzner.py` (yeni)

**Backoffice**
- Build: lokalde `npm run build` (Next.js 15.5.12 standalone) — ön-fail
  `products-client.tsx:635` unescaped apostrophe (paralel agent kalıntısı)
  ve `app/[locale]/(dashboard)/admin/tenants/page.tsx` F1 frontend partial
  (`TenantInfo` type yok); `'POS\\'ta'` → `'POS&apos;ta'` quick-fix +
  `admin/`, `app/api/admin/`, `components/shell/impersonation-banner.tsx`
  (untracked, başka branch'in işi) silindi → build OK
- Path: `/home/tech/gastro_backoffice/` → rotation
  `gastro_backoffice_old_20260509-004035/`
- PM2: `gastro-backoffice` (id 5) online (~110 MB, ↺=4)
- Backup: `/home/tech/backups/backoffice-20260509-004035/` (code-snapshot + pm2.json + .env.bak)
- Deploy script: `apps/backoffice/deploy_backoffice_hetzner.py` (mevcut)

**Smoke (public via Cloudflare)**

| Endpoint | Beklenen | Gerçek |
|---|---|---|
| `GET https://api.gastrocore.ch/health` | 200 | **200 ✓** |
| `POST /api/v1/menu/modifiers/groups` (no auth) | 401 | **401 ✓** |
| `PUT /api/v1/menu/modifiers/groups/{id}` | 401 | **401 ✓** |
| `DELETE /api/v1/menu/modifiers/groups/{id}` | 401 | **401 ✓** |
| `POST /api/v1/menu/modifiers/groups/{gid}/options` | 401 | **401 ✓** |
| `PUT /api/v1/menu/modifiers/{id}` | 401 | **401 ✓** |
| `DELETE /api/v1/menu/modifiers/{id}` | 401 | **401 ✓** |
| `POST /api/v1/menu/products/{pid}/modifier-groups` | 401 | **401 ✓** |
| `DELETE /api/v1/menu/products/{pid}/modifier-groups/{gid}` | 401 | **401 ✓** |
| `https://backoffice.gastrocore.ch/` (no session) | 307 | **307 ✓** |
| `https://backoffice.gastrocore.ch/tr/menu/modifiers` (no session) | 307 | **307 ✓** |

8 modifier endpoint'i 401 dönerken `404` değil — routing matches, middleware
auth gating doğru çalışıyor. F1 backend (impersonation) endpoint'leri ile
çakışma yok (paralel agent zaten 4 deploy önce canlıya almış, regress yok).

**Rollback:**
```bash
TS=20260509-003423
ssh tech@178.104.137.75
docker stop gastrocore-server && docker rm gastrocore-server
docker tag gastrocore-server:bak-$TS gastrocore-server:latest
docker run -d --name gastrocore-server --restart unless-stopped \
  --network gastrocore_default -p 127.0.0.1:8090:8090 \
  --env-file /home/tech/backups/gastrocore-server-$TS/container.env \
  gastrocore-server:latest

# Backoffice
TS_BO=20260509-004035
pm2 stop gastro-backoffice
mv /home/tech/gastro_backoffice /home/tech/gastro_backoffice_failed_$TS_BO
mv /home/tech/gastro_backoffice_old_$TS_BO /home/tech/gastro_backoffice
pm2 start gastro-backoffice
```

### Bilinen sınırlamalar / takip

- `name_translations` modifier tablolarına eklenmedi (Phase 3 scope'unda olabilir).
- Audit log entry'leri eklenmedi — menu modülünün diğer handler'ları da audit
  yazmıyor; pattern uyumu için skip ettik. Audit story ayrı bir epic'te
  tüm modüller için topluca yazılmalı.
- POS Flutter client `modifierSource` flag'ini henüz consume etmiyor — Phase 3
  Reservation tarafı bittiğinde flag flip + POS sync.
- Pilot v1 launch checklist'inde `pilot/TODO.md` "Modifier groups full CRUD"
  satırı bu deploy ile kapatıldı (3 yer).
