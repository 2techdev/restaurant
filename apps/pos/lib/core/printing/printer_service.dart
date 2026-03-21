import 'dart:async';

import 'escpos/esc_pos_builder.dart';
import 'printer_connection_type.dart';
import 'printer_device.dart';
import 'printer_provider_interface.dart';
import 'providers/bluetooth_printer_provider.dart';
import 'providers/usb_printer_provider.dart';
import 'providers/wifi_printer_provider.dart';

/// Yazıcı servisinin anlık durumu.
class PrinterStatus {
  const PrinterStatus({
    required this.isConnected,
    this.device,
    this.connectionType,
  });

  final bool isConnected;
  final PrinterDevice? device;
  final PrinterConnectionType? connectionType;

  @override
  String toString() =>
      'PrinterStatus(connected=$isConnected, type=${connectionType?.label}, '
      'device=${device?.name})';
}

/// GastroCore POS ana yazıcı servisi.
///
/// * Tek bir aktif bağlantı yönetir (WiFi, USB veya Bluetooth).
/// * Mutex ile eşzamanlı yazdırma çakışmasını önler.
/// * USB tak/çıkar olaylarını dinleyerek otomatik yeniden bağlanır.
/// * [statusStream] ile UI bileşenleri durumu reaktif olarak takip eder.
///
/// Kullanım:
/// ```dart
/// final service = PrinterService();
///
/// // WiFi bağlantısı
/// await service.connectWifi('192.168.1.100');
///
/// // Fiş yazdır
/// await service.printBytes(receiptBytes);
///
/// // Kasa çekmecesi aç
/// await service.openCashDrawer();
/// ```
class PrinterService {
  PrinterService({
    WiFiPrinterProvider? wifiProvider,
    UsbPrinterProvider? usbProvider,
    BluetoothPrinterProvider? bluetoothProvider,
  })  : _wifi = wifiProvider ?? WiFiPrinterProvider(),
        _usb = usbProvider ?? UsbPrinterProvider(),
        _bt = bluetoothProvider ?? BluetoothPrinterProvider() {
    _setupUsbAutoReconnect();
  }

  final WiFiPrinterProvider _wifi;
  final UsbPrinterProvider _usb;
  final BluetoothPrinterProvider _bt;

  PrinterProviderInterface? _active; // Şu an bağlı provider

  // Auto-reconnect için son bağlı USB cihaz bilgisi
  PrinterDevice? _lastUsbDevice;
  StreamSubscription<Map<String, dynamic>>? _usbEventSub;

  // Mutex — eşzamanlı yazdırma isteklerini sıraya alır
  Completer<void>? _printLock;

  // Status stream
  final _statusController =
      StreamController<PrinterStatus>.broadcast(sync: true);

  /// Bağlantı durumu değişimlerini dinleyin.
  Stream<PrinterStatus> get statusStream => _statusController.stream;

  // ---------------------------------------------------------------------------
  // Durum
  // ---------------------------------------------------------------------------

  bool get isConnected => _active?.isConnected ?? false;

  PrinterDevice? get connectedDevice => _active?.connectedDevice;

  PrinterConnectionType? get connectionType {
    final d = connectedDevice;
    return d?.connectionType;
  }

  PrinterStatus get status => PrinterStatus(
        isConnected: isConnected,
        device: connectedDevice,
        connectionType: connectionType,
      );

  // ---------------------------------------------------------------------------
  // Keşif
  // ---------------------------------------------------------------------------

  /// Bağlı USB yazıcıları listeler.
  Future<List<PrinterDevice>> discoverUsbPrinters() =>
      _usb.discoverDevices();

  /// Eşleşmiş Bluetooth yazıcıları listeler.
  Future<List<PrinterDevice>> discoverBluetoothPrinters() =>
      _bt.discoverDevices();

  // ---------------------------------------------------------------------------
  // Bağlantı
  // ---------------------------------------------------------------------------

  /// WiFi (TCP Socket) ile bağlan.
  ///
  /// [address] → "192.168.1.100" veya "192.168.1.100:9100"
  Future<bool> connectWifi(String address, {String name = 'WiFi Yazici'}) {
    final device = PrinterDevice(
      name: name,
      address: address,
      connectionType: PrinterConnectionType.wifi,
    );
    return _connectWith(_wifi, device);
  }

  /// USB cihaza bağlan.
  Future<bool> connectUsb(PrinterDevice device) =>
      _connectWith(_usb, device);

  /// Bluetooth cihaza bağlan.
  Future<bool> connectBluetooth(PrinterDevice device) =>
      _connectWith(_bt, device);

  Future<bool> _connectWith(
    PrinterProviderInterface provider,
    PrinterDevice device,
  ) async {
    await disconnect();
    final ok = await provider.connect(device);
    if (ok) {
      _active = provider;
      if (device.connectionType == PrinterConnectionType.usb) {
        _lastUsbDevice = device;
      }
      _emitStatus();
    }
    return ok;
  }

  /// Mevcut bağlantıyı kes.
  Future<void> disconnect() async {
    if (_active == null) return;
    await _active?.disconnect();
    _active = null;
    _emitStatus();
  }

  // ---------------------------------------------------------------------------
  // Yazdırma
  // ---------------------------------------------------------------------------

  /// Ham ESC/POS byte'larını yazdır (mutex korumalı).
  Future<bool> printBytes(List<int> bytes) async {
    if (!isConnected) return false;

    // Önceki yazdırma işlemi bitene kadar bekle
    while (_printLock != null) {
      try {
        await _printLock!.future;
      } catch (_) {}
    }
    _printLock = Completer<void>();

    try {
      return await _active!.sendBytes(bytes);
    } finally {
      _printLock!.complete();
      _printLock = null;
    }
  }

  /// Basit metin yazdır (ESC/POS initialize + text + feed + cut).
  Future<bool> printText(String text) {
    final bytes = EscPosBuilder()
        .initialize()
        .alignLeft()
        .textLine(text)
        .feed(3)
        .cut()
        .build();
    return printBytes(bytes);
  }

  /// Kasa çekmecesini aç.
  Future<bool> openCashDrawer() {
    final bytes = EscPosBuilder().openCashDrawer().build();
    return printBytes(bytes);
  }

  // ---------------------------------------------------------------------------
  // USB Auto-reconnect
  // ---------------------------------------------------------------------------

  void _setupUsbAutoReconnect() {
    _usbEventSub = _usb.usbEvents.listen((event) {
      final action = event['action'] as String?;
      final vendorId = event['vendorId'] as int?;

      if (action == 'USB_DEVICE_DETACHED') {
        _handleUsbDetached(vendorId);
      } else if (action == 'USB_DEVICE_ATTACHED') {
        _handleUsbAttached(vendorId);
      }
    });
  }

  void _handleUsbDetached(int? vendorId) {
    if (_active == _usb && isConnected) {
      _active = null;
      _emitStatus();
    }
  }

  void _handleUsbAttached(int? vendorId) {
    final last = _lastUsbDevice;
    if (last == null) return;

    // Aynı vendor ID mi?
    if (vendorId != null && last.vendorId != null && vendorId != last.vendorId) {
      return;
    }

    // 1.5 sn bekle, cihaz hazır olsun
    Future.delayed(const Duration(milliseconds: 1500), () async {
      final printers = await _usb.discoverDevices();
      if (printers.isEmpty) return;

      final target = printers.firstWhere(
        (p) => p.vendorId == last.vendorId,
        orElse: () => printers.first,
      );
      await connectUsb(target);
    });
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  Future<void> dispose() async {
    await _usbEventSub?.cancel();
    await disconnect();
    await _statusController.close();
  }

  // ---------------------------------------------------------------------------
  // Private
  // ---------------------------------------------------------------------------

  void _emitStatus() {
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }
}
