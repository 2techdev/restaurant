/// Riverpod providers for cloud sync state management.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gastrocore_pos/core/config/app_endpoints.dart';
import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/core/providers/connectivity_provider.dart';
import 'package:gastrocore_pos/features/sync/data/clients/sync_api_client.dart';
import 'package:gastrocore_pos/features/sync/data/clients/websocket_sync_client.dart';
import 'package:gastrocore_pos/features/sync/data/repositories/sync_repository_impl.dart';
import 'package:gastrocore_pos/features/sync/domain/repositories/sync_repository.dart';

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

/// The cloud REST API base URL (defaults to [AppEndpoints.apiBaseUrl]).
/// Overridable at runtime via Settings → Sync.
final syncServerUrlProvider = StateProvider<String>(
  (ref) => AppEndpoints.apiBaseUrl,
);

/// The cloud WebSocket base URL (defaults to [AppEndpoints.wsBaseUrl]).
/// Exposed separately so REST and WS can live on different subdomains
/// (e.g. `api.2hub.ch` + `ws.2hub.ch`). Overridable at runtime via
/// Settings → Sync.
final wsServerUrlProvider = StateProvider<String>(
  (ref) => AppEndpoints.wsBaseUrl,
);

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

/// The sync API HTTP client.
final syncApiClientProvider = Provider<SyncApiClient>((ref) {
  final url = ref.watch(syncServerUrlProvider);
  final client = SyncApiClient(baseUrl: url);
  ref.onDispose(client.dispose);
  return client;
});

/// The sync repository (outbox + API).
final syncRepositoryProvider = Provider<SyncRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final api = ref.watch(syncApiClientProvider);
  final tenantId = ref.watch(tenantIdProvider);
  final deviceId = ref.watch(deviceIdProvider);
  return SyncRepositoryImpl(
    db: db,
    apiClient: api,
    tenantId: tenantId,
    deviceId: deviceId,
  );
});

// ---------------------------------------------------------------------------
// Sync state
// ---------------------------------------------------------------------------

/// The overall state of the sync engine.
class SyncState {
  const SyncState({
    this.status = SyncStatus.idle,
    this.pendingCount = 0,
    this.lastSyncAt,
    this.lastError,
  });

  final SyncStatus status;
  final int pendingCount;
  final DateTime? lastSyncAt;
  final String? lastError;

  SyncState copyWith({
    SyncStatus? status,
    int? pendingCount,
    DateTime? lastSyncAt,
    String? lastError,
  }) {
    return SyncState(
      status: status ?? this.status,
      pendingCount: pendingCount ?? this.pendingCount,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      lastError: lastError,
    );
  }
}

/// Manages sync lifecycle: push pending events, pull remote events.
///
/// Sync is triggered by:
///   1. Explicit [sync] call (e.g. WebSocket push notification, UI tap).
///   2. Periodic timer — every [_kPeriodicInterval] (default 5 min).
///   3. Connectivity transition: offline → online via [connectivityAutoSyncProvider].
///
/// Before each push cycle, failed events within the retry limit are reset to
/// pending so they are included in the next batch.
class SyncNotifier extends StateNotifier<SyncState> {
  SyncNotifier({
    required SyncRepository repository,
    Duration periodicInterval = const Duration(minutes: 5),
  })  : _repo = repository,
        super(const SyncState()) {
    _refreshPendingCount();
    _periodicTimer = Timer.periodic(periodicInterval, (_) => sync());
  }

  final SyncRepository _repo;
  bool _syncing = false;
  Timer? _periodicTimer;

  @override
  void dispose() {
    _periodicTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshPendingCount() async {
    try {
      final count = await _repo.getPendingCount();
      state = SyncState(
        status: state.status,
        pendingCount: count,
        lastSyncAt: state.lastSyncAt,
        lastError: state.lastError,
      );
    } catch (_) {}
  }

  /// Trigger a full push + pull sync cycle.
  ///
  /// Concurrent calls are de-duplicated — if a sync is already in progress
  /// the second call returns immediately.
  Future<void> sync() async {
    if (_syncing) return;
    _syncing = true;
    state = state.copyWith(status: SyncStatus.syncing, lastError: null);

    try {
      // Reset transient failures so they get another chance this cycle.
      final implRepo = _repo;
      if (implRepo is SyncRepositoryImpl) {
        await implRepo.resetFailedEvents();
      }

      // 1. Push pending outbox events to the cloud.
      await _repo.pushPendingEvents();

      // 2. Pull remote events (paginated).
      final lastCursor = await _repo.getLastCursor();
      await _repo.pullRemoteEvents(lastCursor);

      state = state.copyWith(
        status: SyncStatus.idle,
        pendingCount: 0,
        lastSyncAt: DateTime.now(),
      );
    } catch (e) {
      state = state.copyWith(
        status: SyncStatus.error,
        lastError: e.toString(),
      );
    } finally {
      _syncing = false;
      await _refreshPendingCount();
    }
  }

  /// Notify the sync engine that a new event was enqueued locally.
  void onEventEnqueued() {
    state = state.copyWith(pendingCount: state.pendingCount + 1);
  }

}

/// Global sync state provider.
final syncProvider = StateNotifierProvider<SyncNotifier, SyncState>((ref) {
  final repo = ref.watch(syncRepositoryProvider);
  return SyncNotifier(repository: repo);
});

/// Convenience provider: number of pending sync events.
final pendingEventCountProvider = Provider<int>((ref) {
  return ref.watch(syncProvider).pendingCount;
});

/// WebSocket sync client for real-time notifications.
///
/// Connects automatically and triggers a pull sync when the server pushes a
/// "new_events" notification. Also sends a heartbeat ping every 30 seconds.
final webSocketSyncClientProvider = Provider<WebSocketSyncClient>((ref) {
  final url = ref.watch(wsServerUrlProvider);
  final deviceId = ref.watch(deviceIdProvider);
  final tenantId = ref.watch(tenantIdProvider);

  final client = WebSocketSyncClient(
    baseUrl: url,
    deviceId: deviceId,
    tenantId: tenantId,
    onNewEvents: (_) => ref.read(syncProvider.notifier).sync(),
  );

  client.connect();
  ref.onDispose(client.dispose);
  return client;
});

/// Watches network connectivity and triggers a sync cycle whenever
/// the device transitions from offline → online.
///
/// Read this provider from each flavor's root app widget to activate it.
final connectivityAutoSyncProvider = Provider<void>((ref) {
  ref.listen<ConnectivityState>(connectivityProvider, (previous, current) {
    if (current == ConnectivityState.online &&
        previous != ConnectivityState.online) {
      ref.read(syncProvider.notifier).sync();
    }
  });
});
