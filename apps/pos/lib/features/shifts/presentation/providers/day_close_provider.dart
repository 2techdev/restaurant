/// Riverpod providers for the day-close wizard.
///
/// Exposes:
/// - [dayCloseRepositoryProvider]   – singleton repository
/// - [dayCloseNotifierProvider]     – wizard state + submit action
/// - [dayCloseHistoryProvider]      – historical summaries for reporting
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/core/services/backup_service.dart';
import 'package:gastrocore_pos/features/shifts/data/repositories/day_close_repository_impl.dart';
import 'package:gastrocore_pos/features/shifts/domain/day_close_calculator.dart';
import 'package:gastrocore_pos/features/shifts/domain/entities/day_close_summary_entity.dart';
import 'package:gastrocore_pos/features/shifts/presentation/providers/shift_provider.dart';

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

final dayCloseRepositoryProvider = Provider<DayCloseRepositoryImpl>((ref) {
  final db = ref.watch(databaseProvider);
  return DayCloseRepositoryImpl(db);
});

// ---------------------------------------------------------------------------
// Wizard state
// ---------------------------------------------------------------------------

/// Immutable state for the day-close wizard.
class DayCloseState {
  /// Denomination breakdown entered by the cashier.
  /// Key = denomination in cents, value = piece count.
  final Map<int, int> denominationBreakdown;

  /// Optional cashier notes.
  final String notes;

  /// True while the close operation is in progress.
  final bool isSubmitting;

  /// Error message if the last submit failed.
  final String? error;

  /// The summary created after a successful close, or null before close.
  final DayCloseSummaryEntity? result;

  const DayCloseState({
    this.denominationBreakdown = const {},
    this.notes = '',
    this.isSubmitting = false,
    this.error,
    this.result,
  });

  DayCloseState copyWith({
    Map<int, int>? denominationBreakdown,
    String? notes,
    bool? isSubmitting,
    String? Function()? error,
    DayCloseSummaryEntity? Function()? result,
  }) {
    return DayCloseState(
      denominationBreakdown:
          denominationBreakdown ?? this.denominationBreakdown,
      notes: notes ?? this.notes,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: error != null ? error() : this.error,
      result: result != null ? result() : this.result,
    );
  }

  /// Total cash from the denomination breakdown, in cents.
  int get countedCashCents =>
      DayCloseCalculator.denominationTotal(denominationBreakdown);
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

final dayCloseNotifierProvider =
    StateNotifierProvider<DayCloseNotifier, DayCloseState>((ref) {
  return DayCloseNotifier(ref);
});

class DayCloseNotifier extends StateNotifier<DayCloseState> {
  final Ref _ref;

  DayCloseNotifier(this._ref) : super(const DayCloseState()) {
    // Initialise breakdown with all CHF denominations at zero count.
    state = state.copyWith(
      denominationBreakdown: {for (final d in ChfDenomination.all) d: 0},
    );
  }

  // -------------------------------------------------------------------------
  // Denomination editing
  // -------------------------------------------------------------------------

  /// Increment the count for [denomination] by 1.
  void increment(int denomination) {
    final updated = Map<int, int>.from(state.denominationBreakdown);
    updated[denomination] = (updated[denomination] ?? 0) + 1;
    state = state.copyWith(denominationBreakdown: updated);
  }

  /// Decrement the count for [denomination] by 1 (minimum 0).
  void decrement(int denomination) {
    final updated = Map<int, int>.from(state.denominationBreakdown);
    final current = updated[denomination] ?? 0;
    if (current > 0) updated[denomination] = current - 1;
    state = state.copyWith(denominationBreakdown: updated);
  }

  /// Set an exact count for [denomination].
  void setCount(int denomination, int count) {
    if (count < 0) return;
    final updated = Map<int, int>.from(state.denominationBreakdown);
    updated[denomination] = count;
    state = state.copyWith(denominationBreakdown: updated);
  }

  /// Update the cashier notes.
  void setNotes(String notes) => state = state.copyWith(notes: notes);

  // -------------------------------------------------------------------------
  // Submit – close shift and persist summary
  // -------------------------------------------------------------------------

  /// Execute the full day-close sequence:
  ///
  /// 1. Validate denomination breakdown.
  /// 2. Close the shift via [currentShiftProvider].
  /// 3. Persist a [DayCloseSummaryEntity].
  /// 4. Trigger Z-report printing (caller handles this after the future).
  /// 5. Trigger auto-backup.
  ///
  /// Returns the created [DayCloseSummaryEntity] on success.
  /// Throws a [DayCloseException] on validation failure.
  Future<DayCloseSummaryEntity> submitClose({
    required String cashierName,
    required Map<String, int> paymentBreakdown,
    int expectedCashCents = 0,
  }) async {
    // Validate breakdown.
    final validationError =
        DayCloseCalculator.validateBreakdown(state.denominationBreakdown);
    if (validationError != null) {
      throw DayCloseException(validationError);
    }

    state = state.copyWith(isSubmitting: true, error: () => null);

    try {
      final shiftNotifier = _ref.read(currentShiftProvider.notifier);
      final currentShift = _ref.read(currentShiftProvider);
      if (currentShift == null) {
        throw const DayCloseException('No active shift to close.');
      }

      final tenantId = _ref.read(tenantIdProvider);
      final countedCash = state.countedCashCents;
      final discrepancy = DayCloseCalculator.discrepancy(
        countedCash: countedCash,
        expectedCash: expectedCashCents,
      );

      // 1. Close the shift.
      final closedShift = await shiftNotifier.closeShift(
        closingCash: countedCash,
        notes: state.notes.isEmpty ? null : state.notes,
      );

      if (closedShift == null) {
        throw const DayCloseException('Failed to close shift.');
      }

      // 2. Persist the day-close summary.
      final repo = _ref.read(dayCloseRepositoryProvider);
      final totalOrders = closedShift.totalOrders;
      final totalRevenue = closedShift.totalSales;

      final summary = await repo.saveSummary(
        tenantId: tenantId,
        shiftId: closedShift.id,
        deviceId: closedShift.deviceId,
        cashierName: cashierName,
        totalRevenueCents: totalRevenue,
        totalOrders: totalOrders,
        avgOrderCents: DayCloseCalculator.avgOrderCents(
          totalRevenueCents: totalRevenue,
          totalOrders: totalOrders,
        ),
        countedCashCents: countedCash,
        expectedCashCents: expectedCashCents,
        discrepancyCents: discrepancy,
        denominationBreakdown: Map.from(state.denominationBreakdown),
        paymentBreakdown: paymentBreakdown,
        closedAt: closedShift.closedAt ?? DateTime.now(),
      );

      // 3. Auto-backup (best-effort).
      _autoBackup();

      state = state.copyWith(isSubmitting: false, result: () => summary);
      _ref.invalidate(dayCloseHistoryProvider);
      return summary;
    } catch (e) {
      final msg = e is DayCloseException ? e.message : e.toString();
      state = state.copyWith(isSubmitting: false, error: () => msg);
      rethrow;
    }
  }

  Future<void> _autoBackup() async {
    try {
      await BackupService().createBackup();
    } catch (_) {
      // Silent — backup failures never block the shift close.
    }
  }
}

// ---------------------------------------------------------------------------
// History
// ---------------------------------------------------------------------------

/// All day-close summaries for the current tenant, newest first.
final dayCloseHistoryProvider =
    FutureProvider<List<DayCloseSummaryEntity>>((ref) async {
  final repo = ref.watch(dayCloseRepositoryProvider);
  final tenantId = ref.watch(tenantIdProvider);
  return repo.getHistory(tenantId);
});

// ---------------------------------------------------------------------------
// Exception
// ---------------------------------------------------------------------------

class DayCloseException implements Exception {
  const DayCloseException(this.message);
  final String message;

  @override
  String toString() => 'DayCloseException: $message';
}
