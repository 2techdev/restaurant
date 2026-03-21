import 'dart:typed_data';

import '../escpos/report_builder.dart';
import '../models/print_models.dart';
import '../printer_service.dart';

/// Z-Raporu ve X-Raporu yazdırma use case'i.
///
/// [ReportBuilder] ile ESC/POS byte dizisi üretir ve [PrinterService]
/// aracılığıyla yazıcıya gönderir.
///
/// Z ve X raporları aynı veri formatını ([ShiftReportData]) kullanır.
/// Fark yalnızca [ShiftReportData.reportTitle] alanında ('Z-RAPPORT' / 'X-RAPPORT')
/// ve kapanış mesajında görünür. Kasa sıfırlama işlemi bu use case'in
/// sorumluluğunda değildir; çağıran katman tarafından yönetilmelidir.
///
/// Riverpod kullanımı:
/// ```dart
/// final useCase = ref.read(printReportUseCaseProvider);
///
/// // Z-Raporu (gün sonu)
/// final ok = await useCase.printZReport(ShiftReportData(
///   reportTitle: 'Z-RAPPORT',
///   reportNo: 12,
///   shiftStart: shiftStart,
///   printedAt: DateTime.now(),
///   grossSales: 425000,
///   netSales: 412500,
///   netRevenue: 407500,
///   paymentBreakdown: {'Bar': 125000, 'Karte': 250000, 'TWINT': 32500},
///   mwstEntries: [...],
///   orderCount: 45,
/// ));
///
/// // X-Raporu (ara kontrol)
/// final ok = await useCase.printXReport(data.copyWith(
///   reportTitle: 'X-RAPPORT',
/// ));
/// ```
class PrintReportUseCase {
  const PrintReportUseCase(this._service);

  final PrinterService _service;

  /// Z-Raporu yazdır (gün sonu kapanış).
  ///
  /// [data.reportTitle] 'Z-RAPPORT' olarak ayarlanmış olmalıdır.
  Future<bool> printZReport(ShiftReportData data) async {
    assert(
      data.reportTitle.contains('Z'),
      'Z-Raporu için reportTitle "Z-RAPPORT" olmalıdır.',
    );
    final bytes = buildReport(data);
    return _service.printBytes(bytes);
  }

  /// X-Raporu yazdır (ara kontrol, kasayı sıfırlamaz).
  ///
  /// [data.reportTitle] 'X-RAPPORT' olarak ayarlanmış olmalıdır.
  Future<bool> printXReport(ShiftReportData data) async {
    assert(
      data.reportTitle.contains('X'),
      'X-Raporu için reportTitle "X-RAPPORT" olmalıdır.',
    );
    final bytes = buildReport(data);
    return _service.printBytes(bytes);
  }

  /// Yalnızca byte dizisi üretir (test / önizleme için).
  Uint8List buildReport(ShiftReportData data) =>
      ReportBuilder(data: data).build();
}
