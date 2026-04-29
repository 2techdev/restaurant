/// Retention policy for the audit log.
///
/// Swiss commercial law (OR Art. 958f) and the MWST regulation require
/// books of account — including the audit trail of receipts, voids, and
/// price overrides — to be kept for **10 years**. Once a row is past
/// that window, retaining it is no longer mandatory and in some
/// jurisdictions is actively discouraged (GDPR data minimisation).
///
/// The default retention is a runtime constant rather than a database
/// column so a field tweak (e.g. shortening a pilot's window) needs a
/// code change and a version bump — the kind of change that should
/// ship through code review, not an admin panel toggle.
library;

/// Default retention window. Set to 10 years to match the Swiss legal
/// minimum; callers can override by passing a different value to
/// [auditLogRetentionCutoff].
const int kAuditLogRetentionYears = 10;

/// Oldest timestamp that must still be kept, given [now] and the
/// retention window in years. Everything strictly older than the
/// returned value is safe to purge.
///
/// Uses calendar-year arithmetic so "10 years ago" lands on the same
/// day-of-month, not `now - 3650 days` (leap years would otherwise
/// shift it by two or three days).
DateTime auditLogRetentionCutoff(
  DateTime now, {
  int years = kAuditLogRetentionYears,
}) {
  return DateTime(
    now.year - years,
    now.month,
    now.day,
    now.hour,
    now.minute,
    now.second,
    now.millisecond,
    now.microsecond,
  );
}
