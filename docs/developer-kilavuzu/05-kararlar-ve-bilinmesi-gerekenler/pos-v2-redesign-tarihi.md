# POS v2 Redesign Tarihi

POS satış ekranının `.design/pos-v2/` referansına göre baştan tasarlanma süreci. Bir gün içinde birden fazla iterasyonla pilot-ready hale geldi.

## Başlangıç Durumu

- Eski shell: `fine_dining_shell.dart` + `fast_food_shell.dart` ayrı implementasyonlar.
- Bottom bar + header + products grid ayrı iken güncelleme zor.
- Kategori chip'leri küçük, product card'da kategori rengi sadece bir şerit.
- 2-row Schnell bar + avatar'lı tile'lar kalabalık görünüyordu.

## Reference Design

- `.design/pos-v2/POS.html` - tam ekran mockup.
- `.design/pos-v2/parts.jsx` - React parçaları (referans).

Tasarım hedefi:
- Minimal chrome (dark top bar + light body).
- 1-row Schnell bar (8 tile -> sonra 6 tile'a düşürüldü).
- Kategori rengini product card'ın tamamına yayma.
- Blue selected border (`V2.sel = 0xFF486BE1`).
- Ivory / Midnight palette switch.
- Produktbilder on/off.

## Iterasyon Zaman Çizelgesi

### 1. Items grid hiç render olmuyordu (kritik bug)
Debug çıktısı `inner=1160x0` gösterdi. Schnell bar layout'u Expanded'ı 0 height'a itiyordu.

Çözüm: Belt-and-suspenders fix (kullanıcı onayı ile):
- **A**: `SizedBox(height: N, child: ...)` ile explicit height.
- **B**: İç Column'lara `MainAxisSize.min`.

Commit: `f57970f fix(pos): use MainAxisSize.min + fixed-height header/schnell to restore items grid`

Detay: [mainaxis-size-leak.md](mainaxis-size-leak.md).

### 2. Debug decoration strip, reference design'a port
Amber debug strip, lime/red/purple visibility marker'lari, `_innerConstraintsProvider` - hepsi kaldırıldı.

Yeni design implemente edildi:
- 1-row Schnell bar (başlangıçta 8 tile).
- Full category-color background product cards.
- Blue 3px selected border.
- Produktbilder on/off toggle.
- Tweaks floating overlay.

Commit: `053318d redesign(pos): 1-row Schnell bar + text-only category cards per reference design + Produktbilder toggle`

### 3. Test sonrası refinement (3 nokta)
Kullanıcı APK'yi cihazda test etti, feedback:
1. Kategori-name başlık şeridi kaldırılsın.
2. Schnell bar 8 -> 6 tile.
3. Product grid kolon sayısı 5 sabit, kart yüksekliği arttır (tablet'te tap target).

Commit: `efccaab refine(pos): drop category header + 6-wide Schnell + taller cards for tablet tap targets`

### 4. Header strip tamamen kaldırıldı, gear top bar'a taşındı
Kullanıcı ekran görüntüsü ile: 40px items header strip gereksiz, gear ikonu dark top bar'a.

- `_ItemsHeader` widget'i silindi.
- Top bar'a `_TopIcon(Icons.tune)` eklendi.
- Icon styling: dark bar üstünde white ikon (`0xB3FFFFFF`).

Commit: `c6ea47a refine(pos): remove items header strip, move Tweaks gear to top bar`

### 5. Schnell tiles full-height'e genişletildi
Kullanıcı: "Hala tam yüksekliği kullanmıyor, full fill yap."

- `_SchnellBar` container vertical padding 10 -> 6.
- Parent SizedBox 92 -> 108.
- `_SchnellTile` inner layout `MainAxisSize.min` + `mainAxisAlignment: spaceBetween` ile isim yukarı, fiyat aşağı.

Commit: `a20acc3 refine(pos): Schnell tiles fill full allocated height for tablet tap targets`

### Final: `a20acc3`
Pilot-ready. Şu anki `jolly-final` worktree'si bu commit'te.

## Kaldırılan Dosya/Kodlar

- `_ItemsHeader` widget (kategori-name + gear shown here önceden).
- `_innerConstraintsProvider` (debug için eklenen).
- Amber/lime/red/purple debug decoration widget'ları.
- Eski `fine_dining_shell.dart` / `fast_food_shell.dart` inner implementation - şu an sadece `PosV2Shell`'i sarmalayan wrapper.

## Eklenmiş Dosya/Kodlar

### Yeni provider'lar (pos_v2_shell.dart:44-59)
```dart
final v2SelectedLineIdProvider = StateProvider<String?>((ref) => null);
final v2RailActiveProvider = StateProvider<String>((ref) => 'sale');
final productImagesEnabledProvider = StateProvider<bool>((ref) => false);
enum PosPalette { ivory, midnight }
final posPaletteProvider = StateProvider<PosPalette>((ref) => PosPalette.ivory);
```

### Yeni widget'lar
- `_SchnellTile` - light blue-grey bg, text-only, two-line name.
- `_PCard` (yeniden yazıldı) - full category bg + subtitle + qty badge.
- `_TweaksOverlay` - gear tıklaması ile açılan floating popover.
- `_SegmentedPair<T>` - Tweaks içinde generic toggle.
- `_TopIcon` - dark top bar için gear ikonu.
- `_ItemsGrid` - LayoutBuilder + mainAxisExtent 130px.

### Tema eklemeleri (`pos_v2_theme.dart`)
- `V2Text.pName`, `pSub`, `pPrice`, `pCurrency`, `schnellName`, `schnellPrice`, `schnellCur`, `inCart`.
- `V2.sel = 0xFF486BE1` (blue vurgu).
- `V2.surface`, `V2.line`, `V2.ink` serisi.

## Öğrenilen Dersler

### MainAxisSize kritik
Nested Column'larda her zaman `MainAxisSize.min` düşün. `.max` default'u constraint leak'e sebep olabilir, özellikle LayoutBuilder/Expanded karışık.

### Belt-and-suspenders her zaman daha güvenli
Kullanıcı pilot-ready bir APK beklerken iki çözümü (A + B) aynı anda uygulamak en hızlı yoldu. "Tek çözüm yeter" optimizasyonu bazen yeni baştan debug süresi getirir.

### Reference design = source of truth
`.design/pos-v2/POS.html` + `parts.jsx` değişmeden kalır. Flutter port için pixel-perfect çıkış vermek hedef. Özgürleşmeler kullanıcı onayı gerekir.

### Tablet tap target
Tablet'te parmak ~12mm (~44px). Schnell tile minimum 92px, sonunda 108px. Product card 130px. Bu değerler deneyle bulundu.

### Rebuild iyice test et
Kullanıcı her refine'dan sonra APK'yi cihazda test etti. Pixel value'lar emulator'da doğru görünüyorsa bile gerçek cihazta farklı olabilir.

## Commit Listesi (Kronolojik)

```
f57970f fix(pos): use MainAxisSize.min + fixed-height header/schnell to restore items grid
053318d redesign(pos): 1-row Schnell bar + text-only category cards per reference design + Produktbilder toggle
efccaab refine(pos): drop category header + 6-wide Schnell + taller cards for tablet tap targets
c6ea47a refine(pos): remove items header strip, move Tweaks gear to top bar
a20acc3 refine(pos): Schnell tiles fill full allocated height for tablet tap targets
```

## Kalan İş (Opsiyonel)

- Palette persistence (`shared_preferences` ile Ivory/Midnight seçimi hatırlansın).
- Popularity-based Schnell picks (şu an `products.take(6)`).
- Category chip ayrı breadcrumb komponentin kaldırılması / düşünülmesi.
- Midnight palette'de kategori renklerinin ton adaptasyonu (daha koyu varyantlar).
