/// Printer configuration settings entity.
///
/// Covers receipt and kitchen printers with WiFi / USB / Bluetooth
/// connection types, IP addresses, ports, and auto-print preferences.
library;

import 'dart:convert';

enum PrinterConnectionType {
  wifi,
  usb,
  bluetooth;

  String get label => switch (this) {
        wifi => 'WiFi / Network',
        usb => 'USB',
        bluetooth => 'Bluetooth',
      };

  static PrinterConnectionType fromString(String s) =>
      PrinterConnectionType.values.firstWhere(
        (e) => e.name == s,
        orElse: () => PrinterConnectionType.wifi,
      );
}

/// Paper roll width (mm) for thermal receipt printers.
enum PaperWidth {
  mm58(58),
  mm80(80);

  const PaperWidth(this.mm);
  final int mm;

  String get label => '${mm}mm';

  static PaperWidth fromInt(int mm) =>
      PaperWidth.values.firstWhere(
        (e) => e.mm == mm,
        orElse: () => PaperWidth.mm80,
      );
}

class PrinterSettings {
  const PrinterSettings({
    this.connectionType = PrinterConnectionType.wifi,
    this.receiptPrinterIp = '',
    this.receiptPrinterPort = 9100,
    this.kitchenPrinterIp = '',
    this.kitchenPrinterPort = 9100,
    this.paperWidth = PaperWidth.mm80,
    this.autoPrintOnPayment = true,
    this.autoPrintKitchenTicket = true,
    this.characterSet = 'UTF-8',
  });

  final PrinterConnectionType connectionType;

  /// Receipt printer IP address (used when [connectionType] is WiFi).
  final String receiptPrinterIp;

  /// Receipt printer TCP port (default: 9100).
  final int receiptPrinterPort;

  /// Kitchen printer IP address (used when [connectionType] is WiFi).
  final String kitchenPrinterIp;

  /// Kitchen printer TCP port (default: 9100).
  final int kitchenPrinterPort;

  /// Thermal paper width for ESC/POS formatting.
  final PaperWidth paperWidth;

  /// Automatically print receipt after successful payment.
  final bool autoPrintOnPayment;

  /// Automatically send kitchen ticket when order is confirmed.
  final bool autoPrintKitchenTicket;

  /// ESC/POS character set (e.g. "UTF-8", "CP1252").
  final String characterSet;

  PrinterSettings copyWith({
    PrinterConnectionType? connectionType,
    String? receiptPrinterIp,
    int? receiptPrinterPort,
    String? kitchenPrinterIp,
    int? kitchenPrinterPort,
    PaperWidth? paperWidth,
    bool? autoPrintOnPayment,
    bool? autoPrintKitchenTicket,
    String? characterSet,
  }) {
    return PrinterSettings(
      connectionType: connectionType ?? this.connectionType,
      receiptPrinterIp: receiptPrinterIp ?? this.receiptPrinterIp,
      receiptPrinterPort: receiptPrinterPort ?? this.receiptPrinterPort,
      kitchenPrinterIp: kitchenPrinterIp ?? this.kitchenPrinterIp,
      kitchenPrinterPort: kitchenPrinterPort ?? this.kitchenPrinterPort,
      paperWidth: paperWidth ?? this.paperWidth,
      autoPrintOnPayment: autoPrintOnPayment ?? this.autoPrintOnPayment,
      autoPrintKitchenTicket:
          autoPrintKitchenTicket ?? this.autoPrintKitchenTicket,
      characterSet: characterSet ?? this.characterSet,
    );
  }

  Map<String, dynamic> toJson() => {
        'connectionType': connectionType.name,
        'receiptPrinterIp': receiptPrinterIp,
        'receiptPrinterPort': receiptPrinterPort,
        'kitchenPrinterIp': kitchenPrinterIp,
        'kitchenPrinterPort': kitchenPrinterPort,
        'paperWidth': paperWidth.mm,
        'autoPrintOnPayment': autoPrintOnPayment,
        'autoPrintKitchenTicket': autoPrintKitchenTicket,
        'characterSet': characterSet,
      };

  factory PrinterSettings.fromJson(Map<String, dynamic> json) =>
      PrinterSettings(
        connectionType: PrinterConnectionType.fromString(
          (json['connectionType'] as String?) ?? 'wifi',
        ),
        receiptPrinterIp: (json['receiptPrinterIp'] as String?) ?? '',
        receiptPrinterPort: (json['receiptPrinterPort'] as int?) ?? 9100,
        kitchenPrinterIp: (json['kitchenPrinterIp'] as String?) ?? '',
        kitchenPrinterPort: (json['kitchenPrinterPort'] as int?) ?? 9100,
        paperWidth: PaperWidth.fromInt((json['paperWidth'] as int?) ?? 80),
        autoPrintOnPayment: (json['autoPrintOnPayment'] as bool?) ?? true,
        autoPrintKitchenTicket:
            (json['autoPrintKitchenTicket'] as bool?) ?? true,
        characterSet: (json['characterSet'] as String?) ?? 'UTF-8',
      );

  String toJsonString() => jsonEncode(toJson());

  factory PrinterSettings.fromJsonString(String s) =>
      PrinterSettings.fromJson(jsonDecode(s) as Map<String, dynamic>);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PrinterSettings &&
          connectionType == other.connectionType &&
          receiptPrinterIp == other.receiptPrinterIp &&
          receiptPrinterPort == other.receiptPrinterPort &&
          kitchenPrinterIp == other.kitchenPrinterIp &&
          kitchenPrinterPort == other.kitchenPrinterPort &&
          paperWidth == other.paperWidth &&
          autoPrintOnPayment == other.autoPrintOnPayment &&
          autoPrintKitchenTicket == other.autoPrintKitchenTicket &&
          characterSet == other.characterSet;

  @override
  int get hashCode => Object.hash(
        connectionType,
        receiptPrinterIp,
        receiptPrinterPort,
        kitchenPrinterIp,
        kitchenPrinterPort,
        paperWidth,
        autoPrintOnPayment,
        autoPrintKitchenTicket,
        characterSet,
      );
}
