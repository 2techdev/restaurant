# POS Developer Kılavuzu

Bu kılavuz, `gastrocore_pos` uygulamasını geliştirici gözüyle anlayabilmeniz için yazıldı. Tüm feature'lar, mimari kararlar, Swiss compliance detayları ve günlük geliştirme akışı parçalara bölündü.

Dosya yolu + satır numarası referansları verilirken **jolly-final** worktree'si baz alındı (`E:\Project\Restaurant\.claude\worktrees\jolly-final`). Kod kimlikleri (sınıf adları, fonksiyonlar, provider adları) İngilizce bırakıldı, açıklamalar Türkçe.

## Mantıksal Düzen

### 00 - Genel Bakış
Projenin ne olduğu, hangi teknolojilerle çalıştığı ve dizin haritası.
- [Proje Nedir](00-genel-bakis/proje-nedir.md)
- [Teknoloji Stack](00-genel-bakis/teknoloji-stack.md)
- [Dizin Yapısı](00-genel-bakis/dizin-yapisi.md)

### 01 - Mimari
Katmanlar, state yönetimi, yerel veri tabanı, flavor / country config ve tasarım sistemi.
- [Katmanlar (Clean Architecture)](01-mimari/katmanlar.md)
- [State Management (Riverpod)](01-mimari/state-management.md)
- [Database (Drift)](01-mimari/database.md)
- [Flavors / Country Config](01-mimari/flavors.md)
- [Design System (Tokens, Theme, POS v2)](01-mimari/design-system.md)

### 02 - Features
POS'un en sık dokunulan altı feature ailesi. Her alt klasör o feature'ın domain + providers + UI entry point'lerini anlatır.

Orders:
- [POS v2 Shell](02-features/orders/pos-v2-shell.md)
- [Schnell Bar](02-features/orders/schnell-bar.md)
- [Product Cards](02-features/orders/product-cards.md)
- [Tweaks Paneli](02-features/orders/tweaks-panel.md)
- [Bottom Action Bar](02-features/orders/bottom-action-bar.md)

Menu:
- [Menu Feature](02-features/menu/menu-feature.md)
- [Sold-Out (Ürün Yok)](02-features/menu/sold-out.md)

Payment:
- [Payment Flow](02-features/payment/payment-flow.md)

Kitchen:
- [Kitchen / KDS](02-features/kitchen/kitchen-kds.md)

Customer:
- [Customers + Reservations + Tables](02-features/customer/customer-ekosistemi.md)
- [Loyalty ve Müşteri Bağlama](02-features/customer/loyalty-ve-musteri-baglama.md)

Pricing:
- [Happy Hour](02-features/pricing/happy-hour.md)

Shifts:
- [Mesai (Clock In / Out)](02-features/shifts/mesai-clock.md)

Orders (ek):
- [Receipt Reprint ve KOPIE Banner](02-features/orders/reprint-ve-kopie.md)

Reporting:
- [Reports](02-features/reporting/reports.md)

### 03 - Swiss Compliance
İsviçre pazarı için kritik: KDV, TWINT / Wallee, Swiss QR-Bill, makbuz formatları, storno.
- [İsviçre KDV Kuralları](03-swiss-compliance/vat-isvicre.md)
- [Swiss QR-Bill](03-swiss-compliance/swiss-qr-bill.md)
- [Wallee / TWINT Entegrasyonu](03-swiss-compliance/wallee-twint.md)
- [Makbuz (Receipt)](03-swiss-compliance/receipt.md)
- [Storno / İade](03-swiss-compliance/storno-refund.md)

### 04 - Dev Workflow
Günlük geliştirme akışı: build, worktrees, debug ipuçları, testler.
- [Build ve Release](04-dev-workflow/build-release.md)
- [Git Worktrees](04-dev-workflow/git-worktrees.md)
- [Debug İpuçları](04-dev-workflow/debug-ipuclari.md)
- [Testleri Çalıştır](04-dev-workflow/test-calistir.md)

### 05 - Kararlar ve Bilinmesi Gerekenler
Geçmiş deneyim, kararlar, yanıltıcı bug'ler.
- [POS v2 Redesign Tarihi](05-kararlar-ve-bilinmesi-gerekenler/pos-v2-redesign-tarihi.md)
- [MainAxisSize Leak (inner=1160x0)](05-kararlar-ve-bilinmesi-gerekenler/mainaxis-size-leak.md)
- [Tasarım Kararları](05-kararlar-ve-bilinmesi-gerekenler/tasarim-kararlari.md)
- [Tenant Switcher Ertelendi](05-kararlar-ve-bilinmesi-gerekenler/tenant-switcher-ertelendi.md)

## Nasıl Okumalı

- **Yeni katılan geliştirici**: 00 -> 01 -> 04 sırası yeterli, feature'lar ihtiyaç olduğunda.
- **Orders ekranına dokunacak**: 01/design-system + 02-features/orders tamamı.
- **Swiss pilot için hazırlanıyorsunuz**: 03-swiss-compliance komple + 02-features/payment.
- **Layout bug avlıyorsunuz**: 05/mainaxis-size-leak ilk durak.

## Versiyon

Bu kılavuz `claude/pilot-final` branch'inin pilot-hazır final kesintisine göre hazırlandı (E-refund commit `0823d48` üstüne docs sync). Sonraki pilot iterasyonlarında bu satır güncellenmeli, satır numaraları kayabilir, sınıf adları sabit kalır.
