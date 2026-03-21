import 'dart:io';

import 'package:flutter/services.dart';

import '../printer_device.dart';
import '../printer_connection_type.dart';
import '../printer_provider_interface.dart';

/// Android Bluetooth (RFCOMM SPP) yazıcı provider'ı.
///
/// Kotlin tarafında [PrinterPlugin.kt] → `connectBluetoothPrinter` metodunu çağırır.
/// SPP UUID: 00001101-0000-1000-8000-00805F9B34FB
class BluetoothPrinterProvider implements PrinterProviderInterface {
  static const _channel = MethodChannel('com.gastrocore.gastrocore_pos/printer');

  PrinterDevice? _device;

  // ---------------------------------------------------------------------------
  // PrinterProviderInterface
  // ---------------------------------------------------------------------------

  @override
  bool get isConnected => _device != null;

  @override
  PrinterDevice? get connectedDevice => _device;

  /// Android BluetoothAdapter'dan eşleşmiş cihazları listeler.
  @override
  Future<List<PrinterDevice>> discoverDevices() async {
    if (!Platform.isAndroid) return [];
    try {
      final result =
          await _channel.invokeMethod<List>('getBluetoothPrinters');
      if (result == null) return [];
      return result.map((d) {
        final map = Map<String, dynamic>.from(d as Map);
        return PrinterDevice(
          name: map['name'] as String? ?? 'BT Yazici',
          address: map['address'] as String? ?? '',
          connectionType: PrinterConnectionType.bluetooth,
        );
      }).toList();
    } on PlatformException {
      return [];
    }
  }

  /// [device.address] → MAC adresi ("AA:BB:CC:DD:EE:FF")
  @override
  Future<bool> connect(PrinterDevice device) async {
    assert(device.connectionType == PrinterConnectionType.bluetooth);
    if (!Platform.isAndroid) return false;

    try {
      final ok = await _channel.invokeMethod<bool>(
        'connectBluetoothPrinter',
        {'address': device.address},
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
      // Yoksay
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
