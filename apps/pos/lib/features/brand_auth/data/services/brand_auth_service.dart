/// HTTP client for brand-level email/password authentication against
/// the GastroCore backend at pos.2tech.ch.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

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
/// Base URL defaults to `https://pos.2tech.ch`. All methods throw
/// [AuthException] on non-2xx responses or network errors.
class BrandAuthService {
  BrandAuthService({String? baseUrl}) {
    final raw = baseUrl ?? 'https://pos.2tech.ch';
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

    // The server returns a nested `store` object with brand/store context.
    final storeData =
        (data['store'] ?? data['context'] ?? data) as Map<String, dynamic>;

    final roleStr = (storeData['user_role'] as String? ?? 'staff').toLowerCase();
    final role = switch (roleStr) {
      'owner' => BrandUserRole.owner,
      'manager' => BrandUserRole.manager,
      _ => BrandUserRole.staff,
    };

    final ctx = StoreContext(
      brandId: (storeData['brand_id'] as String? ??
              data['brand_id'] as String? ??
              '')
          .toString(),
      storeId: (storeData['store_id'] as String? ??
              data['store_id'] as String? ??
              '')
          .toString(),
      storeName: (storeData['store_name'] as String? ??
              data['store_name'] as String? ??
              'My Restaurant')
          .toString(),
      brandName: (storeData['brand_name'] as String? ??
              data['restaurant_name'] as String? ??
              'My Brand')
          .toString(),
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
