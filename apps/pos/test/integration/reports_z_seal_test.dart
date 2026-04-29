/// Integration test for the reports repository — snapshot aggregation
/// and Z-seal monotonic sequencing against a real in-memory database.
library;

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/features/reports/data/repositories/reports_repository.dart';

const _tenantA = 'tenant-a';
const _tenantB = 'tenant-b';

Future<void> _insertPaidTicket(
  AppDatabase db, {
  required String tenantId,
  required String id,
  required int orderNumber,
  required DateTime closedAt,
  required int subtotal,
  required int tax,
  int discount = 0,
  String? discountType,
  double? discountValue,
}) async {
  final now = DateTime.now();
  await db.into(db.tickets).insert(TicketsCompanion(
        id: Value(id),
        tenantId: Value(tenantId),
        orderNumber: Value(orderNumber),
        status: const Value('fully_paid'),
        subtotal: Value(subtotal),
        taxAmount: Value(tax),
        discountAmount: Value(discount),
        discountType: Value(discountType),
        discountValue: Value(discountValue),
        total: Value(subtotal + tax - discount),
        openedAt: Value(closedAt.subtract(const Duration(minutes: 30))),
        closedAt: Value(closedAt),
        deviceId: const Value('TEST-POS'),
        createdAt: Value(now),
        updatedAt: Value(now),
      ));
}

void main() {
  group('ReportsRepository', () {
    late AppDatabase db;
    late ReportsRepository repo;

    setUp(() {
      db = AppDatabase.createInMemory();
      repo = ReportsRepository(db);
    });

    tearDown(() => db.close());

    test('generateSnapshot aggregates totals inside the window', () async {
      final day = DateTime(2026, 4, 20);
      final outside = day.subtract(const Duration(days: 1));

      await _insertPaidTicket(
        db,
        tenantId: _tenantA,
        id: 't1',
        orderNumber: 1,
        closedAt: day.add(const Duration(hours: 12)),
        subtotal: 1000,
        tax: 81,
      );
      await _insertPaidTicket(
        db,
        tenantId: _tenantA,
        id: 't2',
        orderNumber: 2,
        closedAt: day.add(const Duration(hours: 19)),
        subtotal: 2000,
        tax: 162,
      );
      // Outside the window — must not be counted.
      await _insertPaidTicket(
        db,
        tenantId: _tenantA,
        id: 't3',
        orderNumber: 3,
        closedAt: outside.add(const Duration(hours: 10)),
        subtotal: 9999,
        tax: 810,
      );
      // Different tenant — must not be counted either.
      await _insertPaidTicket(
        db,
        tenantId: _tenantB,
        id: 't4',
        orderNumber: 4,
        closedAt: day.add(const Duration(hours: 12)),
        subtotal: 5000,
        tax: 405,
      );

      final snap = await repo.generateSnapshot(
        tenantId: _tenantA,
        from: day,
        to: day.add(const Duration(days: 1)),
      );

      expect(snap.ticketCount, 2);
      expect(snap.grossTotalCents, 1000 + 81 + 2000 + 162);
      expect(snap.taxTotalCents, 81 + 162);
      expect(snap.netTotalCents, snap.grossTotalCents - snap.taxTotalCents);
    });

    test('gift detection flags 100% percentage discount tickets', () async {
      final day = DateTime(2026, 4, 20);
      await _insertPaidTicket(
        db,
        tenantId: _tenantA,
        id: 'gift-1',
        orderNumber: 1,
        closedAt: day.add(const Duration(hours: 14)),
        subtotal: 2500,
        tax: 0,
        discount: 2500,
        discountType: 'percent',
        discountValue: 100,
      );

      final snap = await repo.generateSnapshot(
        tenantId: _tenantA,
        from: day,
        to: day.add(const Duration(days: 1)),
      );

      expect(snap.giftTotalCents, 2500);
    });

    test('sealZReport assigns monotonic, per-tenant sequence numbers',
        () async {
      final day = DateTime(2026, 4, 20);
      final snap = await repo.generateSnapshot(
        tenantId: _tenantA,
        from: day,
        to: day.add(const Duration(days: 1)),
      );

      final seal1 = await repo.sealZReport(
          tenantId: _tenantA, closedBy: 'alice', snapshot: snap);
      final seal2 = await repo.sealZReport(
          tenantId: _tenantA, closedBy: 'alice', snapshot: snap);
      final seal3 = await repo.sealZReport(
          tenantId: _tenantA, closedBy: 'alice', snapshot: snap);

      expect(seal1.sequenceNumber, 1);
      expect(seal2.sequenceNumber, 2);
      expect(seal3.sequenceNumber, 3);

      // Different tenant starts its own sequence at 1.
      final crossTenant = await repo.sealZReport(
          tenantId: _tenantB, closedBy: 'bob', snapshot: snap);
      expect(crossTenant.sequenceNumber, 1);

      final listA = await repo.listZSeals(_tenantA);
      expect(listA.map((s) => s.sequenceNumber), [3, 2, 1]);
      expect(listA.every((s) => s.tenantId == _tenantA), isTrue);
    });

    test('listZSeals round-trips the snapshot payload', () async {
      final day = DateTime(2026, 4, 20);
      await _insertPaidTicket(
        db,
        tenantId: _tenantA,
        id: 't1',
        orderNumber: 1,
        closedAt: day.add(const Duration(hours: 12)),
        subtotal: 1000,
        tax: 81,
      );
      final original = await repo.generateSnapshot(
        tenantId: _tenantA,
        from: day,
        to: day.add(const Duration(days: 1)),
      );
      await repo.sealZReport(
          tenantId: _tenantA, closedBy: 'alice', snapshot: original);

      final fromDb = (await repo.listZSeals(_tenantA)).single;
      expect(fromDb.snapshot.ticketCount, original.ticketCount);
      expect(fromDb.snapshot.grossTotalCents, original.grossTotalCents);
      expect(fromDb.snapshot.taxTotalCents, original.taxTotalCents);
      expect(fromDb.closedBy, 'alice');
    });
  });
}
