import 'package:flutter_test/flutter_test.dart';
import 'package:gastrocore_dashboard/core/api/models.dart';

void main() {
  group('DashboardStats', () {
    test('demo returns valid stats', () {
      final stats = DashboardStats.demo;
      expect(stats.totalRevenue, greaterThan(0));
      expect(stats.orderCount, greaterThan(0));
      expect(stats.topItems.length, equals(5));
    });

    test('fromJson parses correctly', () {
      final json = {
        'date': '2026-03-21',
        'total_revenue': 384750,
        'order_count': 47,
        'avg_ticket': 8186,
        'active_orders': 6,
        'tables_occupied': 8,
        'open_orders': 6,
        'staff_on_shift': 4,
        'top_items': <dynamic>[],
      };
      final stats = DashboardStats.fromJson(json);
      expect(stats.totalRevenue, equals(384750));
      expect(stats.orderCount, equals(47));
      expect(stats.topItems, isEmpty);
    });
  });

  group('RevenuePoint', () {
    test('demo returns 7 data points', () {
      expect(RevenuePoint.demo.length, equals(7));
    });
  });

  group('Order', () {
    test('demo returns 25 orders', () {
      expect(Order.demo.length, equals(25));
    });
  });

  group('MWSTReport', () {
    test('demo totals add up', () {
      final report = MWSTReport.demo;
      expect(report.totalGross, equals(report.totalNet + report.totalTax));
    });
  });
}
