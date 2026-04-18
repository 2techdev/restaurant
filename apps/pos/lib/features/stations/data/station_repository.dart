/// Drift-backed repository for [StationEntity].
///
/// Stations are the KDS grouping primitive: tickets are filtered by station
/// code and printers can be wired per station. The repo seeds a set of Swiss
/// restaurant defaults (Kitchen / Grill / Cold / Dessert / Bar) on first run.
library;

import 'package:drift/drift.dart';
import 'package:flutter/material.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/features/stations/domain/entities/station_entity.dart';

class StationRepository {
  final AppDatabase _db;

  StationRepository(this._db);

  // ---------------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------------

  Stream<List<StationEntity>> watchActiveStations(String tenantId) {
    final query = _db.select(_db.stations)
      ..where(
        (s) => s.tenantId.equals(tenantId) &
            s.isDeleted.equals(false) &
            s.isActive.equals(true),
      )
      ..orderBy([(s) => OrderingTerm.asc(s.sortOrder)]);
    return query.watch().map((rows) => rows.map(_toEntity).toList());
  }

  Stream<List<StationEntity>> watchAllStations(String tenantId) {
    final query = _db.select(_db.stations)
      ..where((s) => s.tenantId.equals(tenantId) & s.isDeleted.equals(false))
      ..orderBy([(s) => OrderingTerm.asc(s.sortOrder)]);
    return query.watch().map((rows) => rows.map(_toEntity).toList());
  }

  Future<List<StationEntity>> getActiveStations(String tenantId) async {
    final query = _db.select(_db.stations)
      ..where(
        (s) => s.tenantId.equals(tenantId) &
            s.isDeleted.equals(false) &
            s.isActive.equals(true),
      )
      ..orderBy([(s) => OrderingTerm.asc(s.sortOrder)]);
    final rows = await query.get();
    return rows.map(_toEntity).toList();
  }

  Future<StationEntity?> getByCode(String tenantId, String code) async {
    final query = _db.select(_db.stations)
      ..where(
        (s) => s.tenantId.equals(tenantId) &
            s.code.equals(code) &
            s.isDeleted.equals(false),
      );
    final row = await query.getSingleOrNull();
    return row == null ? null : _toEntity(row);
  }

  // ---------------------------------------------------------------------------
  // Mutations
  // ---------------------------------------------------------------------------

  Future<void> upsert(StationEntity station) async {
    final now = DateTime.now();
    await _db.into(_db.stations).insertOnConflictUpdate(
          StationsCompanion(
            id: Value(station.id),
            tenantId: Value(station.tenantId),
            code: Value(station.code),
            name: Value(station.name),
            icon: Value(station.icon),
            color: Value(station.color),
            sortOrder: Value(station.sortOrder),
            isDefault: Value(station.isDefault),
            isActive: Value(station.isActive),
            createdAt: Value(now),
            updatedAt: Value(now),
            syncStatus: const Value(0),
            isDeleted: const Value(false),
          ),
        );
  }

  Future<void> setActive(String id, bool isActive) async {
    await (_db.update(_db.stations)..where((s) => s.id.equals(id))).write(
      StationsCompanion(
        isActive: Value(isActive),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Soft-delete a non-default station.
  Future<void> softDelete(String id) async {
    await (_db.update(_db.stations)..where((s) => s.id.equals(id))).write(
      StationsCompanion(
        isDeleted: const Value(true),
        isActive: const Value(false),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Seeding
  // ---------------------------------------------------------------------------

  /// Seed Swiss default stations if the tenant has none.
  ///
  /// Codes match the historical [Products.printerGroup] / [KitchenTicket
  /// .printerGroup] values so existing tickets keep routing to the right
  /// lane without any data migration.
  Future<void> seedDefaults(String tenantId) async {
    final existing = await getActiveStations(tenantId);
    if (existing.isNotEmpty) return;

    final now = DateTime.now();
    final defaults = <StationsCompanion>[
      _defaultRow(
        id: 'station-kitchen',
        tenantId: tenantId,
        code: 'kitchen',
        name: 'Kitchen',
        icon: Icons.local_fire_department,
        color: '#FB923C',
        sortOrder: 1,
        now: now,
      ),
      _defaultRow(
        id: 'station-grill',
        tenantId: tenantId,
        code: 'grill',
        name: 'Grill',
        icon: Icons.outdoor_grill,
        color: '#EF4444',
        sortOrder: 2,
        now: now,
      ),
      _defaultRow(
        id: 'station-cold',
        tenantId: tenantId,
        code: 'cold',
        name: 'Cold / Salads',
        icon: Icons.ac_unit,
        color: '#38BDF8',
        sortOrder: 3,
        now: now,
      ),
      _defaultRow(
        id: 'station-dessert',
        tenantId: tenantId,
        code: 'dessert',
        name: 'Dessert',
        icon: Icons.cake,
        color: '#BF5AF2',
        sortOrder: 4,
        now: now,
      ),
      _defaultRow(
        id: 'station-bar',
        tenantId: tenantId,
        code: 'bar',
        name: 'Bar',
        icon: Icons.local_bar,
        color: '#FACC15',
        sortOrder: 5,
        now: now,
      ),
    ];

    await _db.batch((batch) {
      for (final row in defaults) {
        batch.insert(_db.stations, row, mode: InsertMode.insertOrIgnore);
      }
    });
  }

  StationsCompanion _defaultRow({
    required String id,
    required String tenantId,
    required String code,
    required String name,
    required IconData icon,
    required String color,
    required int sortOrder,
    required DateTime now,
  }) {
    return StationsCompanion(
      id: Value(id),
      tenantId: Value(tenantId),
      code: Value(code),
      name: Value(name),
      icon: Value(icon.codePoint.toString()),
      color: Value(color),
      sortOrder: Value(sortOrder),
      isDefault: const Value(true),
      isActive: const Value(true),
      createdAt: Value(now),
      updatedAt: Value(now),
      syncStatus: const Value(0),
      isDeleted: const Value(false),
    );
  }

  // ---------------------------------------------------------------------------
  // Mapper
  // ---------------------------------------------------------------------------

  StationEntity _toEntity(Station row) {
    return StationEntity(
      id: row.id,
      tenantId: row.tenantId,
      code: row.code,
      name: row.name,
      icon: row.icon,
      color: row.color,
      sortOrder: row.sortOrder,
      isDefault: row.isDefault,
      isActive: row.isActive,
    );
  }
}
