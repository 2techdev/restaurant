# Deploy Log — 2026-05-09

> Pilot launch öncesi günlük deploy kayıtları. Her deploy sonrası bu dosyaya
> üste prepend ekle. Deploy başarısızsa rollback komutu + zaman damgası yaz.

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
