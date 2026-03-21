/// Riverpod providers for the reservation feature.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/features/reservations/data/repositories/reservation_repository_impl.dart';
import 'package:gastrocore_pos/features/reservations/domain/entities/reservation_entity.dart';

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

final reservationRepositoryProvider = Provider<ReservationRepositoryImpl>((ref) {
  return ReservationRepositoryImpl(ref.watch(databaseProvider));
});

// ---------------------------------------------------------------------------
// Date selection
// ---------------------------------------------------------------------------

/// Selected calendar date (defaults to today).
final selectedReservationDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

// ---------------------------------------------------------------------------
// Streams
// ---------------------------------------------------------------------------

/// Real-time reservations for the currently selected date.
final reservationsForDateProvider =
    StreamProvider<List<ReservationEntity>>((ref) {
  final repo = ref.watch(reservationRepositoryProvider);
  final tenantId = ref.watch(tenantIdProvider);
  final date = ref.watch(selectedReservationDateProvider);
  return repo.watchReservationsForDate(tenantId, date);
});

/// Upcoming + today's reservations (active statuses only).
final upcomingReservationsProvider =
    StreamProvider<List<ReservationEntity>>((ref) {
  final repo = ref.watch(reservationRepositoryProvider);
  final tenantId = ref.watch(tenantIdProvider);
  return repo.watchUpcomingReservations(tenantId);
});

/// Watch a single reservation by ID.
final reservationByIdProvider =
    StreamProvider.family<ReservationEntity?, String>((ref, id) {
  final repo = ref.watch(reservationRepositoryProvider);
  return repo.watchById(id);
});

// ---------------------------------------------------------------------------
// Reservation management notifier
// ---------------------------------------------------------------------------

class ReservationManagementState {
  final bool isLoading;
  final String? error;
  final String? conflictTableId;

  const ReservationManagementState({
    this.isLoading = false,
    this.error,
    this.conflictTableId,
  });

  ReservationManagementState copyWith({
    bool? isLoading,
    String? error,
    String? conflictTableId,
  }) {
    return ReservationManagementState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      conflictTableId: conflictTableId,
    );
  }
}

class ReservationManagementNotifier
    extends StateNotifier<ReservationManagementState> {
  final ReservationRepositoryImpl _repo;
  final Ref _ref;

  ReservationManagementNotifier(this._repo, this._ref)
      : super(const ReservationManagementState());

  String get _tenantId => _ref.read(tenantIdProvider);

  /// Create a new reservation, checking for conflicts first.
  /// Returns the created entity, or null if conflict / error.
  Future<ReservationEntity?> createReservation({
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
    state = state.copyWith(isLoading: true);
    try {
      if (tableId != null) {
        final conflict = await _repo.hasConflict(
          tableId: tableId,
          date: date,
          timeStart: timeStart,
          timeEnd: timeEnd,
        );
        if (conflict) {
          state = ReservationManagementState(conflictTableId: tableId);
          return null;
        }
      }
      final entity = await _repo.create(
        tenantId: _tenantId,
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
        createdBy: createdBy,
      );
      state = state.copyWith(isLoading: false);
      return entity;
    } catch (e) {
      state = ReservationManagementState(error: e.toString());
      return null;
    }
  }

  /// Update an existing reservation with conflict check.
  Future<bool> updateReservation({
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
    state = state.copyWith(isLoading: true);
    try {
      if (tableId != null && timeStart != null && timeEnd != null && date != null) {
        final conflict = await _repo.hasConflict(
          tableId: tableId,
          date: date,
          timeStart: timeStart,
          timeEnd: timeEnd,
          excludeId: id,
        );
        if (conflict) {
          state = ReservationManagementState(conflictTableId: tableId);
          return false;
        }
      }
      await _repo.update(
        id: id,
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
      );
      state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      state = ReservationManagementState(error: e.toString());
      return false;
    }
  }

  Future<void> updateStatus(String id, ReservationStatus status) async {
    try {
      await _repo.updateStatus(id, status);
    } catch (e) {
      state = ReservationManagementState(error: e.toString());
    }
  }

  Future<void> markSeated(String id) => updateStatus(id, ReservationStatus.seated);
  Future<void> markConfirmed(String id) => updateStatus(id, ReservationStatus.confirmed);
  Future<void> markCancelled(String id) => updateStatus(id, ReservationStatus.cancelled);
  Future<void> markNoShow(String id) => updateStatus(id, ReservationStatus.noShow);

  Future<void> deleteReservation(String id) async {
    state = state.copyWith(isLoading: true);
    try {
      await _repo.delete(id);
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = ReservationManagementState(error: e.toString());
    }
  }

  void clearError() => state = const ReservationManagementState();
}

final reservationManagementProvider = StateNotifierProvider<
    ReservationManagementNotifier, ReservationManagementState>((ref) {
  return ReservationManagementNotifier(
    ref.watch(reservationRepositoryProvider),
    ref,
  );
});
