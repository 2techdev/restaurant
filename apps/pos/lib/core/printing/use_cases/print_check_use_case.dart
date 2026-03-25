import 'dart:typed_data';

import '../escpos/adisyon_builder.dart';
import '../models/print_models.dart';
import '../printer_service.dart';

/// Adisyon (check/bill) yazdırma use case'i.
///
/// Mevcut siparişi kapatmadan müşteri için ara fatura basar.
/// Ödeme bilgisi içermez — sadece ürünler + toplam + "Bitte zahlen".
///
/// Riverpod kullanımı:
/// ```dart
/// final useCase = ref.read(printCheckUseCaseProvider);
/// await useCase(adisyonData);
/// ```
class PrintCheckUseCase {
  const PrintCheckUseCase(this._service);

  final PrinterService _service;

  /// [data]'dan ESC/POS adisyon üretir ve yazıcıya gönderir.
  /// Başarılı ise `true`, yazıcı hatası varsa `false` döner.
  Future<bool> call(AdisyonData data) async {
    final bytes = build(data);
    return _service.printBytes(bytes);
  }

  /// Yalnızca byte dizisi üretir (test / önizleme için).
  Uint8List build(AdisyonData data) => AdisyonBuilder(data: data).build();
}
