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

class ClockStatus {
  const ClockStatus({
    required this.userId,
    required this.userName,
    required this.isClockedIn,
    this.clockedInAt,
    this.clockedOutAt,
    this.workedToday = Duration.zero,
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
  /// calendar day under inspection. If [isClockedIn] is true, the open
  /// interval (clockedInAt → now) is NOT added here — the UI formats it
  /// separately so the "live" portion can be styled differently.
  final Duration workedToday;

  ClockStatus copyWith({
    bool? isClockedIn,
    DateTime? clockedInAt,
    DateTime? clockedOutAt,
    Duration? workedToday,
  }) =>
      ClockStatus(
        userId: userId,
        userName: userName,
        isClockedIn: isClockedIn ?? this.isClockedIn,
        clockedInAt: clockedInAt ?? this.clockedInAt,
        clockedOutAt: clockedOutAt ?? this.clockedOutAt,
        workedToday: workedToday ?? this.workedToday,
      );
}
