import 'package:flutter_test/flutter_test.dart';
import 'package:gastrocore_boss/features/dashboard/dashboard_repository.dart';

void main() {
  group('DashboardRepository placeholder data', () {
    test('emits an initial metrics snapshot immediately', () async {
      final repo = DashboardRepository();
      final first = await repo
          .watchLiveMetrics(interval: const Duration(milliseconds: 50))
          .first;

      expect(first.todayRevenueChf, greaterThan(0));
      expect(first.openTableCount, greaterThanOrEqualTo(0));
      expect(first.activeOrderCount, greaterThanOrEqualTo(0));
      expect(first.last15MinCovers, greaterThanOrEqualTo(0));
      expect(first.top5, hasLength(5));
      expect(first.asOf.isBefore(DateTime.now().add(const Duration(seconds: 1))),
          isTrue);
    });

    test('top5 entries have non-empty names and positive quantities',
        () async {
      final first = await DashboardRepository()
          .watchLiveMetrics(interval: const Duration(milliseconds: 50))
          .first;
      for (final p in first.top5) {
        expect(p.name, isNotEmpty);
        expect(p.quantity, greaterThan(0));
        expect(p.revenueChf, greaterThanOrEqualTo(0));
      }
    });
  });
}
