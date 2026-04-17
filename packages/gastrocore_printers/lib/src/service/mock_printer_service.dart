/// In-memory [PrinterService] for tests and simulation mode.
///
/// All "prints" append to [printHistory]; templates still render real
/// ESC/POS bytes so tests can assert on the output.
library;

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

import '../models/kitchen_ticket_data.dart';
import '../models/printer_config.dart';
import '../models/printer_status.dart';
import '../models/printer_target.dart';
import '../models/receipt_data.dart';
import '../templates/kitchen_ticket_template.dart';
import '../templates/receipt_template.dart';
import 'printer_service.dart';

/// A single captured print job — templates emit real ESC/POS bytes, which
/// tests can decode to assert against (e.g. "receipt contains 'TOTAL CHF'").
class CapturedPrint {
  final PrinterTarget target;
  final PrinterConfig config;
  final List<int> bytes;
  final DateTime at;
  final String kind; // "kitchen" / "receipt" / "test"

  const CapturedPrint({
    required this.target,
    required this.config,
    required this.bytes,
    required this.at,
    required this.kind,
  });

  /// Decoded ASCII — drops ESC/POS control bytes so tests can grep for
  /// human-readable substrings ("Entrecôte", "TOTAL CHF").
  String get asciiText {
    final printable = bytes
        .where((b) => (b >= 0x20 && b < 0x7f) || b == 0x0a)
        .map((b) => String.fromCharCode(b))
        .join();
    return printable;
  }
}

class MockPrinterService implements PrinterService {
  List<PrinterConfig> _configs;

  final CapabilityProfile _profile;

  /// Set true to simulate every primary printer being offline (useful for
  /// testing backup fallback).
  bool failPrimary;

  /// Set true to fail the backup too.
  bool failBackup;

  final List<CapturedPrint> printHistory = [];

  MockPrinterService._({
    required List<PrinterConfig> configs,
    required CapabilityProfile profile,
    required this.failPrimary,
    required this.failBackup,
  })  : _configs = List.unmodifiable(configs),
        _profile = profile;

  /// Async factory — mirrors [EscPosPrinterService.create] so swapping the
  /// implementation in tests is a one-line change.
  static Future<MockPrinterService> create({
    List<PrinterConfig> configs = const [],
    bool failPrimary = false,
    bool failBackup = false,
  }) async {
    final profile = await CapabilityProfile.load();
    return MockPrinterService._(
      configs: configs,
      profile: profile,
      failPrimary: failPrimary,
      failBackup: failBackup,
    );
  }

  @override
  void updateConfigs(List<PrinterConfig> configs) {
    _configs = List.unmodifiable(configs);
  }

  @override
  Future<PrintOutcome> printKitchenTicket(
    KitchenTicketData ticket, {
    required PrinterTarget target,
  }) async {
    final primary = _pick(target, backup: false);
    final backup = _pick(target, backup: true);
    return _sendWithFallback(
      primary: primary,
      backup: backup,
      buildBytes: (c) => KitchenTicketTemplate(c, _profile).build(ticket),
      kind: 'kitchen',
    );
  }

  @override
  Future<PrintOutcome> printReceipt(ReceiptData receipt) async {
    final primary = _pick(PrinterTarget.receipt, backup: false);
    final backup = _pick(PrinterTarget.receipt, backup: true);
    return _sendWithFallback(
      primary: primary,
      backup: backup,
      buildBytes: (c) => ReceiptTemplate(c, _profile).build(receipt),
      kind: 'receipt',
    );
  }

  @override
  Future<PrintOutcome> testPrint(PrinterConfig config) async {
    final bytes = [0x1b, 0x40]; // ESC @ (init)
    final captured = CapturedPrint(
      target: config.target,
      config: config,
      bytes: bytes,
      at: DateTime.now(),
      kind: 'test',
    );
    printHistory.add(captured);
    return PrintOutcome(
      success: true,
      configId: config.id,
      target: config.target,
      bytesWritten: bytes.length,
    );
  }

  @override
  Future<List<PrinterStatus>> statusAll() async {
    return _configs
        .map((c) => PrinterStatus(
              configId: c.id,
              target: c.target,
              health: c.enabled
                  ? (failPrimary && !c.isBackup
                      ? PrinterHealth.offline
                      : PrinterHealth.online)
                  : PrinterHealth.offline,
              lastSeenAt: DateTime.now(),
            ))
        .toList();
  }

  @override
  Future<void> dispose() async {}

  // ── Internals ────────────────────────────────────────────────────────

  PrinterConfig? _pick(PrinterTarget target, {required bool backup}) {
    for (final c in _configs) {
      if (c.target == target && c.enabled && c.isBackup == backup) return c;
    }
    return null;
  }

  Future<PrintOutcome> _sendWithFallback({
    required PrinterConfig? primary,
    required PrinterConfig? backup,
    required List<int> Function(PrinterConfig) buildBytes,
    required String kind,
  }) async {
    if (primary == null && backup == null) {
      return const PrintOutcome(
        success: false,
        configId: '',
        target: PrinterTarget.receipt,
        errorMessage: 'no_enabled_printer_for_target',
      );
    }

    if (primary != null && !failPrimary) {
      return _capture(primary, buildBytes(primary), kind);
    }
    if (backup != null && !failBackup) {
      return _capture(backup, buildBytes(backup), kind);
    }
    return PrintOutcome(
      success: false,
      configId: (primary ?? backup)!.id,
      target: (primary ?? backup)!.target,
      errorMessage: 'all_printers_simulated_offline',
    );
  }

  PrintOutcome _capture(PrinterConfig config, List<int> bytes, String kind) {
    printHistory.add(CapturedPrint(
      target: config.target,
      config: config,
      bytes: bytes,
      at: DateTime.now(),
      kind: kind,
    ));
    return PrintOutcome(
      success: true,
      configId: config.id,
      target: config.target,
      bytesWritten: bytes.length,
    );
  }
}
