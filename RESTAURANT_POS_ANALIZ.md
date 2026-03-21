# Restoran POS Sistemi - Kapsamli Analiz ve Mimari Plan

## Proje Amaci

Uygun fiyatli, offline calisan, Android tabanli restoran POS yazilimi gelistirmek.
Ilk hedef: tamamen offline calisan restoran sistemi.
Sonraki adimlar: web paneli, sunucu sync, online siparis.

---

## 1. Acik Kaynak Alternatif Degerlendirmesi

### A) Market / Perakende Icin En Gucluler

| Proje | Lisans | GitHub Yildiz | Son Surum | Ozellikler | Dezavantajlar |
|-------|--------|---------------|-----------|------------|---------------|
| **ERPNext + POS Awesome** | GPL | 32.2k | v16.9.0 (10 Mart 2026) | Offline mod, background sync, vardiya, barkod, tartili urun | Web tabanli, agir framework, Python/JS |
| **Lakasir** | GPL-3.0 | 848 | Ekim 2025 | Laravel API + Flutter mobile, barkod, stok, voucher, termal yazici | Offline-sync ERPNext kadar net degil |
| **NexoPOS** | GPL-3.0 | 1.2k | 7 Mart 2026 | Modul gelistirme, REST API | Marketplace ucretli eklentiler, vendor lock riski |
| **OSPOS** | Ozel | 4.1k | Haziran 2025 | Stok, vergi, fatura, rewards, restoran masalari | Footer imzasi zorunlu - white-label engeli |

### B) Restoran Icin Adaylar

| Proje | Lisans | GitHub Yildiz | Son Surum | Ozellikler | Dezavantajlar |
|-------|--------|---------------|-----------|------------|---------------|
| **ViewTouch** | GPL-3.0 | 214 | 27 Aralik 2025 | Restoran icin tasarlanmis, RPi destegi, mutfak gosterimi | C++/X11, modern web stack degil |
| **FloreantPOS** | Acik | ~30k restoran | v1.5(?) | Offline, VAT, raporlar, dine-in/delivery/kitchen | Git deposu dagnik, gelistirme akisi puruzlu |
| **SambaPOS** | GPL-3.0 | ~2k | v3 | Turkiye'de yaygin, guclu siparis yonetimi, modular | C#/WPF Windows masaustu - mobil degil |

### C) Hem Restoran Hem Market

| Proje | Lisans | GitHub Yildiz | Ozellikler | Dezavantajlar |
|-------|--------|---------------|------------|---------------|
| **Odoo Community + OCA/pos** | LGPL-3.0 | 49.4k | Floor plan, siparis yonetimi, mutfak bildirimi, adisyon bolme | Framework agir, gelistirme disiplini gerekli |

### D) Uzak Durulmasi Gereken Cekirdekler

- **OSPOS**: White-label kisiti (footer imzasi kaldirilmiyor)
- **NexoPOS**: Marketplace bagimliligi, ucretli eklenti modeli
- **FloreantPOS**: Dagnik upstream, temiz Git tabani yok

---

## 2. Teknoloji Secimi Karsilastirmasi

### Flutter vs Native Kotlin vs ERPNext

| Faktor | Flutter | Native Kotlin | ERPNext Uzerine |
|--------|---------|---------------|-----------------|
| Android app | Mukemmel (native-yakini) | En iyi (native) | Web tabanli (tarayici) |
| Gercek offline | SQLite + Drift (tam offline) | Room + SQLite (tam offline) | Sinirli ("gecici offline") |
| Web dashboard (Phase 2) | Ayni kod tabani | Ayri kod gerekli | Hazir var |
| iOS (gelecek) | Ayni kod tabani | KMP (olgunlasmamis) | Web olarak var |
| Gelistirme hizi | %30-40 daha hizli MVP | Daha yavas, tek platform | Hizli ama framework ogrenmek lazim |
| Termal yazici | unified_esc_pos_printer | ESCPOS-ThermalPrinter | Web USB (sinirli) |
| Tek kisi/kucuk takim | Tek kod tabani | Birden fazla kod tabani | Tek ama Python/JS bilgisi sart |
| Maliyet | Dusuk (tek codebase) | Yuksek (platform basina) | Orta (framework ogrenme sureci) |
| Ticari urun markalama | Kolay, tam kontrol | Kolay, tam kontrol | Lisans karmasik (GPL) |
| Performans | Cok iyi | En iyi | Tarayici bagimli |

### Onerilen Stack (Flutter Yolu)

- **Client:** Flutter 3.x + Dart
- **Yerel DB:** Drift (SQLite ORM, type-safe, migration destegi, reactive streams)
- **State Management:** Riverpod 2.x
- **Sync Engine:** Custom sync protokolu (Phase 2)
- **Server (Phase 2):** Go veya Node.js/Express
- **Server DB:** PostgreSQL
- **Yazici:** unified_esc_pos_printer (Bluetooth, USB, Network, BLE tek API)
- **DI:** get_it + injectable
- **Navigation:** go_router
- **API:** dio + retrofit

### Onerilen Stack (ERPNext Yolu)

- **Client:** Web tarayici (ERPNext POS UI)
- **Backend:** Frappe Framework (Python)
- **DB:** MariaDB
- **Offline:** POS Awesome eklentisi ile sinirli offline
- **Mobile:** WebView sarmalayici veya ayri Flutter app (hibrit karmasiklik)

### Onerilen Stack (Hibrit: Flutter + ERPNext Backend)

- **Client:** Flutter (tam offline Android)
- **Backend (Phase 2):** ERPNext API'leri
- **Sync:** Flutter <-> ERPNext REST API
- **Avantaj:** Android'de gercek offline + ERPNext'in hazir muhasebe/stok modulleri
- **Dezavantaj:** Iki farkli ekosistem, entegrasyon maliyeti yuksek

---

## 3. Mimari Tasarim (Flutter Sifirdan Yolu)

### Genel Sistem Mimarisi

```
Phase 1 (Offline Android):

  [Android Tablet/Telefon]
  +------------------------------------------+
  |  Flutter App                              |
  |  +--------------------------------------+ |
  |  | Presentation (UI/Widgets)            | |
  |  +--------------------------------------+ |
  |  | Application (Use Cases)              | |
  |  +--------------------------------------+ |
  |  | Domain (Entity, Repository arayuz)   | |
  |  +--------------------------------------+ |
  |  | Data (Drift/SQLite, Printer, Local)  | |
  |  +--------------------------------------+ |
  |  | SQLite DB (tum veri yerelde)          | |
  |  +--------------------------------------+ |
  |  | Bluetooth Termal Yazici              | |
  +------------------------------------------+

Phase 2 (Sunucu Sync Eklenir):

  [Android Tablet x N]          [Bulut Sunucu]
  +--------------------+         +------------------------+
  |  Flutter App       |  <----> | Go/Node API Server     |
  |  Yerel SQLite      |  sync   | PostgreSQL             |
  |  Offline-first     |         | Auth / Multi-tenant    |
  +--------------------+         +------------------------+
                                        |
                                 +------+------+
                                 | Web Panel   |
                                 | (Flutter Web|
                                 |  veya React)|
                                 +--------------+

Phase 3 (Tam Platform):

  [Tabletler]  [Web Panel]  [QR Menu]  [Online Siparis]
      \           |              |            /
       \          |              |           /
        +-------- API Gateway (Go/Node) ---+
                       |
              +--------+--------+
              | PostgreSQL      |
              | Redis (cache)   |
              | S3 (gorseller)  |
              +-----------------+
```

### Clean Architecture Katmanlari

```
+---------------------------------------------------+
|                  PRESENTATION                      |
|  Ekranlar / Widget'lar / Sayfalar                  |
|  State: Riverpod provider'lari                     |
+---------------------------------------------------+
|                  APPLICATION                       |
|  Use Case'ler (her is aksiyonu icin bir tane)      |
|  Application Service'ler                           |
|  DTO'lar / ViewModel'ler                           |
+---------------------------------------------------+
|                    DOMAIN                          |
|  Entity'ler (Order, Product, Table, Payment...)    |
|  Value Object'ler (Money, Quantity, PIN...)         |
|  Repository Arayuzleri (abstract)                  |
|  Domain Service'ler (fiyat hesaplama, vergi)        |
|  Domain Event'ler                                  |
+---------------------------------------------------+
|                     DATA                           |
|  Repository Implementasyonlari                     |
|  Drift DAO'lari (SQLite tablo + sorgular)          |
|  Sync Engine (kuyruk, upload, download)            |
|  Printer Service (ESC/POS soyutlamasi)             |
+---------------------------------------------------+
```

### Temel Mimari Kararlar

1. **Dependency Rule:** Bagimliliklar sadece iceri dogru. Domain, Data veya Presentation'i bilmez.
2. **Feature-first modul yapisi:** Her ozellik (siparisler, menu, masalar, odemeler, mutfak, raporlar) kendi icinde bagimsiz.
3. **Multi-tenant ilk gunden:** Her tablo `tenant_id` iceriyor. Offline'da bile cihaz bir restoran kimligine sahip.
4. **Event-driven:** Domain event'leri (OrderCreated, PaymentCompleted) in-app event bus uzerinden yayinlanir.
5. **Fiyatlar integer:** TL yerine kurus (1500 = 15.00 TL) - floating-point hatalari onlenir.
6. **UUID primary key:** Offline cihazlar bagimsiz kayit olusturabilir, merkezi sequence gerekmez.

---

## 4. Veritabani Semasi (Core Tablolar)

### Tenant ve Kullanicilar

```sql
tenants (
  id              TEXT PRIMARY KEY,   -- UUID
  name            TEXT NOT NULL,
  address         TEXT,
  phone           TEXT,
  tax_rate        REAL DEFAULT 0,
  currency_code   TEXT DEFAULT 'TRY',
  settings_json   TEXT,
  created_at      INTEGER NOT NULL,
  updated_at      INTEGER NOT NULL
)

users (
  id              TEXT PRIMARY KEY,
  tenant_id       TEXT NOT NULL,
  name            TEXT NOT NULL,
  pin_hash        TEXT NOT NULL,       -- 4-6 haneli PIN, hashli
  role            TEXT NOT NULL,       -- 'admin','manager','waiter','cashier','kitchen'
  is_active       INTEGER DEFAULT 1,
  permissions_json TEXT,
  created_at      INTEGER NOT NULL,
  updated_at      INTEGER NOT NULL,
  sync_status     INTEGER DEFAULT 0   -- 0=synced, 1=pending, 2=conflict
)
```

### Menu / Urunler

```sql
categories (
  id              TEXT PRIMARY KEY,
  tenant_id       TEXT NOT NULL,
  name            TEXT NOT NULL,
  display_order   INTEGER DEFAULT 0,
  color           TEXT,
  icon            TEXT,
  parent_id       TEXT,               -- alt kategoriler
  is_active       INTEGER DEFAULT 1,
  created_at      INTEGER,
  updated_at      INTEGER,
  sync_status     INTEGER DEFAULT 0
)

products (
  id              TEXT PRIMARY KEY,
  tenant_id       TEXT NOT NULL,
  category_id     TEXT,
  name            TEXT NOT NULL,
  description     TEXT,
  price           INTEGER NOT NULL,    -- kurus cinsinden
  cost_price      INTEGER DEFAULT 0,
  tax_group       TEXT DEFAULT 'default',
  image_path      TEXT,
  barcode         TEXT,
  is_active       INTEGER DEFAULT 1,
  display_order   INTEGER DEFAULT 0,
  prep_time_min   INTEGER,
  printer_group   TEXT DEFAULT 'kitchen',
  created_at      INTEGER,
  updated_at      INTEGER,
  sync_status     INTEGER DEFAULT 0
)

modifier_groups (
  id              TEXT PRIMARY KEY,
  tenant_id       TEXT NOT NULL,
  name            TEXT NOT NULL,       -- "Boyut", "Ekstralar", "Pisirme"
  selection_type  TEXT DEFAULT 'single',
  min_selections  INTEGER DEFAULT 0,
  max_selections  INTEGER DEFAULT 1,
  is_required     INTEGER DEFAULT 0,
  display_order   INTEGER DEFAULT 0,
  created_at      INTEGER,
  updated_at      INTEGER,
  sync_status     INTEGER DEFAULT 0
)

modifiers (
  id              TEXT PRIMARY KEY,
  tenant_id       TEXT NOT NULL,
  group_id        TEXT NOT NULL,
  name            TEXT NOT NULL,
  price_delta     INTEGER DEFAULT 0,
  is_default      INTEGER DEFAULT 0,
  display_order   INTEGER DEFAULT 0,
  created_at      INTEGER,
  updated_at      INTEGER,
  sync_status     INTEGER DEFAULT 0
)

product_modifier_groups (
  id              TEXT PRIMARY KEY,
  product_id      TEXT NOT NULL,
  modifier_group_id TEXT NOT NULL,
  display_order   INTEGER DEFAULT 0
)
```

### Kat Plani / Masalar

```sql
floors (
  id              TEXT PRIMARY KEY,
  tenant_id       TEXT NOT NULL,
  name            TEXT NOT NULL,       -- "Ana Salon", "Teras", "Bar"
  display_order   INTEGER DEFAULT 0,
  created_at      INTEGER,
  updated_at      INTEGER,
  sync_status     INTEGER DEFAULT 0
)

tables (
  id              TEXT PRIMARY KEY,
  tenant_id       TEXT NOT NULL,
  floor_id        TEXT NOT NULL,
  name            TEXT NOT NULL,       -- "M1", "M2", "Bar-1"
  capacity        INTEGER DEFAULT 4,
  shape           TEXT DEFAULT 'rectangle',
  pos_x           REAL DEFAULT 0,
  pos_y           REAL DEFAULT 0,
  width           REAL DEFAULT 1,
  height          REAL DEFAULT 1,
  status          TEXT DEFAULT 'available',
  current_order_id TEXT,
  created_at      INTEGER,
  updated_at      INTEGER,
  sync_status     INTEGER DEFAULT 0
)
```

### Siparisler / Adisyonlar

```sql
orders (
  id              TEXT PRIMARY KEY,
  tenant_id       TEXT NOT NULL,
  order_number    INTEGER NOT NULL,    -- gunluk sira numarasi
  order_type      TEXT DEFAULT 'dine_in', -- 'dine_in','takeaway','delivery','online'
  table_id        TEXT,
  waiter_id       TEXT,
  customer_name   TEXT,
  guest_count     INTEGER DEFAULT 1,
  status          TEXT DEFAULT 'open',
  subtotal        INTEGER DEFAULT 0,
  tax_amount      INTEGER DEFAULT 0,
  discount_amount INTEGER DEFAULT 0,
  discount_type   TEXT,
  discount_value  REAL,
  total           INTEGER DEFAULT 0,
  notes           TEXT,
  opened_at       INTEGER NOT NULL,
  closed_at       INTEGER,
  created_at      INTEGER,
  updated_at      INTEGER,
  sync_status     INTEGER DEFAULT 0,
  device_id       TEXT NOT NULL
)

order_items (
  id              TEXT PRIMARY KEY,
  tenant_id       TEXT NOT NULL,
  order_id        TEXT NOT NULL,
  product_id      TEXT NOT NULL,
  product_name    TEXT NOT NULL,       -- siparis anindaki isim (denormalize)
  quantity        REAL NOT NULL DEFAULT 1,
  unit_price      INTEGER NOT NULL,
  subtotal        INTEGER NOT NULL,
  tax_amount      INTEGER DEFAULT 0,
  discount_amount INTEGER DEFAULT 0,
  status          TEXT DEFAULT 'ordered',
  sent_to_kitchen INTEGER DEFAULT 0,
  notes           TEXT,               -- "sogansiz", "ekstra acili"
  course          INTEGER DEFAULT 1,
  created_at      INTEGER,
  updated_at      INTEGER,
  sync_status     INTEGER DEFAULT 0
)

order_item_modifiers (
  id              TEXT PRIMARY KEY,
  order_item_id   TEXT NOT NULL,
  modifier_id     TEXT NOT NULL,
  modifier_name   TEXT NOT NULL,
  price_delta     INTEGER DEFAULT 0,
  created_at      INTEGER
)
```

### Odemeler

```sql
payments (
  id              TEXT PRIMARY KEY,
  tenant_id       TEXT NOT NULL,
  order_id        TEXT NOT NULL,
  payment_method  TEXT NOT NULL,       -- 'cash','credit_card','debit_card','other'
  amount          INTEGER NOT NULL,
  tip_amount      INTEGER DEFAULT 0,
  reference       TEXT,
  received_by     TEXT,
  paid_at         INTEGER NOT NULL,
  created_at      INTEGER,
  updated_at      INTEGER,
  sync_status     INTEGER DEFAULT 0
)
```

### Vardiyalar / Kasa Yonetimi

```sql
shifts (
  id              TEXT PRIMARY KEY,
  tenant_id       TEXT NOT NULL,
  user_id         TEXT NOT NULL,
  device_id       TEXT NOT NULL,
  opening_cash    INTEGER NOT NULL,
  closing_cash    INTEGER,
  expected_cash   INTEGER,
  difference      INTEGER,
  total_sales     INTEGER DEFAULT 0,
  total_orders    INTEGER DEFAULT 0,
  status          TEXT DEFAULT 'open',
  opened_at       INTEGER NOT NULL,
  closed_at       INTEGER,
  notes           TEXT,
  created_at      INTEGER,
  updated_at      INTEGER,
  sync_status     INTEGER DEFAULT 0
)

cash_movements (
  id              TEXT PRIMARY KEY,
  tenant_id       TEXT NOT NULL,
  shift_id        TEXT NOT NULL,
  type            TEXT NOT NULL,       -- 'pay_in','pay_out','tip','expense'
  amount          INTEGER NOT NULL,
  description     TEXT,
  performed_by    TEXT,
  performed_at    INTEGER NOT NULL,
  created_at      INTEGER,
  sync_status     INTEGER DEFAULT 0
)
```

### Mutfak Gorunum

```sql
kitchen_tickets (
  id              TEXT PRIMARY KEY,
  tenant_id       TEXT NOT NULL,
  order_id        TEXT NOT NULL,
  table_name      TEXT,
  order_number    INTEGER,
  printer_group   TEXT DEFAULT 'kitchen',
  status          TEXT DEFAULT 'pending',
  sent_at         INTEGER NOT NULL,
  started_at      INTEGER,
  completed_at    INTEGER,
  created_at      INTEGER,
  sync_status     INTEGER DEFAULT 0
)

kitchen_ticket_items (
  id              TEXT PRIMARY KEY,
  ticket_id       TEXT NOT NULL,
  order_item_id   TEXT NOT NULL,
  product_name    TEXT NOT NULL,
  quantity        REAL NOT NULL,
  modifiers_text  TEXT,
  notes           TEXT,
  status          TEXT DEFAULT 'pending',
  created_at      INTEGER
)
```

### Sync Altyapisi

```sql
sync_queue (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  entity_type     TEXT NOT NULL,
  entity_id       TEXT NOT NULL,
  operation       TEXT NOT NULL,       -- 'create','update','delete'
  payload_json    TEXT NOT NULL,
  device_id       TEXT NOT NULL,
  timestamp       INTEGER NOT NULL,
  retry_count     INTEGER DEFAULT 0,
  status          TEXT DEFAULT 'pending',
  error_message   TEXT,
  created_at      INTEGER NOT NULL
)

sync_metadata (
  entity_type     TEXT PRIMARY KEY,
  last_sync_at    INTEGER,
  last_cursor     TEXT
)
```

---

## 5. Offline Sync Stratejisi

### Model: Event Sourcing Lite + Last-Writer-Wins

```
[Cihaz A]                        [Sunucu]                       [Cihaz B]
    |                                |                                |
    |-- siparis #101 olustur ------->|                                |
    |   (sync_queue'ya eklenir)      |                                |
    |                                |<-- siparis #101 indir ---------|
    |                                |                                |
    |-- urun ekle #101 ------------>|                                |
    |-- [offline oldu] -------------|                                |
    |                                |<-- urun ekle #101 ------------|
    |   (A offline, yerelde ekler,   |    (B de urun ekler)           |
    |    sync kuyruguna yazar)       |                                |
    |                                |                                |
    |-- [online oldu] ------------->|                                |
    |   kuyruktaki degisiklikleri    |                                |
    |   yukler, sunucu birlestirir   |                                |
```

### Entity Bazinda Conflict Stratejisi

| Entity Tipi | Strateji | Neden |
|-------------|----------|-------|
| Menu/Urunler | Sunucu kazanir | Menu merkezi yonetilir |
| Kategoriler | Sunucu kazanir | Ayni |
| Masalar (durum) | Son yazan kazanir | Masa durumu gecici |
| Siparisler | Alan bazli birlestirme | Iki garson farkli alanlar degistirebilir |
| Siparis kalemleri | Append-only + LWW | Urun ekleme catismaz |
| Odemeler | Append-only | Odemeler degistirilemez |
| Vardiyalar | Cihaza ait | Her vardiya tek cihaza ait |
| Kullanicilar | Sunucu kazanir | Admin merkezi yonetir |

### Sync Kuyrugu Isleme Algoritmasi

```
1. Her yerel yazma isleminde (insert/update/delete):
   a. Yerel SQLite'a yaz (aninda, kullanici sonucu gorur)
   b. sync_queue'ya kayit ekle (status='pending')
   c. Entity'nin sync_status = 1 (pending) yap

2. Sync upload (online oldugunda, her 5-30 saniye):
   a. sync_queue'dan pending kayitlari al (timestamp sirasina gore)
   b. Her kayit icin:
      - POST /api/sync/upload
      - 200 OK: status='uploaded', sync_status=0
      - 409 CONFLICT: status='conflict', sync_status=2
      - Network hatasi: retry_count artir, exponential backoff

3. Sync download (online oldugunda, her 10-60 saniye):
   a. GET /api/sync/download?entity=orders&since={last_sync_timestamp}
   b. Her sunucu entity icin:
      - Yerelde yoksa: ekle
      - sync_status=0 (temiz): sunucu versiyonuyla uzerine yaz
      - sync_status=1 (bekleyen yerel degisiklik): atla
      - sync_status=2 (catisma): kullaniciya goster
```

---

## 6. Modul Yapisi

### Modul Bagimlilk Grafigi

```
                    +----------+
                    |   app    |  (ana giris, routing, DI kurulumu)
                    +----+-----+
                         |
          +--------------+---------------+-----------------+
          v              v               v                 v
   +------------+ +-----------+ +------------+  +------------+
   |  feature/  | | feature/  | |  feature/  |  |  feature/  |
   |  orders    | |  menu     | |  tables    |  |  kitchen   |
   +------+-----+ +-----+-----+ +------+-----+  +------+-----+
          |              |              |                |
   +------+--+    +------+--+   +------+--+     +------+--+
   | feature/|    | feature/|   | feature/|     | feature/|
   |payments |    | reports |   |  auth   |     |printing |
   +---------+    +---------+   +---------+     +---------+
          |              |              |                |
          +--------------+--------------+----------------+
                         |
                    +----+-----+
                    |   core   |  (paylasilan: DB, sync, modeller, utils, tema)
                    +----------+
```

### Plugin/Uzanti Sistemi (ticari katmanlar icin)

```dart
abstract class PosPlugin {
  String get id;
  String get name;
  bool get isEnabled;
  void initialize();
  void dispose();
  List<Widget> getSettingsWidgets();
  List<NavigationItem>? getNavItems();
}

// Gelecek plugin ornekleri:
// - InventoryPlugin (stok yonetimi)
// - LoyaltyPlugin (musteri puanlari)
// - OnlineOrderPlugin (QR menu entegrasyonu)
// - MultibranchPlugin (sube yonetimi)
// - AdvancedReportsPlugin (ileri analitik)
```

---

## 7. Proje Klasor Yapisi

```
restaurant_pos/
+-- lib/
|   +-- main.dart
|   +-- app.dart
|   |
|   +-- core/
|   |   +-- database/
|   |   |   +-- app_database.dart         # Drift veritabani sinifi
|   |   |   +-- tables/                   # Drift tablo tanimlari
|   |   |   +-- migrations/              # Sema migration'lari
|   |   |
|   |   +-- sync/
|   |   |   +-- sync_engine.dart          # Ana sync orkestratoru
|   |   |   +-- sync_queue_manager.dart
|   |   |   +-- conflict_resolver.dart
|   |   |   +-- connectivity_monitor.dart
|   |   |
|   |   +-- printing/
|   |   |   +-- printer_service.dart      # Soyut yazici arayuzu
|   |   |   +-- esc_pos_printer.dart      # ESC/POS implementasyonu
|   |   |   +-- receipt_template.dart
|   |   |   +-- kitchen_ticket_template.dart
|   |   |
|   |   +-- di/                           # Dependency Injection
|   |   +-- router/                       # go_router rotalar
|   |   +-- theme/                        # Tema, renkler, tipografi
|   |   +-- utils/                        # Money, UUID, tarih
|   |   +-- constants/
|   |   +-- error/                        # Failure/Exception tipleri
|   |   +-- plugin/                       # Plugin registry
|   |
|   +-- features/
|   |   +-- auth/                         # PIN ile giris
|   |   |   +-- domain/ application/ data/ presentation/
|   |   +-- menu/                         # Kategori ve urun yonetimi
|   |   |   +-- domain/ application/ data/ presentation/
|   |   +-- tables/                       # Kat plani ve masa yonetimi
|   |   |   +-- domain/ application/ data/ presentation/
|   |   +-- orders/                       # Siparis alma (ana ekran)
|   |   |   +-- domain/ application/ data/ presentation/
|   |   +-- payments/                     # Odeme ve adisyon bolme
|   |   |   +-- domain/ application/ data/ presentation/
|   |   +-- kitchen/                      # Mutfak ekrani (KDS)
|   |   |   +-- domain/ application/ data/ presentation/
|   |   +-- shifts/                       # Vardiya ve kasa
|   |   |   +-- domain/ application/ data/ presentation/
|   |   +-- reports/                      # Raporlar
|   |   |   +-- domain/ application/ data/ presentation/
|   |   +-- settings/                     # Ayarlar
|   |       +-- presentation/
|   |
|   +-- shared/
|       +-- widgets/                      # Ortak POS widget'lari
|
+-- test/                                 # Testler
+-- assets/                               # Gorseller, ikonlar, fontlar
+-- android/                              # Android'e ozel
+-- web/                                  # Flutter Web (Phase 2)
```

---

## 8. Gelistirme Fazlari

### Phase 1A: Temel Altyapi (3-4 hafta)
- Proje kurulumu (Flutter, Drift, Riverpod, go_router, DI)
- Core veritabani tum tablolarla
- Tema sistemi, paylasilan widget'lar
- PIN ile giris ekrani
- Temel ayarlar ekrani
- Navigasyon iskeleti

### Phase 1B: Menu ve Urunler (2-3 hafta)
- Kategori CRUD (renk/ikon ile)
- Urun CRUD (isim, fiyat, kategori, vergi grubu)
- Modifier grup ve modifier CRUD
- Urun-modifier atamasi
- Urun grid UI (siparis ekranindaki ana panel)
- Kategori tab navigasyonu
- Urun arama

### Phase 1C: Masa Yonetimi (2 hafta)
- Kat/bolum yonetimi
- Masa CRUD (isim, kapasite, sekil, pozisyon)
- Gorsel kat plani (drag-drop)
- Masa durumu gostergeleri
- Masadan siparis acma

### Phase 1D: Siparis Alma - Ana Dongu (3-4 hafta)
- Siparis olusturma (masadan veya paket)
- Urunu siparise ekleme
- Modifier secim dialogu
- Siparis paneli (sag taraf: urun listesi, ara toplamlar)
- Urun silme/duzenleme, miktar degistirme
- Siparis ve urun notlari
- Kurs yonetimi (1. kurs, 2. kurs)
- Siparis numarasi uretimi (gunluk sirali)
- Fiyat hesaplama motoru (vergi, modifier, indirim)
- Indirim uygulama (yuzde veya sabit)

### Phase 1E: Mutfak ve Yazici (2-3 hafta)
- Bluetooth yazici kesfetme
- Yazici eslestirme ve ayar ekrani
- Fis sablonu (ESC/POS komutlari)
- Mutfaga gonder basildiginda yazici ciktisi
- Mutfak Ekrani (KDS) - bekleyen siparis listesi + zamanlayici
- Bump (tamamla) islevi
- Odeme sonrasi fis yazdir

### Phase 1F: Odemeler ve Kapanis (2 hafta)
- Odeme ekrani (nakit, kart secimi)
- Nakit odeme + para ustu hesaplama
- Adisyon bolme (esit, urun bazli, ozel tutar)
- Birden fazla odeme yontemi
- Siparis kapatma
- Masa otomatik serbest birakma

### Phase 1G: Vardiya ve Raporlar (2 hafta)
- Vardiya acma (acilis kasasi)
- Vardiya kapatma (kasa sayimi, fark)
- Vardiya icinde kasa giris/cikis
- Gunluk satis raporu
- Urun satis raporu
- Vardiya ozet raporu
- Tarih araligi filtreleme

**Phase 1 Toplam: 16-20 hafta (tek gelistirici).**
**2 gelistirici ile 10-12 haftaya indirilebilir.**

### Phase 2: Sunucu Sync ve Web (8-12 hafta)
- Go veya Node.js API sunucu + PostgreSQL
- JWT auth, tenant-scoped
- Sync endpoint'leri
- Flutter'da sync engine (background isolate)
- Conflict resolution (otomatik + manuel)
- Flutter Web dashboard (raporlar, menu yonetimi)
- Coklu cihaz destegi

### Phase 3: Ileri Ozellikler (devam eden)
- Online siparis (QR menu)
- Stok yonetimi
- Musteri sadakat programi
- Cok subeli destek
- Entegrasyonlar (muhasebe, teslimat platformlari)

---

## 9. Sifirdan mi, Fork mu?

### Degerlendirme

**SambaPOS:** C# / WPF Windows masaustu. GPL-3.0. Mobil degil, offline-first degil, Flutter ile uyumsuz. Veritabani sema konseptleri referans olarak yararli ama kod yeniden kullanilamaz. GPL turev calismada acik kaynak zorunlulugu getirir.

**ERPNext:** Python/JS web uygulamasi. POS modulu dev ERP'nin kucuk bir eklentisi. Fork edip budamak sifirdan yazmaktan uzun surer. Ama Phase 2'de backend olarak kullanilabilir (hibrit yol).

**Acik kaynak Flutter POS'lar (flutter_pos vb.):** Demo kalitesinde, uretim restoran POS'u degil. Masa yonetimi, mutfak ekrani, modifier, vardiya, multi-device sync yok.

### Oneri

**Sifirdan Flutter ile yap.** SambaPOS'un ozellik setini urun gereksinimleri kontrol listesi olarak kullan. UI akislarini (siparis alma, masa yonetimi, adisyon sistemi) UX ilhami olarak incele. Clean architecture ve modular tasarim birinci gunden yatirim olarak geri doner.

---

## 10. Dagitim ve Fiyatlandirma Stratejisi

### Phase 1 (Sadece Offline):
- APK olarak dagit veya Google Play
- Sifir sunucu maliyeti
- Gelir: cihaz basina tek seferlik lisans veya yillik abonelik

### Phase 2 (Sunuculu):
- Supabase ucretsiz katman (500MB Postgres) veya
- Hetzner VPS (4 EUR/ay) Go + PostgreSQL
- 100 restoran icin aylik sunucu maliyeti: 20-50 EUR

### Fiyatlandirma Modeli Onerisi:
- **Ucretsiz:** Tek cihaz, sadece offline, tek kat
- **Standart:** Coklu cihaz sync, web panel - 50-100 TL/ay
- **Premium:** Online siparis, stok, sadakat, cok sube - 200-300 TL/ay

---

## 11. Uc Yolun Ozet Karsilastirmasi

| Kriter | Flutter Sifirdan | ERPNext Uzerine | Flutter + ERPNext Hibrit |
|--------|-----------------|-----------------|--------------------------|
| Gercek offline | TAM | SINIRLI | TAM (Flutter tarafi) |
| Android native | EVET | HAYIR (web) | EVET |
| Gelistirme hizi (MVP) | 12-16 hafta | 4-6 hafta (ama ogrenme egrisi) | 16-20 hafta |
| Uzun vade esneklik | COK YUKSEK | ORTA (framework siniri) | YUKSEK |
| Ticari markalama | KOLAY | ZOR (lisans) | ORTA |
| Bakim maliyeti | DUSUK (tek codebase) | YUKSEK (framework guncelleme) | YUKSEK (iki ekosistem) |
| Web panel | Phase 2'de Flutter Web | HAZIR | KARMASIK |
| Onerilen mi? | EVET (1. tercih) | Hizli prototip icin | Cok spesifik durumlarda |
```

**Hazirlayan:** Claude AI
**Tarih:** 19 Mart 2026
**Proje:** 2Tech Restoran POS Sistemi
