/// Dashboard endpoints — live metrics for the operator console.
library;

import '../client/gastrocore_client.dart';

/// Snapshot of "right now" numbers an operator wants to see.
class LiveMetrics {
  final String tenantId;
  final DateTime asOf;
  final int openTicketCount;
  final int todayTicketCount;
  final int todayRevenue;
  final int todayGuestCount;
  final int activeStaffCount;
  final double averageTicket;
  final int pendingKdsOrders;

  const LiveMetrics({
    required this.tenantId,
    required this.asOf,
    required this.openTicketCount,
    required this.todayTicketCount,
    required this.todayRevenue,
    required this.todayGuestCount,
    required this.activeStaffCount,
    required this.averageTicket,
    required this.pendingKdsOrders,
  });

  factory LiveMetrics.fromJson(Map<String, dynamic> json) => LiveMetrics(
        tenantId: json['tenant_id'] as String,
        asOf: DateTime.parse(json['as_of'] as String),
        openTicketCount:
            (json['open_ticket_count'] as num?)?.toInt() ?? 0,
        todayTicketCount:
            (json['today_ticket_count'] as num?)?.toInt() ?? 0,
        todayRevenue: (json['today_revenue'] as num?)?.toInt() ?? 0,
        todayGuestCount:
            (json['today_guest_count'] as num?)?.toInt() ?? 0,
        activeStaffCount:
            (json['active_staff_count'] as num?)?.toInt() ?? 0,
        averageTicket: (json['average_ticket'] as num?)?.toDouble() ?? 0.0,
        pendingKdsOrders:
            (json['pending_kds_orders'] as num?)?.toInt() ?? 0,
      );
}

/// One slice of the hour-of-day revenue chart.
class HourlyBucket {
  final int hour; // 0..23
  final int revenue;
  final int ticketCount;

  const HourlyBucket({
    required this.hour,
    required this.revenue,
    required this.ticketCount,
  });

  factory HourlyBucket.fromJson(Map<String, dynamic> json) => HourlyBucket(
        hour: (json['hour'] as num).toInt(),
        revenue: (json['revenue'] as num).toInt(),
        ticketCount: (json['ticket_count'] as num).toInt(),
      );
}

class DashboardEndpoint {
  final GastrocoreClient _client;

  const DashboardEndpoint(this._client);

  /// Instantaneous snapshot for the live panel.
  Future<LiveMetrics> getLiveMetrics({
    required String tenantId,
    String? storeId,
  }) async {
    final json = await _client.get(
      '/api/v1/dashboard/live',
      queryParams: {
        'tenant_id': tenantId,
        if (storeId != null) 'store_id': storeId,
      },
    );
    return LiveMetrics.fromJson(json);
  }

  /// Hour-of-day revenue series for today (or for [day] if provided).
  Future<List<HourlyBucket>> getHourlyRevenue({
    required String tenantId,
    String? storeId,
    DateTime? day,
  }) async {
    final list = await _client.getList(
      '/api/v1/dashboard/hourly',
      queryParams: {
        'tenant_id': tenantId,
        if (storeId != null) 'store_id': storeId,
        if (day != null) 'day': day.toIso8601String(),
      },
    );
    return list
        .map((j) => HourlyBucket.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// Count of guests currently seated across every floor.
  Future<int> seatedGuestCount({
    required String tenantId,
    String? storeId,
  }) async {
    final json = await _client.get(
      '/api/v1/dashboard/seated',
      queryParams: {
        'tenant_id': tenantId,
        if (storeId != null) 'store_id': storeId,
      },
    );
    return (json['count'] as num?)?.toInt() ?? 0;
  }
}
