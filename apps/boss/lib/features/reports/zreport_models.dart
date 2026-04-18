/// Local DTOs for the Boss Z-report screen.
///
/// Modelled on Swiss MWST reporting: each VAT rate forms a bucket with
/// its own gross/net/tax tally; payment methods (cash/card/twint/...)
/// are tracked separately.
///
/// TODO(boss-sprint2): replace with `gastrocore_models` versions once
/// commit a1e3fc0 (ReportApi.zReport DTOs) lands here.
library;

class ZReport {
  final DateTime businessDay;
  final double grossSalesChf;
  final double netSalesChf;
  final double discountTotalChf;
  final double serviceChargeChf;
  final List<VatBucket> vatBuckets;
  final List<PaymentBucket> paymentBuckets;

  const ZReport({
    required this.businessDay,
    required this.grossSalesChf,
    required this.netSalesChf,
    required this.discountTotalChf,
    required this.serviceChargeChf,
    required this.vatBuckets,
    required this.paymentBuckets,
  });

  double get totalTaxChf =>
      vatBuckets.fold(0.0, (sum, b) => sum + b.taxChf);

  /// Parse a JSON envelope as returned by the Go backend's
  /// `GET /api/v1/reports/zreport?date=YYYY-MM-DD` endpoint.
  ///
  /// The schema is intentionally tolerant of missing fields so the parser
  /// works against both the placeholder repo and the eventual real
  /// payload.
  factory ZReport.fromJson(Map<String, dynamic> json) {
    final raw = (json['data'] ?? json) as Map<String, dynamic>;

    return ZReport(
      businessDay: DateTime.parse(
        raw['business_day'] as String? ??
            raw['date'] as String? ??
            DateTime.now().toIso8601String(),
      ),
      grossSalesChf: _toDouble(raw['gross_sales_chf'] ?? raw['gross']),
      netSalesChf: _toDouble(raw['net_sales_chf'] ?? raw['net']),
      discountTotalChf:
          _toDouble(raw['discount_total_chf'] ?? raw['discount']),
      serviceChargeChf:
          _toDouble(raw['service_charge_chf'] ?? raw['service_charge']),
      vatBuckets: _parseList(
        raw['vat_buckets'] ?? raw['mwst'] ?? const [],
        VatBucket.fromJson,
      ),
      paymentBuckets: _parseList(
        raw['payment_buckets'] ?? raw['payments'] ?? const [],
        PaymentBucket.fromJson,
      ),
    );
  }

  static List<T> _parseList<T>(
    Object input,
    T Function(Map<String, dynamic>) parser,
  ) {
    if (input is! List) return const [];
    return input
        .whereType<Map<String, dynamic>>()
        .map(parser)
        .toList(growable: false);
  }
}

class VatBucket {
  /// Rate as a percentage, e.g. 8.1 for the standard Swiss MWST rate.
  final double ratePercent;
  final double netChf;
  final double taxChf;

  const VatBucket({
    required this.ratePercent,
    required this.netChf,
    required this.taxChf,
  });

  double get grossChf => netChf + taxChf;

  factory VatBucket.fromJson(Map<String, dynamic> json) => VatBucket(
        ratePercent: _toDouble(json['rate_percent'] ?? json['rate']),
        netChf: _toDouble(json['net_chf'] ?? json['net']),
        taxChf: _toDouble(json['tax_chf'] ?? json['tax']),
      );
}

class PaymentBucket {
  /// Canonical method code: `cash`, `card`, `twint`, `voucher`, etc.
  final String method;
  final double amountChf;
  final int count;

  const PaymentBucket({
    required this.method,
    required this.amountChf,
    required this.count,
  });

  factory PaymentBucket.fromJson(Map<String, dynamic> json) => PaymentBucket(
        method: (json['method'] as String? ?? 'unknown').toLowerCase(),
        amountChf: _toDouble(json['amount_chf'] ?? json['amount']),
        count: (json['count'] as num?)?.toInt() ?? 0,
      );
}

double _toDouble(Object? raw) {
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw) ?? 0;
  return 0;
}
