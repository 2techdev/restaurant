import 'dart:typed_data';

import '../escpos/kitchen_ticket_builder.dart';
import '../models/print_models.dart';
import '../printer_service.dart';

/// Mutfak adisyonu (Bestellbon) yazdırma use case'i.
///
/// [KitchenTicketBuilder] ile ESC/POS byte dizisi üretir ve [PrinterService]
/// aracılığıyla yazıcıya gönderir.
///
/// Riverpod kullanımı:
/// ```dart
/// final useCase = ref.read(printKitchenTicketUseCaseProvider);
/// final ok = await useCase(data);
/// ```
///
/// Çoklu yazıcı grubuna gönderim (mutfak + bar gibi) için her grup için
/// ayrı bir [KitchenTicketData] oluşturulmalı ve ayrı yazıcılara gönderilmelidir:
/// ```dart
/// final hotItems = items.where((i) => i.printerGroup == 'Kueche').toList();
/// final barItems = items.where((i) => i.printerGroup == 'Bar').toList();
///
/// if (hotItems.isNotEmpty) {
///   await useCase(KitchenTicketData(
///     tableNo: tableNo,
///     orderNo: orderNo,
///     printerGroup: 'Kueche',
///     items: hotItems,
///     dateTime: DateTime.now(),
///   ));
/// }
/// ```
class PrintKitchenTicketUseCase {
  const PrintKitchenTicketUseCase(this._service);

  final PrinterService _service;

  /// [data]'dan ESC/POS adisyon üretir ve yazıcıya gönderir.
  /// Başarılı ise `true`, yazıcı hatası varsa `false` döner.
  Future<bool> call(KitchenTicketData data) async {
    final bytes = build(data);
    return _service.printBytes(bytes);
  }

  /// Yalnızca byte dizisi üretir (test / önizleme için).
  Uint8List build(KitchenTicketData data) =>
      KitchenTicketBuilder(data: data).build();
}
