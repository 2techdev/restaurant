/// Tests for the waiter + hourly aggregation in [ReportsRepository].
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/features/reports/data/repositories/reports_repository.dart';

const _tenant = 't-rep';

Future<void> _seedUser(
  AppDatabase db, {
  required String id,
  required String name,
}) async {
  final now = DateTime.now();
  await db.into(db.users).insert(UsersCompanion.insert(
        id: id,
        tenantId: _tenant,
        name: name,
        pinHash: 'x',
        role: 'waiter',
        createdAt: now,
        updatedAt: now,
      ));
}

Future<void> _seedTicket(
  AppDatabase db, {
  required String id,
  required String waiterId,
  required int total,
  required DateTime closedAt,
  int tax = 0,
}) async {
  await db.into(db.tickets).insert(TicketsCompanion.insert(
        id: id,
        tenantId: _tenant,
        orderNumber: 1,
        waiterId: Value(waiterId),
        status: const Value('fully_paid'),
        subtotal: Value(total - tax),
        taxAmount: Value(tax),
        total: Value(total),
        openedAt: closedAt.subtract(const Duration(hours: 1)),
        closedAt: Value(closedAt),
        createdAt: closedAt,
        updatedAt: closedAt,
        deviceId: 'DEV-1',
      ));
}

Future<void> _seedPayment(
  AppDatabase db, {
  required String id,
  required String ticketId,
  required int amount,
  int tip = 0,
}) async {
  final now = DateTime.now();
  await db.into(db.payments).insert(PaymentsCompanion.insert(
        id: id,
        tenantId: _tenant,
        billId: 'bill-$ticketId',
        ticketId: ticketId,
        paymentMethod: 'cash',
        amount: amount,
        tipAmount: Value(tip),
        receivedBy: 'u-system',
        paidAt: now,
        createdAt: now,
        updatedAt: now,
      ));
}

void main() {
  group('ReportsRepository.generateSnapshot', () {
    late AppDatabase db;
    late ReportsRepository repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = ReportsRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('aggregates per-waiter ticket count, revenue, and tips', () async {
      await _seedUser(db, id: 'u-1', name: 'Alice');
      await _seedUser(db, id: 'u-2', name: 'Bob');

      final t0 = DateTime(2026, 4, 22, 12, 0);
      await _seedTicket(db,
          id: 't1', waiterId: 'u-1', total: 2000, closedAt: t0);
      await _seedTicket(db,
          id: 't2',
          waiterId: 'u-1',
          total: 3000,
          closedAt: t0.add(const Duration(hours: 1)));
      await _seedTicket(db,
          id: 't3',
          waiterId: 'u-2',
          total: 5000,
          closedAt: t0.add(const Duration(hours: 2)));

      await _seedPayment(db,
          id: 'p1', ticketId: 't1', amount: 2000, tip: 200);
      await _seedPayment(db,
          id: 'p2', ticketId: 't2', amount: 3000, tip: 0);
      await _seedPayment(db,
          id: 'p3', ticketId: 't3', amount: 5000, tip: 500);

      final snap = await repo.generateSnapshot(
        tenantId: _tenant,
        from: DateTime(2026, 4, 22),
        to: DateTime(2026, 4, 23),
      );

      // Sorted by revenue desc: Bob (5000) before Alice (5000 too but one
      // ticket). Actually Alice 5000, Bob 5000 — tiebreak is insertion
      // order, so check both by id.
      expect(snap.waiters.length, 2);
      final alice = snap.waiters.firstWhere((w) => w.waiterId == 'u-1');
      final bob = snap.waiters.firstWhere((w) => w.waiterId == 'u-2');
      expect(alice.waiterName, 'Alice');
      expect(alice.ticketCount, 2);
      expect(alice.revenueCents, 5000);
      expect(alice.tipCents, 200);
      expect(bob.waiterName, 'Bob');
      expect(bob.ticketCount, 1);
      expect(bob.revenueCents, 5000);
      expect(bob.tipCents, 500);
    });

    test('skips tickets with no waiter assigned', () async {
      final t0 = DateTime(2026, 4, 22, 10, 0);
      await _seedTicket(db,
          id: 't-anon', waiterId: '', total: 1000, closedAt: t0);

      final snap = await repo.generateSnapshot(
        tenantId: _tenant,
        from: DateTime(2026, 4, 22),
        to: DateTime(2026, 4, 23),
      );
      expect(snap.waiters, isEmpty);
      expect(snap.ticketCount, 1); // still counted in the overall total
    });

    test('hourly breakdown buckets tickets by closed hour', () async {
      await _seedUser(db, id: 'u-1', name: 'Alice');
      // 2 tickets at 12:00, 1 ticket at 19:00
      await _seedTicket(db,
          id: 't1',
          waiterId: 'u-1',
          total: 1000,
          closedAt: DateTime(2026, 4, 22, 12, 5));
      await _seedTicket(db,
          id: 't2',
          waiterId: 'u-1',
          total: 2000,
          closedAt: DateTime(2026, 4, 22, 12, 45));
      await _seedTicket(db,
          id: 't3',
          waiterId: 'u-1',
          total: 4000,
          closedAt: DateTime(2026, 4, 22, 19, 15));

      final snap = await repo.generateSnapshot(
        tenantId: _tenant,
        from: DateTime(2026, 4, 22),
        to: DateTime(2026, 4, 23),
      );
      expect(snap.hourly.length, 2);
      final noon = snap.hourly.firstWhere((h) => h.hour == 12);
      final evening = snap.hourly.firstWhere((h) => h.hour == 19);
      expect(noon.ticketCount, 2);
      expect(noon.revenueCents, 3000);
      expect(evening.ticketCount, 1);
      expect(evening.revenueCents, 4000);
    });

    test('fallback: waiter name defaults to id when user row missing',
        () async {
      final t0 = DateTime(2026, 4, 22, 11, 0);
      await _seedTicket(db,
          id: 't1', waiterId: 'u-ghost', total: 1500, closedAt: t0);

      final snap = await repo.generateSnapshot(
        tenantId: _tenant,
        from: DateTime(2026, 4, 22),
        to: DateTime(2026, 4, 23),
      );
      expect(snap.waiters.single.waiterId, 'u-ghost');
      expect(snap.waiters.single.waiterName, 'u-ghost');
    });
  });
}
