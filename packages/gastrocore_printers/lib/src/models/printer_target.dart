/// Which role this printer plays inside a store.
library;

enum PrinterTarget {
  /// Kitchen printer — hot food line. Backup for KDS (KDS is authoritative).
  kitchen,

  /// Bar printer — drinks station.
  bar,

  /// Receipt printer — at POS / cashier, prints customer fiş on payment.
  receipt;

  String get wire {
    switch (this) {
      case PrinterTarget.kitchen:
        return 'kitchen';
      case PrinterTarget.bar:
        return 'bar';
      case PrinterTarget.receipt:
        return 'receipt';
    }
  }

  static PrinterTarget fromWire(String value) {
    switch (value) {
      case 'kitchen':
        return PrinterTarget.kitchen;
      case 'bar':
        return PrinterTarget.bar;
      case 'receipt':
        return PrinterTarget.receipt;
      default:
        throw ArgumentError('Unknown PrinterTarget: $value');
    }
  }
}

/// Physical transport to the printer.
enum PrinterConnectionType {
  /// TCP/IP over ethernet (recommended for pilot).
  ethernet,

  /// Direct USB — requires platform plugin, not wired for pilot.
  usb;

  String get wire => this == PrinterConnectionType.ethernet ? 'ethernet' : 'usb';

  static PrinterConnectionType fromWire(String value) {
    switch (value) {
      case 'ethernet':
        return PrinterConnectionType.ethernet;
      case 'usb':
        return PrinterConnectionType.usb;
      default:
        throw ArgumentError('Unknown PrinterConnectionType: $value');
    }
  }
}

/// Thermal paper width. 80mm is the fine-dining default.
enum PrinterPaperWidth {
  mm58,
  mm80;

  String get wire => this == PrinterPaperWidth.mm58 ? '58mm' : '80mm';

  static PrinterPaperWidth fromWire(String value) {
    switch (value) {
      case '58mm':
        return PrinterPaperWidth.mm58;
      case '80mm':
        return PrinterPaperWidth.mm80;
      default:
        return PrinterPaperWidth.mm80;
    }
  }
}
