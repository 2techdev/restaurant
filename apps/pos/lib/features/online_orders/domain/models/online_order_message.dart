/// Domain models for the POS WebSocket messages pushed from the server
/// when a customer places an order through the online ordering platform.
library;

// ---------------------------------------------------------------------------
// OnlineOrderMessage
// ---------------------------------------------------------------------------

/// A decoded POS WebSocket frame.
class OnlineOrderMessage {
  final String type;       // "new_order" | "order_status_update"
  final String tenantId;
  final Map<String, dynamic> payload;

  const OnlineOrderMessage({
    required this.type,
    required this.tenantId,
    required this.payload,
  });

  factory OnlineOrderMessage.fromJson(Map<String, dynamic> json) {
    return OnlineOrderMessage(
      type: json['type'] as String? ?? '',
      tenantId: json['tenant_id'] as String? ?? '',
      payload: (json['payload'] as Map<String, dynamic>?) ?? {},
    );
  }
}

// ---------------------------------------------------------------------------
// OnlineOrderPayload  (type == "new_order")
// ---------------------------------------------------------------------------

class OnlineOrderItemModifier {
  final String modifierId;
  final String modifierName;
  final int priceDelta; // cents

  const OnlineOrderItemModifier({
    required this.modifierId,
    required this.modifierName,
    required this.priceDelta,
  });

  factory OnlineOrderItemModifier.fromJson(Map<String, dynamic> j) {
    return OnlineOrderItemModifier(
      modifierId: j['modifier_id'] as String? ?? '',
      modifierName: j['modifier_name'] as String? ?? '',
      priceDelta: (j['price_delta'] as num?)?.toInt() ?? 0,
    );
  }
}

class OnlineOrderItemPayload {
  final String productId;
  final String productName;
  final int quantity;
  final int unitPrice;  // cents
  final int subtotal;   // cents
  final String? notes;
  final List<OnlineOrderItemModifier> modifiers;

  const OnlineOrderItemPayload({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.subtotal,
    this.notes,
    this.modifiers = const [],
  });

  factory OnlineOrderItemPayload.fromJson(Map<String, dynamic> j) {
    final mods = (j['modifiers'] as List<dynamic>?)
            ?.map((m) => OnlineOrderItemModifier.fromJson(
                m as Map<String, dynamic>))
            .toList() ??
        [];
    return OnlineOrderItemPayload(
      productId: j['product_id'] as String? ?? '',
      productName: j['product_name'] as String? ?? '',
      quantity: (j['quantity'] as num?)?.toInt() ?? 1,
      unitPrice: (j['unit_price'] as num?)?.toInt() ?? 0,
      subtotal: (j['subtotal'] as num?)?.toInt() ?? 0,
      notes: j['notes'] as String?,
      modifiers: mods,
    );
  }
}

class OnlineOrderPayload {
  final String id;
  final int orderNumber;
  final String orderType;   // "dine_in" | "takeaway" | "delivery"
  final String channel;     // "qr" | "web" | "kiosk"
  final String? customerName;
  final int? tableNumber;
  final String? notes;
  final int subtotal;       // cents
  final int taxAmount;      // cents
  final int total;          // cents
  final List<OnlineOrderItemPayload> items;
  final String status;
  final int estimatedWaitMinutes;

  const OnlineOrderPayload({
    required this.id,
    required this.orderNumber,
    required this.orderType,
    required this.channel,
    this.customerName,
    this.tableNumber,
    this.notes,
    required this.subtotal,
    required this.taxAmount,
    required this.total,
    required this.items,
    required this.status,
    this.estimatedWaitMinutes = 20,
  });

  factory OnlineOrderPayload.fromJson(Map<String, dynamic> j) {
    final rawItems = (j['items'] as List<dynamic>?) ?? [];
    return OnlineOrderPayload(
      id: j['id'] as String? ?? '',
      orderNumber: (j['order_number'] as num?)?.toInt() ?? 0,
      orderType: j['order_type'] as String? ?? 'dine_in',
      channel: j['channel'] as String? ?? 'qr',
      customerName: j['customer_name'] as String?,
      tableNumber: (j['table_number'] as num?)?.toInt(),
      notes: j['notes'] as String?,
      subtotal: (j['subtotal'] as num?)?.toInt() ?? 0,
      taxAmount: (j['tax_amount'] as num?)?.toInt() ?? 0,
      total: (j['total'] as num?)?.toInt() ?? 0,
      items: rawItems
          .map((i) =>
              OnlineOrderItemPayload.fromJson(i as Map<String, dynamic>))
          .toList(),
      status: j['status'] as String? ?? 'open',
      estimatedWaitMinutes:
          (j['estimated_wait_minutes'] as num?)?.toInt() ?? 20,
    );
  }
}

// ---------------------------------------------------------------------------
// OnlineOrderStatusPayload  (type == "order_status_update")
// ---------------------------------------------------------------------------

class OnlineOrderStatusPayload {
  final String orderId;
  final int orderNumber;
  final String status;

  const OnlineOrderStatusPayload({
    required this.orderId,
    required this.orderNumber,
    required this.status,
  });

  factory OnlineOrderStatusPayload.fromJson(Map<String, dynamic> j) {
    return OnlineOrderStatusPayload(
      orderId: j['order_id'] as String? ?? '',
      orderNumber: (j['order_number'] as num?)?.toInt() ?? 0,
      status: j['status'] as String? ?? '',
    );
  }
}
