/// Secure storage wrapper for JWT tokens and store context.
library;

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:gastrocore_pos/features/brand_auth/domain/entities/store_context.dart';

/// Keys used in secure storage.
abstract final class _Keys {
  static const accessToken = 'brand_access_token';
  static const refreshToken = 'brand_refresh_token';
  static const storeContext = 'brand_store_context';
  static const rememberMe = 'brand_remember_me';
}

/// Persists and retrieves JWT tokens + [StoreContext] from the device's
/// secure keychain / keystore (via flutter_secure_storage).
class TokenStorage {
  const TokenStorage([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  // ---------------------------------------------------------------------------
  // Write
  // ---------------------------------------------------------------------------

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    required StoreContext storeContext,
    required bool rememberMe,
  }) async {
    await Future.wait([
      _storage.write(key: _Keys.accessToken, value: accessToken),
      _storage.write(key: _Keys.refreshToken, value: refreshToken),
      _storage.write(
        key: _Keys.storeContext,
        value: jsonEncode(_contextToJson(storeContext)),
      ),
      _storage.write(
        key: _Keys.rememberMe,
        value: rememberMe ? '1' : '0',
      ),
    ]);
  }

  Future<void> updateAccessToken(String accessToken) async {
    await _storage.write(key: _Keys.accessToken, value: accessToken);
  }

  Future<void> updateLastSync(DateTime lastSync) async {
    final raw = await _storage.read(key: _Keys.storeContext);
    if (raw == null) return;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      json['last_sync_at'] = lastSync.toIso8601String();
      await _storage.write(
        key: _Keys.storeContext,
        value: jsonEncode(json),
      );
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Read
  // ---------------------------------------------------------------------------

  Future<String?> readAccessToken() =>
      _storage.read(key: _Keys.accessToken);

  Future<String?> readRefreshToken() =>
      _storage.read(key: _Keys.refreshToken);

  Future<StoreContext?> readStoreContext() async {
    final raw = await _storage.read(key: _Keys.storeContext);
    if (raw == null) return null;
    try {
      return _contextFromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> readRememberMe() async {
    final v = await _storage.read(key: _Keys.rememberMe);
    return v == '1';
  }

  // ---------------------------------------------------------------------------
  // Clear
  // ---------------------------------------------------------------------------

  Future<void> clearAll() async {
    await Future.wait([
      _storage.delete(key: _Keys.accessToken),
      _storage.delete(key: _Keys.refreshToken),
      _storage.delete(key: _Keys.storeContext),
      _storage.delete(key: _Keys.rememberMe),
    ]);
  }

  // ---------------------------------------------------------------------------
  // JSON helpers
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _contextToJson(StoreContext ctx) => {
        'brand_id': ctx.brandId,
        'store_id': ctx.storeId,
        'store_name': ctx.storeName,
        'brand_name': ctx.brandName,
        'user_role': ctx.userRole.name,
        'is_online_mode': ctx.isOnlineMode,
        if (ctx.lastSyncAt != null)
          'last_sync_at': ctx.lastSyncAt!.toIso8601String(),
      };

  StoreContext _contextFromJson(Map<String, dynamic> json) {
    final roleStr = (json['user_role'] as String? ?? 'staff').toLowerCase();
    final role = switch (roleStr) {
      'owner' => BrandUserRole.owner,
      'manager' => BrandUserRole.manager,
      _ => BrandUserRole.staff,
    };
    final lastSyncRaw = json['last_sync_at'] as String?;
    return StoreContext(
      brandId: json['brand_id'] as String? ?? '',
      storeId: json['store_id'] as String? ?? '',
      storeName: json['store_name'] as String? ?? '',
      brandName: json['brand_name'] as String? ?? '',
      userRole: role,
      isOnlineMode: (json['is_online_mode'] as bool?) ?? true,
      lastSyncAt:
          lastSyncRaw != null ? DateTime.tryParse(lastSyncRaw) : null,
    );
  }
}
