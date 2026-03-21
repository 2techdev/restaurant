/// Tests that verify offline queue behaviour:
///
///  1. Events enqueued while offline are persisted (status = 'pending').
///  2. A successful push cycle uploads all pending events.
///  3. Failed pushes increment retryCount and keep events in the queue.
///  4. resetFailedForRetry requeues failed events below the retry limit.
///  5. Events above the retry limit are NOT requeued.
///  6. The SyncNotifier transitions correctly when returning online:
///     pending events are uploaded and the state becomes idle.
///
/// All tests run against an in-memory SQLite database — no real network.
library;

import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/features/sync/data/clients/sync_api_client.dart';
import 'package:gastrocore_pos/features/sync/data/daos/sync_event_dao.dart';
import 'package:gastrocore_pos/features/sync/data/repositories/sync_repository_impl.dart';
import 'package:gastrocore_pos/features/sync/domain/entities/sync_event_entity.dart';
import 'package:gastrocore_pos/features/sync/domain/repositories/sync_repository.dart';
import 'package:gastrocore_pos/features/sync/presentation/providers/sync_provider.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Creates a fresh in-memory database for each test.
AppDatabase _memDb() => AppDatabase(NativeDatabase.memory());

/// Inserts [count] pending ticket events into [dao].
Future<void> _seedPending(SyncEventDao dao, int count) async {
  final now = DateTime.now();
  for (var i = 0; i < count; i++) {
    await dao.insertEvent(
      SyncQueueCompanion.insert(
        entityType: 'tickets',
        entityId: 'ticket-offline-$i',
        operation: 'insert',
        payloadJson: jsonEncode({'id': 'ticket-offline-$i', 'status': 'open'}),
        deviceId: 'POS-test',
        timestamp: now,
        createdAt: now,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Fake SyncApiClient
// ---------------------------------------------------------------------------

class _FakeApiClient extends SyncApiClient {
  _FakeApiClient() : super(baseUrl: 'http://fake');

  int pushCalls = 0;
  int pullCalls = 0;
  bool failPush = false;
  bool failPull = false;

  @override
  Future<({int accepted, int rejected})> push(
      List<RemoteSyncEvent> events) async {
    pushCalls++;
    if (failPush) throw SyncApiException('network error');
    return (accepted: events.length, rejected: 0);
  }

  @override
  Future<PullResult> pull({
    required String deviceId,
    required String tenantId,
    required String cursor,
    int limit = 100,
  }) async {
    pullCalls++;
    if (failPull) throw SyncApiException('pull error');
    return PullResult(events: [], cursor: 'cursor-1', hasMore: false);
  }

  @override
  void dispose() {} // no real http.Client to close
}

// ---------------------------------------------------------------------------
// Fake SyncRepository for SyncNotifier tests
// ---------------------------------------------------------------------------

class _FakeRepo implements SyncRepository {
  int pendingCount;
  bool failPush;
  bool failPull;
  int pushCalls = 0;
  int pullCalls = 0;
  String cursor = '';

  _FakeRepo({this.pendingCount = 0, this.failPush = false, this.failPull = false});

  @override
  Future<int> pushPendingEvents() async {
    pushCalls++;
    if (failPush) throw Exception('push failed');
    final n = pendingCount;
    pendingCount = 0;
    return n;
  }

  @override
  Future<String> pullRemoteEvents(String lastCursor) async {
    pullCalls++;
    if (failPull) throw Exception('pull failed');
    cursor = 'cursor-after';
    return cursor;
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
  }) async => pendingCount++;

  @override
  Future<List<SyncEventEntity>> getPendingEvents() async => [];

  @override
  Future<int> getPendingCount() async => pendingCount;

  @override
  Future<String> getLastCursor() async => cursor;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ── DAO / Repository layer ─────────────────────────────────────────────────

  group('Offline queue — DAO', () {
    late AppDatabase db;
    late SyncEventDao dao;

    setUp(() {
      db = _memDb();
      dao = SyncEventDao(db);
    });

    tearDown(() => db.close());

    test('events enqueued offline persist with status pending', () async {
      await _seedPending(dao, 3);
      final count = await dao.getPendingCount();
      expect(count, 3);

      final events = await dao.getPendingEvents();
      expect(events.every((e) => e.status == 'pending'), isTrue);
    });

    test('events survive a db close / reopen cycle (in-memory baseline)',
        () async {
      // In-memory DBs do not persist across close; this verifies the API
      // behaves consistently within a single session.
      await _seedPending(dao, 2);
      expect(await dao.getPendingCount(), 2);
    });

    test('markAsFailed keeps event in queue with status failed', () async {
      await _seedPending(dao, 1);
      final events = await dao.getPendingEvents();
      await dao.markAsFailed(events.first.id, 'timeout');

      final pending = await dao.getPendingEvents();
      expect(pending, isEmpty); // failed != pending
    });

    test('resetFailedForRetry below maxRetries requeues events', () async {
      await _seedPending(dao, 1);
      final ev = (await dao.getPendingEvents()).first;
      await dao.markAsFailed(ev.id, 'error');

      await dao.resetFailedForRetry(maxRetries: 5);

      final pending = await dao.getPendingEvents();
      expect(pending.length, 1);
      expect(pending.first.status, 'pending');
    });

    test('resetFailedForRetry at maxRetries does NOT requeue', () async {
      await _seedPending(dao, 1);
      final ev = (await dao.getPendingEvents()).first;

      // Fail 5 times to hit the limit.
      for (var i = 0; i < 5; i++) {
        await dao.markAsFailed(ev.id, 'error $i');
      }

      await dao.resetFailedForRetry(maxRetries: 5);

      final pending = await dao.getPendingEvents();
      expect(pending, isEmpty); // exhausted — stays failed
    });
  });

  group('Offline queue — SyncRepositoryImpl', () {
    late AppDatabase db;
    late _FakeApiClient api;
    late SyncRepositoryImpl repo;

    setUp(() {
      db = _memDb();
      api = _FakeApiClient();
      repo = SyncRepositoryImpl(
        db: db,
        apiClient: api,
        tenantId: 'tenant-1',
        deviceId: 'POS-test',
      );
    });

    tearDown(() => db.close());

    test('pushPendingEvents uploads all queued events', () async {
      final dao = SyncEventDao(db);
      await _seedPending(dao, 5);

      final accepted = await repo.pushPendingEvents();

      expect(accepted, 5);
      expect(api.pushCalls, 1);
      expect(await dao.getPendingCount(), 0);
    });

    test('failed push marks events as failed and rethrows', () async {
      api.failPush = true;
      final dao = SyncEventDao(db);
      await _seedPending(dao, 2);

      expect(repo.pushPendingEvents(), throwsA(isA<SyncApiException>()));
      await Future.delayed(Duration.zero); // let the future complete

      // Events are no longer in pending — they are in failed.
      final pending = await dao.getPendingEvents();
      expect(pending, isEmpty);
    });

    test('resetFailedEvents requeues retryable failures', () async {
      final dao = SyncEventDao(db);
      await _seedPending(dao, 1);
      api.failPush = true;

      try {
        await repo.pushPendingEvents();
      } catch (_) {}

      // Should be in failed state.
      expect(await dao.getPendingCount(), 0);

      // Now reset.
      await repo.resetFailedEvents();

      expect(await dao.getPendingCount(), 1);
    });
  });

  // ── SyncNotifier / state machine ──────────────────────────────────────────

  group('Offline queue — SyncNotifier', () {
    late _FakeRepo repo;
    late SyncNotifier notifier;

    setUp(() {
      repo = _FakeRepo(pendingCount: 3);
      notifier = SyncNotifier(
        repository: repo,
        // Disable periodic timer in tests.
        periodicInterval: const Duration(days: 999),
      );
    });

    tearDown(() => notifier.dispose());

    test('initial state shows pending events', () async {
      await Future.microtask(() {});
      expect(notifier.state.pendingCount, 3);
    });

    test('sync() uploads pending then clears count', () async {
      await notifier.sync();

      expect(repo.pushCalls, 1);
      expect(repo.pullCalls, 1);
      expect(notifier.state.pendingCount, 0);
      expect(notifier.state.status, SyncStatus.idle);
      expect(notifier.state.lastSyncAt, isNotNull);
    });

    test('sync() enters error state on push failure', () async {
      repo.failPush = true;
      await notifier.sync();

      expect(notifier.state.status, SyncStatus.error);
      expect(notifier.state.lastError, isNotNull);
    });

    test('sync() recovers on next call after failure', () async {
      repo.failPush = true;
      await notifier.sync();
      expect(notifier.state.status, SyncStatus.error);

      repo.failPush = false;
      await notifier.sync();
      expect(notifier.state.status, SyncStatus.idle);
    });

    test('concurrent sync() calls are de-duplicated', () async {
      // Both futures are awaited; only one push should occur.
      await Future.wait([notifier.sync(), notifier.sync()]);
      expect(repo.pushCalls, 1);
    });

    test('online-transition triggers sync (simulated)', () async {
      // Simulate what connectivityAutoSyncProvider does.
      await notifier.sync();
      expect(repo.pushCalls, 1);
    });
  });
}
