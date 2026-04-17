/// Unit tests for [ServiceCallRepositoryImpl].
///
/// Exercises the create → acknowledge → resolve lifecycle against an
/// in-memory Drift database, and checks that each creation enqueues a matching
/// sync-outbox row (so offline waiter calls bubble up once connectivity
/// returns).
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/core/data/app_initializer.dart';
import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/waiter/data/repositories/service_call_repository_impl.dart';
import 'package:gastrocore_pos/features/waiter/domain/entities/service_call_entity.dart';

const _tenantId = 'tenant-sc-test';
const _deviceId = 'DEV-SC-01';
const _waiterId = 'user-waiter-1';
const _waiterName = 'Luca';

Future<({AppDatabase db, ServiceCallRepositoryImpl repo})> _setup() async {
  final db = AppDatabase.createInMemory();
  await AppInitializer.initialize(db);
  return (db: db, repo: ServiceCallRepositoryImpl(db));
}

ServiceCallEntity _makeCall({
  ServiceCallKind kind = ServiceCallKind.water,
  String? tableId,
  String? note,
}) {
  return ServiceCallEntity(
    id: IdGenerator.generateId(),
    tenantId: _tenantId,
    waiterId: _waiterId,
    waiterName: _waiterName,
    kind: kind,
    tableId: tableId,
    note: note,
    createdAt: DateTime(2026, 4, 17, 12, 0),
  );
}

void main() {
  group('ServiceCallRepositoryImpl', () {
    test('create persists the call and enqueues one sync event', () async {
      final (:db, :repo) = await _setup();
      addTearDown(db.close);

      final call = _makeCall(
        kind: ServiceCallKind.water,
        tableId: 'T-1',
        note: 'extra ice',
      );
      await repo.create(call, deviceId: _deviceId);

      final stored = await db.select(db.serviceCalls).get();
      expect(stored, hasLength(1));
      expect(stored.single.kind, 'water');
      expect(stored.single.note, 'extra ice');
      expect(stored.single.status, 'pending');

      final outbox = await (db.select(db.syncQueue)
            ..where((r) => r.entityType.equals('service_call')))
          .get();
      expect(outbox, hasLength(1));
      expect(outbox.single.entityId, call.id);
      expect(outbox.single.operation, 'create');
      expect(outbox.single.deviceId, _deviceId);
      final payload = jsonDecode(outbox.single.payloadJson) as Map;
      expect(payload['kind'], 'water');
      expect(payload['waiterId'], _waiterId);
    });

    test('acknowledge moves a pending call to acknowledged + stamps actor',
        () async {
      final (:db, :repo) = await _setup();
      addTearDown(db.close);

      final call = _makeCall();
      await repo.create(call, deviceId: _deviceId);
      await repo.acknowledge(id: call.id, byUserId: 'mgr-1');

      final row = await (db.select(db.serviceCalls)
            ..where((c) => c.id.equals(call.id)))
          .getSingle();
      expect(row.status, 'acknowledged');
      expect(row.acknowledgedBy, 'mgr-1');
      expect(row.acknowledgedAt, isNotNull);
    });

    test('resolve drops the call from the active stream', () async {
      final (:db, :repo) = await _setup();
      addTearDown(db.close);

      final a = _makeCall(kind: ServiceCallKind.bread);
      final b = _makeCall(kind: ServiceCallKind.manager);
      await repo.create(a, deviceId: _deviceId);
      await repo.create(b, deviceId: _deviceId);

      await repo.resolve(a.id);

      final active = await repo.watchActive(_tenantId).first;
      expect(active.map((c) => c.id).toList(), [b.id]);
    });

    test('getActiveForWaiter filters by waiter id', () async {
      final (:db, :repo) = await _setup();
      addTearDown(db.close);

      final mine = _makeCall(kind: ServiceCallKind.water);
      await repo.create(mine, deviceId: _deviceId);

      // Insert another waiter's call directly and ensure it's excluded.
      final other = _makeCall(kind: ServiceCallKind.cleanup)
          .copyWith(waiterId: 'other-waiter');
      await db.into(db.serviceCalls).insert(
            ServiceCallsCompanion(
              id: Value(other.id),
              tenantId: Value(other.tenantId),
              waiterId: Value(other.waiterId),
              waiterName: Value(other.waiterName),
              kind: Value(serviceCallKindToString(other.kind)),
              status: const Value('pending'),
              createdAt: Value(other.createdAt),
              updatedAt: Value(DateTime.now()),
            ),
          );

      final mineOnly = await repo.getActiveForWaiter(
        tenantId: _tenantId,
        waiterId: _waiterId,
      );
      expect(mineOnly.map((c) => c.id).toList(), [mine.id]);
    });
  });
}
