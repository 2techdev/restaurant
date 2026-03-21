/// Connectivity state management for GastroCore POS.
///
/// Tracks online/offline/syncing status using connectivity_plus.
/// Offline-first: the app works fully without network; sync is additive.
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/di/providers.dart';

// ---------------------------------------------------------------------------
// Connectivity state
// ---------------------------------------------------------------------------

/// Represents the current network / sync status of the device.
enum ConnectivityState {
  /// Device has network access and can reach the sync server.
  online,

  /// Device has no network access or cannot reach the sync server.
  offline,

  /// Actively uploading/downloading sync data.
  syncing,
}

// ---------------------------------------------------------------------------
// Connectivity notifier
// ---------------------------------------------------------------------------

/// Manages the current [ConnectivityState] using connectivity_plus.
class ConnectivityNotifier extends StateNotifier<ConnectivityState> {
  ConnectivityNotifier() : super(ConnectivityState.offline) {
    _init();
  }

  StreamSubscription<List<ConnectivityResult>>? _subscription;

  void _init() {
    // Check current connectivity immediately.
    Connectivity().checkConnectivity().then(_applyResults);

    // Listen for changes.
    _subscription = Connectivity().onConnectivityChanged.listen(_applyResults);
  }

  void _applyResults(List<ConnectivityResult> results) {
    final hasNetwork = results.any(
      (r) =>
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.ethernet,
    );
    if (state != ConnectivityState.syncing) {
      state = hasNetwork ? ConnectivityState.online : ConnectivityState.offline;
    }
  }

  /// Mark device as actively syncing (overrides online/offline visual).
  void setSyncing() => state = ConnectivityState.syncing;

  /// Restore to the correct online/offline state after sync.
  void clearSyncing() {
    Connectivity().checkConnectivity().then(_applyResults);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

/// Online/offline/syncing state for the device.
final connectivityProvider =
    StateNotifierProvider<ConnectivityNotifier, ConnectivityState>((ref) {
  return ConnectivityNotifier();
});

/// Number of pending operations in the sync queue.
/// Queries the sync_queue table for rows with status = 'pending'.
final pendingSyncCountProvider = FutureProvider<int>((ref) async {
  final db = ref.watch(databaseProvider);
  final result = await db.customSelect(
    "SELECT COUNT(*) AS c FROM sync_queue WHERE status = 'pending'",
  ).getSingle();
  return result.read<int>('c');
});

/// Timestamp of the last successful sync. null if never synced.
final lastSyncTimeProvider = StateProvider<DateTime?>((ref) => null);
