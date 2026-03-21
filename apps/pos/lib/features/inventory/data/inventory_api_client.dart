/// HTTP client for the inventory API.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:gastrocore_pos/features/inventory/domain/inventory_item.dart';
import 'package:gastrocore_pos/features/inventory/domain/stock_movement.dart';

class InventoryApiClient {
  InventoryApiClient({
    required this.baseUrl,
    required this.tenantId,
    this.timeout = const Duration(seconds: 15),
  });

  final String baseUrl;
  final String tenantId;
  final Duration timeout;

  final _client = http.Client();

  void dispose() => _client.close();

  // ── Items ──────────────────────────────────────────────────────────────────

  Future<List<InventoryItem>> listItems({bool lowStockOnly = false}) async {
    final uri = Uri.parse('$baseUrl/api/v1/inventory/items').replace(
      queryParameters: {
        'tenant_id': tenantId,
        if (lowStockOnly) 'low_stock': 'true',
      },
    );
    final response = await _client.get(uri).timeout(timeout);
    _checkStatus(response);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final data = body['data'] as List<dynamic>;
    return data
        .map((e) => InventoryItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<InventoryItem> getItem(String id) async {
    final uri = Uri.parse('$baseUrl/api/v1/inventory/items/$id')
        .replace(queryParameters: {'tenant_id': tenantId});
    final response = await _client.get(uri).timeout(timeout);
    _checkStatus(response);
    return InventoryItem.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<InventoryItem> createItem({
    required String name,
    String? sku,
    required String unit,
    required double currentQty,
    required double minQty,
    double? maxQty,
    int? costPerUnit,
    String? supplier,
    String? notes,
    bool isActive = true,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/inventory/items')
        .replace(queryParameters: {'tenant_id': tenantId});
    final body = jsonEncode({
      'name': name,
      if (sku != null) 'sku': sku,
      'unit': unit,
      'current_qty': currentQty,
      'min_qty': minQty,
      if (maxQty != null) 'max_qty': maxQty,
      if (costPerUnit != null) 'cost_per_unit': costPerUnit,
      if (supplier != null) 'supplier': supplier,
      if (notes != null) 'notes': notes,
      'is_active': isActive,
    });
    final response = await _client
        .post(uri, headers: _jsonHeaders, body: body)
        .timeout(timeout);
    _checkStatus(response);
    return InventoryItem.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> updateItem(
    String id, {
    required String name,
    String? sku,
    required String unit,
    required double minQty,
    double? maxQty,
    int? costPerUnit,
    String? supplier,
    String? notes,
    required bool isActive,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/inventory/items/$id')
        .replace(queryParameters: {'tenant_id': tenantId});
    final body = jsonEncode({
      'name': name,
      if (sku != null) 'sku': sku,
      'unit': unit,
      'min_qty': minQty,
      if (maxQty != null) 'max_qty': maxQty,
      if (costPerUnit != null) 'cost_per_unit': costPerUnit,
      if (supplier != null) 'supplier': supplier,
      if (notes != null) 'notes': notes,
      'is_active': isActive,
    });
    final response = await _client
        .put(uri, headers: _jsonHeaders, body: body)
        .timeout(timeout);
    _checkStatus(response);
  }

  Future<void> deleteItem(String id) async {
    final uri = Uri.parse('$baseUrl/api/v1/inventory/items/$id')
        .replace(queryParameters: {'tenant_id': tenantId});
    final response = await _client.delete(uri).timeout(timeout);
    _checkStatus(response);
  }

  // ── Movements ─────────────────────────────────────────────────────────────

  Future<List<StockMovement>> listMovements({String? itemId}) async {
    final uri = Uri.parse('$baseUrl/api/v1/inventory/movements').replace(
      queryParameters: {
        'tenant_id': tenantId,
        if (itemId != null) 'item_id': itemId,
      },
    );
    final response = await _client.get(uri).timeout(timeout);
    _checkStatus(response);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final data = body['data'] as List<dynamic>;
    return data
        .map((e) => StockMovement.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<StockMovement> createMovement({
    required String itemId,
    required MovementType movementType,
    required double qty,
    String? reference,
    String? notes,
    String? performedBy,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/inventory/movements')
        .replace(queryParameters: {'tenant_id': tenantId});
    final body = jsonEncode({
      'item_id': itemId,
      'movement_type': movementType.apiValue,
      'qty': qty,
      if (reference != null) 'reference': reference,
      if (notes != null) 'notes': notes,
      if (performedBy != null) 'performed_by': performedBy,
    });
    final response = await _client
        .post(uri, headers: _jsonHeaders, body: body)
        .timeout(timeout);
    _checkStatus(response);
    return StockMovement.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  // ── Internals ──────────────────────────────────────────────────────────────

  static const _jsonHeaders = {'Content-Type': 'application/json'};

  void _checkStatus(http.Response response) {
    if (response.statusCode >= 400) {
      final body = response.body;
      String message = 'HTTP ${response.statusCode}';
      try {
        final json = jsonDecode(body) as Map<String, dynamic>;
        message = json['message'] as String? ?? message;
      } catch (_) {}
      throw InventoryApiException(response.statusCode, message);
    }
  }
}

class InventoryApiException implements Exception {
  final int statusCode;
  final String message;
  const InventoryApiException(this.statusCode, this.message);

  @override
  String toString() => 'InventoryApiException($statusCode): $message';
}
