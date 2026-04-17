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

  /// Seed the five canonical Gang rows for a tenant if none exist yet.
  ///
  /// We always provision the full 1..5 range (the allowed `maxGangs` ceiling)
  /// so that flipping `RestaurantSettings.maxGangs` upward at runtime doesn't
  /// have to create new rows. The UI shows only the first
  /// `RestaurantSettings.clampedMaxGangs` entries; the rest are inert.
  ///
  /// `name` is stored for debug/back-compat — user-facing labels are sourced
  /// from `RestaurantSettings.effectiveGangLabels`.
  Future<void> seedDefaultGangs(String tenantId) async {
    final existing = await getGangTemplates(tenantId);
    if (existing.isNotEmpty) return;

    final now = DateTime.now();
    const palette = [
      '#90ABFF', // gang 1 — blue
      '#69F6B8', // gang 2 — green
      '#BF5AF2', // gang 3 — purple
      '#FF9F0A', // gang 4 — orange
      '#FF375F', // gang 5 — red
    ];
    final defaults = [
      for (var i = 1; i <= 5; i++)
        GangTemplatesCompanion(
          id: Value('gang-$i'),
          tenantId: Value(tenantId),
          name: Value('Gang $i'),
          sortOrder: Value(i),
          color: Value(palette[i - 1]),
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

  // =========================================================================
  // Mappers
  // =========================================================================

  GangTemplateEntity _gangTemplateToEntity(GangTemplate row) {
    return GangTemplateEntity(
      id: row.id,
      tenantId: row.tenantId,
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
