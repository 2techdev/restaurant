/// Authentication endpoint methods.
library;

import 'package:gastrocore_models/gastrocore_models.dart';
import '../client/gastrocore_client.dart';

/// Response DTO for a successful login.
class AuthResponse {
  final String token;
  final UserEntity user;
  final DateTime expiresAt;

  const AuthResponse({
    required this.token,
    required this.user,
    required this.expiresAt,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) => AuthResponse(
        token: json['token'] as String,
        user: UserEntity.fromJson(json['user'] as Map<String, dynamic>),
        expiresAt: DateTime.parse(json['expires_at'] as String),
      );
}

class AuthEndpoint {
  final GastrocoreClient _client;

  const AuthEndpoint(this._client);

  /// Authenticate with a staff PIN and return a session token.
  Future<AuthResponse> login({
    required String tenantId,
    required String pin,
    String? deviceId,
  }) async {
    final body = {
      'tenant_id': tenantId,
      'pin': pin,
      if (deviceId != null) 'device_id': deviceId,
    };
    final json = await _client.post('/api/v1/auth/login', body);
    final response = AuthResponse.fromJson(json);
    _client.setAuthToken(response.token);
    return response;
  }

  /// Invalidate the current session token.
  Future<void> logout() async {
    await _client.post('/api/v1/auth/logout', {});
    _client.clearAuthToken();
  }

  /// Refresh the session token.
  Future<AuthResponse> refreshToken() async {
    final json = await _client.post('/api/v1/auth/refresh', {});
    final response = AuthResponse.fromJson(json);
    _client.setAuthToken(response.token);
    return response;
  }

  /// Register or update a POS device.
  Future<void> registerDevice({
    required String tenantId,
    required String deviceId,
    required String deviceName,
    required String deviceType,
  }) async {
    await _client.post('/api/v1/auth/devices', {
      'tenant_id': tenantId,
      'device_id': deviceId,
      'device_name': deviceName,
      'device_type': deviceType,
    });
  }
}
