/// Core HTTP client for the GastroCore Go backend.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;

import '../errors/api_exception.dart';
import '../endpoints/auth_endpoint.dart';
import '../endpoints/dashboard_endpoint.dart';
import '../endpoints/menu_endpoint.dart';
import '../endpoints/orders_endpoint.dart';
import '../endpoints/payment_endpoint.dart';
import '../endpoints/report_endpoint.dart';
import '../endpoints/settings_endpoint.dart';
import '../endpoints/staff_endpoint.dart';
import '../endpoints/sync_endpoint.dart';
import '../endpoints/tables_endpoint.dart';

/// Root HTTP client that owns the base URL and auth token, and exposes
/// typed endpoint groups.
class GastrocoreClient {
  final String baseUrl;
  final http.Client _http;

  String? _authToken;

  late final AuthEndpoint auth;
  late final MenuEndpoint menu;
  late final OrdersEndpoint orders;
  late final TablesEndpoint tables;
  late final SyncEndpoint sync;
  late final PaymentEndpoint payments;
  late final StaffEndpoint staff;
  late final SettingsEndpoint settings;
  late final ReportEndpoint reports;
  late final DashboardEndpoint dashboard;

  GastrocoreClient({
    required this.baseUrl,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client() {
    auth = AuthEndpoint(this);
    menu = MenuEndpoint(this);
    orders = OrdersEndpoint(this);
    tables = TablesEndpoint(this);
    sync = SyncEndpoint(this);
    payments = PaymentEndpoint(this);
    staff = StaffEndpoint(this);
    settings = SettingsEndpoint(this);
    reports = ReportEndpoint(this);
    dashboard = DashboardEndpoint(this);
  }

  /// Set the bearer token used for authenticated requests.
  void setAuthToken(String token) {
    _authToken = token;
  }

  void clearAuthToken() {
    _authToken = null;
  }

  bool get isAuthenticated => _authToken != null;

  // ---------------------------------------------------------------------------
  // Internal helpers used by endpoint classes
  // ---------------------------------------------------------------------------

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (_authToken != null) 'Authorization': 'Bearer $_authToken',
      };

  Uri _uri(String path, [Map<String, String>? queryParams]) {
    final base = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    final pathClean = path.startsWith('/') ? path.substring(1) : path;
    final uri = Uri.parse('$base$pathClean');
    if (queryParams != null && queryParams.isNotEmpty) {
      return uri.replace(queryParameters: queryParams);
    }
    return uri;
  }

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? queryParams,
  }) async {
    final response = await _http.get(
      _uri(path, queryParams),
      headers: _headers,
    );
    return _parseResponse(response);
  }

  Future<List<dynamic>> getList(
    String path, {
    Map<String, String>? queryParams,
  }) async {
    final response = await _http.get(
      _uri(path, queryParams),
      headers: _headers,
    );
    return _parseListResponse(response);
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await _http.post(
      _uri(path),
      headers: _headers,
      body: jsonEncode(body),
    );
    return _parseResponse(response);
  }

  Future<Map<String, dynamic>> put(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await _http.put(
      _uri(path),
      headers: _headers,
      body: jsonEncode(body),
    );
    return _parseResponse(response);
  }

  Future<Map<String, dynamic>> patch(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await _http.patch(
      _uri(path),
      headers: _headers,
      body: jsonEncode(body),
    );
    return _parseResponse(response);
  }

  Future<void> delete(String path) async {
    final response = await _http.delete(
      _uri(path),
      headers: _headers,
    );
    _assertSuccess(response);
  }

  Map<String, dynamic> _parseResponse(http.Response response) {
    _assertSuccess(response);
    if (response.body.isEmpty) return {};
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  List<dynamic> _parseListResponse(http.Response response) {
    _assertSuccess(response);
    if (response.body.isEmpty) return [];
    final decoded = jsonDecode(response.body);
    if (decoded is List) return decoded;
    // Unwrap common envelope patterns: { "data": [...] }
    if (decoded is Map<String, dynamic>) {
      for (final key in ['data', 'items', 'results']) {
        if (decoded[key] is List) return decoded[key] as List;
      }
    }
    return [];
  }

  void _assertSuccess(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;

    String message = 'Request failed';
    String? errorCode;

    try {
      final body =
          jsonDecode(response.body) as Map<String, dynamic>;
      message = body['message'] as String? ??
          body['error'] as String? ??
          message;
      errorCode = body['code'] as String?;
    } catch (_) {
      // Non-JSON error body — use status text
      message = response.reasonPhrase ?? message;
    }

    throw ApiException(
      statusCode: response.statusCode,
      message: message,
      errorCode: errorCode,
    );
  }

  /// Dispose the underlying HTTP client.
  void dispose() {
    _http.close();
  }
}
