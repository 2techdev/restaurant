/// Reads clock-in / clock-out audit rows and reduces them to a per-user
/// [ClockStatus] snapshot.
///
/// The audit log is the source of truth — no dedicated clock table. This
/// keeps the pilot schema stable (v16) and gives us the full history for
/// free. The downside (linear scan over audit rows) is fine at pilot
/// volumes; we pull at most 500 recent rows per call.
library;

import 'package:gastrocore_pos/features/audit_log/data/daos/audit_log_dao.dart';
import 'package:gastrocore_pos/features/audit_log/domain/entities/audit_action.dart';
import 'package:gastrocore_pos/features/audit_log/domain/entities/audit_log_entry_entity.dart';
import 'package:gastrocore_pos/features/shifts/domain/entities/clock_status.dart';

class ClockRepository {
  ClockRepository(this._dao);

  final AuditLogDao _dao;

  /// Fetch the current clock state for every user that has at least one
  /// clock-in entry in the last [historyWindow]. The [now] argument is
  /// kept explicit so tests can feed a deterministic clock; production
  /// callers should pass [DateTime.now()].
  Future<List<ClockStatus>> getStatuses({
    required String tenantId,
    required DateTime now,
    Duration historyWindow = const Duration(days: 7),
  }) async {
    final from = now.subtract(historyWindow);
    // Pull both clock actions in a single query, newest first.
    final rows = await _dao.getEntries(
      tenantId: tenantId,
      from: from,
      // No `to` — include rows timestamped a few seconds ahead of [now]
      // (clock skew across devices) so a just-logged clock-in is not
      // invisible to the first refresh.
      limit: 500,
    );
    return reduceStatuses(rows: rows, now: now);
  }

  /// Pure reducer extracted so the unit tests can exercise the state
  /// machine without a database.
  ///
  /// [rows] must be ordered newest-first (as [AuditLogDao.getEntries]
  /// returns them). Rows whose action is not a clock or break event
  /// are ignored. The reducer walks events chronologically and
  /// subtracts break intervals from the corresponding worked interval
  /// so [ClockStatus.workedToday] reflects billable time only.
  static List<ClockStatus> reduceStatuses({
    required List<AuditLogEntryEntity> rows,
    required DateTime now,
  }) {
    // Walk oldest → newest so the workedToday accumulator stays simple.
    final chron = rows.reversed
        .where((r) =>
            r.action == AuditAction.userClockedIn ||
            r.action == AuditAction.userClockedOut ||
            r.action == AuditAction.userBreakStarted ||
            r.action == AuditAction.userBreakEnded)
        .toList(growable: false);

    final dayStart = DateTime(now.year, now.month, now.day);

    // Per-user accumulator.
    final byUser = <String, _Acc>{};

    for (final r in chron) {
      final acc = byUser.putIfAbsent(
        r.userId,
        () => _Acc(userId: r.userId, userName: r.userName),
      );
      acc.userName = r.userName; // keep most recent display name
      switch (r.action) {
        case AuditAction.userClockedIn:
          // Starting a fresh shift implicitly closes any dangling break
          // so the state machine cannot deadlock.
          acc.breakSince = null;
          acc.openSince = r.timestamp;
        case AuditAction.userClockedOut:
          // If a break was still open, close it first so the duration
          // accounting stays consistent.
          if (acc.breakSince != null) {
            acc.addBreak(
              from: acc.breakSince!,
              to: r.timestamp,
              dayStart: dayStart,
            );
            acc.breakSince = null;
          }
          final openedAt = acc.openSince;
          if (openedAt != null) {
            acc.addInterval(
              from: openedAt,
              to: r.timestamp,
              dayStart: dayStart,
            );
            acc.openSince = null;
            acc.lastClockOut = r.timestamp;
          } else {
            // clock-out with no matching clock-in — log-only event
            acc.lastClockOut = r.timestamp;
          }
        case AuditAction.userBreakStarted:
          // Double-tap guard: only open a new break if none is running.
          acc.breakSince ??= r.timestamp;
        case AuditAction.userBreakEnded:
          final openedBreak = acc.breakSince;
          if (openedBreak != null) {
            acc.addBreak(
              from: openedBreak,
              to: r.timestamp,
              dayStart: dayStart,
            );
            acc.breakSince = null;
          }
        default:
          // unreachable — filter above restricts the set.
          break;
      }
    }

    return byUser.values
        .map((a) => ClockStatus(
              userId: a.userId,
              userName: a.userName,
              isClockedIn: a.openSince != null,
              clockedInAt: a.openSince,
              clockedOutAt: a.lastClockOut,
              workedToday: a.workedToday,
              breakedToday: a.breakedToday,
              isOnBreak: a.breakSince != null,
              breakStartedAt: a.breakSince,
            ))
        .toList(growable: false);
  }
}

/// Mutable per-user accumulator used by [ClockRepository.reduceStatuses].
class _Acc {
  _Acc({required this.userId, required this.userName});

  final String userId;
  String userName;
  DateTime? openSince;
  DateTime? lastClockOut;
  DateTime? breakSince;
  Duration workedToday = Duration.zero;
  Duration breakedToday = Duration.zero;

  /// Break time accumulated inside the currently-open worked interval.
  /// Subtracted from `workedToday` at clock-out so billable time reflects
  /// paid hours only — see [addInterval].
  Duration _pendingBreak = Duration.zero;

  void addInterval({
    required DateTime from,
    required DateTime to,
    required DateTime dayStart,
  }) {
    // Clamp [from, to] to today so a shift that started yesterday only
    // contributes today's slice.
    final dayEnd = dayStart.add(const Duration(days: 1));
    final clampedFrom = from.isBefore(dayStart) ? dayStart : from;
    final clampedTo = to.isAfter(dayEnd) ? dayEnd : to;
    if (clampedTo.isAfter(clampedFrom)) {
      var span = clampedTo.difference(clampedFrom);
      if (_pendingBreak > Duration.zero) {
        span = span > _pendingBreak ? span - _pendingBreak : Duration.zero;
      }
      workedToday += span;
    }
    _pendingBreak = Duration.zero;
  }

  void addBreak({
    required DateTime from,
    required DateTime to,
    required DateTime dayStart,
  }) {
    final dayEnd = dayStart.add(const Duration(days: 1));
    final clampedFrom = from.isBefore(dayStart) ? dayStart : from;
    final clampedTo = to.isAfter(dayEnd) ? dayEnd : to;
    if (clampedTo.isAfter(clampedFrom)) {
      final span = clampedTo.difference(clampedFrom);
      breakedToday += span;
      // Defer subtraction: the corresponding worked interval is still
      // open, so we can't reduce `workedToday` yet. The pending bucket
      // drains the next time [addInterval] closes.
      _pendingBreak += span;
    }
  }
}
