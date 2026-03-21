# GastroCore Platform — Master TODO List

**Son Guncelleme:** 2026-03-20
**Toplam:** 89 Flutter dosya | 29 Go dosya | 38 dokuman | ~54,000 satir

---

## DURUM OZETI

| Bilesen | Durum | Detay |
|---------|-------|-------|
| POS App (Tablet) | ✅ MVP Done | 89 dosya, 27K satir, 13 ekran, 0 error |
| Go Backend | ✅ Iskelet Done | 29 dosya, 32 endpoint, derlenebilir |
| Mimari Dokumanlar | ✅ Done | 38 dosya, 15 ADR |
| Fare Engine | ✅ Done | OrderPin seviyesi, 25 alanli FareBreakdown |
| APK Build | ✅ Done | 142MB debug APK |
| Stitch UI Entegre | ✅ Done | 11 ekran tasarimi uygulandı |

---

## PHASE 1: POS APP TAMAMLAMA (Öncelik 1)

### 1.1 Shared Package Extraction
- [ ] `packages/core_models/` olustur — entity, enum, value object tasi
- [ ] `packages/core_database/` olustur — Drift tablolar, AppDatabase tasi
- [ ] `packages/core_theme/` olustur — AppColors, AppTheme, shared widgets tasi
- [ ] `packages/core_auth/` olustur — PIN auth, user entity tasi
- [ ] `packages/core_sync/` olustur — sync engine, connectivity tasi
- [ ] `packages/core_printing/` olustur — printer service abstraction tasi
- [ ] Melos workspace konfigurasyonu (melos.yaml)
- [ ] POS app'i shared paketlere bagla, import'lari guncelle
- [ ] `flutter analyze` → 0 issue dogrula

### 1.2 Veritabani Guncelleme (Fare Engine + OrderPin gap)
- [ ] tickets tablosuna 16 yeni alan ekle (fare genisletmesi)
- [ ] order_items tablosuna 6 yeni alan ekle (weight, openPrice, taxFree)
- [ ] payments tablosuna 6 yeni alan ekle (subChannel, paymentForm, external)
- [ ] products tablosuna 4 yeni alan ekle (stockStatus, openPrice, weightBased)
- [ ] Migration v1→v2 yaz
- [ ] build_runner calistir, generated dosyalari guncelle
- [ ] Repository'leri yeni alanlarla guncelle
- [ ] Provider'lari yeni alanlarla guncelle

### 1.3 Fare Engine Entegrasyonu
- [ ] POS ekraninda FareEngine kullan (gercek vergi hesaplama)
- [ ] Payment ekraninda FareBreakdown goster
- [ ] Receipt'te detayli fare goster
- [ ] Settings'te FareConfig ayarlari (vergi orani, servis ucreti, yuvarlama)
- [ ] Dine-in vs Takeaway vergi farki (Isvicre)

### 1.4 Eksik UI/UX
- [ ] Stitch'ten yeni tasarimlar iste: S12-S20 (Back Office, Settings, OrderHistory, vs.)
- [ ] Online Order Acceptance ekrani (popup gelen siparis)
- [ ] Device Pairing ekrani (QR ile cihaz esleme)
- [ ] Discount dialog (yuzde/sabit indirim, isimli indirimler)
- [ ] Customer selection dialog (musteri sec/olustur)
- [ ] Quick notes dialog (siparis notlari)
- [ ] Masa birlestirme/ayirma/tasima dialoglari

### 1.5 Donanim Entegrasyonu (Sen Vereceksin)
- [ ] Bluetooth termal yazici — printer discovery + ESC/POS
- [ ] Network yazici (Star Micronics, Epson)
- [ ] Cash drawer tetikleme
- [ ] Barkod okuyucu
- [ ] Terazi entegrasyonu (retail mode)
- [ ] Odeme terminali abstraction (Telpo, SumUp, vs.)

### 1.6 Test
- [ ] FareEngine unit testleri (vergi hesaplama, yuvarlama, indirim)
- [ ] Money class unit testleri
- [ ] Repository integration testleri (Drift)
- [ ] Full order flow E2E testi
- [ ] Split bill testi
- [ ] Refund testi

---

## PHASE 2: KDS APP (Öncelik 2)

- [ ] `apps/kds/` Flutter projesi olustur
- [ ] Shared paketlere bagla (core_models, core_database, core_theme, core_sync)
- [ ] KDS ekranini POS'tan cikart, bagimsiz app yap
- [ ] LAN sync (mDNS + WebSocket) — POS'tan siparis al
- [ ] Station filtreleme (mutfak, bar, tatli)
- [ ] Ses uyarisi (yeni siparis)
- [ ] Bump (tamamla) fonksiyonu
- [ ] Course yonetimi (1. kurs, 2. kurs)
- [ ] Timer renk kodlamasi (yesil < 10dk, turuncu < 20dk, kirmizi > 20dk)
- [ ] Full-screen landscape mode
- [ ] APK build + test

---

## PHASE 3: WAITER APP (Öncelik 3)

- [ ] `apps/waiter/` Flutter projesi olustur
- [ ] Shared paketlere bagla
- [ ] Portrait mode, tek elle kullanim
- [ ] Masa listesi (hizli gorunum)
- [ ] Hizli siparis ekleme (urun grid)
- [ ] Modifier secimi (basitlesmis)
- [ ] Mutfaga gonder
- [ ] Siparis durumu goruntuleme
- [ ] Manager cagirma butonu
- [ ] LAN sync (POS ile ayni ag)
- [ ] PIN giris (basit)
- [ ] APK build + test

---

## PHASE 4: WEB DASHBOARD (Öncelik 4)

- [ ] `web/dashboard/` olustur (Flutter Web veya React karar ver)
- [ ] Login ekrani (email + sifre)
- [ ] Dashboard ana sayfa (gunluk satis, siparis sayisi, gelir)
- [ ] Menu yonetimi (kategori, urun, modifier CRUD + resim upload)
- [ ] Personel yonetimi
- [ ] Raporlar (gunluk, haftalik, aylik, urun performansi)
- [ ] Cihaz yonetimi (bagli tabletler, saglik durumu)
- [ ] Ayarlar (vergi, para birimi, yazici, servis ucreti)
- [ ] Go backend API'leri ile entegre et

---

## PHASE 5: PATRON APP (Öncelik 5)

- [ ] `apps/patron/` Flutter projesi olustur
- [ ] Dashboard (bugunun satislari, siparis sayisi)
- [ ] Coklu sube gorunumu (enterprise)
- [ ] Personel performansi
- [ ] Push notification (vardiya acildi/kapandi, yuksek void orani)
- [ ] Sadece okuma — siparis alma yok
- [ ] Cloud API'ye baglan

---

## PHASE 6: ONLINE ORDERING (Öncelik 6)

### 6.1 Go Backend Online Ordering API
- [ ] Public menu endpoint (/api/v1/public/menu/:shopId)
- [ ] Cart session yonetimi
- [ ] Checkout flow (siparis olustur, odeme)
- [ ] Siparis durumu takibi (SSE/WebSocket)
- [ ] Restoran musaitlik kontrolu (is saatleri)

### 6.2 Web Ordering
- [ ] `web/ordering/` olustur
- [ ] Responsive menu sayfasi (mobil + masaustu)
- [ ] Sepet + checkout
- [ ] Odeme entegrasyonu
- [ ] QR kod ile masa baglantisi (QR menuden siparis)

### 6.3 POS Entegrasyonu
- [ ] Online siparis kabul/red popup'i POS'ta
- [ ] Online siparis → ayni order engine
- [ ] Pickup code uretimi

---

## PHASE 7: CUSTOMER MOBILE APP (Öncelik 7)

- [ ] `apps/customer/` Flutter projesi (Android + iOS)
- [ ] Restoran menu goruntuleme
- [ ] Siparis verme (teslimat/paket)
- [ ] Siparis durumu takibi (gercek zamanli)
- [ ] Siparis gecmisi, tekrar siparis
- [ ] Push notification
- [ ] Odeme entegrasyonu

---

## PHASE 8: ODS — ORDER DISPLAY SCREEN (Öncelik 8)

- [ ] `apps/ods/` Flutter projesi
- [ ] Musteri tarafli siparis durumu ekrani
- [ ] Buyuk ekran/TV optimize
- [ ] "Siparis #42 — Hazirlaniyor", "Siparis #43 — Hazir"
- [ ] LAN sync veya WebSocket ile otomatik guncelleme
- [ ] Tahmini bekleme suresi (opsiyonel)

---

## PHASE 9: KIOSK APP (Öncelik 9)

- [ ] `apps/kiosk/` Flutter projesi
- [ ] Tam ekran, dokunmatik optimize
- [ ] Menu gozatma (buyuk gorseller)
- [ ] Sepete ekle → odeme
- [ ] Odeme terminali entegrasyonu (sadece kart)
- [ ] Siparis numarasi verme
- [ ] Bos ekran (reklam/slideshow)
- [ ] Timeout ayarlari

---

## PHASE 10: ALMANYA PACK (Fiskal)

- [ ] Fiskaly SIGN DE v2 sandbox hesabi ac
- [ ] Cloud Hub'da Fiskaly proxy modulu
- [ ] Transaction lifecycle: start → update → finish
- [ ] Offline siparis + online fiskal finalizasyon akisi
- [ ] DSFinV-K export
- [ ] TSE verisi ile fis yazdirma
- [ ] Fiskaly hata yonetimi (retry, manager override)
- [ ] Test: sandbox'ta tam siparis → fis → TSE imza akisi

---

## PHASE 11: ISVICRE PACK

- [ ] KDV oranlari: %8.1 (normal), %2.6 (indirimli), %3.8 (konaklama)
- [ ] Dine-in vs Takeaway vergi farkini FareEngine'de aktif et
- [ ] 5 Rappen yuvarlama (nakit odemelerde)
- [ ] QR-bill fatura uretimi (QR-IBAN, SCOR referans)
- [ ] Isvicre fis formati
- [ ] UID/VAT format dogrulama (CHE-xxx.xxx.xxx)

---

## PHASE 12: ERPNEXT BRIDGE

- [ ] ERPNext v15 Community Edition Docker kurulumu
- [ ] Go bridge modulu: master data sync (Item, PriceList, Tax)
- [ ] Sales posting (Sales Invoice, Payment Entry)
- [ ] Stock deduction (Stock Entry)
- [ ] Journal Entry (cash movements)
- [ ] End-of-day reconciliation raporu
- [ ] ERPNext down olursa kuyruk yonetimi

---

## PHASE 13: RETAIL / MARKET MODE

- [ ] Barkod ile hizli urun arama
- [ ] Tartili urun (terazi entegrasyonu)
- [ ] Hizli satis modu (masasiz, direkt sat)
- [ ] Perakende fis formati
- [ ] Perakende raporlari
- [ ] Stok sayimi

---

## ALTYAPI / DEVOPS

- [ ] CI/CD pipeline (GitHub Actions) — Flutter build + Go build
- [ ] Docker Compose production config
- [ ] PostgreSQL yedekleme otomasyonu
- [ ] APK release signing (keystore olustur)
- [ ] Play Store developer hesabi ac
- [ ] Monitoring / alerting (basit)
- [ ] Error tracking (Sentry veya Firebase Crashlytics)

---

## BACKLOG (Gelecek)

- [ ] Loyalty / musteri sadakat programi
- [ ] Kupon sistemi
- [ ] Promosyon motoru (happy hour, combo)
- [ ] Multi-language UI (i18n — DE, EN, TR, FR)
- [ ] Multi-currency tam destek
- [ ] Advanced analytics dashboard
- [ ] AI-powered sales prediction
- [ ] Kitchen prep time ML model
- [ ] 3. parti teslimat entegrasyonu (Uber Eats, Wolt)
- [ ] Rezervasyon sistemi
- [ ] QR masa siparis (garson onayiyla)
- [ ] Digital menu board (TV menu)
- [ ] Personel vardiya planlama
- [ ] Envanter yonetimi (recete bazli stok dusumu)

---

## TAMAMLANAN ISLER ✅

### Sprint 1 (2026-03-20)
- [x] Mimari dokumanlar (38 dosya, 23K satir)
- [x] 15 ADR (Architecture Decision Records)
- [x] Flutter POS App scaffolding
- [x] 22 Drift veritabani tablosu
- [x] Core utils (Money, IdGenerator, Constants, Theme, Colors, Errors)
- [x] 11 domain entity + enum'lar
- [x] 6 repository + 6 Riverpod provider
- [x] Seed data (40+ urun, 5 user, 14 masa, 8 kategori)
- [x] Provider-ekran entegrasyonu (gercek DB verisi)
- [x] 13 UI ekran + 1 modifier dialog
- [x] 10 shared widget (button, numpad, topbar, card, badge, dialog, textfield, empty, loading, money)
- [x] Stitch design system entegrasyonu
- [x] Back Office (menu/table/staff/reports 4 tab)
- [x] Settings ekrani (7 section)
- [x] Order History ekrani
- [x] Sync indicator widget + connectivity provider
- [x] Tum lint warning/info temizligi → 0 issue
- [x] APK debug build (142MB)
- [x] Go cloud backend iskeleti (29 dosya, 32 endpoint)
- [x] PostgreSQL migration (26 tablo)
- [x] Docker + docker-compose
- [x] OrderPin API gap analizi
- [x] Eski APK (TwoPOS) donanim analizi
- [x] FareEngine (25 alanli OrderPin seviyesi hesaplama motoru)
- [x] Entity genisletmeleri (ticket+item+payment+product = 32 yeni alan)
- [x] Multi-app mimari plani (9 app, shared package stratejisi)
- [x] Go backend derleme testi (go build + go vet = 0 error)
