# Menu Feature

Kategori ve ürün yönetimi. POS'un satış ekranı bu feature'ın sunduğu listelerden beslenir.

**Dizin**: `apps/pos/lib/features/menu/`

## Dosyalar

```
features/menu/
├── domain/
│   └── entities/
│       ├── category_entity.dart
│       ├── product_entity.dart
│       ├── modifier_entity.dart
│       └── product_specification_entity.dart
├── data/
│   └── repositories/
│       └── menu_repository_impl.dart
└── presentation/
    ├── providers/
    │   └── menu_provider.dart
    ├── screens/
    │   └── menu_management_screen.dart
    └── widgets/
```

## Entity'ler

### `ProductEntity` (domain/entities/product_entity.dart)
```dart
class ProductEntity {
  final String id;
  final String name;
  final String? description;
  final int priceCents;
  final String categoryId;
  final String? imagePath;
  final bool isAvailable;
  final List<String> modifierGroupIds;
  final String? taxRateCode;           // food, beverage, alcohol, accommodation, standard
  final DateTime updatedAt;
  // ...
}
```

Satır `16`'da `description`, `28`'de `imagePath`. İkisi de POS v2 kartında kullanılır.

### `CategoryEntity`
```dart
class CategoryEntity {
  final String id;
  final String name;
  final int sortOrder;
  final String? color;                 // hex - UI renk haritası bunu kullanır
  // ...
}
```

Category renkleri `_PCard`'da kategori bg'si olarak kullanılır (`colorByCat` map).

### `ModifierEntity` + `ModifierGroupEntity`
```dart
class ModifierEntity {
  final String id;
  final String name;
  final int priceDeltaCents;           // pozitif (ekstra peynir) veya negatif (soğansız)
  final String modifierGroupId;
}
```

Bir ürüne bir modifier group assign edilir (`Extra`, `Soßen`...), group içinden modifier'lar seçilir. POS'ta ürüne dokunulduğunda modifier dialog açılır.

### `ProductSpecificationEntity`
Ürün + variant kombinasyonu (örn "Pizza Quattro - Large"). Sabit fiyat varyantları.

## Repository

### `MenuRepositoryImpl` (data/repositories/menu_repository_impl.dart)

Local-first pattern:
```dart
Future<List<ProductEntity>> listProducts() async {
  final local = await _localDataSource.list();
  return local.map(_toEntity).toList();
}
```

Yerel DB'den okur. Cloud'dan yeni product geldiğinde sync engine `SyncQueue` ve `products` tablosuna yazar, sonra provider `invalidate` olur.

## Provider

### `menu_provider.dart`
Tipik içerik:
```dart
final menuRepositoryProvider = Provider<MenuRepository>((ref) {
  return MenuRepositoryImpl(local: ref.watch(menuLocalDataSourceProvider));
});

final productsProvider = FutureProvider<List<ProductEntity>>((ref) async {
  final repo = ref.watch(menuRepositoryProvider);
  return repo.listProducts();
});

final categoriesProvider = FutureProvider<List<CategoryEntity>>((ref) async {
  final repo = ref.watch(menuRepositoryProvider);
  return repo.listCategories();
});
```

POS v2 shell `_ItemsWrap`'ta:
```dart
final productsAsync = ref.watch(productsProvider);
productsAsync.when(
  data: (products) => _ItemsGrid(products: products, ...),
  loading: () => CircularProgressIndicator(),
  error: (err, _) => Text('Menü konnte nicht geladen werden: $err'),
);
```

## Menu Management Screen

`presentation/screens/menu_management_screen.dart` - Yönetici ürün/kategori CRUD ekranı.

Genelde `backoffice` veya settings altından açılır. Kasiyer buraya erişemez (permission bazlı).

Özellikler:
- Ürün ekle/düzenle/sil
- Kategori sıralama (drag-drop)
- Modifier group yönetimi
- Resim yükleme (image_picker paketi)
- Happy hour override (pricing feature ile birlikte)

## Modifier Group İlişkisi

DB tablolari:
- `Products`
- `ModifierGroups`
- `Modifiers` (bir group'a ait many)
- `ProductModifierGroups` (junction - bir ürün birden fazla group alabilir)

Örnek:
- Product: "Margherita" -> ModifierGroups: ["Boyut", "Ekstra Peynir"]
- "Boyut" -> Modifiers: ["Klein", "Mittel", "Gross"]
- "Ekstra Peynir" -> Modifiers: ["Ja (+1.50 CHF)"]

## Resim Asset'leri

`apps/pos/pubspec.yaml` `assets:` altinda:
```yaml
- assets/images/products/starter.svg
- assets/images/products/main_course.svg
- assets/images/products/pizza.svg
- assets/images/products/dessert.svg
- assets/images/products/beverage.svg
```

Default ürünler seed'lenirken `imagePath` bu pathlerden biri olur. Custom ürünler için `ImagePicker` ile telefondan yüklenir, cihazda `applicationDocumentsDirectory`'ye kaydedilir.

## Tax Rate Code ve FareEngine İlişkisi

`product.taxRateCode` değeri `features/orders/presentation/providers/order_provider.dart:_swissFareConfig` içindeki TaxRateConfig isimleriyle eşleşmeli:
- `food`
- `beverage`
- `alcohol`
- `standard`
- `accommodation`

Takeaway mode'da `food` ürünleri %8.1 yerine %2.6 KDV ile hesaplanır (`dineInRate` vs `takeawayRate`).

## Sync

Menu genellikle cloud'dan gelir (merchant web dashboard'da düzenlenir, cihazlara push edilir). POS cihazda local cache tutar, ama authoritative source cloud.

Çakışma durumunda last-write-wins (`updated_at`).

## Test Senaryolari

- 0 ürün -> products grid `_EmptyGrid`.
- 1 kategori -> tüm kartlar aynı renk.
- Uzun isim -> `maxLines: 1` ellipsis.
- Happy hour aktif -> fiyat strikethrough (pricing feature ile).
- `isAvailable: false` -> ürün kart sönük, tap disabled.
