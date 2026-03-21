/// Riverpod providers for the shift management feature.
///
/// Exposes:
/// - [shiftRepositoryProvider]        – singleton repository
/// - [currentShiftProvider]           – active shift + open/close/cash movement actions
/// - [shiftHistoryProvider]           – all past shifts for the tenant, newest first
/// - [shiftPaymentBreakdownProvider]  – payment method breakdown for a given shift
/// - [deviceShiftsProvider]           – shifts for the current device / register
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/core/services/backup_service.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/shifts/data/repositories/shift_repository_impl.dart';
import 'package:gastrocore_pos/features/shifts/domain/entities/shift_entity.dart';

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

/// Provides a singleton [ShiftRepositoryImpl] backed by the app database.
final shiftRepositoryProvider = Provider<ShiftRepositoryImpl>((ref) {
  final db = ref.watch(databaseProvider);
  return ShiftRepositoryImpl(db);
});

// ---------------------------------------------------------------------------
// Current shift
// ---------------------------------------------------------------------------

/// Manages the currently open shift.
///
/// `null` means no shift is active (the user must open one before
/// accepting orders).
final currentShiftProvider =
    StateNotifierProvider<CurrentShiftNotifier, ShiftEntity?>((ref) {
  return CurrentShiftNotifier(ref);
});

class CurrentShiftNotifier extends StateNotifier<ShiftEntity?> {
  final Ref _ref;

  CurrentShiftNotifier(this._ref) : super(null);

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  /// Load the currently open shift from the database (if any).
  ///
  /// Call at app startup or after login to restore shift state.
  Future<void> loadCurrentShift() async {
    final repo = _ref.read(shiftRepositoryProvider);
    final tenantId = _ref.read(tenantIdProvider);
    state = await repo.getOpenShift(tenantId);
  }

  /// Open a new shift for the given user.
  ///
  /// The device ID is read automatically from [deviceIdProvider].
  Future<ShiftEntity> openShift({
    required String userId,
    required int openingCash,
  }) async {
    final repo = _ref.read(shiftRepositoryProvider);
    final tenantId = _ref.read(tenantIdProvider);
    final deviceId = _ref.read(deviceIdProvider);

    final shift = await repo.openShift(
      tenantId: tenantId,
      userId: userId,
      deviceId: deviceId,
      openingCash: openingCash,
    );

    state = shift;
    // Invalidate history so it reflects the new shift.
    _ref.invalidate(shiftHistoryProvider);
    return shift;
  }

  /// Close the currently open shift.
  ///
  /// Calculates expected cash, records the difference, and transitions
  /// the shift to "closed". Invalidates history so the list refreshes.
  Future<ShiftEntity?> closeShift({
    required int closingCash,
    String? notes,
  }) async {
    if (state == null) return null;

    final repo = _ref.read(shiftRepositoryProvider);
    final closed = await repo.closeShift(
      shiftId: state!.id,
      closingCash: closingCash,
      notes: notes,
    );

    state = null; // No open shift after closing.
    _ref.invalidate(shiftHistoryProvider);

    // Auto-backup on every shift close (best-effort, never throws).
    _autoBackup();

    return closed;
  }

  Future<void> _autoBackup() async {
    try {
      await BackupService().createBackup();
    } catch (_) {
      // Auto-backup failures are silently ignored.
    }
  }

  // -------------------------------------------------------------------------
  // Cash movements
  // -------------------------------------------------------------------------

  /// Record a cash movement (pay-in, pay-out, tip, expense) against the
  /// currently open shift.
  ///
  /// Does nothing if there is no active shift.
  Future<void> addCashMovement({
    required CashMovementType type,
    required int amountCents,
    required String performedBy,
    String? description,
  }) async {
    if (state == null) return;

    final repo = _ref.read(shiftRepositoryProvider);
    final tenantId = _ref.read(tenantIdProvider);

    final movement = CashMovementEntity(
      id: IdGenerator.generateId(),
      tenantId: tenantId,
      shiftId: state!.id,
      type: type,
      amount: amountCents,
      description: description,
      performedBy: performedBy,
      performedAt: DateTime.now(),
    );

    await repo.addCashMovement(movement);
    // Invalidate breakdown so the UI reflects the new movement.
    _ref.invalidate(shiftPaymentBreakdownProvider(state!.id));
  }
}

// ---------------------------------------------------------------------------
// Shift history
// ---------------------------------------------------------------------------

/// All shifts for the current tenant, newest first (max 50).
///
/// Refresh with `ref.invalidate(shiftHistoryProvider)`.
final shiftHistoryProvider = FutureProvider<List<ShiftEntity>>((ref) async {
  final repo = ref.watch(shiftRepositoryProvider);
  final tenantId = ref.watch(tenantIdProvider);
  return repo.getShiftHistory(tenantId);
});

/// Shifts for the current device / register, newest first (max 20).
///
/// Useful for multi-register setups where each terminal only shows its
/// own shift history.
final deviceShiftsProvider = FutureProvider<List<ShiftEntity>>((ref) async {
  final repo = ref.watch(shiftRepositoryProvider);
  final tenantId = ref.watch(tenantIdProvider);
  final deviceId = ref.watch(deviceIdProvider);
  return repo.getShiftsForDevice(tenantId, deviceId);
});

// ---------------------------------------------------------------------------
// Payment breakdown
// ---------------------------------------------------------------------------

/// Payment method breakdown (method → totalCents) for a given shift ID.
///
/// Usage:
/// ```dart
/// final breakdown = ref.watch(shiftPaymentBreakdownProvider(shiftId));
/// ```
final shiftPaymentBreakdownProvider =
    FutureProvider.family<Map<String, int>, String>((ref, shiftId) async {
  final repo = ref.watch(shiftRepositoryProvider);
  final tenantId = ref.watch(tenantIdProvider);
  return repo.getPaymentBreakdown(shiftId, tenantId);
});
