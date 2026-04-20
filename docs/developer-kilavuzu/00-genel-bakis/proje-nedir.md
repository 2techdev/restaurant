# Proje Nedir

## Kısa Tanım

GastroCore, İsviçre pazarına yönelik restoran yönetim platformudur. Tek repoda beş farklı mobil uygulama, bir web uygulaması ve Go tabanlı bir cloud sunucusu bulunur. Tüm cihazlar offline-first çalışır, bağlantı geldiğinde cloud hub ile senkronize olur.

## Ne Yapıyor

- **POS**: Kasiyer ve yönetici için ana satış ekranı. Sipariş açma, masa yönetimi, ödeme alma, rapor çıkarma.
- **Kiosk**: Müşterinin kendi kendine sipariş verebildiği landscape ekran.
- **KDS** (Kitchen Display Screen): Mutfakta duvara asılan ekran, sipariş akışını gösterir.
- **ODS** (Order Display Screen): Lobideki müşterilere sipariş durumunu gösterir.
- **Waiter**: Garsonun elindeki handheld cihaz, masada sipariş alır.
- **Online Ordering** (Flutter Web): Restoranın web sayfasından müşteri siparişi.

Hepsi tek codebase, flavor'lar ile ayrılıyor. Bkz `apps/pos/lib/main.dart`, `apps/pos/lib/main_kiosk.dart`, `apps/pos/lib/main_kds.dart`, `apps/pos/lib/main_ods.dart`, `apps/pos/lib/main_waiter.dart`.

## Hedef Pazar

**İsviçre** (birincil pilot). Bu neye mal oluyor:

- **Para birimi**: CHF ve 5-Rappen yuvarlama zorunlu (0.05 CHF'ye yuvarlanır).
- **KDV (MWST)**:
  - 8.1% dine-in (masada yemek)
  - 2.6% takeaway
  - 3.8% konaklama (accommodation)
- **Dört dil**: DE (birincil) / FR / IT / EN.
- **Swiss QR-Bill**: Fatura üzerinde ISO 20022 QR kodu zorunlu.
- **TWINT / Wallee**: İsviçre'nin ana mobil ödeme yöntemi.

Detay icin bkz [03-swiss-compliance](../03-swiss-compliance/).

## Teknik Temel

- **Frontend**: Flutter 3.35 + Dart SDK ^3.9.2, Riverpod 2.6, GoRouter 14.8, Drift (SQLite) 2.22.
- **Backend**: Go 1.22, stdlib `net/http`, PostgreSQL 16, Redis 7.
- **Sync**: Outbox pattern, REST push/pull + WebSocket gerçek zamanlı fan-out.
- **Çakışma çözümü**: Last-write-wins, `updated_at` bazlı.

Kaynak dosya: `apps/pos/pubspec.yaml`, root `README.md`, [docs/ARCHITECTURE.md](../../ARCHITECTURE.md) (eğer varsa).

## Offline-First Ne Demek

- Cihaz, cloud'a erişilemediğinde hiçbir işlevini kaybetmez.
- Her yazma önce yerel SQLite'a düşer.
- Her yazma aynı zamanda `SyncQueue` outbox tablosuna pending kayıt düşer.
- Bağlantı geldiğinde arka plan zamanlayıcısı `/api/v1/sync/push` ile toplu yükler.
- `/api/v1/sync/pull` ile diğer cihazların yazdıklarını indirir.
- Merge `updated_at` karşılaştırmasıyla yapılır (last-write-wins).

Bu kural, Swiss pilot için kritik: İnternet kesintisinde kasa çalışmaya devam eder, senkronizasyon sonra olur. Detay icin bkz `packages/gastrocore_sync/`.

## Üretim Durumu (Nisan 2026)

- `v1.3.0+130` -> POS ana versiyonu.
- `claude/pilot-final` branch'i pilot-ready aday.
- Swiss pilot pre-launch fazında.

Versiyon detayı icin root `CHANGELOG.md` ve `PROJECT_STATUS.md`.
