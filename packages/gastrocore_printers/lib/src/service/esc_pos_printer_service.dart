/// Real (TCP/IP) ESC/POS printer service.
///
/// One instance per app (POS, Waiter, KDS). Holds the loaded configs and
/// opens short-lived connections on every print — keeping sockets open
/// across an 8h service causes more problems than it solves (firewall
/// timeouts, half-closed TCP on printer reboot).
library;

import 'package:esc_pos_printer_plus/esc_pos_printer_plus.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

import '../models/kitchen_ticket_data.dart';
import '../models/printer_config.dart';
import '../models/printer_status.dart';
import '../models/printer_target.dart';
import '../models/receipt_data.dart';
import '../templates/common.dart';
import '../templates/kitchen_ticket_template.dart';
import '../templates/receipt_template.dart';
import 'printer_service.dart';

class EscPosPrinterService implements PrinterService {
  List<PrinterConfig> _configs;

  final CapabilityProfile _profile;

  /// Connection timeout — kitchen printers are on the same LAN, so 2s is
  /// plenty. Longer waits block the payment flow on dead printers.
  final Duration _connectTimeout;

  EscPosPrinterService._({
    required List<PrinterConfig> configs,
    required CapabilityProfile profile,
    required Duration connectTimeout,
  })  : _configs = List.unmodifiable(configs),
        _profile = profile,
        _connectTimeout = connectTimeout;

  /// Async factory — [CapabilityProfile.load] reads a bundled JSON, so it
  /// must be awaited. Consumers call this once at app startup.
  static Future<EscPosPrinterService> create({
    required List<PrinterConfig> configs,
    Duration connectTimeout = const Duration(seconds: 2),
    String profileName = 'default',
  }) async {
    final profile = await CapabilityProfile.load(name: profileName);
    return EscPosPrinterService._(
      configs: configs,
      profile: profile,
      connectTimeout: connectTimeout,
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
    );
  }

  @override
  Future<PrintOutcome> testPrint(PrinterConfig config) async {
    final generator = Generator(paperSizeFor(config.paperWidth), _profile);
    final bytes = <int>[];
    bytes.addAll(generator.text('TEST PRINT',
        styles: const PosStyles(
          align: PosAlign.center,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
          bold: true,
        )));
    bytes.addAll(generator.text(config.name,
        styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(generator.text('${config.target.wire} · ${config.ip}:${config.port}',
        styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(generator.text(DateTime.now().toIso8601String(),
        styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(generator.feed(2));
    bytes.addAll(generator.cut());
    return _sendRaw(config, bytes);
  }

  @override
  Future<List<PrinterStatus>> statusAll() async {
    final results = <PrinterStatus>[];
    for (final c in _configs) {
      if (!c.enabled) {
        results.add(PrinterStatus(
          configId: c.id,
          target: c.target,
          health: PrinterHealth.offline,
          errorMessage: 'disabled',
        ));
        continue;
      }
      results.add(await _ping(c));
    }
    return results;
  }

  @override
  Future<void> dispose() async {
    // No persistent sockets to close; short-lived connections per-print.
  }

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
  }) async {
    if (primary == null && backup == null) {
      return const PrintOutcome(
        success: false,
        configId: '',
        target: PrinterTarget.receipt,
        errorMessage: 'no_enabled_printer_for_target',
      );
    }

    if (primary != null) {
      final r = await _sendRaw(primary, buildBytes(primary));
      if (r.success) return r;
      // Primary failed — try backup if present.
      if (backup == null) return r;
    }

    return _sendRaw(backup!, buildBytes(backup));
  }

  Future<PrintOutcome> _sendRaw(PrinterConfig config, List<int> bytes) async {
    final stopwatch = Stopwatch()..start();

    if (config.type != PrinterConnectionType.ethernet) {
      return PrintOutcome(
        success: false,
        configId: config.id,
        target: config.target,
        errorMessage: 'usb_not_implemented_pilot_ethernet_only',
        elapsed: stopwatch.elapsed,
      );
    }

    try {
      final printer = NetworkPrinter(paperSizeFor(config.paperWidth), _profile);
      final res = await printer.connect(
        config.ip,
        port: config.port,
        timeout: _connectTimeout,
      );
      if (res != PosPrintResult.success) {
        return PrintOutcome(
          success: false,
          configId: config.id,
          target: config.target,
          errorMessage: res.msg,
          elapsed: stopwatch.elapsed,
        );
      }
      printer.rawBytes(bytes);
      printer.disconnect();
      return PrintOutcome(
        success: true,
        configId: config.id,
        target: config.target,
        bytesWritten: bytes.length,
        elapsed: stopwatch.elapsed,
      );
    } catch (e) {
      return PrintOutcome(
        success: false,
        configId: config.id,
        target: config.target,
        errorMessage: e.toString(),
        elapsed: stopwatch.elapsed,
      );
    }
  }

  Future<PrinterStatus> _ping(PrinterConfig config) async {
    // Cheapest non-destructive probe is a connect + immediate disconnect.
    // We do NOT write any bytes — some printers spit an empty receipt on
    // any non-zero write.
    try {
      final printer = NetworkPrinter(paperSizeFor(config.paperWidth), _profile);
      final res = await printer.connect(
        config.ip,
        port: config.port,
        timeout: _connectTimeout,
      );
      printer.disconnect();
      if (res == PosPrintResult.success) {
        return PrinterStatus(
          configId: config.id,
          target: config.target,
          health: PrinterHealth.online,
          lastSeenAt: DateTime.now(),
        );
      }
      return PrinterStatus(
        configId: config.id,
        target: config.target,
        health: PrinterHealth.offline,
        errorMessage: res.msg,
      );
    } catch (e) {
      return PrinterStatus(
        configId: config.id,
        target: config.target,
        health: PrinterHealth.error,
        errorMessage: e.toString(),
      );
    }
  }
}
