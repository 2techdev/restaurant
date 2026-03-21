import 'package:drift/drift.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/database/tables/audit_log.dart';
import 'package:gastrocore_pos/features/audit_log/domain/entities/audit_action.dart';
import 'package:gastrocore_pos/features/audit_log/domain/entities/audit_log_entry_entity.dart';

part 'audit_log_dao.g.dart';

@DriftAccessor(tables: [AuditLog])
class AuditLogDao extends DatabaseAccessor<AppDatabase>
    with _$AuditLogDaoMixin {
  AuditLogDao(super.attachedDatabase);

  // ---------------------------------------------------------------------------
  // Insert
  // ---------------------------------------------------------------------------

  Future<void> insertEntry(AuditLogCompanion entry) =>
      into(auditLog).insertOnConflictUpdate(entry);

  // ---------------------------------------------------------------------------
  // Query helpers
  // ---------------------------------------------------------------------------

  /// Fetch entries for a tenant with optional filters, newest first.
  ///
  /// [limit] caps the result set (default 200, pass 0 for unlimited).
  Future<List<AuditLogEntryEntity>> getEntries({
    required String tenantId,
    DateTime? from,
    DateTime? to,
    AuditAction? action,
    String? userId,
    int limit = 200,
  }) async {
    final query = select(auditLog)
      ..where((t) => t.tenantId.equals(tenantId))
      ..orderBy([(t) => OrderingTerm.desc(t.timestamp)]);

    if (limit > 0) {
      query.limit(limit);
    }

    if (from != null) {
      query.where((t) => t.timestamp.isBiggerOrEqualValue(from));
    }
    if (to != null) {
      query.where((t) => t.timestamp.isSmallerOrEqualValue(to));
    }
    if (action != null) {
      query.where((t) => t.action.equals(action.name));
    }
    if (userId != null && userId.isNotEmpty) {
      query.where((t) => t.userId.equals(userId));
    }

    final rows = await query.get();
    return rows.map(_toEntity).toList();
  }

  /// Fetch ALL entries for CSV export (no row limit).
  Future<List<AuditLogEntryEntity>> getAllEntries({
    required String tenantId,
    DateTime? from,
    DateTime? to,
    AuditAction? action,
    String? userId,
  }) {
    return getEntries(
      tenantId: tenantId,
      from: from,
      to: to,
      action: action,
      userId: userId,
      limit: 0,
    );
  }

  // ---------------------------------------------------------------------------
  // Mapper
  // ---------------------------------------------------------------------------

  AuditLogEntryEntity _toEntity(AuditLogEntry row) => AuditLogEntryEntity(
        id: row.id,
        tenantId: row.tenantId,
        branchId: row.branchId,
        deviceId: row.deviceId,
        userId: row.userId,
        userName: row.userName,
        managerId: row.managerId,
        managerName: row.managerName,
        action: AuditAction.fromString(row.action),
        entityType: row.entityType,
        entityId: row.entityId,
        oldValueJson: row.oldValueJson,
        newValueJson: row.newValueJson,
        reason: row.reason,
        ipAddress: row.ipAddress,
        timestamp: row.timestamp,
      );
}
