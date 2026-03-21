/// Shelf endpoint handlers for orders on the LAN sync server.
library;

import 'dart:convert';

import 'package:shelf/shelf.dart';

/// `GET /orders?since=<cursor>`  — returns orders modified after [since].
/// `POST /orders`                — accepts an order pushed by a secondary.
class OrdersEndpoint {
  const OrdersEndpoint({
    required this.fetchOrders,
    required this.receiveOrder,
  });

  /// Fetch orders modified after [since] (ISO-8601 string or empty for all).
  /// Returns a list of order JSON maps.
  final Future<List<Map<String, dynamic>>> Function({String since})
      fetchOrders;

  /// Called when a secondary POSTs a new or updated order.
  final Future<void> Function(Map<String, dynamic> orderJson) receiveOrder;

  // ---------------------------------------------------------------------------

  Future<Response> getOrders(Request request) async {
    try {
      final since = request.url.queryParameters['since'] ?? '';
      final orders = await fetchOrders(since: since);
      return Response.ok(
        jsonEncode({'orders': orders, 'count': orders.length}),
        headers: _json,
      );
    } catch (e) {
      return _serverError(e);
    }
  }

  Future<Response> postOrder(Request request) async {
    try {
      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      await receiveOrder(json);
      return Response.ok(
        jsonEncode({'status': 'accepted'}),
        headers: _json,
      );
    } catch (e) {
      return _serverError(e);
    }
  }
}

// ---------------------------------------------------------------------------
// Helpers shared across endpoints
// ---------------------------------------------------------------------------

const _json = {'Content-Type': 'application/json'};

Response _serverError(Object e) => Response.internalServerError(
      body: jsonEncode({'error': e.toString()}),
      headers: _json,
    );
