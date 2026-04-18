/// Z-report repository — fetches an end-of-day rollup for a given date.
///
/// TODO(boss-sprint2): wire to `ReportApi.zReport(date)` once available.
/// For now we synthesize a deterministic placeholder that exercises every
/// VAT bucket and payment method so the UI can be reviewed end-to-end.
library;

import 'zreport_models.dart';

class ZReportRepository {
  Future<ZReport> fetchZReport(DateTime date) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return _placeholder(date);
  }

  ZReport _placeholder(DateTime date) {
    // Deterministic figures — vary slightly with day-of-month so consecutive
    // dates look different in the picker without needing real data.
    final day = date.day;
    final base = 3200 + (day * 35);

    final vat81Net = base * 0.55;
    final vat26Net = base * 0.30;
    final vat0Net = base * 0.05;

    return ZReport(
      businessDay: DateTime(date.year, date.month, date.day),
      grossSalesChf: base.toDouble(),
      netSalesChf: vat81Net + vat26Net + vat0Net,
      discountTotalChf: 42 + (day % 7) * 3.5,
      serviceChargeChf: 18 + (day % 4) * 2.0,
      vatBuckets: [
        VatBucket(
          ratePercent: 8.1,
          netChf: vat81Net,
          taxChf: vat81Net * 0.081,
        ),
        VatBucket(
          ratePercent: 2.6,
          netChf: vat26Net,
          taxChf: vat26Net * 0.026,
        ),
        VatBucket(ratePercent: 0, netChf: vat0Net, taxChf: 0),
      ],
      paymentBuckets: [
        PaymentBucket(method: 'cash', amountChf: base * 0.30, count: 18),
        PaymentBucket(method: 'card', amountChf: base * 0.55, count: 32),
        PaymentBucket(method: 'twint', amountChf: base * 0.15, count: 9),
      ],
    );
  }
}
