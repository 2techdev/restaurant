/// Drift-backed repository for user-defined function buttons.
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/features/action_buttons/domain/entities/action_button_entity.dart';

class ActionButtonRepository {
  final AppDatabase _db;

  ActionButtonRepository(this._db);

  // ---------------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------------

  Future<List<ActionButtonEntity>> getAll(String tenantId) async {
    final query = _db.select(_db.actionButtons)
      ..where(
        (t) => t.tenantId.equals(tenantId) & t.isDeleted.equals(false),
      )
      ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]);
    final rows = await query.get();
    return rows.map(_toEntity).toList();
  }

  Stream<List<ActionButtonEntity>> watchAll(String tenantId) {
    final query = _db.select(_db.actionButtons)
      ..where(
        (t) => t.tenantId.equals(tenantId) & t.isDeleted.equals(false),
      )
      ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]);
    return query.watch().map((rows) => rows.map(_toEntity).toList());
  }

  /// Stream only active buttons for a given position (used by the POS shell).
  Stream<List<ActionButtonEntity>> watchByPosition(
    String tenantId,
    ActionButtonPosition position,
  ) {
    final query = _db.select(_db.actionButtons)
      ..where(
        (t) =>
            t.tenantId.equals(tenantId) &
            t.isDeleted.equals(false) &
            t.isActive.equals(true) &
            t.position.equals(position.name),
      )
      ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]);
    return query.watch().map((rows) => rows.map(_toEntity).toList());
  }

  Future<ActionButtonEntity?> getById(String id) async {
    final query = _db.select(_db.actionButtons)
      ..where((t) => t.id.equals(id) & t.isDeleted.equals(false));
    final row = await query.getSingleOrNull();
    return row == null ? null : _toEntity(row);
  }

  // ---------------------------------------------------------------------------
  // Mutations
  // ---------------------------------------------------------------------------

  Future<void> insert(ActionButtonEntity e) async {
    final now = DateTime.now();
    await _db.into(_db.actionButtons).insert(
          ActionButtonsCompanion.insert(
            id: e.id,
            tenantId: e.tenantId,
            label: e.label,
            position: e.position.name,
            actionType: e.actionType.name,
            actionPayload: Value(jsonEncode(e.actionPayload)),
            colorValue: Value(e.colorValue),
            iconName: Value(e.iconName),
            sortOrder: Value(e.sortOrder),
            isActive: Value(e.isActive),
            roleFilter: Value(
              e.roleFilter == null ? null : jsonEncode(e.roleFilter),
            ),
            createdAt: now,
            updatedAt: now,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<void> update(ActionButtonEntity e) async {
    final now = DateTime.now();
    await (_db.update(_db.actionButtons)..where((t) => t.id.equals(e.id)))
        .write(
      ActionButtonsCompanion(
        label: Value(e.label),
        colorValue: Value(e.colorValue),
        iconName: Value(e.iconName),
        position: Value(e.position.name),
        actionType: Value(e.actionType.name),
        actionPayload: Value(jsonEncode(e.actionPayload)),
        sortOrder: Value(e.sortOrder),
        isActive: Value(e.isActive),
        roleFilter: Value(
          e.roleFilter == null ? null : jsonEncode(e.roleFilter),
        ),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> softDelete(String id) async {
    await (_db.update(_db.actionButtons)..where((t) => t.id.equals(id))).write(
      ActionButtonsCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> reorder(List<String> orderedIds) async {
    await _db.transaction(() async {
      for (var i = 0; i < orderedIds.length; i++) {
        await (_db.update(_db.actionButtons)
              ..where((t) => t.id.equals(orderedIds[i])))
            .write(
          ActionButtonsCompanion(
            sortOrder: Value(i),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Seed
  // ---------------------------------------------------------------------------

  /// Seed a handful of default buttons on first launch. Idempotent: returns
  /// early if the tenant already has any buttons (active or soft-deleted).
  Future<void> seedDefaults(String tenantId) async {
    final hasAny = await (_db.select(_db.actionButtons)
          ..where((t) => t.tenantId.equals(tenantId)))
        .get();
    if (hasAny.isNotEmpty) return;

    final now = DateTime.now();
    final seeds = <ActionButtonsCompanion>[
      ActionButtonsCompanion.insert(
        id: 'act-seed-pct10',
        tenantId: tenantId,
        label: '%10 Rabatt',
        position: ActionButtonPosition.ticketScreen.name,
        actionType: ActionButtonType.percentDiscount.name,
        actionPayload: Value(jsonEncode({'percent': 10})),
        colorValue: const Value(0xFFF57C00),
        iconName: const Value('percent'),
        sortOrder: const Value(0),
        createdAt: now,
        updatedAt: now,
      ),
      ActionButtonsCompanion.insert(
        id: 'act-seed-gift',
        tenantId: tenantId,
        label: 'Geschenk',
        position: ActionButtonPosition.ticketScreen.name,
        actionType: ActionButtonType.markGift.name,
        actionPayload: const Value('{}'),
        colorValue: const Value(0xFFE53935),
        iconName: const Value('card_giftcard'),
        sortOrder: const Value(1),
        createdAt: now,
        updatedAt: now,
      ),
      ActionButtonsCompanion.insert(
        id: 'act-seed-note',
        tenantId: tenantId,
        label: 'Notiz',
        position: ActionButtonPosition.ticketScreen.name,
        actionType: ActionButtonType.addNote.name,
        actionPayload: const Value('{}'),
        colorValue: const Value(0xFF29B6F6),
        iconName: const Value('sticky_note_2'),
        sortOrder: const Value(2),
        createdAt: now,
        updatedAt: now,
      ),
      ActionButtonsCompanion.insert(
        id: 'act-seed-print',
        tenantId: tenantId,
        label: 'Rechnung',
        position: ActionButtonPosition.ticketScreen.name,
        actionType: ActionButtonType.printBill.name,
        actionPayload: const Value('{}'),
        colorValue: const Value(0xFF66BB6A),
        iconName: const Value('receipt_long'),
        sortOrder: const Value(3),
        createdAt: now,
        updatedAt: now,
      ),
      ActionButtonsCompanion.insert(
        id: 'act-seed-course2',
        tenantId: tenantId,
        label: 'Gang 2',
        position: ActionButtonPosition.ticketScreen.name,
        actionType: ActionButtonType.setCourse.name,
        actionPayload: Value(jsonEncode({'gangId': 'gang-2'})),
        colorValue: const Value(0xFFBF5AF2),
        iconName: const Value('restaurant_menu'),
        sortOrder: const Value(4),
        createdAt: now,
        updatedAt: now,
      ),
    ];

    await _db.batch((batch) {
      for (final s in seeds) {
        batch.insert(_db.actionButtons, s, mode: InsertMode.insertOrIgnore);
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Mapping
  // ---------------------------------------------------------------------------

  ActionButtonEntity _toEntity(ActionButton row) => ActionButtonEntity(
        id: row.id,
        tenantId: row.tenantId,
        label: row.label,
        colorValue: row.colorValue,
        iconName: row.iconName,
        position: ActionButtonPosition.fromString(row.position),
        actionType: ActionButtonType.fromString(row.actionType),
        actionPayload: _decodePayload(row.actionPayload),
        sortOrder: row.sortOrder,
        isActive: row.isActive,
        roleFilter: _decodeRoleFilter(row.roleFilter),
      );

  Map<String, dynamic> _decodePayload(String raw) {
    if (raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  List<String>? _decodeRoleFilter(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.cast<String>();
      return null;
    } catch (_) {
      return null;
    }
  }
}
