/// Unit tests for SyncNotifier and SyncApiClient behaviour.
///
/// SyncNotifier is tested against a fake SyncRepository so no real DB or
/// HTTP calls are made.
///
/// Run with:
///   flutter test test/features/sync/sync_provider_test.dart
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gastrocore_pos/features/sync/data/clients/sync_api_client.dart';
import 'package:gastrocore_pos/features/sync/domain/entities/sync_event_entity.dart';
import 'package:gastrocore_pos/features/sync/domain/repositories/sync_repository.dart';
import 'package:gastrocore_pos/features/sync/presentation/providers/sync_provider.dart';

// ---------------------------------------------------------------------------
// Fake SyncRepository
// ---------------------------------------------------------------------------

class _FakeSyncRepository implements SyncRepository {
  int pushCalls = 0;
  int pullCalls = 0;
  String? lastPullCursor;
  bool throwOnPush = false;
  bool throwOnPull = false;
  int pendingCount = 0;
  String lastCursor = '';

  @override
  Future<int> pushPendingEvents() async {
    pushCalls++;
    if (throwOnPush) throw Exception('push failed');
    final pushed = pendingCount;
    pendingCount = 0;
    return pushed;
  }

  @override
  Future<String> pullRemoteEvents(String cursor) async {
    pullCalls++;
    lastPullCursor = cursor;
    if (throwOnPull) throw Exception('pull failed');
    return 'cursor-after-pull';
  }

  @override
  Future<SyncStatus> getSyncStatus() async => SyncStatus.idle;

  @override
  Future<void> enqueueEvent({
    required String tableName,
    required SyncOperation operation,
    required String recordId,
    required String payload,
    required String deviceId,
  }) async {
    pendingCount++;
  }

  @override
  Future<List<SyncEventEntity>> getPendingEvents() async => [];

  @override
  Future<int> getPendingCount() async => pendingCount;

  @override
  Future<String> getLastCursor() async => lastCursor;

  @override
  Future<List<SyncEventEntity>> getDeadLetterEvents() async => [];

  @override
  Future<int> getDeadLetterCount() async => 0;

  @override
  Future<void> requeueDeadLetterEvent(int id) async {}

  @override
  Future<void> purgeDeadLetterEvent(int id) async {}
}

// ---------------------------------------------------------------------------
// SyncNotifier tests
// ---------------------------------------------------------------------------

void main() {
  group('SyncNotifier', () {
    late _FakeSyncRepository repo;
    late SyncNotifier notifier;

    setUp(() {
      repo = _FakeSyncRepository();
      notifier = SyncNotifier(repository: repo);
    });

    tearDown(() => notifier.dispose());

    test('initial state is idle with 0 pending', () async {
      // Allow _refreshPendingCount to complete.
      await Future.microtask(() {});
      expect(notifier.state.status, SyncStatus.idle);
      expect(notifier.state.pendingCount, 0);
      expect(notifier.state.lastSyncAt, isNull);
      expect(notifier.state.lastError, isNull);
    });

    test('sync() transitions to syncing then idle on success', () async {
      final states = <SyncStatus>[];
      notifier.addListener((s) => states.add(s.status));

      await notifier.sync();

      expect(states, contains(SyncStatus.syncing));
      expect(notifier.state.status, SyncStatus.idle);
      expect(notifier.state.lastSyncAt, isNotNull);
      expect(notifier.state.lastError, isNull);
    });

    test('sync() calls pushPendingEvents and pullRemoteEvents', () async {
      await notifier.sync();

      expect(repo.pushCalls, 1);
      expect(repo.pullCalls, 1);
    });

    test('sync() passes the last cursor to pullRemoteEvents', () async {
      repo.lastCursor = '2026-03-21T10:00:00.000000Z';
      await notifier.sync();

      expect(repo.lastPullCursor, '2026-03-21T10:00:00.000000Z');
    });

    test('sync() transitions to error on push failure', () async {
      repo.throwOnPush = true;
      await notifier.sync();

      expect(notifier.state.status, SyncStatus.error);
      expect(notifier.state.lastError, contains('push failed'));
    });

    test('sync() transitions to error on pull failure', () async {
      repo.throwOnPull = true;
      await notifier.sync();

      expect(notifier.state.status, SyncStatus.error);
      expect(notifier.state.lastError, contains('pull failed'));
    });

    test('concurrent sync() calls are de-duplicated', () async {
      // Fire two concurrent syncs; only one should execute.
      await Future.wait([notifier.sync(), notifier.sync()]);

      expect(repo.pushCalls, 1);
    });

    test('onEventEnqueued increments pendingCount', () {
      notifier.onEventEnqueued();
      notifier.onEventEnqueued();
      expect(notifier.state.pendingCount, 2);
    });
  });

  // ---------------------------------------------------------------------------
  // RemoteSyncEvent toJson / fromJson round-trip
  // ---------------------------------------------------------------------------

  group('RemoteSyncEvent', () {
    test('toJson contains all fields', () {
      final event = RemoteSyncEvent(
        id: 'evt-1',
        tenantId: 'tenant-1',
        deviceId: 'dev-1',
        tableName: 'tickets',
        recordId: 'tkt-1',
        operation: 'insert',
        payload: {'status': 'open'},
        createdAt: DateTime.utc(2026, 3, 21, 10, 0, 0),
      );

      final json = event.toJson();

      expect(json['id'], 'evt-1');
      expect(json['tenant_id'], 'tenant-1');
      expect(json['device_id'], 'dev-1');
      expect(json['table_name'], 'tickets');
      expect(json['record_id'], 'tkt-1');
      expect(json['operation'], 'insert');
      expect(json['payload'], {'status': 'open'});
      expect(json['created_at'], '2026-03-21T10:00:00.000Z');
    });
  });

  // ---------------------------------------------------------------------------
  // SyncState copyWith
  // ---------------------------------------------------------------------------

  group('SyncState', () {
    test('copyWith preserves unchanged fields', () {
      final original = SyncState(
        status: SyncStatus.idle,
        pendingCount: 3,
        lastSyncAt: DateTime(2026, 3, 21),
        lastError: null,
      );

      final updated = original.copyWith(status: SyncStatus.syncing);

      expect(updated.status, SyncStatus.syncing);
      expect(updated.pendingCount, 3);
      expect(updated.lastSyncAt, original.lastSyncAt);
      expect(updated.lastError, isNull);
    });

    test('copyWith resets lastError to null explicitly', () {
      final original = SyncState(lastError: 'some error');
      final updated = original.copyWith(status: SyncStatus.idle);
      // copyWith always resets lastError (by design — null means "cleared").
      expect(updated.lastError, isNull);
    });

    test('copyWith with new error preserves it', () {
      final s = const SyncState().copyWith(lastError: 'connection refused');
      expect(s.lastError, 'connection refused');
    });
  });

  // ---------------------------------------------------------------------------
  // SyncApiException
  // ---------------------------------------------------------------------------

  group('SyncApiException', () {
    test('toString includes message', () {
      const ex = SyncApiException('timeout after 30s');
      expect(ex.toString(), contains('timeout after 30s'));
    });
  });
}
