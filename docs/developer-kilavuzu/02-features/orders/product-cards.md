# Product Cards

POS v2 shell'inin sağ sütununda, Schnell bar'ın altında uzanan ürün grid'i.

**Dosya**: [apps/pos/lib/features/orders/presentation/shells/pos_v2_shell.dart:~2140](../../../apps/pos/lib/features/orders/presentation/shells/pos_v2_shell.dart) (`_ItemsGrid`, `_PCard`)

## Grid Düzeni

`_ItemsGrid` widget'ı `LayoutBuilder` + `GridView.builder` kullanır:

```dart
LayoutBuilder(
  builder: (context, constraints) {
    final cols = ((constraints.maxWidth - 44) / 180).floor().clamp(2, 6);
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisExtent: 130,           // her kart 130px yükseklik
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      padding: const EdgeInsets.fromLTRB(22, 6, 22, 20),
      itemCount: products.length,
      itemBuilder: (context, i) => _PCard(product: products[i], ...),
    );
  },
)
```

- Kolon sayısı ekran genişliğine göre 2-6 arası adaptif.
- Her kart sabit 130px yükseklikte (`mainAxisExtent`).
- Aralar 10px, kenar padding 22/6/22/20.

### Neden mainAxisExtent?
`childAspectRatio` kullanmak zorunda değilsiniz. Farklı ekran genişliğinde aspect ratio kayabilir, ama `mainAxisExtent` her zaman 130px garantiler. Tablet'lerde (ana hedef cihaz) tap target bu sayede sabit.

## `_PCard` (pos_v2_shell.dart:~2268)

```dart
class _PCard extends ConsumerWidget {
  final ProductEntity product;
  final Map<String, Color> colorByCat;     // kategori -> renk
  final Map<String, int> colorIdx;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imagesOn = ref.watch(productImagesEnabledProvider);
    final palette  = ref.watch(posPaletteProvider);
    final isSelected = _isSelected(ref, product);
    final qtyInCart  = _qtyInCart(ref, product);

    final bg = colorByCat[product.categoryId] ?? V2.ink3;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () => ref.read(currentTicketProvider.notifier).addItem(product),
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: [
            // Opsiyonel: görsel backdrop
            if (imagesOn && product.imagePath != null)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(product.imagePath!, fit: BoxFit.cover),
                ),
              ),
            // Gradient scrim (görsel okunabilirliği için)
            if (imagesOn)
              Positioned.fill(
                child: Container(decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [bg.withOpacity(0.0), bg.withOpacity(0.9)],
                  ),
                )),
              ),
            // İçerik (isim, altyazı, fiyat)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(product.name, style: V2Text.pName, maxLines: 1),
                  if (product.description != null)
                    Text(product.description!, style: V2Text.pSub, maxLines: 1),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text('CHF', style: V2Text.pCurrency),
                      const SizedBox(width: 4),
                      Text(v2Chf(product.priceCents), style: V2Text.pPrice),
                    ],
                  ),
                ],
              ),
            ),
            // Seçili ise mavi çerçeve
            if (isSelected)
              Positioned.fill(
                child: Container(decoration: BoxDecoration(
                  border: Border.all(color: V2.sel, width: 3),
                  borderRadius: BorderRadius.circular(10),
                )),
              ),
            // Sepette var ise qty badge
            if (qtyInCart > 0)
              Positioned(
                top: 7, right: 7,
                child: Container(
                  width: 28, height: 28,
                  decoration: const BoxDecoration(
                    color: Colors.white, shape: BoxShape.circle,
                  ),
                  child: Center(child: Text('$qtyInCart', style: V2Text.inCart.copyWith(color: bg))),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
```

## Kart Anatomisi

### Arka Plan
- Her kart kategori rengini arka plan olarak alır (`catRed`, `catOrange`, ...).
- Kategori renkleri `colorByCat` map'i üzerinden kategori ID'siyle eşleşir.
- Palette = Midnight ise kategori rengi biraz karartılır (eski davranış; kontrol et).

### Başlık + Subtitle
- `product.name` - Tek satır, ellipsis.
- `product.description` - (opsiyonel) tek satır, ellipsis. Entity field: `ProductEntity.description: String?` (`features/menu/domain/entities/product_entity.dart:16`).

### Fiyat Satırı
- "CHF" (küçük) + fiyat (büyük, bold, tabular figures).
- `v2Chf(priceCents)` helper cents'i `23.50` gibi formatlar (`pos_v2_theme.dart`).

### Seçili Durum (Blue Border)
- `v2SelectedLineIdProvider`'da bu ürüne ait bir line varsa 3px `V2.sel` border.

### Qty Badge
- Beyaz daire, içinde kategori rengiyle quantity yazısı.
- Sağ üst köşe (`top: 7, right: 7`, 28x28).

## Product Images Toggle

`productImagesEnabledProvider` `true` olduğunda:
- `product.imagePath` varsa arka plana `Image.asset` gelir.
- Üstüne `bg.withOpacity(0.0 -> 0.9)` dikey gradient (alt okunabilirlik için scrim).

SVG fotoğraflar `apps/pos/pubspec.yaml` `assets:` listesinde:
```yaml
- assets/images/products/starter.svg
- assets/images/products/main_course.svg
- assets/images/products/pizza.svg
- assets/images/products/dessert.svg
- assets/images/products/beverage.svg
```

Ürün seeding'de hangisinin atandığı `features/menu/data/` altında tanımlı.

## ProductEntity Alanları Kullanımı

```dart
class ProductEntity {
  final String id;
  final String name;
  final String? description;          // subtitle (Card)
  final int priceCents;               // CHF base price
  final String categoryId;            // renk eşlemesi için
  final String? imagePath;            // images toggle açıksa
  // ...
}
```

Kaynak: `apps/pos/lib/features/menu/domain/entities/product_entity.dart`.

## Kart Dokunuşu

```dart
onTap: () => ref.read(currentTicketProvider.notifier).addItem(product),
```

Schnell tile ile aynı davranış. `addItem` içinde:
1. Mevcut ticket yoksa yeni ticket create edilir.
2. Aynı ürün daha önce eklendiyse quantity +1.
3. Yeni ürünse yeni bir `OrderItemEntity` oluşturulur.
4. KDV fare'i `FareEngine` ile hesaplanır.
5. Happy hour aktifse indirim uygulanır.
6. Ticket state güncellenir -> UI tamamen rebuild olur.

## Performans Notu

- `GridView.builder` lazy rendering yapar, sadece ekranda olan kartlar build edilir.
- `_PCard` `ConsumerWidget`'tir, sadece watch edilen provider değiştiğinde rebuild olur.
- `colorByCat` map'i parent'ta bir kez hesaplanır, her build'de yeniden yapılmaz.
- Image.asset cached'tir, ikinci renderda network gitmez.

## Ekran Boyutları

| Genişlik | Kolon sayısı (yaklaşık) |
|---|---|
| 800px | 4 |
| 1024px | 5 |
| 1280px | 5-6 |
| 1920px | 6 (clamp üst sınır) |

Gerçek: `((width - 44) / 180).floor().clamp(2, 6)`.

## Test Edilen Durumlar

- 0 ürün -> `_EmptyGrid` (center mesaj: "Menü yüklenmedi").
- 1 kategorili seed -> tüm kartlar aynı rengin farklı tonları.
- Uzun ürün isimleri -> ellipsis.
- Palette switch -> arka plan tonları değişir.
- Images toggle -> hem on hem off durumunda layout bozulmaz.
