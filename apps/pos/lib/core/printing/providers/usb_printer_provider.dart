import 'dart:io';

import 'package:flutter/services.dart';

import '../printer_device.dart';
import '../printer_connection_type.dart';
import '../printer_provider_interface.dart';

/// Android USB yazıcı provider'ı.
///
/// Android USB Manager + bulk transfer üzerinden iletişim kurar.
/// Flutter ↔ Kotlin köprüsü için [PrinterPlugin.kt] kullanılır.
///
/// Desteklenen vendor ID'ler Kotlin tarafında tanımlıdır; bu sınıf
/// yalnızca Dart katmanını oluşturur.
class UsbPrinterProvider implements PrinterProviderInterface {
  static const _channel = MethodChannel('com.gastrocore.gastrocore_pos/printer');
  static const _usbEventChannel =
      EventChannel('com.gastrocore.gastrocore_pos/printer_usb_events');

  UsbPrinterProvider() {
    if (Platform.isAndroid) {
      _listenUsbEvents();
    }
  }

  PrinterDevice? _device;

  /// USB tak/çıkar olaylarını dışarıya yayınlar.
  /// [PrinterService] bu stream'i auto-reconnect için dinler.
  late final Stream<Map<String, dynamic>> usbEvents = _usbEventChannel
      .receiveBroadcastStream()
      .where((e) => e is Map)
      .map((e) => Map<String, dynamic>.from(e as Map));

  void _listenUsbEvents() {
    // Stream sadece dışarıdan dinlenir; burada subscription açmıyoruz.
    // Lazy stream olarak sunulur, PrinterService subscribe olur.
  }

  // ---------------------------------------------------------------------------
  // PrinterProviderInterface
  // ---------------------------------------------------------------------------

  @override
  bool get isConnected => _device != null;

  @override
  PrinterDevice? get connectedDevice => _device;

  /// Android USB Manager'dan bağlı yazıcıları listeler.
  @override
  Future<List<PrinterDevice>> discoverDevices() async {
    if (!Platform.isAndroid) return [];
    try {
      final result = await _channel.invokeMethod<List>('getUsbPrinters');
      if (result == null) return [];
      return result.map((d) {
        final map = Map<String, dynamic>.from(d as Map);
        return PrinterDevice(
          name: map['name'] as String? ?? 'USB Yazici',
          address: map['deviceId']?.toString() ?? '0',
          connectionType: PrinterConnectionType.usb,
          vendorId: map['vendorId'] as int?,
          productId: map['productId'] as int?,
        );
      }).toList();
    } on PlatformException {
      return [];
    }
  }

  @override
  Future<bool> connect(PrinterDevice device) async {
    assert(device.connectionType == PrinterConnectionType.usb);
    if (!Platform.isAndroid) return false;

    try {
      final deviceId = int.tryParse(device.address) ?? 0;
      final ok = await _channel.invokeMethod<bool>(
        'connectUsbPrinter',
        {'deviceId': deviceId},
      );
      if (ok == true) {
        _device = device;
        return true;
      }
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('disconnectPrinter');
    } on PlatformException {
      // Yoksay — zaten bağlı olmayabilir
    }
    _device = null;
  }

  @override
  Future<bool> sendBytes(List<int> bytes) async {
    if (!Platform.isAndroid || _device == null) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('printBytes', {
        'data': Uint8List.fromList(bytes),
      });
      return ok == true;
    } on PlatformException {
      return false;
    }
  }
}
