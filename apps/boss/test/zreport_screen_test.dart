import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gastrocore_boss/features/reports/zreport_models.dart';
import 'package:gastrocore_boss/features/reports/zreport_providers.dart';
import 'package:gastrocore_boss/features/reports/zreport_repository.dart';
import 'package:gastrocore_boss/features/reports/zreport_screen.dart';
import 'package:intl/date_symbol_data_local.dart';

class _StaticZRepo extends ZReportRepository {
  @override
  Future<ZReport> fetchZReport(DateTime date) async {
    return ZReport(
      businessDay: date,
      grossSalesChf: 4280.50,
      netSalesChf: 3950.20,
      discountTotalChf: 65,
      serviceChargeChf: 22,
      vatBuckets: const [
        VatBucket(ratePercent: 8.1, netChf: 2200, taxChf: 178.20),
        VatBucket(ratePercent: 2.6, netChf: 1500, taxChf: 39.0),
      ],
      paymentBuckets: const [
        PaymentBucket(method: 'cash', amountChf: 1200, count: 18),
        PaymentBucket(method: 'card', amountChf: 2300, count: 32),
        PaymentBucket(method: 'twint', amountChf: 780, count: 9),
      ],
    );
  }
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr');
  });

  testWidgets('ZReportScreen shows summary, VAT, and payment sections',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          zReportRepositoryProvider.overrideWithValue(_StaticZRepo()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ZReportScreen()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Günlük özet'), findsOneWidget);
    expect(find.text('MWST (KDV)'), findsOneWidget);
    expect(find.text('Ödeme yöntemi'), findsOneWidget);
    expect(find.text('Nakit'), findsOneWidget);
    expect(find.text('Kart'), findsOneWidget);
    expect(find.text('TWINT'), findsOneWidget);
    expect(find.text('%8.1'), findsOneWidget);
    expect(find.text('%2.6'), findsOneWidget);
  });

  testWidgets('Prev/next day buttons shift the selected date', (tester) async {
    final container = ProviderContainer(
      overrides: [
        zReportRepositoryProvider.overrideWithValue(_StaticZRepo()),
      ],
    );
    addTearDown(container.dispose);

    final initial = container.read(selectedDateProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: ZReportScreen()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const Key('zreport-prev-day')));
    await tester.pump();

    final after = container.read(selectedDateProvider);
    expect(after, initial.subtract(const Duration(days: 1)));
  });
}
