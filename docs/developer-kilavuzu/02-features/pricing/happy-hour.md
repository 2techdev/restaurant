# Happy Hour (Pricing Rules)

Belirli gün + saat aralıklarında yüzdelik indirim uygulayan feature. Manager Back Office'tan açar/kapar ve kuralları düzenler; POS sipariş hattı kuralı senkron olarak okur.

**Dizin**: `apps/pos/lib/features/pricing/`

## Neden StateNotifier, AsyncNotifier değil

Fiyatlandırma sipariş hattının hot path'inde — her ürün eklendiğinde `order_provider` kuralları okur. `AsyncNotifier` + `await` introduce edilince UI flash'ları ortaya çıkıyor.

Seçtiğimiz yol:

1. `happyHourRulesProvider` = **`StateNotifierProvider<List<HappyHourRule>>`**, default state = `happyHourDefaultRules` (`const`, unmodifiable).
2. Uygulama açılışında `ref.listen(fireImmediately: true)` ile `SettingsRepository`'den yüklenir → state bir kez replace edilir.
3. Sipariş sırasında herhangi bir `await` yok — `ref.read(happyHourRulesProvider)` senkron liste döner.

Yazma tarafı (upsert/remove/toggle) değişikliği hem in-memory state'e hem SharedPreferences'a kaydediyor. Başka bir device bu değişikliği görmüyor — tek cihaz pilot için kasıtlı basitleştirme.

## Entity

```dart
class HappyHourRule {
  final String id;
  final String label;                   // "Pazartesi Bar"
  final Set<int> weekdays;              // 1=Mon, 7=Sun
  final TimeOfDay start;
  final TimeOfDay end;
  final double discountPercent;         // 0..1 (0.15 = %15)
  final bool active;
  final Set<String>? categoryIds;       // null = tüm kategoriler
}
```

`happyHourDefaultRules` (sabit liste): hafta içi 15:00–17:00 %20, cuma 17:00–19:00 %25.

## SettingsRepository entegrasyonu

`SharedPreferences` key: `happy_hour_rules_v1`. JSON blob olarak saklanır (`jsonEncode(rules.map(toJson))`).

- **Load**: `SettingsRepository.getHappyHourRules()` → `List<HappyHourRule>` veya `null`.
- **Save**: `setHappyHourRules(List<HappyHourRule>)` — atomik değiştirir.

Load hatası (bozuk JSON, disk okuma hatası) → `null` döner, default rules olduğu gibi kalır.

## Notifier hareketleri

`HappyHourRulesNotifier`:

- `hydrate()`: Bir kere çağrılır (splash). Boş state → default'lar seed'lenir ve yazılır. Dolu state → blob state'i **replace eder**, default'ları yeniden yazmaz (idempotent).
- `upsert(rule)`: Id eşleşiyorsa in-place replace, eşleşmiyorsa append.
- `remove(id)`: Varsa düşürür, yoksa no-op.
- `toggleActive(id)`: Sadece `active` alanını flip eder, diğer alanlara dokunmaz.

Hepsi yazmadan önce state'i günceller → repository'ye persist eder.

## Sipariş hattı entegrasyonu

`order_provider.dart` yeni item eklerken:

```dart
final rules = ref.read(happyHourRulesProvider);
final now = DateTime.now();
final active = rules.firstWhereOrNull((r) =>
    r.active && r.matches(now) && r.appliesTo(product.categoryId));
if (active != null) {
  discountPercent = active.discountPercent;
}
```

`HappyHourRule.matches(DateTime)` saati TimeOfDay ile karşılaştırır; gece yarısını geçen aralıklar **desteklenmez** (01:00 → 03:00 bir sonraki gün olarak modellenir).

## Back Office editor

`pricing_management_tab.dart` (Ayarlar altında):

- Kural listesi + "Yeni Kural" butonu.
- Her row: gün chip'leri, başlangıç-bitiş, yüzde, aktif switch.
- Düzenle → bottom sheet form (weekday multiselect, TimeOfDay picker'lar, percent slider).
- Sil → confirm dialog.

## Testler

`apps/pos/test/features/pricing/happy_hour_rules_notifier_test.dart` — 10 test, `_FakeSettingsRepository` üzerinde:

1. Initial state default rules, unmodifiable.
2. `hydrate()` boş blob → default'lar seed + repository'ye yazılır.
3. `hydrate()` dolu blob → state replace, default'lar overwrite edilmez.
4. `hydrate()` idempotent — ikinci çağrı yazma oluşturmaz.
5. Load failure → default'lar korunur.
6. `upsert` yeni id → append.
7. `upsert` var olan id → in-place replace.
8. `remove` var olan id → düşer.
9. `remove` bilinmeyen id → no-op, state değişmez.
10. `toggleActive` sadece `active` alanını değiştirir.

## Hatırlatma

- Kurallar **cihaz seviyesinde**. Merkezi yönetim isteniyorsa `SettingsRepository` yerine `tenant_settings` tablosuna taşıyın; her cihaz sync için poll eder.
- Overlapping rules: iki kural aynı anda match ediyorsa ilk bulunan kullanılıyor. Precedence gerekirse `sortOrder` alanı eklenmeli.
