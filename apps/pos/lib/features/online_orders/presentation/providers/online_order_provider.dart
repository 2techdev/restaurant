/// Riverpod providers for real-time online order management.
///
/// When a customer completes an order via the online-ordering storefront, the
/// POS hub pushes a "new_order" WebSocket message. This provider:
///   1. Maintains a [PosWsClient] connected to `/ws/pos`.
///   2. On "new_order": inserts the ticket + items into the local Drift
///      database, plays a notification sound, and adds the order to the
///      [pendingOnlineOrdersProvider] queue (the overlay notification).
///   3. On "order_status_update": removes the order from the pending queue.
///   4. Exposes [acceptOnlineOrder] / [rejectOnlineOrder] which call the REST
///      API and then invalidate [openTicketsProvider] to refresh the UI.
library;

import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/online_orders/data/clients/pos_ws_client.dart';
import 'package:gastrocore_pos/features/online_orders/domain/models/online_order_message.dart';
import 'package:gastrocore_pos/features/orders/presentation/providers/order_provider.dart';
import 'package:gastrocore_pos/features/sync/presentation/providers/sync_provider.dart';

// ---------------------------------------------------------------------------
// Pending online orders (orders waiting for Accept / Reject)
// ---------------------------------------------------------------------------

/// Queue of online orders that have arrived but not yet been accepted/rejected.
final pendingOnlineOrdersProvider =
    StateNotifierProvider<PendingOnlineOrdersNotifier, List<OnlineOrderPayload>>(
  (ref) => PendingOnlineOrdersNotifier(),
);

class PendingOnlineOrdersNotifier
    extends StateNotifier<List<OnlineOrderPayload>> {
  PendingOnlineOrdersNotifier() : super([]);

  void add(OnlineOrderPayload order) {
    if (state.any((o) => o.id == order.id)) return;
    state = [...state, order];
  }

  void remove(String orderId) {
    state = state.where((o) => o.id != orderId).toList();
  }
}

// ---------------------------------------------------------------------------
// Audio player
// ---------------------------------------------------------------------------

final _onlineAlertPlayerProvider = Provider<AudioPlayer>((ref) {
  final player = AudioPlayer();
  ref.onDispose(player.dispose);
  return player;
});

// ---------------------------------------------------------------------------
// POS WebSocket client lifecycle
// ---------------------------------------------------------------------------

/// Starts and manages the [PosWsClient] for this screen.
///
/// auto-disposed when the last listener is removed. Mount it
/// inside the order-centre shell to keep the connection alive while on that screen.
final posWsClientProvider = Provider.autoDispose<PosWsClient>((ref) {
  final baseUrl = ref.watch(wsServerUrlProvider);
  final tenantId = ref.watch(tenantIdProvider);
  final deviceId = ref.watch(deviceIdProvider);

  final client = PosWsClient(
    baseUrl: baseUrl,
    tenantId: tenantId,
    deviceId: deviceId,
    onMessage: (msg) => _handleWsMessage(ref, msg),
  );

  ref.onDispose(client.dispose);
  client.connect();
  return client;
});

/// Routes a decoded WebSocket frame to the appropriate handler.
void _handleWsMessage(Ref ref, Map<String, dynamic> raw) {
  try {
    final msg = OnlineOrderMessage.fromJson(raw);
    switch (msg.type) {
      case 'new_order':
        final order = OnlineOrderPayload.fromJson(msg.payload);
        _onNewOrder(ref, order);
      case 'order_status_update':
        final upd = OnlineOrderStatusPayload.fromJson(msg.payload);
        ref.read(pendingOnlineOrdersProvider.notifier).remove(upd.orderId);
      default:
        break;
    }
  } catch (_) {
    // Ignore parse errors — malformed frames are non-fatal.
  }
}

/// Inserts the incoming online order into the local Drift DB and notifies
/// the UI (overlay + sound).
Future<void> _onNewOrder(Ref ref, OnlineOrderPayload order) async {
  final db = ref.read(databaseProvider);
  final tenantId = ref.read(tenantIdProvider);
  final now = DateTime.now().toUtc();

  final dbOrderType = switch (order.orderType) {
    'takeaway' => 'takeaway',
    'delivery' => 'delivery',
    _ => 'dine_in',
  };

  // Upsert the ticket row (handles duplicate deliveries gracefully).
  await db.into(db.tickets).insertOnConflictUpdate(TicketsCompanion(
    id: Value(order.id),
    tenantId: Value(tenantId),
    orderNumber: Value(order.orderNumber),
    orderType: Value(dbOrderType),
    customerName: Value(order.customerName),
    guestCount: const Value(1),
    status: const Value('open'),
    channel: Value(order.channel),
    subtotal: Value(order.subtotal),
    taxAmount: Value(order.taxAmount),
    discountAmount: const Value(0),
    total: Value(order.total),
    notes: Value(order.notes),
    openedAt: Value(now),
    deviceId: const Value('online'),
    createdAt: Value(now),
    updatedAt: Value(now),
    isDeleted: const Value(false),
  ));

  // Upsert each order item.
  for (final item in order.items) {
    final itemId = IdGenerator.generateId();
    await db.into(db.orderItems).insertOnConflictUpdate(OrderItemsCompanion(
      id: Value(itemId),
      tenantId: Value(tenantId),
      ticketId: Value(order.id),
      productId: Value(item.productId),
      productName: Value(item.productName),
      quantity: Value(item.quantity.toDouble()),
      unitPrice: Value(item.unitPrice),
      subtotal: Value(item.subtotal),
      taxAmount: const Value(0),
      discountAmount: const Value(0),
      status: const Value('ordered'),
      sentToKitchen: const Value(false),
      notes: Value(item.notes),
      course: const Value(1),
      createdAt: Value(now),
      updatedAt: Value(now),
      isDeleted: const Value(false),
    ));

    for (final mod in item.modifiers) {
      await db
          .into(db.orderItemModifiers)
          .insertOnConflictUpdate(OrderItemModifiersCompanion(
            id: Value(IdGenerator.generateId()),
            orderItemId: Value(itemId),
            modifierId: Value(mod.modifierId),
            modifierName: Value(mod.modifierName),
            priceDelta: Value(mod.priceDelta),
            createdAt: Value(now),
          ));
    }
  }

  // Refresh the ongoing orders list in the UI.
  ref.invalidate(openTicketsProvider);

  // Add to the notification queue.
  ref.read(pendingOnlineOrdersProvider.notifier).add(order);

  // Play alert sound (reuse existing KDS beep asset).
  try {
    final player = ref.read(_onlineAlertPlayerProvider);
    await player.play(AssetSource('audio/kds_new_ticket.wav'));
  } catch (_) {
    // Audio failure is non-fatal.
  }
}

// ---------------------------------------------------------------------------
// Accept / Reject actions (called from the overlay buttons)
// ---------------------------------------------------------------------------

/// Accepts an online order: calls the REST endpoint and refreshes the list.
Future<void> acceptOnlineOrder(WidgetRef ref, String orderId) async {
  final baseUrl = ref.read(syncServerUrlProvider);
  try {
    await http.put(
      Uri.parse('$baseUrl/api/v1/online/orders/$orderId/accept'),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (_) {
    // Best-effort; local DB state is already correct.
  }
  ref.read(pendingOnlineOrdersProvider.notifier).remove(orderId);
  ref.invalidate(openTicketsProvider);
}

/// Rejects an online order: calls the REST endpoint, marks local row as
/// cancelled, and removes it from the notification queue.
Future<void> rejectOnlineOrder(
  WidgetRef ref,
  String orderId,
  String reason,
) async {
  final baseUrl = ref.read(syncServerUrlProvider);
  try {
    await http.put(
      Uri.parse('$baseUrl/api/v1/online/orders/$orderId/reject'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'reason': reason}),
    );
  } catch (_) {
    // Best-effort.
  }

  // Update local DB so the ticket disappears from the open list.
  final db = ref.read(databaseProvider);
  await (db.update(db.tickets)..where((t) => t.id.equals(orderId)))
      .write(TicketsCompanion(
    status: const Value('cancelled'),
    updatedAt: Value(DateTime.now().toUtc()),
  ));

  ref.read(pendingOnlineOrdersProvider.notifier).remove(orderId);
  ref.invalidate(openTicketsProvider);
}
