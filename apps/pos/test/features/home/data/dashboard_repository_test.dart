import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/features/home/data/repositories/dashboard_repository.dart';

void main() {
  late AppDatabase db;
  late DashboardRepository repo;

  const tenantId = 'test-tenant';
  const deviceId = 'test-device';
  const userId = 'test-user';

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = DashboardRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  // =========================================================================
  // Helpers
  // =========================================================================

  Future<void> insertTenant() async {
    await db.into(db.tenants).insert(TenantsCompanion(
          id: const Value('test-tenant'),
          name: const Value('Test Restaurant'),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ));
  }

  Future<void> insertTicket({
    required String id,
    required String status,
    required int total,
    required DateTime openedAt,
    String orderType = 'dine_in',
    String? tableId,
  }) async {
    await db.into(db.tickets).insert(TicketsCompanion(
          id: Value(id),
          tenantId: const Value(tenantId),
          orderNumber: const Value(1),
          orderType: Value(orderType),
          tableId: Value(tableId),
          guestCount: const Value(1),
          status: Value(status),
          channel: const Value('pos'),
          subtotal: Value(total),
          taxAmount: const Value(0),
          discountAmount: const Value(0),
          total: Value(total),
          openedAt: Value(openedAt),
          deviceId: const Value(deviceId),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
          isDeleted: const Value(false),
          syncStatus: const Value(0),
        ));
  }

  Future<void> insertPayment({
    required String id,
    required String ticketId,
    required String method,
    required int amount,
    required DateTime paidAt,
  }) async {
    await db.into(db.payments).insert(PaymentsCompanion(
          id: Value(id),
          tenantId: const Value(tenantId),
          billId: Value('bill-$id'),
          ticketId: Value(ticketId),
          paymentMethod: Value(method),
          amount: Value(amount),
          tipAmount: const Value(0),
          tenderedAmount: const Value(0),
          changeAmount: const Value(0),
          receivedBy: const Value(userId),
          paidAt: Value(paidAt),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
          isDeleted: const Value(false),
          syncStatus: const Value(0),
        ));
  }

  Future<void> insertTable({
    required String id,
    required String status,
  }) async {
    await db.into(db.restaurantTables).insert(RestaurantTablesCompanion(
          id: Value(id),
          tenantId: const Value(tenantId),
          floorId: const Value('floor-1'),
          name: Value('T$id'),
          status: Value(status),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
          isDeleted: const Value(false),
          syncStatus: const Value(0),
        ));
  }

  Future<void> insertShift({
    required String id,
    required String status,
    required DateTime openedAt,
    int totalSales = 0,
    int totalOrders = 0,
    int openingCash = 20000,
  }) async {
    await db.into(db.shifts).insert(ShiftsCompanion(
          id: Value(id),
          tenantId: const Value(tenantId),
          userId: const Value(userId),
          deviceId: const Value(deviceId),
          openingCash: Value(openingCash),
          status: Value(status),
          openedAt: Value(openedAt),
          totalSales: Value(totalSales),
          totalOrders: Value(totalOrders),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
          isDeleted: const Value(false),
          syncStatus: const Value(0),
        ));
  }

  // =========================================================================
  // Empty state
  // =========================================================================

  group('getDashboardSummary – empty database', () {
    test('returns zero values when tenant has no data', () async {
      await insertTenant();
      final summary = await repo.getDashboardSummary(tenantId);

      expect(summary.dailyRevenueCents, 0);
      expect(summary.dailyOrderCount, 0);
      expect(summary.cashRevenueCents, 0);
      expect(summary.cardRevenueCents, 0);
      expect(summary.otherRevenueCents, 0);
      expect(summary.occupiedTableCount, 0);
      expect(summary.totalTableCount, 0);
      expect(summary.currentShift, isNull);
      expect(summary.recentOrders, isEmpty);
      expect(summary.hourlySales.length, 24);
      expect(summary.hourlySales.every((h) => h.amountCents == 0), isTrue);
    });
  });

  // =========================================================================
  // Daily revenue
  // =========================================================================

  group('daily revenue', () {
    test('sums only completed tickets from today', () async {
      await insertTenant();
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day, 8);

      await insertTicket(
        id: 't1', status: 'completed', total: 3500, openedAt: startOfDay,
      );
      await insertTicket(
        id: 't2', status: 'completed', total: 2000,
        openedAt: startOfDay.add(const Duration(hours: 1)),
      );
      // Open ticket – must NOT be counted
      await insertTicket(
        id: 't3', status: 'open', total: 1000,
        openedAt: startOfDay.add(const Duration(hours: 2)),
      );

      final summary = await repo.getDashboardSummary(tenantId);
      expect(summary.dailyRevenueCents, 5500);
      expect(summary.dailyOrderCount, 2);
    });

    test('excludes completed tickets from yesterday', () async {
      await insertTenant();
      final yesterday = DateTime.now().subtract(const Duration(days: 1));

      await insertTicket(
        id: 't-yesterday', status: 'completed', total: 99999, openedAt: yesterday,
      );

      final summary = await repo.getDashboardSummary(tenantId);
      expect(summary.dailyRevenueCents, 0);
      expect(summary.dailyOrderCount, 0);
    });

    test('averageOrder is 0 when no orders', () async {
      await insertTenant();
      final summary = await repo.getDashboardSummary(tenantId);
      expect(summary.dailyAverageOrderCents, 0);
    });

    test('averageOrder is calculated correctly', () async {
      await insertTenant();
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day, 9);

      await insertTicket(id: 't1', status: 'completed', total: 6000, openedAt: startOfDay);
      await insertTicket(
          id: 't2', status: 'completed', total: 4000,
          openedAt: startOfDay.add(const Duration(hours: 1)));

      final summary = await repo.getDashboardSummary(tenantId);
      // (6000 + 4000) / 2 = 5000
      expect(summary.dailyAverageOrderCents, 5000);
    });
  });

  // =========================================================================
  // Payment breakdown
  // =========================================================================

  group('payment breakdown', () {
    test('groups cash, card (credit+debit), and other correctly', () async {
      await insertTenant();
      final now = DateTime.now();

      await insertTicket(id: 't1', status: 'completed', total: 10000, openedAt: now);
      await insertPayment(id: 'p1', ticketId: 't1', method: 'cash', amount: 4000, paidAt: now);
      await insertPayment(
          id: 'p2', ticketId: 't1', method: 'credit_card', amount: 3500, paidAt: now);
      await insertPayment(
          id: 'p3', ticketId: 't1', method: 'debit_card', amount: 1500, paidAt: now);
      await insertPayment(id: 'p4', ticketId: 't1', method: 'other', amount: 1000, paidAt: now);

      final summary = await repo.getDashboardSummary(tenantId);
      expect(summary.cashRevenueCents, 4000);
      expect(summary.cardRevenueCents, 5000); // credit_card + debit_card
      expect(summary.otherRevenueCents, 1000);
    });

    test('totalPaymentsCents sums all methods', () async {
      await insertTenant();
      final now = DateTime.now();

      await insertTicket(id: 't1', status: 'completed', total: 9000, openedAt: now);
      await insertPayment(id: 'p1', ticketId: 't1', method: 'cash', amount: 5000, paidAt: now);
      await insertPayment(
          id: 'p2', ticketId: 't1', method: 'credit_card', amount: 4000, paidAt: now);

      final summary = await repo.getDashboardSummary(tenantId);
      expect(summary.totalPaymentsCents, 9000);
    });

    test('excludes payments from yesterday', () async {
      await insertTenant();
      final yesterday = DateTime.now().subtract(const Duration(days: 1));

      await insertTicket(id: 't1', status: 'completed', total: 5000, openedAt: yesterday);
      await insertPayment(
          id: 'p1', ticketId: 't1', method: 'cash', amount: 5000, paidAt: yesterday);

      final summary = await repo.getDashboardSummary(tenantId);
      expect(summary.totalPaymentsCents, 0);
    });
  });

  // =========================================================================
  // Table counts
  // =========================================================================

  group('table counts', () {
    test('counts occupied vs total correctly', () async {
      await insertTenant();
      await insertTable(id: 'tbl1', status: 'occupied');
      await insertTable(id: 'tbl2', status: 'occupied');
      await insertTable(id: 'tbl3', status: 'available');
      await insertTable(id: 'tbl4', status: 'reserved');

      final summary = await repo.getDashboardSummary(tenantId);
      expect(summary.occupiedTableCount, 2);
      expect(summary.totalTableCount, 4);
    });

    test('tableOccupancyRate is correct', () async {
      await insertTenant();
      await insertTable(id: 'tbl1', status: 'occupied');
      await insertTable(id: 'tbl2', status: 'available');
      await insertTable(id: 'tbl3', status: 'available');
      await insertTable(id: 'tbl4', status: 'available');

      final summary = await repo.getDashboardSummary(tenantId);
      expect(summary.tableOccupancyRate, closeTo(0.25, 0.01));
    });
  });

  // =========================================================================
  // Current shift
  // =========================================================================

  group('current shift', () {
    test('returns open shift', () async {
      await insertTenant();
      await insertShift(
        id: 'shift1',
        status: 'open',
        openedAt: DateTime.now().subtract(const Duration(hours: 2)),
        totalSales: 50000,
        totalOrders: 8,
        openingCash: 20000,
      );

      final summary = await repo.getDashboardSummary(tenantId);
      expect(summary.currentShift, isNotNull);
      expect(summary.currentShift!.id, 'shift1');
      expect(summary.currentShift!.isOpen, isTrue);
      expect(summary.currentShift!.totalSales, 50000);
      expect(summary.currentShift!.totalOrders, 8);
      expect(summary.currentShift!.openingCash, 20000);
    });

    test('returns null when no open shift', () async {
      await insertTenant();
      await insertShift(
        id: 'shift1',
        status: 'closed',
        openedAt: DateTime.now().subtract(const Duration(hours: 8)),
      );

      final summary = await repo.getDashboardSummary(tenantId);
      expect(summary.currentShift, isNull);
    });

    test('returns null for closing status', () async {
      await insertTenant();
      await insertShift(
        id: 'shift1',
        status: 'closing',
        openedAt: DateTime.now().subtract(const Duration(hours: 4)),
      );

      final summary = await repo.getDashboardSummary(tenantId);
      expect(summary.currentShift, isNull);
    });
  });

  // =========================================================================
  // Recent orders
  // =========================================================================

  group('recent orders', () {
    test('returns at most 10 orders', () async {
      await insertTenant();
      final now = DateTime.now();

      for (var i = 1; i <= 15; i++) {
        await insertTicket(
          id: 't$i',
          status: 'open',
          total: i * 100,
          openedAt: now.subtract(Duration(minutes: i)),
        );
      }

      final summary = await repo.getDashboardSummary(tenantId);
      expect(summary.recentOrders.length, 10);
    });

    test('orders are sorted newest first', () async {
      await insertTenant();
      final now = DateTime.now();

      await insertTicket(
          id: 'oldest', status: 'open', total: 100,
          openedAt: now.subtract(const Duration(hours: 2)));
      await insertTicket(
          id: 'newest', status: 'open', total: 200,
          openedAt: now.subtract(const Duration(minutes: 5)));

      final summary = await repo.getDashboardSummary(tenantId);
      expect(summary.recentOrders.first.id, 'newest');
      expect(summary.recentOrders.last.id, 'oldest');
    });

    test('orderNumber is zero-padded to 4 digits', () async {
      await insertTenant();
      await db.into(db.tickets).insert(TicketsCompanion(
            id: const Value('t1'),
            tenantId: const Value(tenantId),
            orderNumber: const Value(7),
            orderType: const Value('dine_in'),
            status: const Value('open'),
            channel: const Value('pos'),
            guestCount: const Value(1),
            subtotal: const Value(0),
            taxAmount: const Value(0),
            discountAmount: const Value(0),
            total: const Value(0),
            openedAt: Value(DateTime.now()),
            deviceId: const Value(deviceId),
            createdAt: Value(DateTime.now()),
            updatedAt: Value(DateTime.now()),
            isDeleted: const Value(false),
            syncStatus: const Value(0),
          ));

      final summary = await repo.getDashboardSummary(tenantId);
      expect(summary.recentOrders.first.orderNumber, '0007');
    });

    test('maps status and orderType fields correctly', () async {
      await insertTenant();
      await insertTicket(
        id: 't1',
        status: 'completed',
        total: 5000,
        openedAt: DateTime.now(),
        orderType: 'takeaway',
      );

      final summary = await repo.getDashboardSummary(tenantId);
      expect(summary.recentOrders.first.status, 'completed');
      expect(summary.recentOrders.first.orderType, 'takeaway');
      expect(summary.recentOrders.first.totalCents, 5000);
    });
  });

  // =========================================================================
  // Hourly sales
  // =========================================================================

  group('hourly sales', () {
    test('returns exactly 24 data points', () async {
      await insertTenant();
      final summary = await repo.getDashboardSummary(tenantId);
      expect(summary.hourlySales.length, 24);
    });

    test('each index matches its hour number', () async {
      await insertTenant();
      final summary = await repo.getDashboardSummary(tenantId);
      for (var h = 0; h < 24; h++) {
        expect(summary.hourlySales[h].hour, h);
      }
    });

    test('aggregates completed tickets by hour', () async {
      await insertTenant();
      final today = DateTime.now();
      final noon = DateTime(today.year, today.month, today.day, 12, 0);
      final lunchEnd = DateTime(today.year, today.month, today.day, 12, 45);
      final evening = DateTime(today.year, today.month, today.day, 19, 0);

      await insertTicket(id: 't1', status: 'completed', total: 3000, openedAt: noon);
      await insertTicket(id: 't2', status: 'completed', total: 2000, openedAt: lunchEnd);
      await insertTicket(id: 't3', status: 'completed', total: 5000, openedAt: evening);

      final summary = await repo.getDashboardSummary(tenantId);

      // Hour 12 should have both noon + lunchEnd tickets
      expect(summary.hourlySales[12].amountCents, 5000); // 3000 + 2000
      expect(summary.hourlySales[12].orderCount, 2);

      // Hour 19 should have one ticket
      expect(summary.hourlySales[19].amountCents, 5000);
      expect(summary.hourlySales[19].orderCount, 1);

      // Unrelated hour should be zero
      expect(summary.hourlySales[10].amountCents, 0);
    });

    test('does not count open/cancelled tickets in hourly chart', () async {
      await insertTenant();
      final today = DateTime.now();
      final hour14 = DateTime(today.year, today.month, today.day, 14);

      await insertTicket(id: 't1', status: 'open', total: 9999, openedAt: hour14);
      await insertTicket(id: 't2', status: 'cancelled', total: 9999, openedAt: hour14);

      final summary = await repo.getDashboardSummary(tenantId);
      expect(summary.hourlySales[14].amountCents, 0);
      expect(summary.hourlySales[14].orderCount, 0);
    });

    test('peakHourlyRevenueCents reflects max across all hours', () async {
      await insertTenant();
      final today = DateTime.now();

      // Insert in hour 10: CHF 80
      final h10 = DateTime(today.year, today.month, today.day, 10);
      await insertTicket(id: 't1', status: 'completed', total: 8000, openedAt: h10);

      // Insert in hour 14: CHF 200 (peak)
      final h14 = DateTime(today.year, today.month, today.day, 14);
      await insertTicket(id: 't2', status: 'completed', total: 20000, openedAt: h14);

      final summary = await repo.getDashboardSummary(tenantId);
      expect(summary.peakHourlyRevenueCents, 20000);
    });
  });

  // =========================================================================
  // Tenant isolation
  // =========================================================================

  group('tenant isolation', () {
    test('does not leak data from another tenant', () async {
      await insertTenant();

      // Insert data for a different tenant
      await db.into(db.tickets).insert(TicketsCompanion(
            id: const Value('other-t1'),
            tenantId: const Value('other-tenant'),
            orderNumber: const Value(1),
            orderType: const Value('dine_in'),
            status: const Value('completed'),
            channel: const Value('pos'),
            guestCount: const Value(1),
            subtotal: const Value(50000),
            taxAmount: const Value(0),
            discountAmount: const Value(0),
            total: const Value(50000),
            openedAt: Value(DateTime.now()),
            deviceId: const Value(deviceId),
            createdAt: Value(DateTime.now()),
            updatedAt: Value(DateTime.now()),
            isDeleted: const Value(false),
            syncStatus: const Value(0),
          ));

      // Query for test-tenant – must see 0 revenue
      final summary = await repo.getDashboardSummary(tenantId);
      expect(summary.dailyRevenueCents, 0);
      expect(summary.recentOrders, isEmpty);
    });
  });
}
