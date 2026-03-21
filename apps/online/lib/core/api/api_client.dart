/// HTTP client for GastroCore Online Ordering API.
/// Calls the Go backend at /api/v1/online/* — no auth required.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final int statusCode;
  final String message;
  const ApiException(this.statusCode, this.message);
  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiClient {
  ApiClient({required this.baseUrl});

  final String baseUrl;

  // ---------------------------------------------------------------------------
  // Public endpoints
  // ---------------------------------------------------------------------------

  /// GET /api/v1/online/menu/{restaurantId}
  Future<Map<String, dynamic>> fetchMenu(String restaurantId) async {
    final uri = Uri.parse('$baseUrl/api/v1/online/menu/$restaurantId');
    final response = await http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 15));
    return _decode(response);
  }

  /// POST /api/v1/online/orders
  Future<Map<String, dynamic>> placeOrder(
      Map<String, dynamic> payload) async {
    final uri = Uri.parse('$baseUrl/api/v1/online/orders');
    final response = await http
        .post(uri, headers: _headers, body: json.encode(payload))
        .timeout(const Duration(seconds: 20));
    return _decode(response);
  }

  /// GET /api/v1/online/orders/{orderId}/status
  Future<Map<String, dynamic>> fetchOrderStatus(String orderId) async {
    final uri =
        Uri.parse('$baseUrl/api/v1/online/orders/$orderId/status');
    final response = await http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 10));
    return _decode(response);
  }

  /// POST /api/v1/online/payment/checkout
  /// Creates a Stripe Checkout Session.
  /// Returns { checkout_url, session_id, order_id }.
  Future<Map<String, dynamic>> createPaymentCheckout({
    required String orderId,
    required String restaurantId,
    required int amountCents,
    String currency = 'chf',
    String? description,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/online/payment/checkout');
    final payload = {
      'order_id': orderId,
      'restaurant_id': restaurantId,
      'amount_cents': amountCents,
      'currency': currency,
      if (description != null) 'description': description,
    };
    final response = await http
        .post(uri, headers: _headers, body: json.encode(payload))
        .timeout(const Duration(seconds: 20));
    return _decode(response);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  Map<String, dynamic> _decode(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    String message = 'Request failed';
    try {
      final body = json.decode(response.body) as Map<String, dynamic>;
      message = body['message'] as String? ?? message;
    } catch (_) {}
    throw ApiException(response.statusCode, message);
  }
}
