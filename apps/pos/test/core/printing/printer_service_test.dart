import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gastrocore_pos/core/printing/printer_connection_type.dart';
import 'package:gastrocore_pos/core/printing/printer_device.dart';
import 'package:gastrocore_pos/core/printing/printer_provider_interface.dart';
import 'package:gastrocore_pos/core/printing/printer_service.dart';
import 'package:gastrocore_pos/core/printing/providers/bluetooth_printer_provider.dart';
import 'package:gastrocore_pos/core/printing/providers/usb_printer_provider.dart';
import 'package:gastrocore_pos/core/printing/providers/wifi_printer_provider.dart';

// ---------------------------------------------------------------------------
// Fake providers for testing (no real hardware / Android needed)
// ---------------------------------------------------------------------------

class _FakeProvider implements PrinterProviderInterface {
  bool _connected = false;
  List<int>? lastSentBytes;
  bool failOnConnect = false;
  bool failOnSend = false;

  final PrinterConnectionType type;
  _FakeProvider(this.type);

  @override
  bool get isConnected => _connected;

  @override
  PrinterDevice? get connectedDevice => _connected
      ? PrinterDevice(name: 'Fake', address: 'fake', connectionType: type)
      : null;

  @override
  Future<List<PrinterDevice>> discoverDevices() async => [
        PrinterDevice(
          name: 'Fake Printer',
          address: 'fake-address',
          connectionType: type,
          vendorId: type == PrinterConnectionType.usb ? 0x04B8 : null,
        ),
      ];

  @override
  Future<bool> connect(PrinterDevice device) async {
    if (failOnConnect) return false;
    _connected = true;
    return true;
  }

  @override
  Future<void> disconnect() async => _connected = false;

  @override
  Future<bool> sendBytes(List<int> bytes) async {
    if (!_connected || failOnSend) return false;
    lastSentBytes = bytes;
    return true;
  }
}

/// Stub subclass van UsbPrinterProvider met een lege event stream.
class _StubUsbProvider extends UsbPrinterProvider {
  @override
  Stream<Map<String, dynamic>> get usbEvents => const Stream.empty();
}

/// PrinterService met fake providers.
PrinterService _makeService({
  _FakeProvider? wifi,
  _FakeProvider? usb,
  _FakeProvider? bt,
}) {
  final w = wifi ?? _FakeProvider(PrinterConnectionType.wifi);
  final u = usb ?? _FakeProvider(PrinterConnectionType.usb);
  final b = bt ?? _FakeProvider(PrinterConnectionType.bluetooth);

  // We build PrinterService but replace the internal providers by using
  // the package-private constructor approach via subclassing is not possible,
  // so we test the public API surface with WiFiPrinterProvider (real).
  // For USB/BT tests we use WiFi provider behaviour as a proxy.
  //
  // NOTE: PrinterService accepts optional constructors for injection:
  return _TestPrinterService(
    wifiProvider: w,
    usbProvider: u,
    btProvider: b,
  );
}

/// Testable subclass that accepts fake providers directly.
class _TestPrinterService extends PrinterService {
  _TestPrinterService({
    required _FakeProvider wifiProvider,
    required _FakeProvider usbProvider,
    required _FakeProvider btProvider,
  }) : super(
          wifiProvider: _WiFiAdapter(wifiProvider),
          usbProvider: _UsbAdapter(usbProvider),
          bluetoothProvider: _BtAdapter(btProvider),
        );
}

/// Adapters that bridge _FakeProvider → concrete provider types.
/// WiFiPrinterProvider is final so we subclass with override trick.
class _WiFiAdapter extends WiFiPrinterProvider {
  final _FakeProvider _fake;
  _WiFiAdapter(this._fake);

  @override
  bool get isConnected => _fake.isConnected;
  @override
  PrinterDevice? get connectedDevice => _fake.connectedDevice;
  @override
  Future<List<PrinterDevice>> discoverDevices() => _fake.discoverDevices();
  @override
  Future<bool> connect(PrinterDevice device) => _fake.connect(device);
  @override
  Future<void> disconnect() => _fake.disconnect();
  @override
  Future<bool> sendBytes(List<int> bytes) => _fake.sendBytes(bytes);
}

class _UsbAdapter extends _StubUsbProvider {
  final _FakeProvider _fake;
  _UsbAdapter(this._fake);

  @override
  bool get isConnected => _fake.isConnected;
  @override
  PrinterDevice? get connectedDevice => _fake.connectedDevice;
  @override
  Future<List<PrinterDevice>> discoverDevices() => _fake.discoverDevices();
  @override
  Future<bool> connect(PrinterDevice device) => _fake.connect(device);
  @override
  Future<void> disconnect() => _fake.disconnect();
  @override
  Future<bool> sendBytes(List<int> bytes) => _fake.sendBytes(bytes);
}

class _BtAdapter extends BluetoothPrinterProvider {
  final _FakeProvider _fake;
  _BtAdapter(this._fake);

  @override
  bool get isConnected => _fake.isConnected;
  @override
  PrinterDevice? get connectedDevice => _fake.connectedDevice;
  @override
  Future<List<PrinterDevice>> discoverDevices() => _fake.discoverDevices();
  @override
  Future<bool> connect(PrinterDevice device) => _fake.connect(device);
  @override
  Future<void> disconnect() => _fake.disconnect();
  @override
  Future<bool> sendBytes(List<int> bytes) => _fake.sendBytes(bytes);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('PrinterService', () {
    // -------------------------------------------------------------------------
    // Initial state
    // -------------------------------------------------------------------------

    test('starts disconnected', () {
      final svc = _makeService();
      expect(svc.isConnected, isFalse);
      expect(svc.connectedDevice, isNull);
      expect(svc.connectionType, isNull);
    });

    // -------------------------------------------------------------------------
    // WiFi connect / disconnect
    // -------------------------------------------------------------------------

    test('connectWifi sets isConnected', () async {
      final wifi = _FakeProvider(PrinterConnectionType.wifi);
      final svc = _makeService(wifi: wifi);

      final ok = await svc.connectWifi('192.168.1.100');
      expect(ok, isTrue);
      expect(svc.isConnected, isTrue);
      expect(svc.connectionType, PrinterConnectionType.wifi);
    });

    test('disconnect clears state', () async {
      final svc = _makeService();
      await svc.connectWifi('192.168.1.100');
      await svc.disconnect();

      expect(svc.isConnected, isFalse);
      expect(svc.connectedDevice, isNull);
    });

    test('connect replaces previous connection', () async {
      final wifi = _FakeProvider(PrinterConnectionType.wifi);
      final bt = _FakeProvider(PrinterConnectionType.bluetooth);
      final svc = _makeService(wifi: wifi, bt: bt);

      await svc.connectWifi('192.168.1.100');
      expect(wifi.isConnected, isTrue);

      final btDevice = PrinterDevice(
        name: 'BT',
        address: 'AA:BB:CC:DD:EE:FF',
        connectionType: PrinterConnectionType.bluetooth,
      );
      await svc.connectBluetooth(btDevice);

      // Eski WiFi bağlantısı kesilmiş olmalı
      expect(wifi.isConnected, isFalse);
      expect(bt.isConnected, isTrue);
      expect(svc.connectionType, PrinterConnectionType.bluetooth);
    });

    // -------------------------------------------------------------------------
    // Failed connect
    // -------------------------------------------------------------------------

    test('returns false when provider fails to connect', () async {
      final wifi = _FakeProvider(PrinterConnectionType.wifi)..failOnConnect = true;
      final svc = _makeService(wifi: wifi);

      final ok = await svc.connectWifi('192.168.1.100');
      expect(ok, isFalse);
      expect(svc.isConnected, isFalse);
    });

    // -------------------------------------------------------------------------
    // printBytes
    // -------------------------------------------------------------------------

    test('printBytes sends bytes to active provider', () async {
      final wifi = _FakeProvider(PrinterConnectionType.wifi);
      final svc = _makeService(wifi: wifi);
      await svc.connectWifi('192.168.1.100');

      const testBytes = [0x1B, 0x40, 0x41];
      final ok = await svc.printBytes(testBytes);

      expect(ok, isTrue);
      expect(wifi.lastSentBytes, testBytes);
    });

    test('printBytes returns false when not connected', () async {
      final svc = _makeService();
      final ok = await svc.printBytes([0x01, 0x02]);
      expect(ok, isFalse);
    });

    test('printBytes returns false when send fails', () async {
      final wifi = _FakeProvider(PrinterConnectionType.wifi)..failOnSend = true;
      final svc = _makeService(wifi: wifi);
      await svc.connectWifi('192.168.1.100');

      final ok = await svc.printBytes([0x01]);
      expect(ok, isFalse);
    });

    // -------------------------------------------------------------------------
    // mutex — concurrent print calls are serialised
    // -------------------------------------------------------------------------

    test('concurrent printBytes calls are serialised', () async {
      final wifi = _FakeProvider(PrinterConnectionType.wifi);
      final svc = _makeService(wifi: wifi);
      await svc.connectWifi('192.168.1.100');

      // Aynı anda 3 yazdırma isteği gönder
      final futures = Future.wait([
        svc.printBytes([0x01]),
        svc.printBytes([0x02]),
        svc.printBytes([0x03]),
      ]);
      final results = await futures;
      expect(results, [true, true, true]);
    });

    // -------------------------------------------------------------------------
    // openCashDrawer
    // -------------------------------------------------------------------------

    test('openCashDrawer sends ESC p bytes', () async {
      final wifi = _FakeProvider(PrinterConnectionType.wifi);
      final svc = _makeService(wifi: wifi);
      await svc.connectWifi('192.168.1.100');

      final ok = await svc.openCashDrawer();
      expect(ok, isTrue);
      expect(wifi.lastSentBytes, containsAllInOrder([0x1B, 0x70, 0x00]));
    });

    // -------------------------------------------------------------------------
    // Status stream
    // -------------------------------------------------------------------------

    test('statusStream emits on connect and disconnect', () async {
      final svc = _makeService();
      final statuses = <PrinterStatus>[];
      final sub = svc.statusStream.listen(statuses.add);

      await svc.connectWifi('192.168.1.100');
      await svc.disconnect();
      await sub.cancel();

      expect(statuses.length, 2);
      expect(statuses[0].isConnected, isTrue);
      expect(statuses[1].isConnected, isFalse);
    });

    // -------------------------------------------------------------------------
    // Discovery
    // -------------------------------------------------------------------------

    test('discoverUsbPrinters returns fake device', () async {
      final usb = _FakeProvider(PrinterConnectionType.usb);
      final svc = _makeService(usb: usb);

      final devices = await svc.discoverUsbPrinters();
      expect(devices, isNotEmpty);
      expect(devices.first.connectionType, PrinterConnectionType.usb);
    });

    test('discoverBluetoothPrinters returns fake device', () async {
      final bt = _FakeProvider(PrinterConnectionType.bluetooth);
      final svc = _makeService(bt: bt);

      final devices = await svc.discoverBluetoothPrinters();
      expect(devices, isNotEmpty);
      expect(devices.first.connectionType, PrinterConnectionType.bluetooth);
    });

    // -------------------------------------------------------------------------
    // dispose
    // -------------------------------------------------------------------------

    test('dispose disconnects and closes stream', () async {
      final svc = _makeService();
      await svc.connectWifi('192.168.1.100');
      await svc.dispose();

      expect(svc.isConnected, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // PrinterDevice
  // ---------------------------------------------------------------------------

  group('PrinterDevice', () {
    test('toJson / fromJson round-trip', () {
      const device = PrinterDevice(
        name: 'Epson TM-T88',
        address: '192.168.1.5:9100',
        connectionType: PrinterConnectionType.wifi,
      );
      final json = device.toJson();
      final restored = PrinterDevice.fromJson(json);
      expect(restored, device);
    });

    test('equality is based on name, address, connectionType', () {
      const a = PrinterDevice(
        name: 'X',
        address: 'addr',
        connectionType: PrinterConnectionType.usb,
        vendorId: 0x04B8,
      );
      const b = PrinterDevice(
        name: 'X',
        address: 'addr',
        connectionType: PrinterConnectionType.usb,
        vendorId: 999, // farklı vendorId — equality'i etkilememeli
      );
      expect(a, b);
    });
  });

  // ---------------------------------------------------------------------------
  // PrinterConnectionType
  // ---------------------------------------------------------------------------

  group('PrinterConnectionType', () {
    test('labels are correct', () {
      expect(PrinterConnectionType.wifi.label, 'WiFi');
      expect(PrinterConnectionType.usb.label, 'USB');
      expect(PrinterConnectionType.bluetooth.label, 'Bluetooth');
    });
  });
}
