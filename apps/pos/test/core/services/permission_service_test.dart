/// Unit tests for [PermissionsState].
///
/// These tests cover only the pure-Dart state class (computed getters,
/// copyWith). The actual [PermissionService] methods require a real Android
/// device / emulator and are tested through integration tests.
///
/// Run with: flutter test test/core/services/permission_service_test.dart
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:gastrocore_pos/core/services/permission_service.dart';

void main() {
  // =========================================================================
  // PermissionsState defaults
  // =========================================================================

  group('PermissionsState defaults', () {
    test('all permissions denied by default', () {
      const state = PermissionsState();
      expect(state.camera, PermissionStatus.denied);
      expect(state.bluetooth, PermissionStatus.denied);
      expect(state.bluetoothScan, PermissionStatus.denied);
      expect(state.bluetoothConnect, PermissionStatus.denied);
      expect(state.storage, PermissionStatus.denied);
    });

    test('isLoading is false by default', () {
      const state = PermissionsState();
      expect(state.isLoading, false);
    });

    test('all convenience getters return false when all denied', () {
      const state = PermissionsState();
      expect(state.cameraGranted, isFalse);
      expect(state.bluetoothGranted, isFalse);
      expect(state.storageGranted, isFalse);
      expect(state.allCriticalGranted, isFalse);
    });
  });

  // =========================================================================
  // PermissionsState.cameraGranted
  // =========================================================================

  group('PermissionsState.cameraGranted', () {
    test('granted → true', () {
      final state =
          const PermissionsState().copyWith(camera: PermissionStatus.granted);
      expect(state.cameraGranted, isTrue);
    });

    test('denied → false', () {
      final state =
          const PermissionsState().copyWith(camera: PermissionStatus.denied);
      expect(state.cameraGranted, isFalse);
    });

    test('permanentlyDenied → false', () {
      final state = const PermissionsState()
          .copyWith(camera: PermissionStatus.permanentlyDenied);
      expect(state.cameraGranted, isFalse);
    });
  });

  // =========================================================================
  // PermissionsState.bluetoothGranted
  // =========================================================================

  group('PermissionsState.bluetoothGranted (Android 12+)', () {
    test('scan + connect granted → bluetooth granted', () {
      final state = const PermissionsState().copyWith(
        bluetoothScan: PermissionStatus.granted,
        bluetoothConnect: PermissionStatus.granted,
      );
      expect(state.bluetoothGranted, isTrue);
    });

    test('only scan granted (no connect) → not granted', () {
      final state = const PermissionsState().copyWith(
        bluetoothScan: PermissionStatus.granted,
        bluetoothConnect: PermissionStatus.denied,
      );
      // classic bluetooth is also denied → false
      expect(state.bluetoothGranted, isFalse);
    });

    test('classic bluetooth granted (Android ≤ 11) → bluetooth granted', () {
      final state = const PermissionsState().copyWith(
        bluetooth: PermissionStatus.granted,
        bluetoothScan: PermissionStatus.denied,
        bluetoothConnect: PermissionStatus.denied,
      );
      expect(state.bluetoothGranted, isTrue);
    });

    test('all denied → not granted', () {
      const state = PermissionsState();
      expect(state.bluetoothGranted, isFalse);
    });
  });

  // =========================================================================
  // PermissionsState.storageGranted
  // =========================================================================

  group('PermissionsState.storageGranted', () {
    test('granted → true', () {
      final state = const PermissionsState()
          .copyWith(storage: PermissionStatus.granted);
      expect(state.storageGranted, isTrue);
    });

    test('limited → true (Android 13 media partial access)', () {
      final state = const PermissionsState()
          .copyWith(storage: PermissionStatus.limited);
      expect(state.storageGranted, isTrue);
    });

    test('denied → false', () {
      final state = const PermissionsState()
          .copyWith(storage: PermissionStatus.denied);
      expect(state.storageGranted, isFalse);
    });
  });

  // =========================================================================
  // PermissionsState.allCriticalGranted
  // =========================================================================

  group('PermissionsState.allCriticalGranted', () {
    test('bluetooth granted via modern API → allCritical is true', () {
      final state = const PermissionsState().copyWith(
        bluetoothScan: PermissionStatus.granted,
        bluetoothConnect: PermissionStatus.granted,
      );
      expect(state.allCriticalGranted, isTrue);
    });

    test('bluetooth denied → allCritical is false', () {
      const state = PermissionsState();
      expect(state.allCriticalGranted, isFalse);
    });
  });

  // =========================================================================
  // PermissionsState.copyWith
  // =========================================================================

  group('PermissionsState.copyWith', () {
    test('copies only changed fields', () {
      const original = PermissionsState();
      final updated =
          original.copyWith(camera: PermissionStatus.granted);

      expect(updated.camera, PermissionStatus.granted);
      // All other fields remain as defaults.
      expect(updated.bluetooth, PermissionStatus.denied);
      expect(updated.storage, PermissionStatus.denied);
      expect(updated.isLoading, false);
    });

    test('isLoading can be toggled', () {
      const state = PermissionsState();
      final loading = state.copyWith(isLoading: true);
      expect(loading.isLoading, isTrue);

      final done = loading.copyWith(isLoading: false);
      expect(done.isLoading, isFalse);
    });

    test('full copy without arguments equals original', () {
      final state = const PermissionsState().copyWith(
        camera: PermissionStatus.granted,
        bluetooth: PermissionStatus.granted,
        storage: PermissionStatus.granted,
      );
      final copy = state.copyWith();
      expect(copy.camera, state.camera);
      expect(copy.bluetooth, state.bluetooth);
      expect(copy.storage, state.storage);
    });
  });

  // =========================================================================
  // PermissionsState.toString
  // =========================================================================

  group('PermissionsState.toString', () {
    test('includes all field names', () {
      const state = PermissionsState();
      final str = state.toString();
      expect(str, contains('camera'));
      expect(str, contains('bt:'));
      expect(str, contains('storage'));
    });
  });
}
