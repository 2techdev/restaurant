import 'package:drift/drift.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';

/// Read/write surface for the user_tenant_assignments table (N:M user↔tenant).
///
/// Pairs with [activeTenantProvider]; the operator-facing tenant switcher
/// looks up the candidate list through [getTenantsForUser]. Server-side
/// authoritative state arrives via the cloud-sync pipeline; this repository
/// is the local mirror.
class UserTenantRepository {
  UserTenantRepository(this._db);

  final AppDatabase _db;

  /// Tenants the [userId] has been granted access to (excluding soft-deleted).
  /// Includes both confirmed and pending assignments — the UI greys out
  /// pending ones.
  Future<List<UserTenantAssignment>> getTenantsForUser(String userId) async {
    return (_db.select(_db.userTenantAssignments)
          ..where((t) => t.userId.equals(userId) & t.isDeleted.equals(false))
          ..orderBy([
            (t) => OrderingTerm(expression: t.isConfirmed, mode: OrderingMode.desc),
            (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.asc),
          ]))
        .get();
  }

  /// Whether [userId] has access to [tenantId] (confirmed assignments only).
  Future<bool> hasAccess(String userId, String tenantId) async {
    final row = await (_db.select(_db.userTenantAssignments)
          ..where((t) =>
              t.userId.equals(userId) &
              t.tenantId.equals(tenantId) &
              t.isConfirmed.equals(true) &
              t.isDeleted.equals(false))
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }

  /// Idempotent upsert. Used by the cloud-sync pull when the server
  /// publishes the operator's tenant list.
  Future<void> upsert({
    required String userId,
    required String tenantId,
    String? roleOverride,
    bool isConfirmed = true,
  }) async {
    final now = DateTime.now().toUtc();
    final existing = await (_db.select(_db.userTenantAssignments)
          ..where((t) =>
              t.userId.equals(userId) & t.tenantId.equals(tenantId))
          ..limit(1))
        .getSingleOrNull();

    if (existing == null) {
      await _db.into(_db.userTenantAssignments).insert(
        UserTenantAssignmentsCompanion(
          id: Value(IdGenerator.generateId()),
          userId: Value(userId),
          tenantId: Value(tenantId),
          roleOverride: Value(roleOverride),
          isConfirmed: Value(isConfirmed),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );
    } else {
      await (_db.update(_db.userTenantAssignments)
            ..where((t) => t.id.equals(existing.id)))
          .write(UserTenantAssignmentsCompanion(
        roleOverride: Value(roleOverride),
        isConfirmed: Value(isConfirmed),
        isDeleted: const Value(false),
        updatedAt: Value(now),
        syncStatus: const Value(0),
      ));
    }
  }

  /// Soft-delete (server-side revocation propagated to local).
  Future<void> revoke({required String userId, required String tenantId}) async {
    final now = DateTime.now().toUtc();
    await (_db.update(_db.userTenantAssignments)
          ..where((t) =>
              t.userId.equals(userId) & t.tenantId.equals(tenantId)))
        .write(UserTenantAssignmentsCompanion(
      isDeleted: const Value(true),
      isConfirmed: const Value(false),
      updatedAt: Value(now),
      syncStatus: const Value(0),
    ));
  }
}
