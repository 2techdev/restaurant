/// Abstract façade that the POS / KDS / Waiter apps talk to.
///
/// Real implementation is [EscPosPrinterService]; tests use
/// [MockPrinterService]. Both are the only thing consumer code imports — no
/// direct calls to `esc_pos_printer_plus` from feature code.
library;

import '../models/kitchen_ticket_data.dart';
import '../models/printer_config.dart';
import '../models/printer_status.dart';
import '../models/printer_target.dart';
import '../models/receipt_data.dart';

/// Outcome of a single print job.
class PrintOutcome {
  final bool success;
  final String configId;
  final PrinterTarget target;
  final int bytesWritten;
  final String? errorMessage;
  final Duration elapsed;

  const PrintOutcome({
    required this.success,
    required this.configId,
    required this.target,
    this.bytesWritten = 0,
    this.errorMessage,
    this.elapsed = Duration.zero,
  });

  @override
  String toString() => success
      ? 'PrintOutcome(OK $target $configId, ${bytesWritten}B, ${elapsed.inMilliseconds}ms)'
      : 'PrintOutcome(FAIL $target $configId — $errorMessage)';
}

abstract class PrinterService {
  /// Send a kitchen or bar ticket. If the primary printer for [target] is
  /// unreachable and a backup is configured, the backup is tried.
  ///
  /// Returns a single [PrintOutcome] — success on primary or backup, failure
  /// if both are unreachable (or target is disabled).
  Future<PrintOutcome> printKitchenTicket(
    KitchenTicketData ticket, {
    required PrinterTarget target,
  });

  /// Print a customer receipt on the receipt printer. Same backup fallback
  /// as [printKitchenTicket].
  Future<PrintOutcome> printReceipt(ReceiptData receipt);

  /// Fire a minimal test ticket to verify the physical printer responds.
  /// Used by backoffice "Test Print" button.
  Future<PrintOutcome> testPrint(PrinterConfig config);

  /// Current connectivity health for every configured printer (ping each
  /// one with a zero-byte write or a cached last-seen).
  Future<List<PrinterStatus>> statusAll();

  /// Replace the loaded config set (after backoffice PUT).
  void updateConfigs(List<PrinterConfig> configs);

  /// Release sockets. Call on app dispose.
  Future<void> dispose();
}
