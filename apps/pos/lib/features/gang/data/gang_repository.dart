/// Gang repository — CRUD for gang_templates and order_gang_states.
library;

import 'package:drift/drift.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/features/gang/domain/entities/gang_template_entity.dart';

class GangRepository {
  final AppDatabase _db;

  GangRepository(this._db);

  // =========================================================================
  // Gang Templates
  // =========================================================================

  /// Watch all active gang templates for [tenantId], sorted by sortOrder.
  Stream<List<GangTemplateEntity>> watchGangTemplates(String tenantId) {
    final query = _db.select(_db.gangTemplates)
      ..where(
        (t) => t.tenantId.equals(tenantId) &
            t.isDeleted.equals(false) &
            t.isActive.equals(true),
      )
      ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]);
    return query.watch().map(
          (rows) => rows.map(_gangTemplateToEntity).toList(),
        );
  }

  /// Fetch all active gang templates once.
  Future<List<GangTemplateEntity>> getGangTemplates(String tenantId) async {
    final query = _db.select(_db.gangTemplates)
      ..where(
        (t) => t.tenantId.equals(tenantId) &
            t.isDeleted.equals(false) &
            t.isActive.equals(true),
      )
      ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]);
    final rows = await query.get();
    return rows.map(_gangTemplateToEntity).toList();
  }

  /// Get a single gang template by id.
  Future<GangTemplateEntity?> getGangTemplateById(String id) async {
    final query = _db.select(_db.gangTemplates)
      ..where((t) => t.id.equals(id) & t.isDeleted.equals(false));
    final row = await query.getSingleOrNull();
    return row == null ? null : _gangTemplateToEntity(row);
  }

  /// Seed the three canonical Gangs for a tenant if none exist yet.
  ///
  /// Policy (2026-04-17 decision): Gang labels are fixed — **"Gang 1", "Gang
  /// 2", "Gang 3"** — and cannot be renamed. Seed and UI are kept in lock-step
  /// so both a fresh install and an override attempt end up displaying the
  /// same literal label to the cook.
  ///
  /// Per-gang color (used for the KDS card header + per-gang alert banner):
  ///   Gang 1 → #90ABFF (primary blue)
  ///   Gang 2 → #69F6B8 (green)
  ///   Gang 3 → #BF5AF2 (purple)
  Future<void> seedDefaultGangs(String tenantId) async {
    final existing = await getGangTemplates(tenantId);
    if (existing.isNotEmpty) {
      // Rewrite legacy default names (Vorspeise / Hauptgang / Dessert) to
      // the canonical "Gang N" label so dev installs that pre-date the fixed
      // label policy converge on the new standard on next launch.
      await _rewriteDefaultGangNames(tenantId);
      return;
    }

    final now = DateTime.now();
    final defaults = [
      GangTemplatesCompanion(
        id: const Value('gang-1'),
        tenantId: Value(tenantId),
        name: const Value('Gang 1'),
        sortOrder: const Value(1),
        color: const Value('#90ABFF'),
        isDefault: const Value(true),
        isActive: const Value(true),
        createdAt: Value(now),
        updatedAt: Value(now),
        syncStatus: const Value(0),
        isDeleted: const Value(false),
      ),
      GangTemplatesCompanion(
        id: const Value('gang-2'),
        tenantId: Value(tenantId),
        name: const Value('Gang 2'),
        sortOrder: const Value(2),
        color: const Value('#69F6B8'),
        isDefault: const Value(true),
        isActive: const Value(true),
        createdAt: Value(now),
        updatedAt: Value(now),
        syncStatus: const Value(0),
        isDeleted: const Value(false),
      ),
      GangTemplatesCompanion(
        id: const Value('gang-3'),
        tenantId: Value(tenantId),
        name: const Value('Gang 3'),
        sortOrder: const Value(3),
        color: const Value('#BF5AF2'),
        isDefault: const Value(true),
        isActive: const Value(true),
        createdAt: Value(now),
        updatedAt: Value(now),
        syncStatus: const Value(0),
        isDeleted: const Value(false),
      ),
    ];

    await _db.batch((batch) {
      for (final gang in defaults) {
        batch.insert(
          _db.gangTemplates,
          gang,
          mode: InsertMode.insertOrIgnore,
        );
      }
    });
  }

  /// Force default-Gang rows onto the canonical `Gang N` label.
  ///
  /// Only touches rows where `isDefault == true` — tenant-specific renames
  /// would be respected, but today `isDefault` is the only shipped Gang.
  Future<void> _rewriteDefaultGangNames(String tenantId) async {
    for (var i = 1; i <= 3; i++) {
      await (_db.update(_db.gangTemplates)
            ..where((t) =>
                t.tenantId.equals(tenantId) &
                t.isDefault.equals(true) &
                t.sortOrder.equals(i) &
                t.name.equals('Gang $i').not()))
          .write(GangTemplatesCompanion(
        name: Value('Gang $i'),
        updatedAt: Value(DateTime.now()),
      ));
    }
  }

  // =========================================================================
  // Order Gang States
  // =========================================================================

  /// Get the Gang state for a specific (ticket, gangTemplate) pair.
  Future<OrderGangStateEntity?> getOrderGangState(
    String ticketId,
    String gangTemplateId,
  ) async {
    final query = _db.select(_db.orderGangStates)
      ..where(
        (t) =>
            t.ticketId.equals(ticketId) &
            t.gangTemplateId.equals(gangTemplateId) &
            t.isDeleted.equals(false),
      );
    final row = await query.getSingleOrNull();
    return row == null ? null : _gangStateToEntity(row);
  }

  /// Watch all gang states for a ticket.
  Stream<List<OrderGangStateEntity>> watchOrderGangStates(String ticketId) {
    final query = _db.select(_db.orderGangStates)
      ..where(
        (t) => t.ticketId.equals(ticketId) & t.isDeleted.equals(false),
      );
    return query.watch().map((rows) => rows.map(_gangStateToEntity).toList());
  }

  /// Fetch all gang states for a ticket (once).
  Future<List<OrderGangStateEntity>> getOrderGangStates(
      String ticketId) async {
    final query = _db.select(_db.orderGangStates)
      ..where(
        (t) => t.ticketId.equals(ticketId) & t.isDeleted.equals(false),
      );
    final rows = await query.get();
    return rows.map(_gangStateToEntity).toList();
  }

  /// Ensure a gang state row exists for (ticketId, gangTemplateId).
  /// Creates one in 'pending' state if missing.
  Future<OrderGangStateEntity> ensureGangState({
    required String id,
    required String tenantId,
    required String ticketId,
    required String gangTemplateId,
  }) async {
    final existing = await getOrderGangState(ticketId, gangTemplateId);
    if (existing != null) return existing;

    final now = DateTime.now();
    final companion = OrderGangStatesCompanion(
      id: Value(id),
      tenantId: Value(tenantId),
      ticketId: Value(ticketId),
      gangTemplateId: Value(gangTemplateId),
      status: const Value('pending'),
      createdAt: Value(now),
      updatedAt: Value(now),
      syncStatus: const Value(0),
      isDeleted: const Value(false),
    );
    await _db.into(_db.orderGangStates).insert(
          companion,
          mode: InsertMode.insertOrIgnore,
        );
    return (await getOrderGangState(ticketId, gangTemplateId))!;
  }

  /// Fire a Gang — transition to 'fired' and stamp firedAt.
  Future<void> fireGang(String ticketId, String gangTemplateId) async {
    final now = DateTime.now();
    await (_db.update(_db.orderGangStates)
          ..where(
            (t) =>
                t.ticketId.equals(ticketId) &
                t.gangTemplateId.equals(gangTemplateId),
          ))
        .write(
      OrderGangStatesCompanion(
        status: const Value('fired'),
        firedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  /// Mark a Gang as ready.
  Future<void> markGangReady(String ticketId, String gangTemplateId) async {
    final now = DateTime.now();
    await (_db.update(_db.orderGangStates)
          ..where(
            (t) =>
                t.ticketId.equals(ticketId) &
                t.gangTemplateId.equals(gangTemplateId),
          ))
        .write(
      OrderGangStatesCompanion(
        status: const Value('ready'),
        readyAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  /// Mark a Gang as served.
  Future<void> markGangServed(String ticketId, String gangTemplateId) async {
    final now = DateTime.now();
    await (_db.update(_db.orderGangStates)
          ..where(
            (t) =>
                t.ticketId.equals(ticketId) &
                t.gangTemplateId.equals(gangTemplateId),
          ))
        .write(
      OrderGangStatesCompanion(
        status: const Value('served'),
        servedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  /// Recall a Gang back one step in the lifecycle.
  ///
  /// Accepts [toStatus] as the target state and clears the later-stage
  /// timestamp(s) so the recall looks and behaves like the gang never reached
  /// them. Used by the KDS card when a cook taps-by-mistake and long-presses
  /// to undo: served → ready, ready → fired, fired → pending.
  ///
  /// Only `pending`, `fired`, and `ready` are valid recall targets — you can't
  /// recall *to* served or in_prep from here (no UX need yet).
  Future<void> recallGang({
    required String ticketId,
    required String gangTemplateId,
    required GangOrderStatus toStatus,
  }) async {
    final now = DateTime.now();
    final companion = switch (toStatus) {
      GangOrderStatus.pending => OrderGangStatesCompanion(
          status: const Value('pending'),
          firedAt: const Value(null),
          readyAt: const Value(null),
          servedAt: const Value(null),
          updatedAt: Value(now),
        ),
      GangOrderStatus.fired => OrderGangStatesCompanion(
          status: const Value('fired'),
          readyAt: const Value(null),
          servedAt: const Value(null),
          updatedAt: Value(now),
        ),
      GangOrderStatus.ready => OrderGangStatesCompanion(
          status: const Value('ready'),
          servedAt: const Value(null),
          updatedAt: Value(now),
        ),
      _ => throw ArgumentError(
          'recallGang: toStatus must be pending/fired/ready, got $toStatus'),
    };
    await (_db.update(_db.orderGangStates)
          ..where(
            (t) =>
                t.ticketId.equals(ticketId) &
                t.gangTemplateId.equals(gangTemplateId),
          ))
        .write(companion);
  }

  // =========================================================================
  // Mappers
  // =========================================================================

  GangTemplateEntity _gangTemplateToEntity(GangTemplate row) {
    return GangTemplateEntity(
      id: row.id,
      tenantId: row.tenantId,
      name: row.name,
      sortOrder: row.sortOrder,
      color: row.color,
      isDefault: row.isDefault,
      isActive: row.isActive,
    );
  }

  OrderGangStateEntity _gangStateToEntity(OrderGangState row) {
    return OrderGangStateEntity(
      id: row.id,
      tenantId: row.tenantId,
      ticketId: row.ticketId,
      gangTemplateId: row.gangTemplateId,
      status: GangOrderStatusX.fromDb(row.status),
      createdAt: row.createdAt,
      firedAt: row.firedAt,
      readyAt: row.readyAt,
      servedAt: row.servedAt,
    );
  }
}
