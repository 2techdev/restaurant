import 'dart:typed_data';

import '../escpos/swiss_receipt_builder.dart';
import '../models/print_models.dart';
import '../printer_service.dart';

/// Satış fişi (Verkaufsbeleg) yazdırma use case'i.
///
/// [SwissReceiptBuilder] ile ESC/POS byte dizisi üretir ve [PrinterService]
/// aracılığıyla yazıcıya gönderir.
///
/// Riverpod kullanımı:
/// ```dart
/// final useCase = ref.read(printReceiptUseCaseProvider);
/// final ok = await useCase(data);
/// ```
///
/// Domain entity'lerinden veri modeli oluşturma:
/// ```dart
/// final data = SwissReceiptData(
///   restaurantName: config.name,
///   mwstNr: config.mwstNr,
///   receiptNo: bill.billNumber,
///   items: ticket.items.map((item) {
///     final net = item.subtotal - item.taxAmount;
///     final rate = net > 0 ? item.taxAmount / net * 100 : 0.0;
///     return SwissReceiptItem(
///       name: item.productName,
///       quantity: item.quantity,
///       unitPrice: item.unitPrice,
///       totalPrice: item.subtotal - item.discountAmount,
///       mwstCode: MwStCode.fromRate(rate),
///       modifiers: item.modifiers.map((m) => m.modifierName).toList(),
///       discountAmount: item.discountAmount,
///       notes: item.notes,
///     );
///   }).toList(),
///   total: bill.total,
///   subtotal: bill.subtotal,
///   discountAmount: bill.discountAmount,
///   mwstBreakdown: _buildMwStBreakdown(ticket.items),
///   payments: bill.payments.map((p) => SwissPaymentLine(
///     method: _methodLabel(p),
///     amount: p.amount,
///   )).toList(),
///   openDrawer: true,
/// );
/// ```
class PrintReceiptUseCase {
  const PrintReceiptUseCase(this._service);

  final PrinterService _service;

  /// [data]'dan ESC/POS fişi üretir ve yazıcıya gönderir.
  /// Başarılı ise `true`, yazıcı hatası varsa `false` döner.
  Future<bool> call(SwissReceiptData data) async {
    final bytes = build(data);
    return _service.printBytes(bytes);
  }

  /// Yalnızca byte dizisi üretir (test / önizleme için).
  Uint8List build(SwissReceiptData data) =>
      SwissReceiptBuilder(data: data).build();
}
