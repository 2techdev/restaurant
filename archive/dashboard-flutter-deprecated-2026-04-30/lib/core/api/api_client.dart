import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'models.dart';

/// Detects the correct base URL from the current hostname.
String _resolveBaseUrl() {
  if (!kIsWeb) return 'http://localhost:8080';
  // ignore: undefined_prefixed_name
  final host = Uri.base.host;
  if (host == 'localhost' || host == '127.0.0.1' || host.startsWith('192.168.')) {
    return 'http://localhost:8080';
  }
  if (host.contains('gastrocore.ch')) {
    return 'https://api.gastrocore.ch';
  }
  // GitHub Pages / demo → use mock
  return '';
}

class ApiClient {
  final String baseUrl;
  final String? token;

  const ApiClient({required this.baseUrl, this.token});

  bool get isMock => baseUrl.isEmpty;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<Map<String, dynamic>> _get(String path, {Map<String, String>? params}) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: params);
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode >= 400) throw ApiException(res.statusCode, res.body);
    return json.decode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('$baseUrl$path');
    final res = await http.post(uri, headers: _headers, body: json.encode(body));
    if (res.statusCode >= 400) throw ApiException(res.statusCode, res.body);
    return json.decode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _put(String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('$baseUrl$path');
    final res = await http.put(uri, headers: _headers, body: json.encode(body));
    if (res.statusCode >= 400) throw ApiException(res.statusCode, res.body);
    return json.decode(res.body) as Map<String, dynamic>;
  }

  // ---------------------------------------------------------------------------
  // Auth
  // ---------------------------------------------------------------------------

  Future<LoginResult> login({required String email, required String password}) async {
    if (isMock) {
      await Future.delayed(const Duration(milliseconds: 600));
      if (email == 'admin@demo.ch' && password == 'demo') {
        return const LoginResult(
          accessToken: 'mock-token',
          refreshToken: 'mock-refresh',
          expiresIn: 86400,
          userId: 'u1',
          name: 'Admin Demo',
          email: 'admin@demo.ch',
          role: 'admin',
        );
      }
      throw const ApiException(401, '{"message":"Invalid credentials"}');
    }
    final data = await _post('/api/v1/auth/admin/login', {
      'email': email,
      'password': password,
    });
    return LoginResult.fromJson(data);
  }

  // ---------------------------------------------------------------------------
  // Dashboard
  // ---------------------------------------------------------------------------

  Future<DashboardStats> getStats() async {
    if (isMock) {
      await Future.delayed(const Duration(milliseconds: 300));
      return DashboardStats.demo;
    }
    final data = await _get('/api/v1/dashboard/stats');
    return DashboardStats.fromJson(data);
  }

  Future<List<RevenuePoint>> getRevenue({String period = '7d'}) async {
    if (isMock) {
      await Future.delayed(const Duration(milliseconds: 200));
      return RevenuePoint.demo;
    }
    final data = await _get('/api/v1/dashboard/revenue', params: {'period': period});
    final list = data['data'] as List<dynamic>? ?? [];
    return list.map((e) => RevenuePoint.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ---------------------------------------------------------------------------
  // Orders
  // ---------------------------------------------------------------------------

  Future<List<Order>> getOrders({String? status, String? dateFrom, String? dateTo}) async {
    if (isMock) {
      await Future.delayed(const Duration(milliseconds: 250));
      var orders = Order.demo;
      if (status != null && status.isNotEmpty) {
        orders = orders.where((o) => o.status == status).toList();
      }
      return orders;
    }
    final params = <String, String>{};
    if (status != null && status.isNotEmpty) params['status'] = status;
    if (dateFrom != null) params['date_from'] = dateFrom;
    if (dateTo != null) params['date_to'] = dateTo;
    final data = await _get('/api/v1/orders', params: params.isEmpty ? null : params);
    final list = (data['data'] as List<dynamic>? ?? []);
    return list.map((e) => Order.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ---------------------------------------------------------------------------
  // Menu
  // ---------------------------------------------------------------------------

  Future<List<MenuCategory>> getCategories() async {
    if (isMock) {
      await Future.delayed(const Duration(milliseconds: 200));
      return MenuCategory.demo;
    }
    final data = await _get('/api/v1/menu/categories');
    final list = data['categories'] as List<dynamic>? ?? data['data'] as List<dynamic>? ?? [];
    return list.map((e) => MenuCategory.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Product>> getProducts({String? categoryId}) async {
    if (isMock) {
      await Future.delayed(const Duration(milliseconds: 200));
      var prods = Product.demo;
      if (categoryId != null) prods = prods.where((p) => p.categoryId == categoryId).toList();
      return prods;
    }
    final params = categoryId != null ? {'category_id': categoryId} : null;
    final data = await _get('/api/v1/menu/products', params: params);
    final list = data['products'] as List<dynamic>? ?? data['data'] as List<dynamic>? ?? [];
    return list.map((e) => Product.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> updateProductAvailability(String productId, bool isAvailable) async {
    if (isMock) {
      await Future.delayed(const Duration(milliseconds: 200));
      return;
    }
    await _put('/api/v1/menu/products/$productId', {'is_available': isAvailable});
  }

  // ---------------------------------------------------------------------------
  // Reports
  // ---------------------------------------------------------------------------

  Future<MWSTReport> getMWSTReport({required String from, required String to}) async {
    if (isMock) {
      await Future.delayed(const Duration(milliseconds: 300));
      return MWSTReport.demo;
    }
    final data = await _get('/api/v1/reports/mwst', params: {'from': from, 'to': to});
    return MWSTReport.fromJson(data);
  }

  Future<List<SalesPoint>> getSalesTimeline({
    required String from,
    required String to,
    String groupBy = 'day',
  }) async {
    if (isMock) {
      await Future.delayed(const Duration(milliseconds: 300));
      return _mockSalesTimeline(from: from, to: to, groupBy: groupBy);
    }
    final data = await _get('/api/v1/reports/sales', params: {
      'from': from,
      'to': to,
      'group_by': groupBy,
    });
    final list = data['timeline'] as List<dynamic>? ?? [];
    return list.map((e) => SalesPoint.fromJson(e as Map<String, dynamic>)).toList();
  }

  List<SalesPoint> _mockSalesTimeline({
    required String from,
    required String to,
    required String groupBy,
  }) {
    const revenues = [210000, 185000, 320000, 274000, 298000, 342000, 384750,
                      198000, 265000, 310000, 287000, 302000, 355000, 391000,
                      220000, 195000, 338000, 285000, 315000, 362000, 405000,
                      230000, 210000, 348000, 295000, 328000, 375000, 418000,
                      245000, 225000];
    final fromDate = DateTime.tryParse(from) ?? DateTime.now().subtract(const Duration(days: 30));
    final toDate = DateTime.tryParse(to) ?? DateTime.now();
    final days = toDate.difference(fromDate).inDays + 1;
    return List.generate(days.clamp(1, 30), (i) {
      final d = fromDate.add(Duration(days: i));
      final label = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      return SalesPoint(
        period: label,
        orderCount: 28 + i % 20,
        revenue: revenues[i % revenues.length],
        tax: (revenues[i % revenues.length] * 0.038).round(),
        discounts: 500 + (i * 200) % 3000,
      );
    });
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String body;

  const ApiException(this.statusCode, this.body);

  String get message {
    try {
      final decoded = json.decode(body) as Map<String, dynamic>;
      return decoded['message'] as String? ?? 'Error $statusCode';
    } catch (_) {
      return 'Error $statusCode';
    }
  }

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Factory that creates an ApiClient with the correct base URL.
ApiClient createApiClient({String? token}) {
  return ApiClient(baseUrl: _resolveBaseUrl(), token: token);
}
