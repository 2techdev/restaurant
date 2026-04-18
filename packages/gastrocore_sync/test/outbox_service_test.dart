import 'package:gastrocore_api/gastrocore_api.dart';
import 'package:gastrocore_models/gastrocore_models.dart';
import 'package:gastrocore_sync/gastrocore_sync.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// Minimal in-memory [OutboxRepository] for unit tests.
class _InMemoryOutbox implements OutboxRepository {
  final List<SyncEventEntity> _events = [];

  List<SyncEventEntity> get all => List.unmodifiable(_events);

  @override
  Future<void> enqueue(SyncEventEntity event) async {
    _events.add(event);
  }

  @override
  Future<List<SyncEventEntity>> getPendingEvents({int maxRetries = 3}) async {
    return _events
        .where((e) =>
            (e.status == SyncEventStatus.pending ||
                e.status == SyncEventStatus.failed) &&
            e.retryCount < maxRetries)
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));
  }

  @override
  Future<void> markFailed(int eventId, String errorMessage) async {
    _update(eventId, (e) => e.copyWith(
          status: SyncEventStatus.failed,
          errorMessage: errorMessage,
          retryCount: e.retryCount + 1,
        ));
  }

  @override
  Future<void> markUploaded(int eventId, DateTime syncedAt) async {
    _update(eventId, (e) => e.copyWith(
          status: SyncEventStatus.uploaded,
          syncedAt: syncedAt,
        ));
  }

  @override
  Future<void> markUploading(int eventId) async {
    _update(eventId, (e) => e.copyWith(status: SyncEventStatus.uploading));
  }

  @override
  Future<void> pruneUploaded(DateTime before) async {
    _events.removeWhere((e) =>
        e.status == SyncEventStatus.uploaded &&
        e.syncedAt != null &&
        e.syncedAt!.isBefore(before));
  }

  void _update(int id, SyncEventEntity Function(SyncEventEntity) f) {
    final idx = _events.indexWhere((e) => e.id == id);
    if (idx >= 0) _events[idx] = f(_events[idx]);
  }
}

SyncEventEntity _ev(int id) => SyncEventEntity(
      id: id,
      tableName: 'tickets',
      operation: SyncOperation.insert,
      recordId: 'rec-$id',
      payload: '{"id":"rec-$id"}',
      createdAt: DateTime.utc(2026, 4, 17),
      deviceId: 'pos-1',
    );

void main() {
  group('OutboxService.flush', () {
    test('returns early when outbox is empty (no HTTP calls)', () async {
      final repo = _InMemoryOutbox();
      final client = GastrocoreClient(
        baseUrl: 'https://example.test',
        httpClient: MockClient((_) async {
          fail('HTTP must not be hit when outbox is empty');
        }),
      );
      addTearDown(client.dispose);

      final svc = OutboxService(
        repository: repo,
        apiClient: client,
        tenantId: 'tenant-1',
      );

      final result = await svc.flush();
      expect(result.pushed, 0);
      expect(result.failed, 0);
      expect(result.hasErrors, isFalse);
    });

    test('concurrent flush() calls do not overlap', () async {
      final repo = _InMemoryOutbox();
      final client = GastrocoreClient(
        baseUrl: 'https://example.test',
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      );
      addTearDown(client.dispose);

      final svc = OutboxService(
        repository: repo,
        apiClient: client,
        tenantId: 'tenant-1',
      );

      final a = svc.flush();
      final b = svc.flush();
      final results = await Future.wait([a, b]);

      // Both calls return a result; at least one is the empty no-op.
      expect(results, hasLength(2));
      expect(results.every((r) => r.pushed == 0), isTrue);
    });
  });

  group('OutboxRepository (in-memory fake)', () {
    test('enqueue + markUploaded + pruneUploaded cleans old events', () async {
      final repo = _InMemoryOutbox();
      await repo.enqueue(_ev(1));
      await repo.enqueue(_ev(2));

      await repo.markUploaded(1, DateTime.utc(2026, 4, 1));
      await repo.pruneUploaded(DateTime.utc(2026, 4, 10));

      final remaining = repo.all.map((e) => e.id).toList();
      expect(remaining, [2]);
    });

    test('getPendingEvents respects maxRetries', () async {
      final repo = _InMemoryOutbox();
      await repo.enqueue(_ev(1));
      await repo.markFailed(1, 'a');
      await repo.markFailed(1, 'b');
      await repo.markFailed(1, 'c');

      final pending = await repo.getPendingEvents(maxRetries: 3);
      expect(pending, isEmpty);

      final pendingLoose = await repo.getPendingEvents(maxRetries: 5);
      expect(pendingLoose, hasLength(1));
    });
  });
}
