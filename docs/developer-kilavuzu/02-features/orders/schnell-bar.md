# Schnell Bar

Hızlı erişim çubuğu. POS v2 shell'inin sağ sütununda, products grid'in üstünde sabit duran 1 satırlık quick-pick tile'lar.

**Dosya**: [apps/pos/lib/features/orders/presentation/shells/pos_v2_shell.dart:2028](../../../apps/pos/lib/features/orders/presentation/shells/pos_v2_shell.dart)

## Amaç

Kasiyerin en sık dokunduğu ürünleri (espresso, bier, kleine pommes gibi) ayrı bir görsel alanda tutmak. Kategori seçip sayfa değiştirmeye gerek kalmaz, en sık satılan 6 ürün tek bir satırda.

## Görsel Spec

```
┌──────────────────────────────────────────────────────────┐
│ ╔════════╗╔════════╗╔════════╗╔════════╗╔════════╗╔════════╗│
│ ║Espresso║║Cappu   ║║Bier    ║║Wasser  ║║Pommes  ║║Wiener  ║│
│ ║         ║║         ║║         ║║         ║║         ║║         ║│
│ ║CHF 3.50 ║║CHF 4.80 ║║CHF 6.00 ║║CHF 4.00 ║║CHF 5.50 ║║CHF 14.0 ║│
│ ╚════════╝╚════════╝╚════════╝╚════════╝╚════════╝╚════════╝│
└──────────────────────────────────────────────────────────┘
```

- **Yükseklik**: 108px (parent `SizedBox(height: 108)`)
- **Tile sayısı**: `picks.take(6)` - yalnız 6 slot
- **Tile arası**: `SizedBox(width: 8)`
- **Kenar boşlukları**: horizontal 22, vertical 6
- **Arka plan**: `V2.surface` + alt `V2.line` border
- **Layout**: `Row` içinde her tile `Expanded` sarmalı, eşit genişlik

## `_SchnellBar` (pos_v2_shell.dart:2028)

```dart
class _SchnellBar extends ConsumerWidget {
  final List<ProductEntity> products;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final picks = products.take(6).toList();
    return Container(
      decoration: const BoxDecoration(
        color: V2.surface,
        border: Border(bottom: BorderSide(color: V2.line, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
      child: Row(
        children: [
          for (int i = 0; i < picks.length; i++) ...[
            Expanded(
              child: _SchnellTile(
                product: picks[i],
                onTap: () => _addToTicket(ref, picks[i]),
              ),
            ),
            if (i < picks.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}
```

## `_SchnellTile` (pos_v2_shell.dart:2085)

Tek tile içi:

```dart
class _SchnellTile extends StatelessWidget {
  static const Color _bg     = Color(0xFFEEF4FB);   // açık mavi-gri
  static const Color _border = Color(0xFFDCE6F2);

  final ProductEntity product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _bg,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            border: Border.all(color: _border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,          // !!! leak fix
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(product.name, style: V2Text.schnellName, maxLines: 2),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('CHF', style: V2Text.schnellCur),
                  const SizedBox(width: 4),
                  Text(v2Chf(product.priceCents), style: V2Text.schnellPrice),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

### MainAxisSize.min Kritik
İlk sürümde `MainAxisSize.max` idi, parent'in Column'u Expanded'e 0 height verdi. Tabletli cihazda grid hiç render olmadı. Fix: `MainAxisSize.min`. Detay hikayesi: [05-kararlar-ve-bilinmesi-gerekenler/mainaxis-size-leak.md](../../05-kararlar-ve-bilinmesi-gerekenler/mainaxis-size-leak.md).

## Ekleme Akışı

```dart
void _addToTicket(WidgetRef ref, ProductEntity product) {
  ref.read(currentTicketProvider.notifier).addItem(product);
}
```

Tek dokunuş - quantity 1 eklenir, aynı ürüne ikinci kez basılırsa mevcut kalemin quantity'si artar (notifier içinde `if (existing) incrementQty`).

## Empty State

Eğer menu hiç yüklenmemişse Schnell bar hiç render olmaz. `_ItemsWrap` içinde guard:
```dart
if (allProducts.isNotEmpty)
  SizedBox(height: 108, child: _SchnellBar(products: allProducts)),
```

## Hangi 6 Ürün?

Şu an `products.take(6)`. Bu productsProvider'dan gelen sıralamaya göre. Gelecekte bir popularity provider veya tenant-config tabanlı seçim istenebilir (`features/menu/domain/entities/product_entity.dart` içindeki `isQuickPick: bool?` alanı kullanılabilir - hazır olduğu yerde).

## Dikkat Edilecekler

- Tile isimleri iki satıra kadar wrap eder (`maxLines: 2`). Çok uzun isimler 3. satıra taşarsa ellipsis. Kontrol `V2Text.schnellName`'de `height: 1.2`.
- Schnell bar kaydırılmaz. Eğer 6'dan fazla ürün gösterilmesi istenirse `ListView.separated` + horizontal scroll'a geçilmesi gerekir (şu an sabit 6 slot).
- Palette ile renk değişmez. Schnell tile'ların arka planı hard-coded `0xFFEEF4FB` (açık mavi-gri). Bu reference design'dan geliyor.
