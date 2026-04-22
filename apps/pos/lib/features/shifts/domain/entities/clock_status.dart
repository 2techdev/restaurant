/// Per-user clock (Mesai) status.
///
/// Derived from the audit log — there is no dedicated clock table. The
/// repository scans [AuditAction.userClockedIn] / [AuditAction.userClockedOut]
/// entries for the tenant and reduces them to the current state and the
/// cumulative worked duration for a given day.
///
/// This entity intentionally carries only the data the UI needs; the
/// reducer lives in [ClockRepository] so tests can exercise it directly.
library;

/// Standard paid-labour threshold (Swiss default). Hours worked in a
/// single day beyond this accrue as [ClockStatus.overtimeToday]. Kept as
/// a top-level constant so both the reducer and widget tests can agree
/// on a single source of truth; operators can override it per tenant
/// later via settings.
const Duration kDailyRegularHours = Duration(hours: 8);

class ClockStatus {
  const ClockStatus({
    required this.userId,
    required this.userName,
    required this.isClockedIn,
    this.clockedInAt,
    this.clockedOutAt,
    this.workedToday = Duration.zero,
    this.breakedToday = Duration.zero,
    this.isOnBreak = false,
    this.breakStartedAt,
  });

  /// Stable user id the audit rows refer to.
  final String userId;

  /// Display name captured on the most recent audit row for this user.
  /// Kept on the entity so the UI does not have to resolve it from the
  /// users table — useful when a user has been deactivated but still has
  /// open shift entries.
  final String userName;

  /// True when the last audit action for this user is [userClockedIn] and
  /// it is not followed by a matching [userClockedOut].
  final bool isClockedIn;

  /// Timestamp of the most recent clock-in (null if the user has never
  /// clocked in, or only has historical clock-outs).
  final DateTime? clockedInAt;

  /// Timestamp of the most recent clock-out. Used for the "last seen" label.
  final DateTime? clockedOutAt;

  /// Sum of all completed clock-in → clock-out intervals inside the
  /// calendar day under inspection. Break intervals are already excluded
  /// by the reducer. If [isClockedIn] is true, the open interval
  /// (clockedInAt → now) is NOT added here — the UI formats it
  /// separately so the "live" portion can be styled differently.
  final Duration workedToday;

  /// Sum of all completed break intervals inside today. Shown next to
  /// the worked time so operators can see their unpaid time at a glance
  /// and managers can reconcile against Schwarzarbeit rules (BKStG).
  final Duration breakedToday;

  /// True when the last break event is a start without a matching end.
  /// While this is true the live accrual ticker is frozen.
  final bool isOnBreak;

  /// Timestamp of the currently-open break. Used by the UI to show the
  /// live break-duration counter alongside the frozen worked time.
  final DateTime? breakStartedAt;

  /// Overtime accumulated today: `max(0, workedToday - kDailyRegularHours)`.
  /// Read-only derivation — the reducer does not split the `workedToday`
  /// bucket so every consumer computes overtime the same way.
  Duration get overtimeToday {
    final delta = workedToday - kDailyRegularHours;
    return delta.isNegative ? Duration.zero : delta;
  }

  ClockStatus copyWith({
    bool? isClockedIn,
    DateTime? clockedInAt,
    DateTime? clockedOutAt,
    Duration? workedToday,
    Duration? breakedToday,
    bool? isOnBreak,
    DateTime? breakStartedAt,
  }) =>
      ClockStatus(
        userId: userId,
        userName: userName,
        isClockedIn: isClockedIn ?? this.isClockedIn,
        clockedInAt: clockedInAt ?? this.clockedInAt,
        clockedOutAt: clockedOutAt ?? this.clockedOutAt,
        workedToday: workedToday ?? this.workedToday,
        breakedToday: breakedToday ?? this.breakedToday,
        isOnBreak: isOnBreak ?? this.isOnBreak,
        breakStartedAt: breakStartedAt ?? this.breakStartedAt,
      );
}
