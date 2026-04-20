# Design System (Tokens, Theme, POS v2)

POS ekranı iki tema katmanına sahiptir:

1. **Core theme** - Tüm app'in taban renk/tipografi sistemi (`core/theme/`).
2. **POS v2 theme** - Orders feature'ının reference design'ına özel override (`features/orders/presentation/theme/pos_v2_theme.dart`).

## Core Theme

**Dosyalar**:
- `apps/pos/lib/core/theme/app_colors.dart` - `AppColors` sınıfı (surface'lar, outline)
- `apps/pos/lib/core/theme/app_tokens.dart` - `AppTokens` (spacing, touch target, radius)
- `apps/pos/lib/core/theme/kinetic_theme.dart` - `GcColors`, `GcText`, `kCashGradient`, `kInsetHighlight`
- `apps/pos/lib/core/theme/app_theme.dart` - `ThemeData` builder

### GcColors (kinetic_theme.dart:40+)

Kategori renkleri (sepette kategori chip'i, KDS durum renkleri vb):
```dart
static const Color primary            = Color(0xFF3841E9);
static const Color catRed             = Color(0xFFE53935);
static const Color catOrange          = Color(0xFFF57C00);
static const Color catYellow          = Color(0xFFBC02D);
static const Color catGreen           = Color(0xFF43A047);
static const Color catTeal            = Color(0xFF00838F);
static const Color catCyan            = Color(0xFF00ACC1);
static const Color catDarkGreen       = Color(0xFF2E7D32);
static const Color catPurple          = Color(0xFF7B1FA2);
```

Surface tier'ları (Material 3 ton sistemini takip eder):
```dart
surfaceContainerLowest  = 0xFFFFFFFF
surfaceContainerLow     = 0xFFEEF1F3
surfaceContainer        = 0xFFE4E9EB
surfaceContainerHigh    = 0xFFDEE3E6
surfaceContainerHighest = 0xFFD8DEE1
```

### AppTokens (app_tokens.dart)

```dart
class AppTokens {
  static const double touchLarge = 56.0;          // BEZAHLEN button height
  static const double bottomBarHeight = 64.0;     // (+ 8 padding = 72)
  static const double radiusM = 8.0;
  static const double spaceS = 8.0;
  static const double spaceM = 12.0;
  static const double spaceL = 16.0;
}
```

### kCashGradient + kInsetHighlight

```dart
const LinearGradient kCashGradient = LinearGradient(
  begin: Alignment.topLeft, end: Alignment.bottomRight,
  colors: [Color(0xFF66BB6A), Color(0xFF43A047)],
);

const Color kInsetHighlight = Color(0x33FFFFFF);   // 20% white üst kenar ışık
```

Buton üstünde 2px kalınlıkta `kInsetHighlight` çizgi = hafif 3D efekti (neomorphism).

## POS v2 Theme (Reference-Specific)

**Dosya**: `apps/pos/lib/features/orders/presentation/theme/pos_v2_theme.dart`

POS v2 ekranı ayrı bir palet kullanır. `.design/pos-v2/POS.html` + `parts.jsx` referansından birebir portlandı.

### V2 renkleri (pos_v2_theme.dart:15-50)

```dart
abstract final class V2 {
  // Background
  static const Color bg       = Color(0xFFF4F5F7);
  static const Color surface  = Color(0xFFFFFFFF);
  static const Color surface2 = Color(0xFFF7F8FA);
  static const Color surface3 = Color(0xFFEEF0F2);
  static const Color line     = Color(0xFFDFE2E5);

  // Text
  static const Color ink  = Color(0xFF2B2E38);    // primary text
  static const Color ink2 = Color(0xFF555966);
  static const Color ink3 = Color(0xFF848893);
  static const Color ink4 = Color(0xFFAEB1B8);    // disabled

  // Top nav bar
  static const Color chrome    = Color(0xFF384151);
  static const Color chrome2   = Color(0xFF2A3140);
  static const Color chromeInk = Color(0xFFECEDEF);

  // Selected / accent
  static const Color sel       = Color(0xFF486BE1);    // mavi vurgu
  static const Color selWeak   = Color(0xFFE3E6F7);
  static const Color accent    = sel;
}
```

`V2.sel` (0xFF486BE1) ürün kartında "seçilmiş" border ve BEZAHLEN'de arka plan.

### V2Text (pos_v2_theme.dart:119+)

Ürün kartı + Schnell bar metin stilleri:
- `V2Text.pName` - Product card başlık (Work Sans, 14/600)
- `V2Text.pSub` - Product card subtitle (12/500, ink2)
- `V2Text.pCurrency` + `V2Text.pPrice` - Fiyat satırı, tabular figures
- `V2Text.schnellName` + `V2Text.schnellPrice` + `V2Text.schnellCur` - Schnell bar
- `V2Text.inCart` - Seçili ürün qty badge
- `V2Text.itemsH` - Items header (kullanımdan kaldırıldı)
- `V2Text.crumb` - Kategori breadcrumb

### Tabular figures

Fiyatlarda rakamların aynı genişliğe oturması için:
```dart
fontFeatures: const [FontFeature.tabularFigures()]
```

Hem Schnell bar'da hem de BottomActionBar'daki `GESAMT` readout'unda kullanılır. Tipografi referansı: [apps/pos/lib/features/orders/presentation/widgets/shell/bottom_action_bar.dart:295](../../apps/pos/lib/features/orders/presentation/widgets/shell/bottom_action_bar.dart).

## POS v2 Palette Switch

`pos_v2_shell.dart:52` içinde runtime'da palette seçilir:

```dart
enum PosPalette { ivory, midnight }
final posPaletteProvider = StateProvider<PosPalette>((ref) => PosPalette.ivory);
```

Tweaks overlay'den kullanıcı değiştirir. Ivory açık tema, Midnight koyu tema. `_PCard` widget'ı provider'ı watch eder, arka plan ve metin rengini değiştirir.

## Tipografi

**Font ailesi**: Work Sans (Google Fonts, `assets/fonts/`).

Kullanılan varyasyonlar:
- Regular (400)
- Medium (500)
- SemiBold (600)
- Bold (700)
- ExtraBold (800) - BEZAHLEN, SCHLIESSEN label'leri
- Black (900) - GESAMT readout, `GcText.displayBlack`

## Touch Target'lar

Kasiyer tabletinde parmakla dokunulur, bu yüzden:
- Ana butonlar: `56px` (`AppTokens.touchLarge`)
- İkon tuşları: en az `36x36`
- Liste item: en az `44px`
- Product card: ~`130px` mainAxisExtent (tablet'ler için yeterli hedef)
- Schnell tile: `108px` yükseklik (iki satır isim + fiyat için)

## Neomorphism Detayları

`_SecondaryButton` + `_PayButton` + `_CloseButton` üstüne 2px `kInsetHighlight` çizgi:
```dart
decoration: BoxDecoration(
  border: Border(top: BorderSide(color: kInsetHighlight, width: 2)),
),
```

Gölge + gradient birlikte, butonun "fiziksel" hissi olsun diye.

## Color Üzerine İlkeler

- **Kategori rengi ürün kartının tamamına yayılır** (POS v2 redesign sonrası). Eskiden küçük chip'ti, şimdi backdrop.
- **Selected state = mavi border** (`V2.sel`, 3px). Arka plan rengi değişmiyor, sadece 3px outline geliyor.
- **inCart badge** = beyaz daire + kategori rengi yazı, sağ üst köşe.
- **CTA renkleri**:
  - Pozitif (SENDEN, BEZAHLEN) = `catGreen` + `kCashGradient`
  - Tehlikeli (SCHLIESSEN, VOID) = `catRed`
  - Sekonder (NEUER BON, TEILEN, KARTE) = `surfaceContainerLowest`

## Kaynak Design Dosyaları

Reference implementation:
- `.design/pos-v2/POS.html` - Mockup HTML
- `.design/pos-v2/parts.jsx` - React parçaları (referans)

Her iki dosya da commit'e girer, port sırasında birebir takip edilir. Değişiklik teklifleri buradaki HTML/JSX'i de güncellemeli.
