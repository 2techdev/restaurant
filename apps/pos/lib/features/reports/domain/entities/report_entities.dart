/// Plain domain models that the reports repository returns.
///
/// These are immutable snapshots — the repository runs the query, aggregates
/// into these shapes, and hands them to the UI. The UI never queries Drift
/// directly so swapping to a remote source later is a no-op at the edges.
library;

import 'dart:convert';

/// One Swiss MWST rate bucket (8.1, 2.6, 3.8 — or whatever the tax
/// profiles table hands us at query time).
class MwstBucket {
  const MwstBucket({
    required this.rateBps,
    required this.grossCents,
    required this.netCents,
    required this.taxCents,
  });

  /// Rate in basis points — 810 = 8.1%, 260 = 2.6%, 380 = 3.8%. Stored
  /// this way to keep arithmetic on integers all the way through.
  final int rateBps;
  final int grossCents;
  final int netCents;
  final int taxCents;

  double get ratePercent => rateBps / 100.0;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'rateBps': rateBps,
        'grossCents': grossCents,
        'netCents': netCents,
        'taxCents': taxCents,
      };

  factory MwstBucket.fromJson(Map<String, dynamic> json) => MwstBucket(
        rateBps: (json['rateBps'] as num).toInt(),
        grossCents: (json['grossCents'] as num).toInt(),
        netCents: (json['netCents'] as num).toInt(),
        taxCents: (json['taxCents'] as num).toInt(),
      );
}

class PaymentBreakdownEntry {
  const PaymentBreakdownEntry({
    required this.method,
    required this.totalCents,
    required this.count,
  });

  final String method; // 'cash' | 'credit_card' | 'debit_card' | 'other'
  final int totalCents;
  final int count;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'method': method,
        'totalCents': totalCents,
        'count': count,
      };

  factory PaymentBreakdownEntry.fromJson(Map<String, dynamic> json) =>
      PaymentBreakdownEntry(
        method: json['method'] as String,
        totalCents: (json['totalCents'] as num).toInt(),
        count: (json['count'] as num).toInt(),
      );
}

class TopProductEntry {
  const TopProductEntry({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.revenueCents,
  });

  final String productId;
  final String productName;
  final double quantity;
  final int revenueCents;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'productId': productId,
        'productName': productName,
        'quantity': quantity,
        'revenueCents': revenueCents,
      };

  factory TopProductEntry.fromJson(Map<String, dynamic> json) =>
      TopProductEntry(
        productId: json['productId'] as String,
        productName: json['productName'] as String,
        quantity: (json['quantity'] as num).toDouble(),
        revenueCents: (json['revenueCents'] as num).toInt(),
      );
}

class CategoryBreakdownEntry {
  const CategoryBreakdownEntry({
    required this.categoryId,
    required this.categoryName,
    required this.revenueCents,
    required this.quantity,
  });

  final String? categoryId;
  final String categoryName;
  final int revenueCents;
  final double quantity;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'categoryId': categoryId,
        'categoryName': categoryName,
        'revenueCents': revenueCents,
        'quantity': quantity,
      };

  factory CategoryBreakdownEntry.fromJson(Map<String, dynamic> json) =>
      CategoryBreakdownEntry(
        categoryId: json['categoryId'] as String?,
        categoryName: json['categoryName'] as String,
        revenueCents: (json['revenueCents'] as num).toInt(),
        quantity: (json['quantity'] as num).toDouble(),
      );
}

/// Per-waiter performance line. [waiterId] is the user id on the tickets
/// table; [waiterName] is pre-joined from the users table so the UI can
/// render it without a second round trip.
class WaiterBreakdownEntry {
  const WaiterBreakdownEntry({
    required this.waiterId,
    required this.waiterName,
    required this.ticketCount,
    required this.revenueCents,
    required this.tipCents,
  });

  final String waiterId;
  final String waiterName;
  final int ticketCount;
  final int revenueCents;
  final int tipCents;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'waiterId': waiterId,
        'waiterName': waiterName,
        'ticketCount': ticketCount,
        'revenueCents': revenueCents,
        'tipCents': tipCents,
      };

  factory WaiterBreakdownEntry.fromJson(Map<String, dynamic> json) =>
      WaiterBreakdownEntry(
        waiterId: json['waiterId'] as String,
        waiterName: json['waiterName'] as String,
        ticketCount: (json['ticketCount'] as num).toInt(),
        revenueCents: (json['revenueCents'] as num).toInt(),
        tipCents: (json['tipCents'] as num).toInt(),
      );
}

class HourlyBreakdownEntry {
  const HourlyBreakdownEntry({
    required this.hour,
    required this.ticketCount,
    required this.revenueCents,
  });

  final int hour; // 0-23
  final int ticketCount;
  final int revenueCents;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'hour': hour,
        'ticketCount': ticketCount,
        'revenueCents': revenueCents,
      };

  factory HourlyBreakdownEntry.fromJson(Map<String, dynamic> json) =>
      HourlyBreakdownEntry(
        hour: (json['hour'] as num).toInt(),
        ticketCount: (json['ticketCount'] as num).toInt(),
        revenueCents: (json['revenueCents'] as num).toInt(),
      );
}

/// Full Z/period/monthly report — the same shape powers all three. The
/// screen picks a label + date window, the repository fills the totals.
class ReportSnapshot {
  const ReportSnapshot({
    required this.fromTs,
    required this.toTs,
    required this.ticketCount,
    required this.grossTotalCents,
    required this.netTotalCents,
    required this.taxTotalCents,
    required this.discountTotalCents,
    required this.giftTotalCents,
    required this.tipTotalCents,
    required this.voidCount,
    required this.mwstBuckets,
    required this.payments,
    required this.topProducts,
    required this.categories,
    required this.hourly,
    this.waiters = const [],
  });

  final DateTime fromTs;
  final DateTime toTs;
  final int ticketCount;
  final int grossTotalCents;
  final int netTotalCents;
  final int taxTotalCents;
  final int discountTotalCents;
  final int giftTotalCents;
  final int tipTotalCents;
  final int voidCount;
  final List<MwstBucket> mwstBuckets;
  final List<PaymentBreakdownEntry> payments;
  final List<TopProductEntry> topProducts;
  final List<CategoryBreakdownEntry> categories;
  final List<HourlyBreakdownEntry> hourly;
  final List<WaiterBreakdownEntry> waiters;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'fromTs': fromTs.toIso8601String(),
        'toTs': toTs.toIso8601String(),
        'ticketCount': ticketCount,
        'grossTotalCents': grossTotalCents,
        'netTotalCents': netTotalCents,
        'taxTotalCents': taxTotalCents,
        'discountTotalCents': discountTotalCents,
        'giftTotalCents': giftTotalCents,
        'tipTotalCents': tipTotalCents,
        'voidCount': voidCount,
        'mwstBuckets': mwstBuckets.map((b) => b.toJson()).toList(),
        'payments': payments.map((p) => p.toJson()).toList(),
        'topProducts': topProducts.map((t) => t.toJson()).toList(),
        'categories': categories.map((c) => c.toJson()).toList(),
        'hourly': hourly.map((h) => h.toJson()).toList(),
        'waiters': waiters.map((w) => w.toJson()).toList(),
      };

  String toJsonString() => jsonEncode(toJson());

  factory ReportSnapshot.fromJson(Map<String, dynamic> json) => ReportSnapshot(
        fromTs: DateTime.parse(json['fromTs'] as String),
        toTs: DateTime.parse(json['toTs'] as String),
        ticketCount: (json['ticketCount'] as num).toInt(),
        grossTotalCents: (json['grossTotalCents'] as num).toInt(),
        netTotalCents: (json['netTotalCents'] as num).toInt(),
        taxTotalCents: (json['taxTotalCents'] as num).toInt(),
        discountTotalCents: (json['discountTotalCents'] as num).toInt(),
        giftTotalCents: (json['giftTotalCents'] as num? ?? 0).toInt(),
        tipTotalCents: (json['tipTotalCents'] as num).toInt(),
        voidCount: (json['voidCount'] as num).toInt(),
        mwstBuckets: (json['mwstBuckets'] as List<dynamic>)
            .map((e) => MwstBucket.fromJson(e as Map<String, dynamic>))
            .toList(),
        payments: (json['payments'] as List<dynamic>)
            .map((e) =>
                PaymentBreakdownEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        topProducts: (json['topProducts'] as List<dynamic>)
            .map((e) => TopProductEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        categories: (json['categories'] as List<dynamic>)
            .map((e) =>
                CategoryBreakdownEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        hourly: (json['hourly'] as List<dynamic>)
            .map((e) =>
                HourlyBreakdownEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        waiters: (json['waiters'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) =>
                WaiterBreakdownEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  factory ReportSnapshot.fromJsonString(String s) =>
      ReportSnapshot.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

/// A previously-sealed Z report pulled back from the ZReports table.
class ZSealEntity {
  const ZSealEntity({
    required this.id,
    required this.tenantId,
    required this.sequenceNumber,
    required this.fromTs,
    required this.toTs,
    required this.closedAt,
    required this.closedBy,
    required this.snapshot,
  });

  final String id;
  final String tenantId;
  final int sequenceNumber;
  final DateTime fromTs;
  final DateTime toTs;
  final DateTime closedAt;
  final String closedBy;
  final ReportSnapshot snapshot;
}
