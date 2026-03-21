import 'dart:typed_data';

/// ESC/POS komut oluşturucu.
///
/// Zincirleme API ile ESC/POS byte dizisi oluşturur:
/// ```dart
/// final bytes = EscPosBuilder()
///     .initialize()
///     .alignCenter()
///     .boldOn()
///     .text('GASTROCORE POS')
///     .boldOff()
///     .feed(2)
///     .cut()
///     .build();
/// ```
class EscPosBuilder {
  final List<int> _buffer = [];

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  /// ESC @ — Yazıcıyı başlangıç durumuna sıfırla
  EscPosBuilder initialize() {
    _buffer.addAll([0x1B, 0x40]);
    return this;
  }

  // ---------------------------------------------------------------------------
  // Text alignment
  // ---------------------------------------------------------------------------

  /// ESC a 0 — Sola hizala
  EscPosBuilder alignLeft() {
    _buffer.addAll([0x1B, 0x61, 0x00]);
    return this;
  }

  /// ESC a 1 — Ortaya hizala
  EscPosBuilder alignCenter() {
    _buffer.addAll([0x1B, 0x61, 0x01]);
    return this;
  }

  /// ESC a 2 — Sağa hizala
  EscPosBuilder alignRight() {
    _buffer.addAll([0x1B, 0x61, 0x02]);
    return this;
  }

  // ---------------------------------------------------------------------------
  // Text style
  // ---------------------------------------------------------------------------

  /// ESC E 1 — Kalın yazı açık
  EscPosBuilder boldOn() {
    _buffer.addAll([0x1B, 0x45, 0x01]);
    return this;
  }

  /// ESC E 0 — Kalın yazı kapalı
  EscPosBuilder boldOff() {
    _buffer.addAll([0x1B, 0x45, 0x00]);
    return this;
  }

  /// ESC - 1 — Alt çizgi açık
  EscPosBuilder underlineOn() {
    _buffer.addAll([0x1B, 0x2D, 0x01]);
    return this;
  }

  /// ESC - 0 — Alt çizgi kapalı
  EscPosBuilder underlineOff() {
    _buffer.addAll([0x1B, 0x2D, 0x00]);
    return this;
  }

  // ---------------------------------------------------------------------------
  // Font size
  // ---------------------------------------------------------------------------

  /// GS ! — Yazı boyutu. [width] ve [height] 1–8 arasında (1 = normal).
  EscPosBuilder textSize({int width = 1, int height = 1}) {
    assert(width >= 1 && width <= 8, 'width 1-8 arası olmalı');
    assert(height >= 1 && height <= 8, 'height 1-8 arası olmalı');
    final n = ((width - 1) << 4) | (height - 1);
    _buffer.addAll([0x1D, 0x21, n]);
    return this;
  }

  /// Normal boyuta döndür (1x1)
  EscPosBuilder textSizeNormal() => textSize(width: 1, height: 1);

  /// Çift genişlik + çift yükseklik (2x2)
  EscPosBuilder textSizeDouble() => textSize(width: 2, height: 2);

  // ---------------------------------------------------------------------------
  // Text output
  // ---------------------------------------------------------------------------

  /// Türkçe karakterleri ASCII'ye çevirip byte olarak yaz.
  EscPosBuilder text(String value) {
    _buffer.addAll(_encodeText(value));
    return this;
  }

  /// Metin yaz + satır sonu (LF)
  EscPosBuilder textLine(String value) {
    text(value);
    _buffer.add(0x0A); // LF
    return this;
  }

  /// İki kolumlu satır yaz (sol ve sağ hizalı, [width] karakter genişliğinde).
  EscPosBuilder twoColumnLine(
    String left,
    String right, {
    int width = 42,
  }) {
    final l = _normalize(left);
    final r = _normalize(right);

    final space = width - l.length - r.length;
    if (space > 0) {
      _buffer.addAll(_encodeText(l + ' ' * space + r));
    } else {
      // Sığmıyorsa birbirinden boşlukla ayır
      _buffer.addAll(_encodeText('$l $r'));
    }
    _buffer.add(0x0A);
    return this;
  }

  /// Ayraç çizgisi (─ karakteri yerine ASCII '-').
  EscPosBuilder divider({int width = 42, String char = '-'}) {
    _buffer.addAll(_encodeText(char * width));
    _buffer.add(0x0A);
    return this;
  }

  // ---------------------------------------------------------------------------
  // Feed & Cut
  // ---------------------------------------------------------------------------

  /// LF — Tek satır besle
  EscPosBuilder newLine() {
    _buffer.add(0x0A);
    return this;
  }

  /// ESC d n — n satır besle
  EscPosBuilder feed([int lines = 3]) {
    _buffer.addAll([0x1B, 0x64, lines]);
    return this;
  }

  /// GS V 1 — Kısmi kesim (partial cut)
  EscPosBuilder cut() {
    _buffer.addAll([0x1D, 0x56, 0x01]);
    return this;
  }

  /// GS V 0 — Tam kesim (full cut)
  EscPosBuilder fullCut() {
    _buffer.addAll([0x1D, 0x56, 0x00]);
    return this;
  }

  // ---------------------------------------------------------------------------
  // Cash drawer
  // ---------------------------------------------------------------------------

  /// ESC p — Kasa çekmecesi aç (Pin 2 ve Pin 5)
  EscPosBuilder openCashDrawer() {
    _buffer.addAll([
      0x1B, 0x70, 0x00, 0x19, 0xFA, // Pin 2
      0x1B, 0x70, 0x01, 0x19, 0xFA, // Pin 5
    ]);
    return this;
  }

  // ---------------------------------------------------------------------------
  // QR Code (basic ESC/POS model 2)
  // ---------------------------------------------------------------------------

  /// QR kod yaz (GS ( k komut dizisi).
  EscPosBuilder qrCode(String data, {int moduleSize = 4}) {
    final dataBytes = _encodeText(data);
    final storeLen = dataBytes.length + 3;
    final pL = storeLen & 0xFF;
    final pH = (storeLen >> 8) & 0xFF;

    _buffer.addAll([
      // Model seç: model 2
      0x1D, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00,
      // Modül boyutu
      0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, moduleSize,
      // Hata düzeltme: M seviyesi
      0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x45, 0x31,
      // Veri depola
      0x1D, 0x28, 0x6B, pL, pH, 0x31, 0x50, 0x30,
      ...dataBytes,
      // Yazdır
      0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30,
    ]);
    return this;
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  /// Oluşturulan byte dizisini döndürür.
  Uint8List build() => Uint8List.fromList(_buffer);

  /// Sıfırla ve yeni zincir başlat.
  EscPosBuilder reset() {
    _buffer.clear();
    return this;
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Türkçe karakterleri ASCII eşdeğerine çevirip Latin-1 byte dizisine kodlar.
  List<int> _encodeText(String text) {
    const map = {
      'ş': 's', 'Ş': 'S',
      'ğ': 'g', 'Ğ': 'G',
      'ı': 'i', 'İ': 'I',
      'ü': 'u', 'Ü': 'U',
      'ö': 'o', 'Ö': 'O',
      'ç': 'c', 'Ç': 'C',
    };

    var converted = text;
    map.forEach((k, v) => converted = converted.replaceAll(k, v));

    final bytes = <int>[];
    for (final codeUnit in converted.codeUnits) {
      bytes.add(codeUnit < 256 ? codeUnit : 0x3F);
    }
    return bytes;
  }

  /// Türkçe karakterleri normalize et (uzunluk hesabı için).
  String _normalize(String text) {
    const map = {
      'ş': 's', 'Ş': 'S',
      'ğ': 'g', 'Ğ': 'G',
      'ı': 'i', 'İ': 'I',
      'ü': 'u', 'Ü': 'U',
      'ö': 'o', 'Ö': 'O',
      'ç': 'c', 'Ç': 'C',
    };
    var out = text;
    map.forEach((k, v) => out = out.replaceAll(k, v));
    return out;
  }
}
