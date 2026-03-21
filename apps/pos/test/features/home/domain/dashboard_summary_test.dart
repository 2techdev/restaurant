import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/features/home/domain/entities/dashboard_summary.dart';
import 'package:gastrocore_pos/features/shifts/domain/entities/shift_entity.dart';

void main() {
  group('HourlySalesPoint', () {
    test('equality holds for identical values', () {
      const a = HourlySalesPoint(hour: 12, amountCents: 5000, orderCount: 3);
      const b = HourlySalesPoint(hour: 12, amountCents: 5000, orderCount: 3);
      expect(a, equals(b));
    });

    test('inequality when any field differs', () {
      const a = HourlySalesPoint(hour: 12, amountCents: 5000, orderCount: 3);
      const b = HourlySalesPoint(hour: 13, amountCents: 5000, orderCount: 3);
      expect(a, isNot(equals(b)));
    });
  });

  group('RecentOrderRow', () {
    final now = DateTime(2026, 3, 20, 14, 30);

    test('equality holds', () {
      final a = RecentOrderRow(
        id: 'abc',
        orderNumber: '0042',
        status: 'completed',
        totalCents: 2500,
        openedAt: now,
        orderType: 'dine_in',
      );
      final b = RecentOrderRow(
        id: 'abc',
        orderNumber: '0042',
        status: 'completed',
        totalCents: 2500,
        openedAt: now,
        orderType: 'dine_in',
      );
      expect(a, equals(b));
    });
  });

  group('DashboardSummaryEntity', () {
    DashboardSummaryEntity makeSummary({
      int dailyRevenueCents = 100000,
      int dailyOrderCount = 10,
      int cashRevenueCents = 40000,
      int cardRevenueCents = 50000,
      int otherRevenueCents = 10000,
      int occupiedTableCount = 3,
      int totalTableCount = 10,
      ShiftEntity? currentShift,
    }) {
      return DashboardSummaryEntity(
        dailyRevenueCents: dailyRevenueCents,
        dailyOrderCount: dailyOrderCount,
        cashRevenueCents: cashRevenueCents,
        cardRevenueCents: cardRevenueCents,
        otherRevenueCents: otherRevenueCents,
        occupiedTableCount: occupiedTableCount,
        totalTableCount: totalTableCount,
        currentShift: currentShift,
        recentOrders: const [],
        hourlySales: List.generate(
          24,
          (h) => HourlySalesPoint(hour: h, amountCents: 0, orderCount: 0),
        ),
      );
    }

    test('dailyAverageOrderCents divides correctly', () {
      // 100 000 cents / 10 orders = 10 000 cents = CHF 100.00
      final s = makeSummary(dailyRevenueCents: 100000, dailyOrderCount: 10);
      expect(s.dailyAverageOrderCents, 10000);
    });

    test('dailyAverageOrderCents is 0 when no orders', () {
      final s = makeSummary(dailyRevenueCents: 0, dailyOrderCount: 0);
      expect(s.dailyAverageOrderCents, 0);
    });

    test('tableOccupancyRate calculates fraction', () {
      final s = makeSummary(occupiedTableCount: 3, totalTableCount: 10);
      expect(s.tableOccupancyRate, closeTo(0.3, 0.001));
    });

    test('tableOccupancyRate is 0.0 when no tables configured', () {
      final s = makeSummary(occupiedTableCount: 0, totalTableCount: 0);
      expect(s.tableOccupancyRate, 0.0);
    });

    test('tableOccupancyRate is 1.0 when all tables occupied', () {
      final s = makeSummary(occupiedTableCount: 5, totalTableCount: 5);
      expect(s.tableOccupancyRate, 1.0);
    });

    test('totalPaymentsCents sums all methods', () {
      final s = makeSummary(
        cashRevenueCents: 40000,
        cardRevenueCents: 50000,
        otherRevenueCents: 10000,
      );
      expect(s.totalPaymentsCents, 100000);
    });

    test('hasActiveShift is false when no shift', () {
      final s = makeSummary();
      expect(s.hasActiveShift, isFalse);
    });

    test('hasActiveShift is true when shift is open', () {
      final shift = ShiftEntity(
        id: 's1',
        tenantId: 'tenant1',
        userId: 'u1',
        deviceId: 'd1',
        openingCash: 20000,
        status: ShiftStatus.open,
        openedAt: DateTime(2026, 3, 20, 8, 0),
      );
      final s = makeSummary(currentShift: shift);
      expect(s.hasActiveShift, isTrue);
    });

    test('hasActiveShift is false when shift is closed', () {
      final shift = ShiftEntity(
        id: 's1',
        tenantId: 'tenant1',
        userId: 'u1',
        deviceId: 'd1',
        openingCash: 20000,
        status: ShiftStatus.closed,
        openedAt: DateTime(2026, 3, 20, 8, 0),
        closedAt: DateTime(2026, 3, 20, 16, 0),
      );
      final s = makeSummary(currentShift: shift);
      expect(s.hasActiveShift, isFalse);
    });

    test('peakHourlyRevenueCents returns max across all hours', () {
      final hourly = List.generate(
        24,
        (h) => HourlySalesPoint(
          hour: h,
          amountCents: h == 12 ? 50000 : 10000,
          orderCount: 1,
        ),
      );
      final s = DashboardSummaryEntity(
        dailyRevenueCents: 0,
        dailyOrderCount: 0,
        cashRevenueCents: 0,
        cardRevenueCents: 0,
        otherRevenueCents: 0,
        occupiedTableCount: 0,
        totalTableCount: 0,
        recentOrders: const [],
        hourlySales: hourly,
      );
      expect(s.peakHourlyRevenueCents, 50000);
    });

    test('peakHourlyRevenueCents is 0 when no sales', () {
      final s = makeSummary();
      expect(s.peakHourlyRevenueCents, 0);
    });

    test('empty() factory creates zero-value entity', () {
      final s = DashboardSummaryEntity.empty();
      expect(s.dailyRevenueCents, 0);
      expect(s.dailyOrderCount, 0);
      expect(s.dailyAverageOrderCents, 0);
      expect(s.occupiedTableCount, 0);
      expect(s.totalTableCount, 0);
      expect(s.hasActiveShift, isFalse);
      expect(s.hourlySales.length, 24);
      expect(s.hourlySales.every((h) => h.amountCents == 0), isTrue);
    });

    test('equality does not consider recentOrders or hourlySales', () {
      final a = makeSummary(dailyRevenueCents: 5000);
      final b = makeSummary(dailyRevenueCents: 5000);
      expect(a, equals(b));
    });
  });
}
