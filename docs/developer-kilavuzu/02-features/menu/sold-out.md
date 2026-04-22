# Sold-Out (Ürün Yok İşareti)

Ürünü menü listesinden **silmeden** satışa kapatan basit toggle. Hem POS ekranında hem menü düzenlemede görünür.

**Dizin**: `apps/pos/lib/features/menu/`

## Veri

`ProductEntity.isAvailable` (bool, default `true`). Migration **v15** ile eklendi:

```sql
ALTER TABLE products ADD COLUMN is_available INTEGER NOT NULL DEFAULT 1;
```

Migration backfill: tüm mevcut ürünler `true` olarak seed'lenir. Downgrade path: kolonu drop etmek yeterli, veri kaybı yok.

## Yazma yolları

1. **Menu edit form** (`features/menu/presentation/screens/product_edit_screen.dart`):
   - "Satışta" switch'i. `MenuRepository.updateProduct(...)` içinden ayarlanır.
2. **POS long-press** (`features/orders/presentation/widgets/_pcard.dart`):
   - Kartta 500ms basılı tut → `MenuNotifier.toggleAvailability(productId)` direkt çağrılır, SnackBar ile geri bildirim verilir.

İkinci yol kasiyerin servisteyken hızlıca "bu ürün bitti" demesi için. Manager onayı yok — ama audit row yazılıyor.

## POS görsel davranış

Card'daki tap kontrolü `_pcard.dart` içinde:

```dart
onTap: product.isAvailable ? () => _addToOrder(product) : null,
onLongPress: isManager ? () => _toggleAvailability(product) : null,
```

Unavailable görünüm:

- Kart opacity 0.45.
- Sol üst köşede kırmızı "BITTI" etiketi.
- Tap devre dışı, long-press hâlâ aktif (manager yeniden açabilsin).

Kategori rengi korunur — kasiyer hangi kategori olduğunu gene ayırt eder.

## Audit

`AuditAction.productMadeUnavailable` / `productMadeAvailable` aksiyonları (`audit_action.dart`). Toggle her iki yoldan tetiklendiğinde `audit_log` satırı yazılır: userId, productId, previousValue, newValue.

## Testler

`apps/pos/test/features/menu/unavailable_toggle_test.dart` — integration test:

- Seed bir ürün, `isAvailable=true`.
- `MenuNotifier.toggleAvailability(id)` → DB'de false olur + audit satırı düşer.
- Tekrar çağır → true olur + ikinci audit satırı.
- Repository non-existent id → exception throw edilir.

## Hatırlatma

- **Stok ile karıştırmayın**. Inventory sistemini kaldırdık (commit `9263f71`). `isAvailable` manuel bir toggle, adet yok.
- Kategori seviyesinde toggle yok — her ürün ayrı. Tüm kategoriyi kapatmak gerekirse ayrı feature.
- Receipt / KDS akışı bu alanı kontrol etmiyor; kez sipariş oluştuktan sonra "bitti" olması yazdırmayı durdurmaz. Sipariş alındıktan sonra değişiklik kitcheni etkilemez.
