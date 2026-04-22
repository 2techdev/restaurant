# Tenant Switcher — Pilot için ertelendi

## Karar

Multi-tenant runtime switcher (birden fazla restoran verisi arasında kullanıcı oturumu sırasında geçiş yapmak) İsviçre pilot sürümünde **uygulanmadı**. Tek `tenantId` `SharedPreferences` üzerinden okunuyor ve uygulamanın her yerine bu sabit değerle besleniyor.

## Neden şimdi değil

- **Pilot tek restoran**. Elimizdeki müşteri (Swiss pilot) tek bir lokasyon işletiyor. Bir hesabın başka tenant'a ait veriye erişmesi kullanım senaryosunda yok.
- **Swiss compliance domain modeli tenantId'ye bağlı**. MWST oranı, para birimi, QR-bill issuer info, storno sayaçları hepsi tenant seviyesinde. Switcher eklemeden önce `TenantSettings` aggregate'ını ayrı bir entity'ye çekmek gerekiyor — aksi halde switcher runtime'da yarı-tutarlı state bırakır.
- **Audit / storno traceability**. Bir oturum içinde tenant geçişi = audit log üzerinde farklı sayaç/numaralandırma. Bugünkü `AuditService` tek tenant varsayımı üzerine kurulu; switcher eklemek `AuditService` imzasını ve DAO queries'i baştan gözden geçirmeyi gerektiriyor.
- **POS hot path performansı**. `tenantIdProvider` şu an senkron bir string getiriyor; switcher eklendiğinde `AsyncValue<String>` dönmesi gerekir. Sipariş akışındaki bütün `ref.read` çağrıları bundan etkilenir.
- **Pilot teslim süresi**. İsviçre pilotu için öncelik: doğru KDV, doğru fiş, mesai takibi, storno uyumu, happy hour. Switcher bu listede en düşük iş değerine sahip.

## Gelecekte eklemek gerekirse yol haritası

1. **Veri modeli**: `TenantEntity` (ad, MWST oranları, QR-bill issuer, currency) — şu an `SettingsRepository` içinde gömülü olan alanları dışa çıkar.
2. **Provider**: `currentTenantProvider` = `StateNotifierProvider<TenantEntity>`; `tenantIdProvider` bunun bir türevi olur.
3. **Switch flow**: Back Office → "Tenant" sekmesi; manager PIN + tenant seçimi. Geçiş sırasında açık siparişler varsa engelle (ön koşul: boş sipariş kuyruğu).
4. **Audit isolation**: `AuditLogDao.watchAll` zaten tenantId filtreli; switcher ekliyken cached stream'leri `invalidate` etmek yeterli.
5. **Storno sayaçları**: `receipt_counters` tablosunda tenantId ile composite primary key. Her tenant kendi serisini tutsun.
6. **Test**: `tenant_switch_test.dart` — iki tenant seed et, birinde ticket aç, diğerine geç, ticket listesinin ayrı olduğunu doğrula.

## Bu kararı geri alma koşulları

Aşağıdakilerden biri olduğunda yeniden açılmalı:

- Pilot müşterisi ikinci bir restoran (farklı MWST profiliyle) açtığında.
- Bir bayilik/franchise senaryosu devreye girdiğinde.
- Merkezi raporlama (tenant-cross aggregate) istek olarak geldiğinde.

## İlgili dosyalar

- `apps/pos/lib/core/di/providers.dart` — `tenantIdProvider`
- `apps/pos/lib/core/services/settings_repository.dart` — tenant seviyesi ayarlar
- `apps/pos/lib/features/audit_log/**` — tenant filtreli query'ler
- `apps/pos/lib/features/payments/data/repositories/refund_repository_impl.dart` — storno sayaçları

## Karar sahibi

Swiss pilot teslimi (2026-04-22). Tek tenant varsayımıyla kalıyoruz; switcher ikinci lokasyon işaretleri belirdiğinde ayrı bir feature olarak planlanır.
