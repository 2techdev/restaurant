# Tweaks Paneli

Üst bardaki gear ikonuna basılınca açılan floating popover. Kasiyere iki hızlı ayar sunar: palet seçimi ve ürün görseli on/off.

**Dosya**: [apps/pos/lib/features/orders/presentation/shells/pos_v2_shell.dart](../../../apps/pos/lib/features/orders/presentation/shells/pos_v2_shell.dart) (`_TweaksOverlay`, `_SegmentedPair`)

## Tetikleme

`_TopBar` içinde gear ikonu (`_TopIcon(icon: Icons.tune)`) tıklandığında:

```dart
_TopIcon(
  icon: Icons.tune,
  onTap: () => showDialog<void>(
    context: context,
    barrierColor: Colors.transparent,             // karartma yok
    builder: (_) => const _TweaksOverlay(),
  ),
),
```

`barrierColor: Colors.transparent` - arka planı karartmaz, popover yüzer.

## Konumlandırma

`_TweaksOverlay.build`:
```dart
class _TweaksOverlay extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          elevation: 12,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TWEAKS', style: ...),
                _SegmentedPair<PosPalette>(
                  label: 'Palette',
                  value: ref.watch(posPaletteProvider),
                  left: PosPalette.ivory,
                  right: PosPalette.midnight,
                  leftLabel: 'Ivory',
                  rightLabel: 'Midnight',
                  onChanged: (v) => ref.read(posPaletteProvider.notifier).state = v,
                ),
                _SegmentedPair<bool>(
                  label: 'Produktbilder',
                  value: ref.watch(productImagesEnabledProvider),
                  left: false,
                  right: true,
                  leftLabel: 'Aus',
                  rightLabel: 'An',
                  onChanged: (v) => ref.read(productImagesEnabledProvider.notifier).state = v,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- Ekranın sağ-altına hizalı.
- 16px dış padding (ekran kenarına yapışmaması için).
- Material card: beyaz, 12px radius, elevation 12.

## `_SegmentedPair<T>` Widget'ı

İki segmentli toggle. Generic tip, hem `PosPalette` hem `bool` hem başka enum'larda kullanılabilir.

```dart
class _SegmentedPair<T> extends StatelessWidget {
  final String label;
  final T value;
  final T left;
  final T right;
  final String leftLabel;
  final String rightLabel;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: ...),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2F6),
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(3),
            child: Row(
              children: [
                _seg(leftLabel, value == left, () => onChanged(left)),
                _seg(rightLabel, value == right, () => onChanged(right)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _seg(String text, bool selected, VoidCallback onTap) => Expanded(
    child: InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? V2.sel : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: selected ? Colors.white : V2.ink2,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
}
```

Seçili segment:
- Arka plan: `V2.sel` (mavi).
- Yazı: beyaz.
- Diğer segment: transparent arka plan, `V2.ink2` yazı.

## Bağlandığı Providerlar

### `posPaletteProvider`
`enum PosPalette { ivory, midnight }`. Ivory = açık tema (default). Midnight = koyu tema.

`_PCard` `ref.watch(posPaletteProvider)` ile palette'i okur, kategori bg'sinin tonunu adapte eder.

### `productImagesEnabledProvider`
`StateProvider<bool>`, default `false`. `true` olduğunda product card arka planına `Image.asset` gelir.

## UX Notları

- Popover açıkken dışarıya tıklamak `showDialog` davranışına göre kapatır.
- Seçim anında provider update olur, UI tüm product card'larda anında rebuild olur.
- Kaydetme butonu yok - her değişiklik canlı uygulanır.
- Kaydırma / kaybolan diyalog yok, küçük popover ne kadar sürerse kalır.

## Persistence

**Şu an**: Bu ayarlar uygulamanın oturum süresince kalır, yeniden başlatmada sıfırlanır (default ivory + images off).

**Gelecek**: `shared_preferences` ile persist edilmesi olası. Yama fikri:
```dart
final posPaletteProvider = StateProvider<PosPalette>((ref) {
  // SharedPreferences'tan initial yükle
  return PosPalette.ivory;
});
```
Bu henüz implemente değil; istenirse trivial bir iş.

## Kullanıcı Akışı

1. Kasiyer sağ üst gear ikonuna dokunur.
2. Sağ-alt köşede popover açılır.
3. "Midnight" toggle -> tüm product cards koyu moda geçer.
4. "Produktbilder An" toggle -> SVG backdrop'lar görünür.
5. Popover dışına tıklar -> kapanır.

## Test Edilen

- Gear dokunuşu popover'ı açar.
- Sağ-alt hizasıdır (her ekran oranında).
- Segment seçimi canlı.
- Kapatma `Navigator.pop(context)` ile veya barrier dokunuşuyla.
