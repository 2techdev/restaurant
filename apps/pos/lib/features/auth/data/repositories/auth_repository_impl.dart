/// Drift-backed implementation of the authentication repository.
///
/// Provides CRUD operations for [UserEntity] records, converting between
/// Drift [User] data classes and domain entities. All queries filter by
/// tenant and exclude soft-deleted rows.
library;

import 'package:drift/drift.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/features/auth/domain/entities/user_entity.dart';

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

  /// Look up a user by tenant and PIN hash. Returns `null` when no match
  /// is found or the user is inactive / deleted.
  Future<UserEntity?> getUserByPin(String tenantId, String pinHash) async {
    final query = _db.select(_db.users)
      ..where(
        (u) =>
            u.tenantId.equals(tenantId) &
            u.pinHash.equals(pinHash) &
            u.isActive.equals(true) &
            u.isDeleted.equals(false),
      );
    final row = await query.getSingleOrNull();
    return row == null ? null : _toEntity(row);
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
      role: Value(entity.role.name),
      isActive: Value(entity.isActive),
      updatedAt: Value(DateTime.now()),
    );
    await (_db.update(_db.users)..where((u) => u.id.equals(entity.id)))
        .write(companion);
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
      role: Value(entity.role.name),
      isActive: Value(entity.isActive),
      createdAt: Value(entity.createdAt),
      updatedAt: Value(entity.updatedAt),
      isDeleted: const Value(false),
      syncStatus: const Value(0),
    );
  }
}
