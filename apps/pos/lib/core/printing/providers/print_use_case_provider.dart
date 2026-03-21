import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../printing_provider.dart';
import '../use_cases/print_receipt_use_case.dart';
import '../use_cases/print_kitchen_ticket_use_case.dart';
import '../use_cases/print_report_use_case.dart';

/// Satış fişi yazdırma use case'i.
///
/// Kullanım:
/// ```dart
/// final useCase = ref.read(printReceiptUseCaseProvider);
/// await useCase(receiptData);
/// ```
final printReceiptUseCaseProvider = Provider<PrintReceiptUseCase>((ref) {
  return PrintReceiptUseCase(ref.watch(printerServiceProvider));
});

/// Mutfak adisyonu yazdırma use case'i.
///
/// Kullanım:
/// ```dart
/// final useCase = ref.read(printKitchenTicketUseCaseProvider);
/// await useCase(ticketData);
/// ```
final printKitchenTicketUseCaseProvider =
    Provider<PrintKitchenTicketUseCase>((ref) {
  return PrintKitchenTicketUseCase(ref.watch(printerServiceProvider));
});

/// Z/X Raporu yazdırma use case'i.
///
/// Kullanım:
/// ```dart
/// final useCase = ref.read(printReportUseCaseProvider);
/// await useCase.printZReport(reportData);
/// await useCase.printXReport(reportData);
/// ```
final printReportUseCaseProvider = Provider<PrintReportUseCase>((ref) {
  return PrintReportUseCase(ref.watch(printerServiceProvider));
});
