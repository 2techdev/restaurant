/// Yazıcı bağlantı türleri
enum PrinterConnectionType {
  /// TCP Socket üzerinden WiFi bağlantısı (port 9100)
  wifi,

  /// Android USB Manager — bulk transfer
  usb,

  /// RFCOMM SPP üzerinden Bluetooth
  bluetooth;

  String get label {
    switch (this) {
      case PrinterConnectionType.wifi:
        return 'WiFi';
      case PrinterConnectionType.usb:
        return 'USB';
      case PrinterConnectionType.bluetooth:
        return 'Bluetooth';
    }
  }
}
