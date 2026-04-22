/// Tests that verify dead-letter queue (DLQ) behaviour:
///
///  1. `parkExceededFailures` moves events whose retryCount has met the
///     maxRetries budget into the terminal `dead` status so they stop
///     blocking the outbox head.
///  2. `resetFailedForRetry` at the same budget leaves dead events alone
///     (no accidental resurrection).
///  3. `getDeadEvents` / `getDeadCount` surface the parked events for the
///     operator-facing DLQ panel.
///  4. `requeueDeadEvent` transitions a dead entry back to `pending` with
///     retryCount=0 and clears the stored error message.
///  5. `purgeDeadEvent` permanently removes the row.
///  6. The SyncRepositoryImpl.resetFailedEvents wrapper parks-then-resets
///     so a single reconnect cycle drains transient + poison failures
///     in the right order.
///
/// All tests run against an in-memory SQLite database.
library;

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/features/sync/data/clients/sync_api_client.dart';
import 'package:gastrocore_pos/features/sync/data/daos/sync_event_dao.dart';
import 'package:gastrocore_pos/features/sync/data/repositories/sync_repository_impl.dart';
import 'package:gastrocore_pos/features/sync/domain/entities/sync_event_entity.dart';

AppDatabase _memDb() => AppDatabase(NativeDatabase.memory());

Future<int> _insertPending(SyncEventDao dao, String id) async {
  final now = DateTime.now();
  return dao.insertEvent(
    SyncQueueCompanion.insert(
      entityType: 'tickets',
      entityId: id,
      operation: 'insert',
      payloadJson: jsonEncode({'id': id}),
      deviceId: 'POS-dlq',
      timestamp: now,
      createdAt: now,
    ),
  );
}

class _FakeFailingClient extends SyncApiClient {
  _FakeFailingClient() : super(baseUrl: 'http://fake');

  int pushCalls = 0;

  @override
  Future<({int accepted, int rejected})> push(
      List<RemoteSyncEvent> events) async {
    pushCalls++;
    throw SyncApiException('forced failure');
  }

  @override
  Future<PullResult> pull({
    required String deviceId,
    required String tenantId,
    required String cursor,
    int limit = 100,
  }) async {
    return PullResult(events: [], cursor: cursor, hasMore: false);
  }

  @override
  void dispose() {}
}

void main() {
  group('DLQ — SyncEventDao', () {
    late AppDatabase db;
    late SyncEventDao dao;

    setUp(() {
      db = _memDb();
      dao = SyncEventDao(db);
    });

    tearDown(() => db.close());

    test('parkExceededFailures moves failed events over budget into dead',
        () async {
      final id = await _insertPending(dao, 'ticket-a');

      // Fail 5 times — that meets the default budget.
      for (var i = 0; i < 5; i++) {
        await dao.markAsFailed(id, 'attempt $i');
      }

      final parked = await dao.parkExceededFailures(maxRetries: 5);
      expect(parked, 1);

      final dead = await dao.getDeadEvents();
      expect(dead.length, 1);
      expect(dead.first.status, 'dead');
      expect(dead.first.errorMessage, 'retry budget exhausted');
    });

    test('parkExceededFailures leaves under-budget failures alone',
        () async {
      final id = await _insertPending(dao, 'ticket-b');

      // Fail 2 times — still has retries left.
      for (var i = 0; i < 2; i++) {
        await dao.markAsFailed(id, 'attempt $i');
      }

      final parked = await dao.parkExceededFailures(maxRetries: 5);
      expect(parked, 0);

      expect(await dao.getDeadCount(), 0);
    });

    test('resetFailedForRetry does not resurrect dead events', () async {
      final id = await _insertPending(dao, 'ticket-c');
      for (var i = 0; i < 5; i++) {
        await dao.markAsFailed(id, 'x');
      }
      await dao.parkExceededFailures(maxRetries: 5);

      await dao.resetFailedForRetry(maxRetries: 5);

      expect(await dao.getPendingCount(), 0);
      expect(await dao.getDeadCount(), 1);
    });

    test('markAsDead forces an event into the DLQ regardless of retries',
        () async {
      final id = await _insertPending(dao, 'ticket-d');
      await dao.markAsDead(id, 'server rejected: schema mismatch');

      final dead = await dao.getDeadEvents();
      expect(dead.length, 1);
      expect(dead.first.errorMessage, 'server rejected: schema mismatch');
    });

    test('requeueDeadEvent clears error + retryCount, returns to pending',
        () async {
      final id = await _insertPending(dao, 'ticket-e');
      for (var i = 0; i < 5; i++) {
        await dao.markAsFailed(id, 'x');
      }
      await dao.parkExceededFailures(maxRetries: 5);

      await dao.requeueDeadEvent(id);

      final pending = await dao.getPendingEvents();
      expect(pending.length, 1);
      expect(pending.first.id, id);
      expect(pending.first.status, 'pending');
      expect(pending.first.retryCount, 0);
      expect(pending.first.errorMessage, isNull);

      expect(await dao.getDeadCount(), 0);
    });

    test('requeueDeadEvent on a pending event is a no-op', () async {
      final id = await _insertPending(dao, 'ticket-f');
      // Event is pending, not dead.

      await dao.requeueDeadEvent(id);

      final pending = await dao.getPendingEvents();
      expect(pending.length, 1);
      expect(pending.first.id, id);
    });

    test('purgeDeadEvent removes the row and returns 1', () async {
      final id = await _insertPending(dao, 'ticket-g');
      await dao.markAsDead(id, 'corrupted');

      final deleted = await dao.purgeDeadEvent(id);
      expect(deleted, 1);

      expect(await dao.getDeadCount(), 0);
    });

    test('purgeDeadEvent refuses to delete a non-dead row', () async {
      final id = await _insertPending(dao, 'ticket-h');
      // Pending, not dead.

      final deleted = await dao.purgeDeadEvent(id);
      expect(deleted, 0);

      expect(await dao.getPendingCount(), 1);
    });
  });

  group('DLQ — SyncRepositoryImpl', () {
    late AppDatabase db;
    late _FakeFailingClient api;
    late SyncRepositoryImpl repo;
    late SyncEventDao dao;

    setUp(() {
      db = _memDb();
      api = _FakeFailingClient();
      dao = SyncEventDao(db);
      repo = SyncRepositoryImpl(
        db: db,
        apiClient: api,
        tenantId: 'tenant-dlq',
        deviceId: 'POS-dlq',
      );
    });

    tearDown(() => db.close());

    test('resetFailedEvents parks over-budget failures before requeuing',
        () async {
      final id = await _insertPending(dao, 'ticket-park');
      for (var i = 0; i < 5; i++) {
        await dao.markAsFailed(id, 'x');
      }

      await repo.resetFailedEvents(maxRetries: 5);

      expect(await dao.getPendingCount(), 0);
      expect(await dao.getDeadCount(), 1);
    });

    test('getDeadLetterEvents surfaces domain entities with dead status',
        () async {
      final id = await _insertPending(dao, 'ticket-surface');
      await dao.markAsDead(id, 'poison');

      final dead = await repo.getDeadLetterEvents();
      expect(dead.length, 1);
      expect(dead.first.status, SyncEventStatus.dead);
      expect(dead.first.errorMessage, 'poison');
    });

    test('requeue + purge round-trip through repository API', () async {
      final id1 = await _insertPending(dao, 'ticket-r');
      final id2 = await _insertPending(dao, 'ticket-p');
      await dao.markAsDead(id1, 'a');
      await dao.markAsDead(id2, 'b');

      await repo.requeueDeadLetterEvent(id1);
      await repo.purgeDeadLetterEvent(id2);

      expect(await repo.getDeadLetterCount(), 0);
      expect(await dao.getPendingCount(), 1);
    });

    test('transient failures do not land in the DLQ on first push', () async {
      await _insertPending(dao, 'ticket-transient');

      try {
        await repo.pushPendingEvents();
      } catch (_) {}

      // First failure — event is failed but not yet dead.
      expect(await dao.getDeadCount(), 0);
    });
  });
}
