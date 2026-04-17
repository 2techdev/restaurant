/// Staff endpoints — users + roles.
library;

import 'package:gastrocore_models/gastrocore_models.dart';

import '../client/gastrocore_client.dart';

class StaffEndpoint {
  final GastrocoreClient _client;

  const StaffEndpoint(this._client);

  // ---------------------------------------------------------------------------
  // Users
  // ---------------------------------------------------------------------------

  Future<List<UserEntity>> listUsers(
    String tenantId, {
    bool includeInactive = false,
  }) async {
    final list = await _client.getList(
      '/api/v1/staff/users',
      queryParams: {
        'tenant_id': tenantId,
        if (includeInactive) 'include_inactive': 'true',
      },
    );
    return list
        .map((j) => UserEntity.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<UserEntity> getUser(String userId) async {
    final json = await _client.get('/api/v1/staff/users/$userId');
    return UserEntity.fromJson(json);
  }

  Future<UserEntity> createUser(UserEntity user, {required String pin}) async {
    final body = {
      ...user.toJson(),
      'pin': pin,
    };
    final json = await _client.post('/api/v1/staff/users', body);
    return UserEntity.fromJson(json);
  }

  Future<UserEntity> updateUser(UserEntity user) async {
    final json = await _client.put(
      '/api/v1/staff/users/${user.id}',
      user.toJson(),
    );
    return UserEntity.fromJson(json);
  }

  /// Rotate a user's PIN. The API hashes server-side.
  Future<void> setPin({required String userId, required String pin}) {
    return _client
        .put('/api/v1/staff/users/$userId/pin', {'pin': pin})
        .then((_) {});
  }

  Future<void> deactivate(String userId) =>
      _client.delete('/api/v1/staff/users/$userId');

  // ---------------------------------------------------------------------------
  // Roles
  // ---------------------------------------------------------------------------

  Future<List<RoleEntity>> listRoles(String tenantId) async {
    final list = await _client.getList(
      '/api/v1/staff/roles',
      queryParams: {'tenant_id': tenantId},
    );
    return list
        .map((j) => RoleEntity.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<RoleEntity> createRole(RoleEntity role) async {
    final json = await _client.post('/api/v1/staff/roles', role.toJson());
    return RoleEntity.fromJson(json);
  }

  Future<RoleEntity> updateRole(RoleEntity role) async {
    final json = await _client.put(
      '/api/v1/staff/roles/${role.id}',
      role.toJson(),
    );
    return RoleEntity.fromJson(json);
  }

  Future<void> deleteRole(String roleId) =>
      _client.delete('/api/v1/staff/roles/$roleId');
}
