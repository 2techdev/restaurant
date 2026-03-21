/// Drift-backed implementation of the reservation repository.
///
/// Manages restaurant reservations: CRUD, conflict detection,
/// status transitions, and real-time streams.
library;

import 'package:drift/drift.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/reservations/domain/entities/reservation_entity.dart';

class ReservationRepositoryImpl {
  final AppDatabase _db;

  ReservationRepositoryImpl(this._db);

  // =========================================================================
  // Queries
  // =========================================================================

  /// All active reservations for a given date, ordered by start time.
  Future<List<ReservationEntity>> getReservationsForDate(
    String tenantId,
    DateTime date,
  ) async {
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final query = _db.select(_db.reservations)
      ..where(
        (r) =>
            r.tenantId.equals(tenantId) &
            r.isDeleted.equals(false) &
            r.date.isBiggerOrEqualValue(dayStart) &
            r.date.isSmallerThanValue(dayEnd),
      )
      ..orderBy([(r) => OrderingTerm.asc(r.timeStart)]);
    return (await query.get()).map(_toEntity).toList();
  }

  /// Real-time stream of reservations for a specific date.
  Stream<List<ReservationEntity>> watchReservationsForDate(
    String tenantId,
    DateTime date,
  ) {
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    return (_db.select(_db.reservations)
          ..where(
            (r) =>
                r.tenantId.equals(tenantId) &
                r.isDeleted.equals(false) &
                r.date.isBiggerOrEqualValue(dayStart) &
                r.date.isSmallerThanValue(dayEnd),
          )
          ..orderBy([(r) => OrderingTerm.asc(r.timeStart)]))
        .watch()
        .map((rows) => rows.map(_toEntity).toList());
  }

  /// Today's + upcoming reservations (active statuses only).
  Stream<List<ReservationEntity>> watchUpcomingReservations(String tenantId) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    return (_db.select(_db.reservations)
          ..where(
            (r) =>
                r.tenantId.equals(tenantId) &
                r.isDeleted.equals(false) &
                r.date.isBiggerOrEqualValue(todayStart) &
                (r.status.equals('pending') | r.status.equals('confirmed')),
          )
          ..orderBy([
            (r) => OrderingTerm.asc(r.date),
            (r) => OrderingTerm.asc(r.timeStart),
          ]))
        .watch()
        .map((rows) => rows.map(_toEntity).toList());
  }

  /// Reservations for a specific table on a given date (for conflict checks).
  Future<List<ReservationEntity>> getReservationsForTable(
    String tableId,
    DateTime date,
  ) async {
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final query = _db.select(_db.reservations)
      ..where(
        (r) =>
            r.tableId.equals(tableId) &
            r.isDeleted.equals(false) &
            r.date.isBiggerOrEqualValue(dayStart) &
            r.date.isSmallerThanValue(dayEnd) &
            (r.status.equals('pending') | r.status.equals('confirmed') | r.status.equals('seated')),
      )
      ..orderBy([(r) => OrderingTerm.asc(r.timeStart)]);
    return (await query.get()).map(_toEntity).toList();
  }

  /// Fetch a single reservation by ID.
  Future<ReservationEntity?> getById(String id) async {
    final row = await (_db.select(_db.reservations)
          ..where((r) => r.id.equals(id) & r.isDeleted.equals(false)))
        .getSingleOrNull();
    return row != null ? _toEntity(row) : null;
  }

  /// Watch a single reservation for real-time updates.
  Stream<ReservationEntity?> watchById(String id) {
    return (_db.select(_db.reservations)
          ..where((r) => r.id.equals(id) & r.isDeleted.equals(false)))
        .watchSingleOrNull()
        .map((row) => row != null ? _toEntity(row) : null);
  }

  // =========================================================================
  // Conflict detection
  // =========================================================================

  /// Returns true if [tableId] already has an active reservation overlapping
  /// the [timeStart]–[timeEnd] window on [date]. Excludes [excludeId].
  Future<bool> hasConflict({
    required String tableId,
    required DateTime date,
    required DateTime timeStart,
    required DateTime timeEnd,
    String? excludeId,
  }) async {
    final existing = await getReservationsForTable(tableId, date);
    for (final r in existing) {
      if (excludeId != null && r.id == excludeId) continue;
      // Overlap: start < other.end AND end > other.start
      if (timeStart.isBefore(r.timeEnd) && timeEnd.isAfter(r.timeStart)) {
        return true;
      }
    }
    return false;
  }

  // =========================================================================
  // CRUD
  // =========================================================================

  Future<ReservationEntity> create({
    required String tenantId,
    required String customerName,
    String? customerPhone,
    String? customerEmail,
    String? tableId,
    required DateTime date,
    required DateTime timeStart,
    required DateTime timeEnd,
    int partySize = 2,
    ReservationStatus status = ReservationStatus.pending,
    String? notes,
    ReservationChannel channel = ReservationChannel.walkIn,
    String? createdBy,
  }) async {
    final id = IdGenerator.generateId();
    final now = DateTime.now();
    await _db.into(_db.reservations).insert(ReservationsCompanion(
          id: Value(id),
          tenantId: Value(tenantId),
          customerName: Value(customerName),
          customerPhone: Value(customerPhone),
          customerEmail: Value(customerEmail),
          tableId: Value(tableId),
          date: Value(date),
          timeStart: Value(timeStart),
          timeEnd: Value(timeEnd),
          partySize: Value(partySize),
          status: Value(status.value),
          notes: Value(notes),
          channel: Value(channel.value),
          createdAt: Value(now),
          createdBy: Value(createdBy),
          updatedAt: Value(now),
        ));
    return ReservationEntity(
      id: id,
      tenantId: tenantId,
      customerName: customerName,
      customerPhone: customerPhone,
      customerEmail: customerEmail,
      tableId: tableId,
      date: date,
      timeStart: timeStart,
      timeEnd: timeEnd,
      partySize: partySize,
      status: status,
      notes: notes,
      channel: channel,
      createdAt: now,
      createdBy: createdBy,
    );
  }

  Future<void> update({
    required String id,
    String? customerName,
    String? customerPhone,
    String? customerEmail,
    String? tableId,
    DateTime? date,
    DateTime? timeStart,
    DateTime? timeEnd,
    int? partySize,
    ReservationStatus? status,
    String? notes,
    ReservationChannel? channel,
  }) async {
    final current = await (_db.select(_db.reservations)
          ..where((r) => r.id.equals(id)))
        .getSingleOrNull();
    if (current == null) return;

    await (_db.update(_db.reservations)..where((r) => r.id.equals(id))).write(
      ReservationsCompanion(
        customerName: Value(customerName ?? current.customerName),
        customerPhone: Value(customerPhone ?? current.customerPhone),
        customerEmail: Value(customerEmail ?? current.customerEmail),
        tableId: Value(tableId ?? current.tableId),
        date: Value(date ?? current.date),
        timeStart: Value(timeStart ?? current.timeStart),
        timeEnd: Value(timeEnd ?? current.timeEnd),
        partySize: Value(partySize ?? current.partySize),
        status: Value(status?.value ?? current.status),
        notes: Value(notes ?? current.notes),
        channel: Value(channel?.value ?? current.channel),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> updateStatus(String id, ReservationStatus status) async {
    await (_db.update(_db.reservations)..where((r) => r.id.equals(id))).write(
      ReservationsCompanion(
        status: Value(status.value),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Soft-delete a reservation.
  Future<void> delete(String id) async {
    await (_db.update(_db.reservations)..where((r) => r.id.equals(id))).write(
      ReservationsCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  // =========================================================================
  // Mapper
  // =========================================================================

  ReservationEntity _toEntity(Reservation row) {
    return ReservationEntity(
      id: row.id,
      tenantId: row.tenantId,
      customerName: row.customerName,
      customerPhone: row.customerPhone,
      customerEmail: row.customerEmail,
      tableId: row.tableId,
      date: row.date,
      timeStart: row.timeStart,
      timeEnd: row.timeEnd,
      partySize: row.partySize,
      status: ReservationStatus.fromString(row.status),
      notes: row.notes,
      channel: ReservationChannel.fromString(row.channel),
      createdAt: row.createdAt,
      createdBy: row.createdBy,
    );
  }
}
