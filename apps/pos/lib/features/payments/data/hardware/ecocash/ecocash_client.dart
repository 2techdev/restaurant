/// EcoCash V4.2 kiosk service — HTTP client.
///
/// Wraps every endpoint we use (token, status, device_cash, sale, sale_cancel,
/// get/transaction). Caches the 60-minute session token in memory and
/// re-authenticates automatically on `code: "1004"`. Uses `package:http`
/// so no extra dependency is introduced.
library;

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'ecocash_models.dart';

class EcoCashConfig {
  final String baseUrl; // "http://192.168.1.149:8080/" — trailing slash required
  final String deviceId;
  final String clientId;
  final String tokenPass; // cleartext; MD5'd on the wire
  final String currency;

  const EcoCashConfig({
    required this.baseUrl,
    required this.deviceId,
    required this.clientId,
    required this.tokenPass,
    required this.currency,
  });

  bool get isValid =>
      baseUrl.trim().isNotEmpty &&
      deviceId.trim().isNotEmpty &&
      clientId.trim().isNotEmpty &&
      tokenPass.trim().isNotEmpty;
}

class EcoCashException implements Exception {
  final String code;
  final String message;
  EcoCashException(this.code, this.message);
  @override
  String toString() => '[$code] $message';
}

class EcoCashClient {
  EcoCashClient(this.config, {http.Client? http})
      : _http = http ?? _defaultHttp();

  static http.Client _defaultHttp() => http.Client();

  EcoCashConfig config;
  String? _token;
  final http.Client _http;

  static const Duration _timeout = Duration(seconds: 12);

  void clearToken() => _token = null;
  String? get cachedToken => _token;

  Uri _uri(String path) {
    final base = config.baseUrl.endsWith('/')
        ? config.baseUrl
        : '${config.baseUrl}/';
    return Uri.parse('$base$path');
  }

  Future<String> login() async {
    final pwd =
        md5.convert(utf8.encode(config.tokenPass)).toString().toUpperCase();
    final body = {
      'device_id': config.deviceId,
      'client_id': config.clientId,
      'time_stamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'user_name': config.clientId,
      'password': pwd,
    };
    final env = await _post('api/token', body, TokenData.fromJson);
    final t = env.data?.token;
    if (t == null || t.isEmpty) {
      throw EcoCashException(env.code, env.message ?? 'auth failed');
    }
    _token = t;
    return t;
  }

  Future<String> _ensureToken() async => _token ?? await login();

  Future<StatusData> getStatus() async {
    final env = await _post(
      'api/get/status',
      {'token': await _ensureToken()},
      StatusData.fromJson,
    );
    return env.data ?? (throw EcoCashException(env.code, env.message ?? ''));
  }

  Future<SaleStartedData> startSale({
    required String orderId,
    required int amount,
    String payType = 'cash',
  }) async {
    final body = {
      'token': await _ensureToken(),
      'order_id': orderId,
      'date_time': _nowDateTime(),
      'amount': amount,
      'pay_type': payType,
    };
    final env =
        await _post('api/trans/sale', body, SaleStartedData.fromJson);
    return env.data ?? (throw EcoCashException(env.code, env.message ?? ''));
  }

  Future<void> cancelSale({
    required String orderId,
    required String transId,
  }) async {
    final body = {
      'token': await _ensureToken(),
      'order_id': orderId,
      'trans_id': transId,
    };
    await _post<void>('api/trans/sale_cancel', body, null);
  }

  Future<TransactionData> getTransaction({
    String? orderId,
    String? transId,
  }) async {
    final body = {
      'token': await _ensureToken(),
      if (orderId != null) 'order_id': orderId,
      if (transId != null) 'trans_id': transId,
    };
    final env =
        await _post('api/get/transaction', body, TransactionData.fromJson);
    return env.data ?? (throw EcoCashException(env.code, env.message ?? ''));
  }

  Future<ApiEnvelope<T>> _post<T>(
    String path,
    Map<String, dynamic> body,
    T Function(Map<String, dynamic>)? mapper,
  ) async {
    final env = await _send(path, body, mapper);
    if (env.code == '1004') {
      _token = null;
      await login();
      final retryBody = {...body, 'token': _token};
      return _send(path, retryBody, mapper);
    }
    if (!env.isOk && env.code != '1106') {
      throw EcoCashException(env.code, env.message ?? '');
    }
    return env;
  }

  Future<ApiEnvelope<T>> _send<T>(
    String path,
    Map<String, dynamic> body,
    T Function(Map<String, dynamic>)? mapper,
  ) async {
    final res = await _http
        .post(
          _uri(path),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(_timeout);
    if (res.statusCode != 200) {
      throw EcoCashException(
        'HTTP_${res.statusCode}',
        'Kiosk service unreachable (HTTP ${res.statusCode})',
      );
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw EcoCashException('1003', 'Unexpected response shape');
    }
    return ApiEnvelope<T>.fromJson(decoded, mapper);
  }

  static String _nowDateTime() {
    final n = DateTime.now();
    String p(int v) => v.toString().padLeft(2, '0');
    return '${n.year}-${p(n.month)}-${p(n.day)} '
        '${p(n.hour)}:${p(n.minute)}:${p(n.second)}';
  }

  void close() => _http.close();
}
