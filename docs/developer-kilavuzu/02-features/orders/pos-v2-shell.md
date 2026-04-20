# POS v2 Shell

POS v2 shell, ana satış ekranının yeniden tasarlanmış versiyonudur. `.design/pos-v2/POS.html` ve `parts.jsx` referans olarak alındı, birebir Flutter'a portlandı.

**Ana dosya**: [apps/pos/lib/features/orders/presentation/shells/pos_v2_shell.dart](../../../apps/pos/lib/features/orders/presentation/shells/pos_v2_shell.dart)

## Giriş Noktası

`FineDiningShell` ve `FastFoodShell` ikisi de `PosV2Shell`'i sarmalar:

```dart
// features/orders/presentation/shells/fine_dining_shell.dart
class FineDiningShell extends ConsumerWidget {
  const FineDiningShell({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Scaffold(body: PosV2Shell());
  }
}
```

Böylece iki farklı mode (fine dining ve fast food) ayni shell'i kullanır, aralarındaki fark mode ayarında ve feature flag'lerde.

## Layout Topolojisi

`_V2Layout` (pos_v2_shell.dart:80) üç sütunlu ana grid:

```
+------+------------+-------------------------------+
|      | TopBar (44px)                              |
| Nav  +------------+-------------------------------+
| Rail |            |                               |
| 72px | Order      | Items Panel                   |
|      | Column     |   Schnell Bar (108px)          |
|      | 380px      |   Products Grid (LayoutBuilder)|
|      |            |                               |
|      |            |                               |
|      +------------+-------------------------------+
|      | Bottom Action Bar (72px)                   |
+------+------------+-------------------------------+
```

### Ana Widget Ağacı (pos_v2_shell.dart)

| Widget | Satır | Ne yapar |
|---|---|---|
| `PosV2Shell` | 64 | Kök `ConsumerWidget`, sadece `_V2Layout` döner |
| `_V2Layout` | 80 | Üç sütun + üst/alt bar kompozisyonu |
| `_Rail` | 148 | Sol dikey nav rail (72px) |
| `_RailBtn` | 285 | Rail ikon butonu |
| `_TopBar` | 367 | Üst dark bar (brand, ticket meta, mode, search, gear) |
| `_ModeSwitch` | 467 | Dine-in / Takeaway / Delivery toggle |
| `_TopSearchField` | 519 | Arama input'u |
| `_TopIcon` | 583 | Gear ikonu (Tweaks overlay tetikler) |
| `_OrderPanel` | 697 | Orta sütun (ticket items listesi) |
| `_OrderHead` | 714 | Ticket başlığı + guest count |
| `_GangTabs` | 829 | Kurs sekmeleri (Vorspeisen, Hauptgang...) |
| `_ItemsWrap` | ~1844 | Sağ sütun: Schnell bar + products grid |
| `_SchnellBar` | 2028 | 6 quick-pick tile'lı üst sıra |
| `_SchnellTile` | 2085 | Tek quick-pick tile |
| `_ItemsGrid` | ~2140 | `LayoutBuilder` + `GridView.builder` |
| `_PCard` | ~2268 | Ürün kartı (category bg + qty badge) |
| `_TweaksOverlay` | - | Gear'a basınca açılan Palette/Images toggle |
| `_SegmentedPair<T>` | - | Tweaks içindeki iki segment toggle |

## Providerlar

`pos_v2_shell.dart:44-59` içinde tanımlı UI state'leri:

```dart
final v2SelectedLineIdProvider = StateProvider<String?>((ref) => null);
final v2RailActiveProvider = StateProvider<String>((ref) => 'sale');
final productImagesEnabledProvider = StateProvider<bool>((ref) => false);

enum PosPalette { ivory, midnight }
final posPaletteProvider = StateProvider<PosPalette>((ref) => PosPalette.ivory);
```

| Provider | Ne |
|---|---|
| `v2SelectedLineIdProvider` | Ticket listesinde seçili kalem ID'si, quantity/void akışı için |
| `v2RailActiveProvider` | Sol raildeki aktif buton ('sale', 'tables', 'reports'...) |
| `productImagesEnabledProvider` | Ürün kartlarında görsel backdrop'u aç/kapat |
| `posPaletteProvider` | Ivory / Midnight palet seçimi |

Ticket state'i farklı dosyadan gelir: `currentTicketProvider` (`features/orders/presentation/providers/order_provider.dart`).

Menu state'i: `productsProvider` (`features/menu/`).

## Sol Nav Rail

`_Rail` (pos_v2_shell.dart:148) dikey buton dizisi:
- Sale (default, ticket ekranı)
- Tables
- Orders (history)
- Reports
- Settings

Her biri `_RailBtn` (pos_v2_shell.dart:285). Aktif olanın arka planı `V2.sel`, ikon rengi beyaz.

## Top Bar

`_TopBar` (pos_v2_shell.dart:367) sırası (sol -> sağ):
1. `_BrandLockup` (logo + "GastroCore POS")
2. `_TicketMeta` (Bon numarası, tarih)
3. `_ModeSwitch` (dine-in / takeaway / delivery)
4. `Spacer`
5. `_TopIcon(Icons.tune)` (gear - Tweaks overlay)
6. `_TopSearchField` (arama)
7. `_UserPill` (cashier avatar)

Gear butonuna basınca `showDialog` ile `_TweaksOverlay` açılır (`barrierColor: transparent`, sağ-alta hizalı).

## Order Column (Orta Sütun)

`_OrderColumn` (pos_v2_shell.dart:123) - 380px sabit genişlik. İçinde:
- `_OrderHead` - Ticket adı, guest count stepper
- `_GangTabs` - Kurs sekmeleri
- Items listesi (ticket items ScrollView)
- `_GangAddTab` - Yeni kurs ekle

## Items Panel (Sağ Sütun)

Expanded sütun, iki katmandan oluşur:
- **Üst**: Schnell bar (108px sabit). Bkz [schnell-bar.md](schnell-bar.md).
- **Alt**: Product grid, `Expanded` ile kalan alanı doldurur. Bkz [product-cards.md](product-cards.md).

`_ItemsWrap.build` yapısı:
```dart
Column(
  children: [
    if (allProducts.isNotEmpty)
      SizedBox(height: 108, child: _SchnellBar(products: allProducts)),
    Expanded(
      child: productsAsync.when(
        data: (products) {
          if (products.isEmpty) return const _EmptyGrid();
          return _ItemsGrid(products: products, ...);
        },
        loading: () => const Center(child: CircularProgressIndicator(color: V2.accent)),
        error: (err, _) => Center(child: Text('Menü konnte nicht geladen werden: $err')),
      ),
    ),
  ],
)
```

**Kritik**: Empty state'te `SizedBox(108)` render edilmez, yoksa grid bir parça alan kaybeder. Bu guard olmadan ekran boş kalabilir.

## Bottom Action Bar

`BottomActionBar` (`features/orders/presentation/widgets/shell/bottom_action_bar.dart`) ayrı dosyada. `PosV2Shell`'e `_V2Layout` tarafından dikey olarak bağlanır. Bkz [bottom-action-bar.md](bottom-action-bar.md).

## Genel Akış (Tipik Kullanıcı)

1. Kasiyer rail'den `sale` seçili.
2. `_ModeSwitch` ile dine-in seçer.
3. Schnell bar'dan quick-pick ürüne dokunur -> `currentTicketProvider.addItem(product)`.
4. Alternatif: products grid'den bir kart -> aynı şekilde.
5. Orta sütundaki ticket items listesi anlık güncellenir (`ref.watch(currentTicketProvider)`).
6. GESAMT readout (bottom bar) canlı toplanır.
7. SENDEN -> gönderilmemiş kalemleri mutfağa gönderir.
8. BEZAHLEN -> `OrderPaymentScreen`'e push, akış oradan devam.

## Test Dokunulan Noktalar

- Empty menu durumu (`_EmptyGrid`).
- Async error state (text Almanca: "Menü konnte nicht geladen werden").
- Farklı ekran oranlarında grid kolon sayısı adaptasyonu (LayoutBuilder formülü).
- Palette switch (Ivory/Midnight) ürün kartını ve CHF renklerini değiştirir.
- Product images on/off tüm kartları etkiler.
