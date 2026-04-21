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
  /// returns them). Rows whose action is neither clock-in nor clock-out
  /// are ignored.
  static List<ClockStatus> reduceStatuses({
    required List<AuditLogEntryEntity> rows,
    required DateTime now,
  }) {
    // Walk oldest → newest so the workedToday accumulator stays simple.
    final chron = rows.reversed
        .where((r) =>
            r.action == AuditAction.userClockedIn ||
            r.action == AuditAction.userClockedOut)
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
      if (r.action == AuditAction.userClockedIn) {
        // A clock-in while already clocked in is a double-tap — keep the
        // most recent so downstream reports do not over-count.
        acc.openSince = r.timestamp;
      } else {
        // clockOut — if we have an open interval, close it and add to
        // today's total (if the interval overlaps today).
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
          // clock-out with no matching clock-in — log-only event, ignore
          // for totals but remember the timestamp so the UI can show it.
          acc.lastClockOut = r.timestamp;
        }
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
  Duration workedToday = Duration.zero;

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
      workedToday += clampedTo.difference(clampedFrom);
    }
  }
}
