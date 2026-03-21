/// Order placement and tracking providers.
library;

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gastrocore_online/core/api/api_client.dart';
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
// Payment checkout
// ---------------------------------------------------------------------------

class PaymentCheckoutResult {
  final String checkoutUrl;
  final String sessionId;
  final String orderId;

  const PaymentCheckoutResult({
    required this.checkoutUrl,
    required this.sessionId,
    required this.orderId,
  });
}

final createPaymentCheckoutProvider = StateNotifierProvider<
    CreatePaymentCheckoutNotifier,
    AsyncValue<PaymentCheckoutResult?>>((ref) {
  return CreatePaymentCheckoutNotifier(ref);
});

class CreatePaymentCheckoutNotifier
    extends StateNotifier<AsyncValue<PaymentCheckoutResult?>> {
  CreatePaymentCheckoutNotifier(this.ref) : super(const AsyncData(null));

  final Ref ref;

  Future<PaymentCheckoutResult?> createCheckout({
    required String orderId,
    required String restaurantId,
    required int amountCents,
    String currency = 'chf',
    String? description,
  }) async {
    state = const AsyncLoading();
    try {
      final client = ref.read(apiClientProvider);
      final json = await client.createPaymentCheckout(
        orderId: orderId,
        restaurantId: restaurantId,
        amountCents: amountCents,
        currency: currency,
        description: description,
      );
      final result = PaymentCheckoutResult(
        checkoutUrl: json['checkout_url'] as String,
        sessionId: json['session_id'] as String,
        orderId: json['order_id'] as String,
      );
      state = AsyncData(result);
      return result;
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
