/// Drift-backed repository for manager override verification and audit logging.
///
/// All override operations (void, refund, discount, price change) must call
/// [verifyManagerPin] to authenticate the approver, then [logOverride] to
/// write a permanent record to the [AuditLog] table.
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/auth/domain/entities/user_entity.dart';
import 'package:gastrocore_pos/features/overrides/domain/entities/override_action.dart';

class OverrideRepositoryImpl {
  final AppDatabase _db;

  OverrideRepositoryImpl(this._db);

  // =========================================================================
  // PIN verification
  // =========================================================================

  /// Verify [pinHash] belongs to an active manager or admin within [tenantId].
  ///
  /// Returns the approver's [UserEntity] on success, or `null` if the PIN is
  /// incorrect or the user does not have sufficient privilege.
  Future<UserEntity?> verifyManagerPin(
    String tenantId,
    String pinHash,
  ) async {
    final query = _db.select(_db.users)
      ..where(
        (u) =>
            u.tenantId.equals(tenantId) &
            u.pinHash.equals(pinHash) &
            u.isActive.equals(true) &
            u.isDeleted.equals(false),
      );
    final row = await query.getSingleOrNull();
    if (row == null) return null;

    // Require manager or admin role.
    if (!canApproveOverride(row.role)) return null;

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

  // =========================================================================
  // Audit logging
  // =========================================================================

  /// Write an [OverrideLogEntity] to the [AuditLog] table.
  ///
  /// Called immediately after a privileged operation succeeds.
  Future<void> logOverride(OverrideLogEntity log) async {
    await _db.into(_db.auditLog).insert(
          AuditLogCompanion(
            id: Value(log.id),
            tenantId: Value(log.tenantId),
            deviceId: Value(log.deviceId),
            userId: Value(log.approvedByUserId),
            userName: Value(log.approvedByName),
            entityType: Value(log.entityType),
            entityId: Value(log.entityId),
            action: Value(log.action.auditKey),
            newValueJson: Value(log.metadataJson),
            timestamp: Value(log.timestamp),
          ),
        );
  }

  /// Create an [OverrideLogEntity] and persist it in a single call.
  ///
  /// Convenience wrapper around [logOverride] for common use.
  Future<OverrideLogEntity> createAndLogOverride({
    required String tenantId,
    required String deviceId,
    required String requestedByUserId,
    required String requestedByName,
    required UserEntity approver,
    required OverrideAction action,
    required String entityType,
    required String entityId,
    required String reason,
    String? notes,
    Map<String, dynamic> metadata = const {},
  }) async {
    final log = OverrideLogEntity(
      id: IdGenerator.generateId(),
      tenantId: tenantId,
      deviceId: deviceId,
      requestedByUserId: requestedByUserId,
      requestedByName: requestedByName,
      approvedByUserId: approver.id,
      approvedByName: approver.name,
      action: action,
      entityType: entityType,
      entityId: entityId,
      reason: reason,
      notes: notes,
      metadata: metadata,
      timestamp: DateTime.now(),
    );
    await logOverride(log);
    return log;
  }

  // =========================================================================
  // Queries
  // =========================================================================

  /// Return all override log entries for [tenantId], newest first.
  ///
  /// Optionally filter by [entityId] to get overrides for a specific ticket.
  Future<List<OverrideLogEntity>> getOverrideLogs(
    String tenantId, {
    String? entityId,
  }) async {
    var query = _db.select(_db.auditLog)
      ..where(
        (a) =>
            a.tenantId.equals(tenantId) &
            a.action.like('override:%'),
      )
      ..orderBy([(a) => OrderingTerm.desc(a.timestamp)]);

    final rows = await query.get();

    return rows
        .where((r) => entityId == null || r.entityId == entityId)
        .map(_toEntity)
        .toList();
  }

  // =========================================================================
  // Mapper
  // =========================================================================

  OverrideLogEntity _toEntity(AuditLogEntry row) {
    Map<String, dynamic> data = {};
    if (row.newValueJson != null) {
      try {
        data = (jsonDecode(row.newValueJson!) as Map<String, dynamic>);
      } catch (_) {}
    }

    return OverrideLogEntity(
      id: row.id,
      tenantId: row.tenantId,
      deviceId: row.deviceId,
      requestedByUserId: (data['requestedBy'] as String?) ?? '',
      requestedByName: (data['requestedByName'] as String?) ?? '',
      approvedByUserId: row.userId,
      approvedByName: (data['approvedByName'] as String?) ?? '',
      action: OverrideActionLabel.fromAuditKey(row.action),
      entityType: row.entityType,
      entityId: row.entityId,
      reason: (data['reason'] as String?) ?? '',
      notes: data['notes'] as String?,
      metadata: data,
      timestamp: row.timestamp,
    );
  }
}
