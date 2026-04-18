import 'package:flutter_test/flutter_test.dart';
import 'package:gastrocore_boss/features/reports/zreport_models.dart';

void main() {
  group('ZReport.fromJson', () {
    test('parses canonical envelope (data wrapper)', () {
      final z = ZReport.fromJson({
        'data': {
          'business_day': '2026-04-17',
          'gross_sales_chf': 4280.50,
          'net_sales_chf': 3950.20,
          'discount_total_chf': 65,
          'service_charge_chf': 22,
          'vat_buckets': [
            {'rate_percent': 8.1, 'net_chf': 2200, 'tax_chf': 178.20},
            {'rate_percent': 2.6, 'net_chf': 1500, 'tax_chf': 39.0},
          ],
          'payment_buckets': [
            {'method': 'CASH', 'amount_chf': 1200, 'count': 18},
            {'method': 'card', 'amount_chf': 2300, 'count': 32},
          ],
        },
      });

      expect(z.businessDay, DateTime(2026, 4, 17));
      expect(z.grossSalesChf, 4280.50);
      expect(z.vatBuckets, hasLength(2));
      expect(z.vatBuckets[0].ratePercent, 8.1);
      expect(z.totalTaxChf, closeTo(217.20, 0.001));
      expect(z.paymentBuckets, hasLength(2));
      // Method codes are normalised to lowercase.
      expect(z.paymentBuckets[0].method, 'cash');
    });

    test('falls back to short field names', () {
      final z = ZReport.fromJson({
        'date': '2026-04-17',
        'gross': 100,
        'net': 90,
        'discount': 5,
        'service_charge': 2,
        'mwst': [
          {'rate': 8.1, 'net': 90, 'tax': 7.29},
        ],
        'payments': [
          {'method': 'twint', 'amount': 100, 'count': 4},
        ],
      });
      expect(z.grossSalesChf, 100);
      expect(z.vatBuckets.single.ratePercent, 8.1);
      expect(z.paymentBuckets.single.method, 'twint');
      expect(z.paymentBuckets.single.count, 4);
    });

    test('tolerates missing buckets', () {
      final z = ZReport.fromJson({
        'business_day': '2026-04-17',
        'gross_sales_chf': 0,
      });
      expect(z.vatBuckets, isEmpty);
      expect(z.paymentBuckets, isEmpty);
      expect(z.totalTaxChf, 0);
    });

    test('coerces string-valued numbers', () {
      final z = ZReport.fromJson({
        'business_day': '2026-04-17',
        'gross_sales_chf': '123.45',
        'vat_buckets': [
          {'rate_percent': '8.1', 'net_chf': '100', 'tax_chf': '8.10'},
        ],
      });
      expect(z.grossSalesChf, 123.45);
      expect(z.vatBuckets.single.taxChf, closeTo(8.10, 0.001));
    });
  });

  group('VatBucket', () {
    test('grossChf == net + tax', () {
      const b = VatBucket(ratePercent: 8.1, netChf: 100, taxChf: 8.10);
      expect(b.grossChf, closeTo(108.10, 0.001));
    });
  });
}
