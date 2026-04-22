/// Unit tests for the pure [ClockRepository.reduceStatuses] reducer.
///
/// The repository owns a subtle state machine:
///   * A clockIn while already open overwrites the open-since stamp
///     (so a double-tap does not silently accumulate a fake interval).
///   * A clockOut with no matching clockIn logs-only — no interval is
///     added, but the last-seen timestamp updates.
///   * Worked-time accumulation clamps to today's calendar slice so a
///     shift that straddles midnight only contributes the on-today part.
///
/// Run with:
///   flutter test test/features/shifts/clock_repository_test.dart
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/features/audit_log/domain/entities/audit_action.dart';
import 'package:gastrocore_pos/features/audit_log/domain/entities/audit_log_entry_entity.dart';
import 'package:gastrocore_pos/features/shifts/data/clock_repository.dart';

AuditLogEntryEntity _row({
  required String id,
  required String userId,
  required String userName,
  required AuditAction action,
  required DateTime at,
}) {
  return AuditLogEntryEntity(
    id: id,
    tenantId: 't1',
    deviceId: 'd1',
    userId: userId,
    userName: userName,
    action: action,
    entityType: 'user',
    entityId: userId,
    timestamp: at,
  );
}

void main() {
  // A fixed "today" makes the clamping checks deterministic.
  final today = DateTime(2026, 4, 22, 14, 0); // Wed 22.04.2026 14:00
  final nineAm = DateTime(2026, 4, 22, 9, 0);
  final tenAm = DateTime(2026, 4, 22, 10, 0);
  final noon = DateTime(2026, 4, 22, 12, 0);
  final onePm = DateTime(2026, 4, 22, 13, 0);

  group('ClockRepository.reduceStatuses', () {
    test('returns empty list when no rows are supplied', () {
      final out = ClockRepository.reduceStatuses(rows: const [], now: today);
      expect(out, isEmpty);
    });

    test('single clockIn leaves the user open with zero worked time', () {
      // Rows come newest-first from the DAO.
      final rows = [
        _row(
          id: 'a1', userId: 'u1', userName: 'Ali',
          action: AuditAction.userClockedIn, at: nineAm,
        ),
      ];
      final out = ClockRepository.reduceStatuses(rows: rows, now: today);

      expect(out.length, 1);
      expect(out.first.userId, 'u1');
      expect(out.first.isClockedIn, isTrue);
      expect(out.first.clockedInAt, nineAm);
      expect(out.first.workedToday, Duration.zero,
          reason: 'open interval is not counted in workedToday');
    });

    test('clockIn + clockOut produces a closed interval and accumulates time',
        () {
      final rows = [
        _row(
          id: 'a2', userId: 'u1', userName: 'Ali',
          action: AuditAction.userClockedOut, at: noon,
        ),
        _row(
          id: 'a1', userId: 'u1', userName: 'Ali',
          action: AuditAction.userClockedIn, at: nineAm,
        ),
      ];
      final out = ClockRepository.reduceStatuses(rows: rows, now: today);

      expect(out.first.isClockedIn, isFalse);
      expect(out.first.workedToday, const Duration(hours: 3));
      expect(out.first.clockedOutAt, noon);
      expect(out.first.clockedInAt, isNull,
          reason: 'no open interval once the last event is a clockOut');
    });

    test('two closed intervals sum', () {
      // 09:00-10:00 + 12:00-13:00 = 2h
      final rows = [
        _row(
          id: 'a4', userId: 'u1', userName: 'Ali',
          action: AuditAction.userClockedOut, at: onePm,
        ),
        _row(
          id: 'a3', userId: 'u1', userName: 'Ali',
          action: AuditAction.userClockedIn, at: noon,
        ),
        _row(
          id: 'a2', userId: 'u1', userName: 'Ali',
          action: AuditAction.userClockedOut, at: tenAm,
        ),
        _row(
          id: 'a1', userId: 'u1', userName: 'Ali',
          action: AuditAction.userClockedIn, at: nineAm,
        ),
      ];
      final out = ClockRepository.reduceStatuses(rows: rows, now: today);

      expect(out.first.workedToday, const Duration(hours: 2));
      expect(out.first.isClockedIn, isFalse);
    });

    test('double clockIn overwrites the open-since stamp', () {
      // 09:00 clockIn (forgotten to clockOut), 10:00 clockIn again.
      // Status should reflect the 10:00 start so subsequent duration
      // calculations do not include the stale slot.
      final rows = [
        _row(
          id: 'a2', userId: 'u1', userName: 'Ali',
          action: AuditAction.userClockedIn, at: tenAm,
        ),
        _row(
          id: 'a1', userId: 'u1', userName: 'Ali',
          action: AuditAction.userClockedIn, at: nineAm,
        ),
      ];
      final out = ClockRepository.reduceStatuses(rows: rows, now: today);

      expect(out.first.isClockedIn, isTrue);
      expect(out.first.clockedInAt, tenAm);
      expect(out.first.workedToday, Duration.zero);
    });

    test('clockOut with no matching clockIn does NOT add an interval', () {
      final rows = [
        _row(
          id: 'a1', userId: 'u1', userName: 'Ali',
          action: AuditAction.userClockedOut, at: noon,
        ),
      ];
      final out = ClockRepository.reduceStatuses(rows: rows, now: today);

      expect(out.first.isClockedIn, isFalse);
      expect(out.first.workedToday, Duration.zero);
      expect(out.first.clockedOutAt, noon,
          reason: 'the last-seen timestamp still updates');
    });

    test('interval that started yesterday only counts todays slice', () {
      final yesterday = DateTime(2026, 4, 21, 22, 0); // 22:00 yesterday
      final twoAmToday = DateTime(2026, 4, 22, 2, 0); // 02:00 today
      final rows = [
        _row(
          id: 'a2', userId: 'u1', userName: 'Ali',
          action: AuditAction.userClockedOut, at: twoAmToday,
        ),
        _row(
          id: 'a1', userId: 'u1', userName: 'Ali',
          action: AuditAction.userClockedIn, at: yesterday,
        ),
      ];
      final out = ClockRepository.reduceStatuses(rows: rows, now: today);

      // Only 00:00 → 02:00 today counts (2h), NOT the 4h overnight total.
      expect(out.first.workedToday, const Duration(hours: 2));
    });

    test('unrelated audit actions are ignored', () {
      final rows = [
        _row(
          id: 'a2', userId: 'u1', userName: 'Ali',
          action: AuditAction.orderCreated, at: tenAm,
        ),
        _row(
          id: 'a1', userId: 'u1', userName: 'Ali',
          action: AuditAction.userClockedIn, at: nineAm,
        ),
      ];
      final out = ClockRepository.reduceStatuses(rows: rows, now: today);
      expect(out.first.isClockedIn, isTrue);
      expect(out.first.clockedInAt, nineAm);
    });

    test('tracks multiple users independently', () {
      final rows = [
        _row(
          id: 'b1', userId: 'u2', userName: 'Berfin',
          action: AuditAction.userClockedIn, at: tenAm,
        ),
        _row(
          id: 'a2', userId: 'u1', userName: 'Ali',
          action: AuditAction.userClockedOut, at: noon,
        ),
        _row(
          id: 'a1', userId: 'u1', userName: 'Ali',
          action: AuditAction.userClockedIn, at: nineAm,
        ),
      ];
      final out = ClockRepository.reduceStatuses(rows: rows, now: today);

      final ali = out.firstWhere((s) => s.userId == 'u1');
      final berfin = out.firstWhere((s) => s.userId == 'u2');
      expect(ali.isClockedIn, isFalse);
      expect(ali.workedToday, const Duration(hours: 3));
      expect(berfin.isClockedIn, isTrue);
      expect(berfin.workedToday, Duration.zero);
    });

    test('a closed break subtracts from worked time and adds to breakedToday',
        () {
      // 09:00 clockIn, 10:00 break start, 10:30 break end, 12:00 clockOut.
      // Worked should be (12:00-09:00) - (10:30-10:00) = 2h 30m.
      final tenThirty = DateTime(2026, 4, 22, 10, 30);
      final rows = [
        _row(
          id: 'e4', userId: 'u1', userName: 'Ali',
          action: AuditAction.userClockedOut, at: noon,
        ),
        _row(
          id: 'e3', userId: 'u1', userName: 'Ali',
          action: AuditAction.userBreakEnded, at: tenThirty,
        ),
        _row(
          id: 'e2', userId: 'u1', userName: 'Ali',
          action: AuditAction.userBreakStarted, at: tenAm,
        ),
        _row(
          id: 'e1', userId: 'u1', userName: 'Ali',
          action: AuditAction.userClockedIn, at: nineAm,
        ),
      ];
      final out = ClockRepository.reduceStatuses(rows: rows, now: today);
      expect(out.first.workedToday, const Duration(hours: 2, minutes: 30));
      expect(out.first.breakedToday, const Duration(minutes: 30));
      expect(out.first.isOnBreak, isFalse);
    });

    test('an open break leaves isOnBreak=true with breakStartedAt populated',
        () {
      final rows = [
        _row(
          id: 'e2', userId: 'u1', userName: 'Ali',
          action: AuditAction.userBreakStarted, at: tenAm,
        ),
        _row(
          id: 'e1', userId: 'u1', userName: 'Ali',
          action: AuditAction.userClockedIn, at: nineAm,
        ),
      ];
      final out = ClockRepository.reduceStatuses(rows: rows, now: today);
      expect(out.first.isClockedIn, isTrue);
      expect(out.first.isOnBreak, isTrue);
      expect(out.first.breakStartedAt, tenAm);
    });

    test('clockOut while on break auto-closes the break', () {
      final rows = [
        _row(
          id: 'e3', userId: 'u1', userName: 'Ali',
          action: AuditAction.userClockedOut, at: noon,
        ),
        _row(
          id: 'e2', userId: 'u1', userName: 'Ali',
          action: AuditAction.userBreakStarted, at: tenAm,
        ),
        _row(
          id: 'e1', userId: 'u1', userName: 'Ali',
          action: AuditAction.userClockedIn, at: nineAm,
        ),
      ];
      final out = ClockRepository.reduceStatuses(rows: rows, now: today);
      expect(out.first.isOnBreak, isFalse);
      // Break 10:00-12:00 = 2h closed implicitly at clockOut.
      expect(out.first.breakedToday, const Duration(hours: 2));
      // Worked (3h total) minus break (2h) = 1h.
      expect(out.first.workedToday, const Duration(hours: 1));
    });

    test('overtime getter exposes hours worked beyond the daily threshold',
        () {
      // 9h interval => 1h overtime at the default 8h threshold.
      final earlyMorning = DateTime(2026, 4, 22, 6, 0);
      final threePm = DateTime(2026, 4, 22, 15, 0);
      final rows = [
        _row(
          id: 'o2', userId: 'u1', userName: 'Ali',
          action: AuditAction.userClockedOut, at: threePm,
        ),
        _row(
          id: 'o1', userId: 'u1', userName: 'Ali',
          action: AuditAction.userClockedIn, at: earlyMorning,
        ),
      ];
      final out = ClockRepository.reduceStatuses(rows: rows, now: today);
      expect(out.first.workedToday, const Duration(hours: 9));
      expect(out.first.overtimeToday, const Duration(hours: 1));
    });

    test('uses the most recent user name captured on the audit row', () {
      final rows = [
        _row(
          id: 'a2', userId: 'u1', userName: 'Ali Yeni',
          action: AuditAction.userClockedOut, at: noon,
        ),
        _row(
          id: 'a1', userId: 'u1', userName: 'Ali Eski',
          action: AuditAction.userClockedIn, at: nineAm,
        ),
      ];
      final out = ClockRepository.reduceStatuses(rows: rows, now: today);
      expect(out.first.userName, 'Ali Yeni');
    });
  });
}
