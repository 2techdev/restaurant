import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gastrocore_boss/features/dashboard/dashboard_models.dart';
import 'package:gastrocore_boss/features/dashboard/dashboard_providers.dart';
import 'package:gastrocore_boss/features/dashboard/dashboard_screen.dart';
import 'package:gastrocore_boss/features/dashboard/dashboard_repository.dart';

class _StaticRepo extends DashboardRepository {
  @override
  Stream<LiveMetrics> watchLiveMetrics({Duration interval = const Duration(seconds: 30)}) {
    return Stream.value(
      LiveMetrics(
        todayRevenueChf: 4280,
        openTableCount: 7,
        activeOrderCount: 12,
        last15MinCovers: 9,
        top5: const [
          TopProduct(name: 'Ribeye', quantity: 18, revenueChf: 882),
          TopProduct(name: 'Caesar', quantity: 22, revenueChf: 396),
          TopProduct(name: 'Tiramisu', quantity: 15, revenueChf: 187),
          TopProduct(name: 'Espresso', quantity: 41, revenueChf: 184),
          TopProduct(name: 'Wasser', quantity: 28, revenueChf: 168),
        ],
        asOf: DateTime(2026, 4, 17, 12, 30, 0),
      ),
    );
  }

  @override
  Stream<PaymentEvent> watchPaymentEvents() => const Stream.empty();
}

void main() {
  testWidgets('DashboardScreen renders KPI tiles and revenue', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dashboardRepositoryProvider.overrideWithValue(_StaticRepo()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: DashboardScreen()),
        ),
      ),
    );
    await tester.pump(); // initial frame
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Bugün'), findsOneWidget);
    expect(find.textContaining('CHF'), findsWidgets);
    expect(find.text('Açık masa'), findsOneWidget);
    expect(find.text('Aktif sipariş'), findsOneWidget);
    expect(find.text('Son 15dk kişi'), findsOneWidget);
    expect(find.text('En çok satan 5'), findsOneWidget);
    expect(find.byKey(const Key('boss-revenue-card')), findsOneWidget);
  });

  testWidgets('DashboardScreen shows top product names', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dashboardRepositoryProvider.overrideWithValue(_StaticRepo()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: DashboardScreen()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Ribeye'), findsWidgets);
    expect(find.text('× 18'), findsOneWidget);
    expect(find.text('× 22'), findsOneWidget);
  });
}
