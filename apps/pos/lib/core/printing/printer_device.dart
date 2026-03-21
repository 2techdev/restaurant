import 'printer_connection_type.dart';

/// Yazıcı cihazını temsil eden değer nesnesi.
///
/// Hem keşif listelerinde hem de kaydedilmiş yapılandırmada kullanılır.
class PrinterDevice {
  const PrinterDevice({
    required this.name,
    required this.address,
    required this.connectionType,
    this.vendorId,
    this.productId,
  });

  /// Kullanıcıya gösterilen cihaz adı.
  final String name;

  /// Bağlantı adresi:
  ///   WiFi      → "192.168.1.100:9100"
  ///   USB       → deviceId (integer string)
  ///   Bluetooth → MAC adresi ("AA:BB:CC:DD:EE:FF")
  final String address;

  final PrinterConnectionType connectionType;

  /// Yalnızca USB yazıcılar için (yeniden bağlanmada kullanılır).
  final int? vendorId;
  final int? productId;

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'name': name,
    'address': address,
    'connectionType': connectionType.name,
    'vendorId': vendorId,
    'productId': productId,
  };

  factory PrinterDevice.fromJson(Map<String, dynamic> json) => PrinterDevice(
    name: json['name'] as String,
    address: json['address'] as String,
    connectionType: PrinterConnectionType.values.firstWhere(
      (e) => e.name == json['connectionType'],
      orElse: () => PrinterConnectionType.usb,
    ),
    vendorId: json['vendorId'] as int?,
    productId: json['productId'] as int?,
  );

  // ---------------------------------------------------------------------------
  // Equality
  // ---------------------------------------------------------------------------

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PrinterDevice &&
          name == other.name &&
          address == other.address &&
          connectionType == other.connectionType;

  @override
  int get hashCode => Object.hash(name, address, connectionType);

  @override
  String toString() =>
      'PrinterDevice(name: $name, address: $address, type: ${connectionType.label})';
}
