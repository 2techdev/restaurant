/// Domain models for online order submission and tracking.
library;

// ---------------------------------------------------------------------------
// Order type
// ---------------------------------------------------------------------------

enum OrderType { dineIn, takeaway }

extension OrderTypeExtension on OrderType {
  String get apiValue =>
      this == OrderType.dineIn ? 'dine_in' : 'takeaway';
}

// ---------------------------------------------------------------------------
// Order status (for tracking)
// ---------------------------------------------------------------------------

enum OrderStatus {
  received,
  preparing,
  ready,
  served,
  unknown;

  static OrderStatus fromString(String s) {
    switch (s) {
      case 'received':
      case 'open':
      case 'items_added':
        return OrderStatus.received;
      case 'sent_to_kitchen':
      case 'preparing':
        return OrderStatus.preparing;
      case 'ready':
      case 'fully_served':
      case 'partially_served':
        return OrderStatus.ready;
      case 'served':
      case 'closed':
      case 'fully_paid':
        return OrderStatus.served;
      default:
        return OrderStatus.unknown;
    }
  }
}

// ---------------------------------------------------------------------------
// Placed order response
// ---------------------------------------------------------------------------

class PlacedOrder {
  final String id;
  final int orderNumber;
  final OrderStatus status;
  final int estimatedWaitMinutes;
  final DateTime createdAt;

  const PlacedOrder({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.estimatedWaitMinutes,
    required this.createdAt,
  });

  factory PlacedOrder.fromJson(Map<String, dynamic> json) => PlacedOrder(
        id: json['id'] as String,
        orderNumber: json['order_number'] as int,
        status: OrderStatus.fromString(
            json['status'] as String? ?? 'received'),
        estimatedWaitMinutes:
            json['estimated_wait_minutes'] as int? ?? 20,
        createdAt: DateTime.tryParse(
                json['created_at'] as String? ?? '') ??
            DateTime.now(),
      );
}

// ---------------------------------------------------------------------------
// Order status response (for polling)
// ---------------------------------------------------------------------------

class OrderStatusResponse {
  final String orderId;
  final int orderNumber;
  final OrderStatus status;
  final int estimatedWaitMinutes;

  const OrderStatusResponse({
    required this.orderId,
    required this.orderNumber,
    required this.status,
    required this.estimatedWaitMinutes,
  });

  factory OrderStatusResponse.fromJson(Map<String, dynamic> json) =>
      OrderStatusResponse(
        orderId: json['order_id'] as String,
        orderNumber: json['order_number'] as int,
        status: OrderStatus.fromString(
            json['status'] as String? ?? 'received'),
        estimatedWaitMinutes:
            json['estimated_wait_minutes'] as int? ?? 20,
      );
}
