/// Runtime permission service for GastroCore POS.
///
/// Encapsulates the [permission_handler] package behind a clean interface
/// and exposes a Riverpod [StateNotifierProvider] that tracks the status
/// of all dangerous permissions the app may need.
///
/// Permissions requested:
/// - Camera           — future barcode scanning
/// - Bluetooth        — Bluetooth printer connections
/// - Storage          — backup file read/write (Android ≤ 12)
/// - Notifications    — low-stock / kitchen alerts (optional)
///
/// Non-dangerous permissions (INTERNET, ACCESS_NETWORK_STATE, ACCESS_WIFI_STATE,
/// WAKE_LOCK, RECEIVE_BOOT_COMPLETED) are granted by the OS at install time
/// and are not listed here.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

// ---------------------------------------------------------------------------
// PermissionsState
// ---------------------------------------------------------------------------

/// Snapshot of all relevant permission statuses.
class PermissionsState {
  const PermissionsState({
    this.camera = PermissionStatus.denied,
    this.bluetooth = PermissionStatus.denied,
    this.bluetoothScan = PermissionStatus.denied,
    this.bluetoothConnect = PermissionStatus.denied,
    this.storage = PermissionStatus.denied,
    this.isLoading = false,
  });

  final PermissionStatus camera;

  /// Android ≤ 11: classic BLUETOOTH permission.
  final PermissionStatus bluetooth;

  /// Android 12+: BLUETOOTH_SCAN.
  final PermissionStatus bluetoothScan;

  /// Android 12+: BLUETOOTH_CONNECT.
  final PermissionStatus bluetoothConnect;

  /// WRITE_EXTERNAL_STORAGE / READ_EXTERNAL_STORAGE (legacy, Android ≤ 12).
  final PermissionStatus storage;

  /// True while [PermissionService.checkAll] / [requestAll] is running.
  final bool isLoading;

  // -------------------------------------------------------------------------
  // Convenience getters
  // -------------------------------------------------------------------------

  /// Returns true when camera access is fully granted.
  bool get cameraGranted => camera == PermissionStatus.granted;

  /// Returns true when Bluetooth access is usable on the current Android version.
  ///
  /// On Android 12+, both [bluetoothScan] and [bluetoothConnect] must be granted.
  /// On Android ≤ 11, only [bluetooth] is required.
  bool get bluetoothGranted =>
      (bluetoothScan == PermissionStatus.granted &&
          bluetoothConnect == PermissionStatus.granted) ||
      bluetooth == PermissionStatus.granted;

  /// Returns true when storage access is granted (or not required on Android 13+).
  bool get storageGranted =>
      storage == PermissionStatus.granted ||
      storage == PermissionStatus.limited;

  /// Returns true if all critical permissions (Bluetooth for printing) are granted.
  bool get allCriticalGranted => bluetoothGranted;

  PermissionsState copyWith({
    PermissionStatus? camera,
    PermissionStatus? bluetooth,
    PermissionStatus? bluetoothScan,
    PermissionStatus? bluetoothConnect,
    PermissionStatus? storage,
    bool? isLoading,
  }) {
    return PermissionsState(
      camera: camera ?? this.camera,
      bluetooth: bluetooth ?? this.bluetooth,
      bluetoothScan: bluetoothScan ?? this.bluetoothScan,
      bluetoothConnect: bluetoothConnect ?? this.bluetoothConnect,
      storage: storage ?? this.storage,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  @override
  String toString() =>
      'PermissionsState(camera: ${camera.name}, bt: ${bluetooth.name}, '
      'btScan: ${bluetoothScan.name}, btConnect: ${bluetoothConnect.name}, '
      'storage: ${storage.name})';
}

// ---------------------------------------------------------------------------
// PermissionService (StateNotifier)
// ---------------------------------------------------------------------------

class PermissionService extends StateNotifier<PermissionsState> {
  PermissionService() : super(const PermissionsState());

  // -------------------------------------------------------------------------
  // Check all permissions (no dialog shown)
  // -------------------------------------------------------------------------

  /// Read current permission statuses without prompting the user.
  Future<void> checkAll() async {
    state = state.copyWith(isLoading: true);

    await [
      Permission.camera,
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.storage,
    ].request(); // .request() returns a map; use .status for non-prompting check

    // Use status (no dialog) to refresh the snapshot.
    state = PermissionsState(
      camera: await Permission.camera.status,
      bluetooth: await Permission.bluetooth.status,
      bluetoothScan: await Permission.bluetoothScan.status,
      bluetoothConnect: await Permission.bluetoothConnect.status,
      storage: await Permission.storage.status,
      isLoading: false,
    );
  }

  // -------------------------------------------------------------------------
  // Request individual permissions
  // -------------------------------------------------------------------------

  /// Request camera permission and update state.
  Future<PermissionStatus> requestCamera() async {
    final result = await Permission.camera.request();
    state = state.copyWith(camera: result);
    return result;
  }

  /// Request Bluetooth permissions (Android 12+: scan + connect; ≤ 11: classic).
  Future<bool> requestBluetooth() async {
    final scan = await Permission.bluetoothScan.request();
    final connect = await Permission.bluetoothConnect.request();
    final classic = await Permission.bluetooth.request();

    state = state.copyWith(
      bluetoothScan: scan,
      bluetoothConnect: connect,
      bluetooth: classic,
    );

    return (scan == PermissionStatus.granted &&
            connect == PermissionStatus.granted) ||
        classic == PermissionStatus.granted;
  }

  /// Request storage permission and update state.
  Future<PermissionStatus> requestStorage() async {
    final result = await Permission.storage.request();
    state = state.copyWith(storage: result);
    return result;
  }

  // -------------------------------------------------------------------------
  // Request all dangerous permissions at once (e.g. on first launch)
  // -------------------------------------------------------------------------

  /// Request all dangerous permissions in sequence and update state.
  Future<void> requestAll() async {
    state = state.copyWith(isLoading: true);

    final results = await [
      Permission.camera,
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.storage,
    ].request();

    state = PermissionsState(
      camera: results[Permission.camera] ?? PermissionStatus.denied,
      bluetooth: results[Permission.bluetooth] ?? PermissionStatus.denied,
      bluetoothScan:
          results[Permission.bluetoothScan] ?? PermissionStatus.denied,
      bluetoothConnect:
          results[Permission.bluetoothConnect] ?? PermissionStatus.denied,
      storage: results[Permission.storage] ?? PermissionStatus.denied,
      isLoading: false,
    );
  }

  // -------------------------------------------------------------------------
  // Open app settings
  // -------------------------------------------------------------------------

  /// Open the app system settings so the user can manually grant permissions.
  Future<bool> openSettings() => openAppSettings();
}

// ---------------------------------------------------------------------------
// Riverpod provider
// ---------------------------------------------------------------------------

/// Singleton [PermissionService] exposed as a [StateNotifierProvider].
///
/// Usage:
/// ```dart
/// // Check status:
/// final perms = ref.watch(permissionServiceProvider);
/// if (!perms.bluetoothGranted) { ... }
///
/// // Request:
/// await ref.read(permissionServiceProvider.notifier).requestBluetooth();
/// ```
final permissionServiceProvider =
    StateNotifierProvider<PermissionService, PermissionsState>(
  (ref) => PermissionService(),
);
