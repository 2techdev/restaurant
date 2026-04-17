/// Report endpoints — Z-report, sales by range, top products.
library;

import 'package:gastrocore_models/gastrocore_models.dart';

import '../client/gastrocore_client.dart';

/// End-of-day rollup (Z-report) for a single business day / shift window.
class ZReport {
  final String tenantId;
  final String? storeId;
  final DateTime from;
  final DateTime to;

  /// Per-tax-bucket subtotals in cents.
  final Map<SwissMwstBucket, int> taxableByBucket;

  /// Tax collected per bucket (cents).
  final Map<SwissMwstBucket, int> taxByBucket;

  /// Per-payment-method totals (enum keyed).
  final Map<PaymentMethod, int> paymentsByMethod;

  final int grossSales;
  final int netSales;
  final int discountsTotal;
  final int serviceChargeTotal;
  final int tipsTotal;
  final int cashCountExpected;
  final int ticketCount;

  const ZReport({
    required this.tenantId,
    this.storeId,
    required this.from,
    required this.to,
    required this.taxableByBucket,
    required this.taxByBucket,
    required this.paymentsByMethod,
    required this.grossSales,
    required this.netSales,
    required this.discountsTotal,
    required this.serviceChargeTotal,
    required this.tipsTotal,
    required this.cashCountExpected,
    required this.ticketCount,
  });

  factory ZReport.fromJson(Map<String, dynamic> json) => ZReport(
        tenantId: json['tenant_id'] as String,
        storeId: json['store_id'] as String?,
        from: DateTime.parse(json['from'] as String),
        to: DateTime.parse(json['to'] as String),
        taxableByBucket: _bucketMap(json['taxable_by_bucket']),
        taxByBucket: _bucketMap(json['tax_by_bucket']),
        paymentsByMethod: _paymentMap(json['payments_by_method']),
        grossSales: (json['gross_sales'] as num?)?.toInt() ?? 0,
        netSales: (json['net_sales'] as num?)?.toInt() ?? 0,
        discountsTotal: (json['discounts_total'] as num?)?.toInt() ?? 0,
        serviceChargeTotal:
            (json['service_charge_total'] as num?)?.toInt() ?? 0,
        tipsTotal: (json['tips_total'] as num?)?.toInt() ?? 0,
        cashCountExpected:
            (json['cash_count_expected'] as num?)?.toInt() ?? 0,
        ticketCount: (json['ticket_count'] as num?)?.toInt() ?? 0,
      );

  static Map<SwissMwstBucket, int> _bucketMap(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        SwissMwstBucket.values.firstWhere(
              (e) => e.name == entry.key,
              orElse: () => SwissMwstBucket.standard,
            ): (entry.value as num?)?.toInt() ?? 0,
    };
  }

  static Map<PaymentMethod, int> _paymentMap(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        PaymentMethod.values.firstWhere(
              (e) => e.name == entry.key,
              orElse: () => PaymentMethod.other,
            ): (entry.value as num?)?.toInt() ?? 0,
    };
  }
}

/// One row in the top-products sales breakdown.
class ProductSales {
  final String productId;
  final String productName;
  final int quantity;
  final int grossAmount;

  const ProductSales({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.grossAmount,
  });

  factory ProductSales.fromJson(Map<String, dynamic> json) => ProductSales(
        productId: json['product_id'] as String,
        productName: json['product_name'] as String,
        quantity: (json['quantity'] as num).toInt(),
        grossAmount: (json['gross_amount'] as num).toInt(),
      );
}

class ReportEndpoint {
  final GastrocoreClient _client;

  const ReportEndpoint(this._client);

  /// Generate / fetch a Z-report for the closing window.
  Future<ZReport> zReport({
    required String tenantId,
    String? storeId,
    required DateTime from,
    required DateTime to,
  }) async {
    final json = await _client.get(
      '/api/v1/reports/z',
      queryParams: {
        'tenant_id': tenantId,
        if (storeId != null) 'store_id': storeId,
        'from': from.toIso8601String(),
        'to': to.toIso8601String(),
      },
    );
    return ZReport.fromJson(json);
  }

  /// Daily sales totals grouped by business date.
  Future<Map<DateTime, int>> salesByDay({
    required String tenantId,
    required DateTime from,
    required DateTime to,
  }) async {
    final list = await _client.getList(
      '/api/v1/reports/sales-by-day',
      queryParams: {
        'tenant_id': tenantId,
        'from': from.toIso8601String(),
        'to': to.toIso8601String(),
      },
    );
    return {
      for (final row in list.cast<Map<String, dynamic>>())
        DateTime.parse(row['date'] as String):
            (row['gross'] as num).toInt(),
    };
  }

  Future<List<ProductSales>> topProducts({
    required String tenantId,
    required DateTime from,
    required DateTime to,
    int limit = 20,
  }) async {
    final list = await _client.getList(
      '/api/v1/reports/top-products',
      queryParams: {
        'tenant_id': tenantId,
        'from': from.toIso8601String(),
        'to': to.toIso8601String(),
        'limit': limit.toString(),
      },
    );
    return list
        .map((j) => ProductSales.fromJson(j as Map<String, dynamic>))
        .toList();
  }
}
