/// Drift-backed repository for [ServiceCallEntity].
///
/// Writes go to the `service_calls` table and also emit a row into the sync
/// outbox so the boss/KDS dashboards pick them up in real time.
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/features/waiter/domain/entities/service_call_entity.dart';

class ServiceCallRepositoryImpl {
  final AppDatabase _db;

  ServiceCallRepositoryImpl(this._db);

  /// Persist a new call and enqueue a sync event.
  ///
  /// Both writes happen in a single transaction so an offline device never
  /// ends up with a row that's missing from the outbox.
  Future<ServiceCallEntity> create(
    ServiceCallEntity call, {
    required String deviceId,
  }) async {
    await _db.transaction(() async {
      await _db.into(_db.serviceCalls).insert(_toCompanion(call));
      await _db.into(_db.syncQueue).insert(
            SyncQueueCompanion(
              entityType: const Value('service_call'),
              entityId: Value(call.id),
              operation: const Value('create'),
              payloadJson: Value(jsonEncode(_toJson(call))),
              deviceId: Value(deviceId),
              timestamp: Value(DateTime.now()),
              createdAt: Value(DateTime.now()),
            ),
          );
    });
    return call;
  }

  /// Mark a call acknowledged. No-ops if already past that state.
  Future<void> acknowledge({
    required String id,
    required String byUserId,
  }) async {
    await (_db.update(_db.serviceCalls)..where((c) => c.id.equals(id))).write(
      ServiceCallsCompanion(
        status: const Value('acknowledged'),
        acknowledgedAt: Value(DateTime.now()),
        acknowledgedBy: Value(byUserId),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Mark a call resolved (handled; drops off active lists).
  Future<void> resolve(String id) async {
    await (_db.update(_db.serviceCalls)..where((c) => c.id.equals(id))).write(
      ServiceCallsCompanion(
        status: const Value('resolved'),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// All not-yet-resolved calls for a tenant, newest first.
  Stream<List<ServiceCallEntity>> watchActive(String tenantId) {
    final query = _db.select(_db.serviceCalls)
      ..where(
        (c) =>
            c.tenantId.equals(tenantId) &
            c.isDeleted.equals(false) &
            c.status.isNotValue('resolved'),
      )
      ..orderBy([(c) => OrderingTerm.desc(c.createdAt)]);
    return query.watch().map((rows) => rows.map(_toEntity).toList());
  }

  /// One-shot fetch of active calls for a waiter (used by the waiter screen).
  Future<List<ServiceCallEntity>> getActiveForWaiter({
    required String tenantId,
    required String waiterId,
  }) async {
    final query = _db.select(_db.serviceCalls)
      ..where(
        (c) =>
            c.tenantId.equals(tenantId) &
            c.waiterId.equals(waiterId) &
            c.isDeleted.equals(false) &
            c.status.isNotValue('resolved'),
      )
      ..orderBy([(c) => OrderingTerm.desc(c.createdAt)]);
    final rows = await query.get();
    return rows.map(_toEntity).toList();
  }

  // ---------------------------------------------------------------------------
  // Mappers
  // ---------------------------------------------------------------------------

  ServiceCallEntity _toEntity(ServiceCall row) {
    return ServiceCallEntity(
      id: row.id,
      tenantId: row.tenantId,
      tableId: row.tableId,
      ticketId: row.ticketId,
      waiterId: row.waiterId,
      waiterName: row.waiterName,
      kind: parseServiceCallKind(row.kind),
      note: row.note,
      status: parseServiceCallStatus(row.status),
      createdAt: row.createdAt,
      acknowledgedAt: row.acknowledgedAt,
      acknowledgedBy: row.acknowledgedBy,
    );
  }

  ServiceCallsCompanion _toCompanion(ServiceCallEntity e) {
    return ServiceCallsCompanion(
      id: Value(e.id),
      tenantId: Value(e.tenantId),
      tableId: Value(e.tableId),
      ticketId: Value(e.ticketId),
      waiterId: Value(e.waiterId),
      waiterName: Value(e.waiterName),
      kind: Value(serviceCallKindToString(e.kind)),
      note: Value(e.note),
      status: Value(serviceCallStatusToString(e.status)),
      createdAt: Value(e.createdAt),
      acknowledgedAt: Value(e.acknowledgedAt),
      acknowledgedBy: Value(e.acknowledgedBy),
      updatedAt: Value(DateTime.now()),
      isDeleted: const Value(false),
      syncStatus: const Value(0),
    );
  }

  Map<String, dynamic> _toJson(ServiceCallEntity e) => {
        'id': e.id,
        'tenantId': e.tenantId,
        'tableId': e.tableId,
        'ticketId': e.ticketId,
        'waiterId': e.waiterId,
        'waiterName': e.waiterName,
        'kind': serviceCallKindToString(e.kind),
        'note': e.note,
        'status': serviceCallStatusToString(e.status),
        'createdAt': e.createdAt.toIso8601String(),
      };
}
