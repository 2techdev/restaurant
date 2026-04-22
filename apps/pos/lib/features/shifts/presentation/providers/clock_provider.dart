/// Riverpod providers for the per-user clock (Mesai) feature.
///
/// Exposes:
///   * [clockRepositoryProvider] - singleton repo bound to the audit DAO
///   * [clockStatusesProvider]   - AsyncNotifier returning the live per-user
///                                 status list
///   * [ClockStatusesNotifier.toggle] - clock-in/out toggle that writes the
///                                 audit row and refreshes the list
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/features/audit_log/presentation/providers/audit_log_provider.dart';
import 'package:gastrocore_pos/features/shifts/data/clock_repository.dart';
import 'package:gastrocore_pos/features/shifts/domain/entities/clock_status.dart';

final clockRepositoryProvider = Provider<ClockRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return ClockRepository(db.auditLogDao);
});

/// Per-user Mesai status list, newest-state-first. Refreshes on mutation
/// and on explicit `ref.invalidate` calls from the UI pull-to-refresh.
final clockStatusesProvider =
    AsyncNotifierProvider<ClockStatusesNotifier, List<ClockStatus>>(
  ClockStatusesNotifier.new,
);

class ClockStatusesNotifier extends AsyncNotifier<List<ClockStatus>> {
  @override
  Future<List<ClockStatus>> build() => _load();

  Future<List<ClockStatus>> _load() async {
    final repo = ref.read(clockRepositoryProvider);
    final tenantId = ref.read(tenantIdProvider);
    return repo.getStatuses(tenantId: tenantId, now: DateTime.now());
  }

  /// Flip the clock state for the given user. Writes the audit row first,
  /// then refreshes the list so the UI always reflects persisted truth.
  Future<void> toggle({
    required String userId,
    required String userName,
    required bool currentlyClockedIn,
    String? reason,
  }) async {
    final audit = ref.read(auditServiceProvider);
    if (currentlyClockedIn) {
      await audit.logUserClockedOut(userId, userName, reason: reason);
    } else {
      await audit.logUserClockedIn(userId, userName);
    }
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_load);
  }

  /// Pause / resume the current paid interval. Writes either a
  /// [AuditAction.userBreakStarted] or [AuditAction.userBreakEnded] and
  /// refreshes the list. A no-op if the user is not currently clocked
  /// in — the UI should hide the button in that case anyway.
  Future<void> toggleBreak({
    required String userId,
    required String userName,
    required bool currentlyOnBreak,
    String? reason,
  }) async {
    final audit = ref.read(auditServiceProvider);
    if (currentlyOnBreak) {
      await audit.logUserBreakEnded(userId, userName, reason: reason);
    } else {
      await audit.logUserBreakStarted(userId, userName, reason: reason);
    }
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_load);
  }

  /// Force-reload without mutating.
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_load);
  }
}

/// View model used by the Back Office clock list tile; exposed as its own
/// class so the UI can keep logic-free and the widget test can build
/// deterministic snapshots without touching the provider graph.
@immutable
class ClockTileViewModel {
  const ClockTileViewModel({
    required this.status,
    required this.now,
  });

  final ClockStatus status;
  final DateTime now;

  /// Total worked time including the currently-open interval (if any)
  /// minus any currently-open break. The "live" ticker subtracts the
  /// live break duration so the worked counter freezes while the
  /// operator is on break.
  Duration get totalWorked {
    final base = status.workedToday;
    final openedAt = status.clockedInAt;
    if (status.isClockedIn && openedAt != null && now.isAfter(openedAt)) {
      var live = base + now.difference(openedAt);
      final bStart = status.breakStartedAt;
      if (status.isOnBreak && bStart != null && now.isAfter(bStart)) {
        final liveBreak = now.difference(bStart);
        live = live > liveBreak ? live - liveBreak : Duration.zero;
      }
      return live;
    }
    return base;
  }

  /// Total paused time today including an open break.
  Duration get totalBreak {
    final base = status.breakedToday;
    final bStart = status.breakStartedAt;
    if (status.isOnBreak && bStart != null && now.isAfter(bStart)) {
      return base + now.difference(bStart);
    }
    return base;
  }

  /// Overtime derived from the live [totalWorked] against the configured
  /// threshold — recomputed on every tick so the UI can colour-flip the
  /// moment the operator crosses 8 hours.
  Duration get overtime {
    final delta = totalWorked - kDailyRegularHours;
    return delta.isNegative ? Duration.zero : delta;
  }

  /// Short "H:MM" worked-time label.
  String get workedLabel => _fmt(totalWorked);

  /// Short "H:MM" paused-time label.
  String get breakLabel => _fmt(totalBreak);

  /// Short "H:MM" overtime label.
  String get overtimeLabel => _fmt(overtime);

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    return '${h}h ${m.toString().padLeft(2, '0')}m';
  }
}
