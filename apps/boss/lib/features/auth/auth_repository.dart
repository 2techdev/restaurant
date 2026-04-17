/// Auth repository — wraps gastrocore_api auth endpoint with boss-specific
/// concerns (owner role guard, token storage).
///
/// TODO(boss-sprint2): swap to dedicated `/api/v1/auth/boss-login` endpoint
/// once backend exposes it. For now we reuse the staff-PIN login and assert
/// the returned user role is in [ownerRoles].
library;

import 'package:gastrocore_api/gastrocore_api.dart';

import 'auth_state.dart';

class AuthRepository {
  final GastrocoreClient _client;

  AuthRepository(this._client);

  /// Log in with a staff PIN and assert owner role.
  Future<BossSession> loginWithPin({
    required String tenantId,
    required String pin,
  }) async {
    final response = await _client.auth.login(
      tenantId: tenantId,
      pin: pin,
    );
    return _toSession(response);
  }

  /// Log in with email + password.
  ///
  /// TODO(boss-sprint2): backend currently only exposes PIN login. Email
  /// support requires `/api/v1/auth/email-login` (in Phase 3 / Epic 7).
  /// Until that lands, this method throws so the UI shows an error.
  Future<BossSession> loginWithEmail({
    required String email,
    required String password,
  }) async {
    throw UnimplementedError(
      'E-posta girişi henüz aktif değil — şimdilik PIN ile giriş yapın.',
    );
  }

  Future<void> logout() => _client.auth.logout();

  BossSession _toSession(AuthResponse r) {
    if (!isOwnerRole(r.user.role)) {
      throw const _NotOwnerException();
    }
    return BossSession(
      user: r.user,
      token: r.token,
      expiresAt: r.expiresAt,
    );
  }
}

class _NotOwnerException implements Exception {
  const _NotOwnerException();
  @override
  String toString() =>
      'Bu hesabın Boss uygulamasına erişim yetkisi yok (owner / manager rolü gerekli).';
}
