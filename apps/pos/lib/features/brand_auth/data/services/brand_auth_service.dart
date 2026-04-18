/// HTTP client for brand-level email/password authentication against
/// the GastroCore backend at api.2hub.ch.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:gastrocore_pos/core/config/app_endpoints.dart';
import 'package:gastrocore_pos/features/brand_auth/domain/entities/auth_result.dart';
import 'package:gastrocore_pos/features/brand_auth/domain/entities/register_request.dart';
import 'package:gastrocore_pos/features/brand_auth/domain/entities/store_context.dart';

/// Thrown when an auth request fails.
class AuthException implements Exception {
  const AuthException(this.message);
  final String message;

  @override
  String toString() => 'AuthException: $message';
}

/// Communicates with the GastroCore REST API for brand authentication.
///
/// Base URL defaults to [AppEndpoints.apiBaseUrl] (Hetzner pilot unless
/// overridden via `--dart-define=API_HOST=…`). All methods throw
/// [AuthException] on non-2xx responses or network errors.
class BrandAuthService {
  BrandAuthService({String? baseUrl}) {
    final raw = baseUrl ?? AppEndpoints.apiBaseUrl;
    _base = raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  late final String _base;
  final _client = http.Client();

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Login with email + password.
  ///
  /// Returns an [AuthResult] containing JWT tokens and the [StoreContext].
  Future<AuthResult> login(String email, String password) async {
    final response = await _post('/api/v1/auth/login', {
      'email': email.trim(),
      'password': password,
    });
    return _parseAuthResult(response);
  }

  /// Register a new brand + store.
  ///
  /// On success the server auto-provisions a default store and returns
  /// a fully authenticated [AuthResult].
  Future<AuthResult> register(RegisterRequest request) async {
    final response = await _post('/api/v1/auth/register', request.toJson());
    return _parseAuthResult(response);
  }

  /// Exchange a refresh token for a new access token.
  ///
  /// Returns the new access token string.
  Future<String> refreshToken(String refreshToken) async {
    final response = await _post('/api/v1/auth/refresh', {
      'refresh_token': refreshToken,
    });
    final data = _decode(response);
    final token = data['access_token'] as String?;
    if (token == null || token.isEmpty) {
      throw const AuthException('No access_token in refresh response');
    }
    return token;
  }

  void dispose() => _client.close();

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Future<http.Response> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      return await _client.post(
        Uri.parse('$_base$path'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(body),
      );
    } catch (e) {
      throw AuthException('Network error: $e');
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = 'HTTP ${response.statusCode}';
      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        message = (body['message'] ?? body['error'] ?? message).toString();
      } catch (_) {}
      throw AuthException(message);
    }
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const AuthException('Invalid JSON response from server');
    }
  }

  AuthResult _parseAuthResult(http.Response response) {
    final data = _decode(response);

    final accessToken = data['access_token'] as String? ?? '';
    final refreshToken = data['refresh_token'] as String? ?? '';

    if (accessToken.isEmpty) {
      throw const AuthException('Missing access_token in response');
    }

    // The multi-tenant backend returns fields on a nested `user` object:
    //   { access_token, refresh_token, user: { store_id, organization_id, role, … } }
    // Older/alternate shapes may expose a flat `store` or `context` object
    // or root-level scalars; probe all of them in priority order.
    final userData = data['user'] as Map<String, dynamic>?;
    final storeData = (data['store'] ?? data['context'] ?? const {})
        as Map<String, dynamic>;

    String pick(String key, [String fallback = '']) {
      final fromUser = userData?[key];
      if (fromUser is String && fromUser.isNotEmpty) return fromUser;
      if (fromUser is List && fromUser.isNotEmpty) {
        // e.g. `store_ids: ["…"]` — take the first entry.
        final first = fromUser.first;
        if (first is String && first.isNotEmpty) return first;
      }
      final fromStore = storeData[key];
      if (fromStore is String && fromStore.isNotEmpty) return fromStore;
      final fromRoot = data[key];
      if (fromRoot is String && fromRoot.isNotEmpty) return fromRoot;
      return fallback;
    }

    final storeId = pick('store_id').isNotEmpty
        ? pick('store_id')
        : pick('store_ids');

    final brandId = pick('organization_id').isNotEmpty
        ? pick('organization_id')
        : pick('brand_id');

    final roleStr = pick('role', pick('user_role', 'staff')).toLowerCase();
    final role = switch (roleStr) {
      'owner' => BrandUserRole.owner,
      'manager' => BrandUserRole.manager,
      _ => BrandUserRole.staff,
    };

    final ctx = StoreContext(
      brandId: brandId,
      storeId: storeId,
      storeName: pick('store_name', 'My Restaurant'),
      brandName: pick('brand_name').isNotEmpty
          ? pick('brand_name')
          : pick('restaurant_name', 'My Brand'),
      userRole: role,
      isOnlineMode: true,
    );

    return AuthResult(
      accessToken: accessToken,
      refreshToken: refreshToken,
      storeContext: ctx,
    );
  }
}
