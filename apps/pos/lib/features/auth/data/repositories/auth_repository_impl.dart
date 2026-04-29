/// Drift-backed implementation of the authentication repository.
///
/// Provides CRUD operations for [UserEntity] records, converting between
/// Drift [User] data classes and domain entities. All queries filter by
/// tenant and exclude soft-deleted rows.
library;

import 'package:drift/drift.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/features/auth/domain/entities/user_entity.dart';

/// Thrown by [AuthRepositoryImpl.getUserByPin] when the same PIN hash resolves
/// to multiple active users within a tenant. PIN-only login cannot
/// disambiguate in that case — admin must re-assign PINs.
class PinCollisionException implements Exception {
  const PinCollisionException(this.matchCount);
  final int matchCount;

  @override
  String toString() => 'PinCollisionException: $matchCount users share this PIN';
}

class AuthRepositoryImpl {
  final AppDatabase _db;

  AuthRepositoryImpl(this._db);

  // -------------------------------------------------------------------------
  // Queries
  // -------------------------------------------------------------------------

  /// Return all active (non-deleted) users for [tenantId].
  Future<List<UserEntity>> getAllUsers(String tenantId) async {
    final query = _db.select(_db.users)
      ..where((u) => u.tenantId.equals(tenantId) & u.isDeleted.equals(false));
    final rows = await query.get();
    return rows.map(_toEntity).toList();
  }

  /// Look up a user by tenant and PIN hash. Returns `null` when no active,
  /// non-deleted user matches the hash. Throws [PinCollisionException] if
  /// more than one user shares the same PIN within the tenant — PIN-only
  /// login requires uniqueness and admin must resolve the conflict.
  Future<UserEntity?> getUserByPin(String tenantId, String pinHash) async {
    final query = _db.select(_db.users)
      ..where(
        (u) =>
            u.tenantId.equals(tenantId) &
            u.pinHash.equals(pinHash) &
            u.isActive.equals(true) &
            u.isDeleted.equals(false),
      );
    final rows = await query.get();
    if (rows.isEmpty) return null;
    if (rows.length > 1) {
      throw PinCollisionException(rows.length);
    }
    return _toEntity(rows.first);
  }

  // -------------------------------------------------------------------------
  // Commands
  // -------------------------------------------------------------------------

  /// Insert a new user.
  Future<void> createUser(UserEntity entity) async {
    await _db.into(_db.users).insert(_toCompanion(entity));
  }

  /// Update an existing user (matched by primary key).
  Future<void> updateUser(UserEntity entity) async {
    final companion = UsersCompanion(
      name: Value(entity.name),
      pinHash: Value(entity.pinHash),
      managerPinHash: Value(entity.managerPinHash),
      role: Value(entity.role.name),
      isActive: Value(entity.isActive),
      updatedAt: Value(DateTime.now()),
    );
    await (_db.update(_db.users)..where((u) => u.id.equals(entity.id)))
        .write(companion);
  }

  /// Set or clear the dedicated manager override PIN for a user.
  ///
  /// Pass `null` to remove the override PIN (falls back to [pinHash]).
  Future<void> updateManagerPin(String userId, String? managerPinHash) async {
    await (_db.update(_db.users)..where((u) => u.id.equals(userId))).write(
      UsersCompanion(
        managerPinHash: Value(managerPinHash),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Soft-delete a user by setting [isDeleted] to true.
  Future<void> deleteUser(String id) async {
    await (_db.update(_db.users)..where((u) => u.id.equals(id))).write(
      UsersCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Mappers
  // -------------------------------------------------------------------------

  UserEntity _toEntity(User row) {
    return UserEntity(
      id: row.id,
      tenantId: row.tenantId,
      name: row.name,
      pinHash: row.pinHash,
      managerPinHash: row.managerPinHash,
      role: UserRole.values.firstWhere(
        (r) => r.name == row.role,
        orElse: () => UserRole.waiter,
      ),
      isActive: row.isActive,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  UsersCompanion _toCompanion(UserEntity entity) {
    return UsersCompanion(
      id: Value(entity.id),
      tenantId: Value(entity.tenantId),
      name: Value(entity.name),
      pinHash: Value(entity.pinHash),
      managerPinHash: Value(entity.managerPinHash),
      role: Value(entity.role.name),
      isActive: Value(entity.isActive),
      createdAt: Value(entity.createdAt),
      updatedAt: Value(entity.updatedAt),
      isDeleted: const Value(false),
      syncStatus: const Value(0),
    );
  }
}
