/// Unit tests for [getTicketUrgency] — ticket-level timer tiering.
///
/// Sprint 3.4 added the `watch` tier (amber at 5+ min) between `fresh`
/// and `late`. Before this change a pending ticket would stay green for
/// the whole lateThreshold window (default 10 min), which hid slow orders.
///
/// Tiers:
///   fresh       elapsed <  5m  AND status == pending
///   inProgress  elapsed <  5m  AND status == preparing
///   watch       5m <= elapsed < lateThreshold (any status)
///   late        elapsed >= lateThreshold
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/features/kds_app/presentation/screens/kds_main_screen.dart';
import 'package:gastrocore_pos/features/kitchen/domain/entities/kitchen_ticket_entity.dart';

KitchenTicketEntity _ticket({
  required DateTime sentAt,
  KitchenTicketStatus status = KitchenTicketStatus.pending,
}) {
  return KitchenTicketEntity(
    id: 'kt-1',
    tenantId: 't',
    ticketId: 'tk',
    orderNumber: '0001',
    printerGroup: 'kitchen',
    items: const [],
    sentAt: sentAt,
    status: status,
  );
}

void main() {
  // A single `now` baseline keeps the math readable — every test subtracts
  // from this to simulate a ticket that arrived N minutes ago.
  final now = DateTime(2026, 4, 18, 12, 0, 0);

  group('getTicketUrgency — age-based tiers', () {
    test('< 5 min pending → fresh', () {
      final t = _ticket(sentAt: now.subtract(const Duration(minutes: 2)));
      expect(getTicketUrgency(t, 10, now: now), TicketUrgency.fresh);
    });

    test('< 5 min preparing → inProgress', () {
      final t = _ticket(
        sentAt: now.subtract(const Duration(minutes: 2)),
        status: KitchenTicketStatus.preparing,
      );
      expect(getTicketUrgency(t, 10, now: now), TicketUrgency.inProgress);
    });

    test('exactly 5 min pending → watch (amber kicks in)', () {
      final t = _ticket(sentAt: now.subtract(const Duration(minutes: 5)));
      expect(getTicketUrgency(t, 10, now: now), TicketUrgency.watch);
    });

    test('7 min pending → watch', () {
      final t = _ticket(sentAt: now.subtract(const Duration(minutes: 7)));
      expect(getTicketUrgency(t, 10, now: now), TicketUrgency.watch);
    });

    test('7 min preparing → watch (age wins over status)', () {
      final t = _ticket(
        sentAt: now.subtract(const Duration(minutes: 7)),
        status: KitchenTicketStatus.preparing,
      );
      expect(getTicketUrgency(t, 10, now: now), TicketUrgency.watch);
    });

    test('exactly 10 min → late', () {
      final t = _ticket(sentAt: now.subtract(const Duration(minutes: 10)));
      expect(getTicketUrgency(t, 10, now: now), TicketUrgency.late);
    });

    test('15 min → late (past threshold)', () {
      final t = _ticket(sentAt: now.subtract(const Duration(minutes: 15)));
      expect(getTicketUrgency(t, 10, now: now), TicketUrgency.late);
    });
  });

  group('getTicketUrgency — respects custom lateThreshold', () {
    test('7 min w/ lateThreshold=8 → watch', () {
      final t = _ticket(sentAt: now.subtract(const Duration(minutes: 7)));
      expect(getTicketUrgency(t, 8, now: now), TicketUrgency.watch);
    });

    test('9 min w/ lateThreshold=8 → late', () {
      final t = _ticket(sentAt: now.subtract(const Duration(minutes: 9)));
      expect(getTicketUrgency(t, 8, now: now), TicketUrgency.late);
    });

    test('3 min w/ lateThreshold=15, preparing → inProgress (not watch)', () {
      final t = _ticket(
        sentAt: now.subtract(const Duration(minutes: 3)),
        status: KitchenTicketStatus.preparing,
      );
      expect(getTicketUrgency(t, 15, now: now), TicketUrgency.inProgress);
    });
  });
}
