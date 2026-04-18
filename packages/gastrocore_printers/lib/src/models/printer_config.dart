/// Per-store printer configuration.
library;

import 'printer_target.dart';

/// Static config for a single printer. Persisted in backoffice, fetched at
/// POS startup.
class PrinterConfig {
  final String id;
  final String storeId;
  final PrinterTarget target;
  final String name;
  final PrinterConnectionType type;

  /// IPv4 for ethernet printers. Empty for USB.
  final String ip;

  /// TCP port — ESC/POS network printers use 9100 by default.
  final int port;

  /// USB device path or vendor:product id. Empty for ethernet.
  final String usbPath;

  final PrinterPaperWidth paperWidth;

  /// If false, the service skips this printer (consumer gets a no-op).
  final bool enabled;

  /// If the primary printer for this target fails, the service tries the
  /// backup. Only one backup per target is honoured.
  final bool isBackup;

  /// Optional logo bytes (PNG) to print at the top of receipts. Null on
  /// kitchen/bar targets.
  final List<int>? logoPng;

  const PrinterConfig({
    required this.id,
    required this.storeId,
    required this.target,
    required this.name,
    this.type = PrinterConnectionType.ethernet,
    this.ip = '',
    this.port = 9100,
    this.usbPath = '',
    this.paperWidth = PrinterPaperWidth.mm80,
    this.enabled = true,
    this.isBackup = false,
    this.logoPng,
  });

  factory PrinterConfig.fromJson(Map<String, dynamic> json) => PrinterConfig(
        id: json['id'] as String,
        storeId: json['store_id'] as String,
        target: PrinterTarget.fromWire(json['target'] as String),
        name: json['name'] as String,
        type: PrinterConnectionType.fromWire(
            json['type'] as String? ?? 'ethernet'),
        ip: json['ip'] as String? ?? '',
        port: (json['port'] as num?)?.toInt() ?? 9100,
        usbPath: json['usb_path'] as String? ?? '',
        paperWidth: PrinterPaperWidth.fromWire(
            json['paper_width'] as String? ?? '80mm'),
        enabled: json['enabled'] as bool? ?? true,
        isBackup: json['is_backup'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'store_id': storeId,
        'target': target.wire,
        'name': name,
        'type': type.wire,
        'ip': ip,
        'port': port,
        'usb_path': usbPath,
        'paper_width': paperWidth.wire,
        'enabled': enabled,
        'is_backup': isBackup,
      };

  PrinterConfig copyWith({
    String? id,
    String? storeId,
    PrinterTarget? target,
    String? name,
    PrinterConnectionType? type,
    String? ip,
    int? port,
    String? usbPath,
    PrinterPaperWidth? paperWidth,
    bool? enabled,
    bool? isBackup,
    List<int>? logoPng,
  }) =>
      PrinterConfig(
        id: id ?? this.id,
        storeId: storeId ?? this.storeId,
        target: target ?? this.target,
        name: name ?? this.name,
        type: type ?? this.type,
        ip: ip ?? this.ip,
        port: port ?? this.port,
        usbPath: usbPath ?? this.usbPath,
        paperWidth: paperWidth ?? this.paperWidth,
        enabled: enabled ?? this.enabled,
        isBackup: isBackup ?? this.isBackup,
        logoPng: logoPng ?? this.logoPng,
      );

  @override
  String toString() =>
      'PrinterConfig($name, $target, ${type.wire} $ip:$port, enabled=$enabled, backup=$isBackup)';
}
