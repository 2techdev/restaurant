import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'printer_service.dart';
import 'printer_device.dart';
import 'printer_connection_type.dart';

// ---------------------------------------------------------------------------
// PrinterService singleton
// ---------------------------------------------------------------------------

/// Uygulama genelinde tek [PrinterService] örneği.
///
/// `ProviderScope` içinde override edilmesine gerek yok — servis
/// kendi bağımlılıklarını (provider'ları) dahili olarak yönetir.
final printerServiceProvider = Provider<PrinterService>((ref) {
  final service = PrinterService();
  ref.onDispose(service.dispose);
  return service;
});

// ---------------------------------------------------------------------------
// Status
// ---------------------------------------------------------------------------

/// Yazıcı bağlantı durumunu reaktif olarak sunar.
///
/// UI'da AsyncValue olarak kullanın:
/// ```dart
/// final status = ref.watch(printerStatusProvider);
/// ```
final printerStatusProvider = StreamProvider<PrinterStatus>((ref) {
  final service = ref.watch(printerServiceProvider);
  return service.statusStream;
});

// ---------------------------------------------------------------------------
// USB device discovery
// ---------------------------------------------------------------------------

/// Bağlı USB yazıcı listesi. Sayfa açıldığında `ref.refresh` ile tetikleyin.
final usbPrinterListProvider = FutureProvider<List<PrinterDevice>>((ref) {
  return ref.read(printerServiceProvider).discoverUsbPrinters();
});

// ---------------------------------------------------------------------------
// Bluetooth device discovery
// ---------------------------------------------------------------------------

/// Eşleşmiş Bluetooth yazıcı listesi.
final bluetoothPrinterListProvider =
    FutureProvider<List<PrinterDevice>>((ref) {
  return ref.read(printerServiceProvider).discoverBluetoothPrinters();
});

// ---------------------------------------------------------------------------
// Actions (StateNotifier)
// ---------------------------------------------------------------------------

/// Yazıcı eylemlerini (bağlan, bağlantıyı kes, yazdır) kapsayan notifier.
///
/// Kullanım:
/// ```dart
/// final notifier = ref.read(printerActionsProvider.notifier);
/// await notifier.connectWifi('192.168.1.100');
/// await notifier.printBytes(bytes);
/// ```
class PrinterActionsNotifier extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  PrinterService get _service => ref.read(printerServiceProvider);

  Future<bool> connectWifi(String address, {String name = 'WiFi Yazici'}) =>
      _run(() => _service.connectWifi(address, name: name));

  Future<bool> connectUsb(PrinterDevice device) =>
      _run(() => _service.connectUsb(device));

  Future<bool> connectBluetooth(PrinterDevice device) =>
      _run(() => _service.connectBluetooth(device));

  Future<void> disconnect() => _service.disconnect();

  Future<bool> printBytes(List<int> bytes) =>
      _run(() => _service.printBytes(bytes));

  Future<bool> openCashDrawer() => _run(_service.openCashDrawer);

  Future<bool> _run(Future<bool> Function() action) async {
    state = const AsyncValue.loading();
    try {
      final result = await action();
      state = const AsyncValue.data(null);
      return result;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// Bağlantı türüne göre etiket.
  String connectionLabel(PrinterConnectionType type) => type.label;
}

final printerActionsProvider =
    NotifierProvider<PrinterActionsNotifier, AsyncValue<void>>(
  PrinterActionsNotifier.new,
);
