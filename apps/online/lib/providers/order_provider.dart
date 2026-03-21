/// Order placement and tracking providers.
library;

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gastrocore_online/domain/cart.dart';
import 'package:gastrocore_online/domain/models/order_models.dart';
import 'package:gastrocore_online/providers/menu_provider.dart';

// ---------------------------------------------------------------------------
// Place order
// ---------------------------------------------------------------------------

final placeOrderProvider =
    StateNotifierProvider<PlaceOrderNotifier, AsyncValue<PlacedOrder?>>((ref) {
  return PlaceOrderNotifier(ref);
});

class PlaceOrderNotifier
    extends StateNotifier<AsyncValue<PlacedOrder?>> {
  PlaceOrderNotifier(this.ref) : super(const AsyncData(null));

  final Ref ref;

  Future<PlacedOrder?> placeOrder({
    required String restaurantId,
    required Cart cart,
    String? customerName,
  }) async {
    state = const AsyncLoading();
    try {
      final client = ref.read(apiClientProvider);
      final payload = cart.toOrderPayload(
        restaurantId: restaurantId,
        customerName: customerName,
      );
      final json = await client.placeOrder(payload);
      final order = PlacedOrder.fromJson(json);
      state = AsyncData(order);
      return order;
    } catch (e, st) {
      state = AsyncError(e, st);
      return null;
    }
  }

  void reset() => state = const AsyncData(null);
}

// ---------------------------------------------------------------------------
// Order tracking (polling every 10 seconds)
// ---------------------------------------------------------------------------

final orderTrackingProvider = StreamProvider.autoDispose
    .family<OrderStatusResponse, String>((ref, orderId) async* {
  final client = ref.read(apiClientProvider);

  while (true) {
    try {
      final json = await client.fetchOrderStatus(orderId);
      final status = OrderStatusResponse.fromJson(json);
      yield status;

      // Stop polling once order is served
      if (status.status == OrderStatus.served) break;
    } catch (_) {
      // Silently retry on network errors
    }
    await Future.delayed(const Duration(seconds: 10));
  }
});
