import 'dart:async';
import 'dart:io';

import '../printer_device.dart';
import '../printer_connection_type.dart';
import '../printer_provider_interface.dart';

/// WiFi (TCP Socket, varsayılan port 9100) yazıcı provider'ı.
///
/// Kullanım:
/// ```dart
/// final provider = WiFiPrinterProvider();
/// await provider.connect(PrinterDevice(
///   name: 'Epson TM-T88',
///   address: '192.168.1.100:9100',
///   connectionType: PrinterConnectionType.wifi,
/// ));
/// await provider.sendBytes(bytes);
/// ```
class WiFiPrinterProvider implements PrinterProviderInterface {
  WiFiPrinterProvider({
    this.connectTimeout = const Duration(seconds: 5),
    this.sendTimeout = const Duration(seconds: 10),
  });

  final Duration connectTimeout;
  final Duration sendTimeout;

  Socket? _socket;
  PrinterDevice? _device;

  // ---------------------------------------------------------------------------
  // PrinterProviderInterface
  // ---------------------------------------------------------------------------

  @override
  bool get isConnected => _socket != null && _device != null;

  @override
  PrinterDevice? get connectedDevice => _device;

  /// WiFi yazıcılar elle IP:port girildiğinden keşif listesi boş döner.
  @override
  Future<List<PrinterDevice>> discoverDevices() async => [];

  /// [device.address] formatı: "192.168.1.100" veya "192.168.1.100:9100"
  @override
  Future<bool> connect(PrinterDevice device) async {
    assert(device.connectionType == PrinterConnectionType.wifi);

    await disconnect();

    final (ip, port) = _parseAddress(device.address);

    try {
      _socket = await Socket.connect(ip, port, timeout: connectTimeout);
      _device = device;
      return true;
    } on SocketException catch (_) {
      _socket = null;
      _device = null;
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;
    _device = null;
  }

  @override
  Future<bool> sendBytes(List<int> bytes) async {
    final socket = _socket;
    if (socket == null) return false;

    try {
      socket.add(bytes);
      await socket.flush().timeout(sendTimeout);
      return true;
    } catch (_) {
      // Soket kapanmışsa bağlantıyı temizle
      await disconnect();
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  (String ip, int port) _parseAddress(String address) {
    final parts = address.split(':');
    if (parts.length == 2) {
      final port = int.tryParse(parts[1]) ?? 9100;
      return (parts[0].trim(), port);
    }
    return (address.trim(), 9100);
  }
}
