# MainAxisSize Leak (inner=1160x0)

POS v2 shell'inde yaşanmış bir Flutter layout bug'ı. Şeytan detaylardaydı; kaydetmezsek bir dahaki sefere tekrar saat harcarız.

## Belirti

POS ekranı açılıyor, top bar + Schnell bar + bottom action bar hepsi görünür durumda. Ama products grid hiçbir yerde yok - orta-alt bölge bomboş siyah/gri.

Debug mode'da hiç exception yok, sadece content invisible.

## Kök Teşhis

`_ItemsWrap.build` içindeki `Expanded` widget'ı LayoutBuilder ile ölçüldüğünde:
```
inner=1160x0
```

Genişlik OK (1160px) ama **yükseklik 0**. Yani products grid'e 0 pixel alan veriliyor, tabi ki görünmüyor.

## Neden 0 Oluyordu

Widget ağacı sorunu:

```
Column (parent - height = infinity / unbounded)
├── _ItemsHeader (eski - Column içinde MainAxisSize.max)   // GREEDY!
├── _SchnellBar (Container, inner Column MainAxisSize.max) // GREEDY!
└── Expanded (child)   ← bu 0 kalıyor
```

`Column` çocuklarına `mainAxisSize: MainAxisSize.max` default'uyla height istiyor, ama parent constraint infinite (veya fit değil).

`_ItemsHeader` ve `_SchnellBar` içindeki **iç Column'ları** `MainAxisSize.max` olduğu için "ben bütün yüksekliği istiyorum" diyor. Outer `Column` bu isteklere uyunca `Expanded`'a 0 kalıyor.

## Flutter'ın Tuhaf Davranışı

Normalde `Column`'un çocuklarına `Expanded` verdiğinde Flutter "Expanded her zaman kalan alanı alır" garantisi verir. Ama eğer parent Column yatay unbounded constraint içindeyse veya iç widget'ların bir biri ile çatışması varsa, Expanded'a aslında 0 düşebilir. Bu rare case ama burda tetiklendi.

Ayrıca `Material -> InkWell -> Container` kombinasyonu içindeki Column'ların default `MainAxisSize.max` olması, outer Column'un height calculation'ını bozdu.

## Çözüm - Belt and Suspenders (A + B)

Kullanıcı "hızlı + kesin çözüm" istedi, ikisi birden uygulandı:

### A: Explicit SizedBox Height
Parent'ta iki üst widget'ı sabit yükseklikte wrap et:
```dart
Column(
  children: [
    if (allProducts.isNotEmpty)
      SizedBox(height: 108, child: _SchnellBar(products: allProducts)),
    Expanded(child: _ItemsGrid(...)),
  ],
)
```

Böylece Flutter "Schnell bar 108, kalan Expanded'ın" diye net bir hesap yapar.

### B: MainAxisSize.min
İç Column'ların ihtirasını kıs:
```dart
// _ItemsHeader (daha sonra tamamen silindi ama o zaman)
Column(
  mainAxisSize: MainAxisSize.min,   // ***
  children: [...],
)

// _SchnellTile
Column(
  mainAxisSize: MainAxisSize.min,   // ***
  crossAxisAlignment: CrossAxisAlignment.start,
  mainAxisAlignment: MainAxisAlignment.spaceBetween,
  children: [
    Text(product.name, ...),
    Row([Text('CHF'), Text(v2Chf(...))]),
  ],
)
```

`.min` ile Column sadece çocuklarının istediği kadar yükseklik ister, "ver hepsini bana" demez.

## Kullanıcı Feedback'i

"GRID IS RENDERING - FIX WORKED"

## Commit

```
f57970f fix(pos): use MainAxisSize.min + fixed-height header/schnell to restore items grid
```

## Sonraki Sprint'te Debug Strip'in Kaldırılması

Debug için eklenen:
- Amber renk debug strip (constraint readout).
- Lime/red/purple visibility markerlari.
- `_innerConstraintsProvider` (constraint'i UI'a yansıtan).

Hepsi bir sonraki commit'te (`053318d`) temizlendi, fix kaldı.

## Dersler

1. **LayoutBuilder içinde width/height yazdır** - constraint leak avlamanın en hızlı yolu.
2. **Kod Column'lari için default'tan şüphe et** - `MainAxisSize.min` yazmak yazmamaktan daha güvenli.
3. **Belt-and-suspenders** - pilot deadline'da "bu yeterlidir" riski alma, iki çözümü üst üste uygula.
4. **IntrinsicHeight pahalı, SizedBox ucuz** - fix alternatifi `IntrinsicHeight` ile wrap etmekti, ama performans sıkıntısı doğurur. Sabit yükseklik sabit yüksekliktir.
5. **Sadece emulator test yetmiyor** - gerçek tablet APK'da layout farklı render olabilir.

## Reprodüce Etmek İçin (İleriki Bug'lar İçin Template)

```dart
// Kötü
Column(
  children: [
    MyHeader(),           // içi MainAxisSize.max
    MyMiddleBar(),        // içi MainAxisSize.max
    Expanded(child: Body()),  // 0 height!
  ],
)

// İyi
Column(
  children: [
    SizedBox(height: 48, child: MyHeader()),
    SizedBox(height: 108, child: MyMiddleBar()),
    Expanded(child: Body()),  // kalan
  ],
)
```

## Alternatif Yaklaşımlar (Seçilmedi)

### `IntrinsicHeight`
```dart
IntrinsicHeight(child: Column(children: [...]))
```
Çalışır ama her frame'de iki pass layout yapar, performans düşer. Grid gibi scrollable içeren widget'larda özellikle kötü.

### `Flexible(flex: 0)`
```dart
Flexible(flex: 0, child: MyHeader())
```
Expanded gibi kalan alanı bölüşmez ama child'ın natural height'ını alır. İşe yarar ama okunabilirlik daha az.

### `LayoutBuilder` ile manuel hesap
Çocukların height'ını tam hesapla. Çok kod, çok hata yeri.

Sonuçta SizedBox + MainAxisSize.min kombinasyonu en temiz çıktı.

## Bu Tarz Bug'ları Erken Yakalamak

- Widget testi yazarken `find.byType(Expanded)` ve size check et.
- Golden test ekranın tamamını karşılaştırır, boş alan baseline ile diff eder.
- `flutter run --trace-startup` - first frame render süresinde layout overflow assertion varsa kırmızı tek satır.

## Şu Anki Durum (a20acc3)

`_ItemsHeader` tamamen silindi. Sadece `_SchnellBar` var, onu da `SizedBox(height: 108, ...)` wrap ediyor:
```dart
if (allProducts.isNotEmpty)
  SizedBox(height: 108, child: _SchnellBar(products: allProducts)),
Expanded(
  child: productsAsync.when(
    data: (products) => _ItemsGrid(products: products, ...),
    loading: () => CircularProgressIndicator(...),
    error: (err, _) => Text('Menü konnte nicht geladen werden'),
  ),
),
```

`_SchnellTile` hala `MainAxisSize.min` tutuyor - iki sigorta.
