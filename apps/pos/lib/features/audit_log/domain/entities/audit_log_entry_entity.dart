import 'audit_action.dart';

/// Immutable domain representation of a single audit log entry.
class AuditLogEntryEntity {
  const AuditLogEntryEntity({
    required this.id,
    required this.tenantId,
    required this.deviceId,
    required this.userId,
    required this.userName,
    required this.action,
    required this.entityType,
    required this.entityId,
    required this.timestamp,
    this.branchId,
    this.managerId,
    this.managerName,
    this.oldValueJson,
    this.newValueJson,
    this.reason,
    this.ipAddress,
  });

  final String id;
  final String tenantId;
  final String? branchId;
  final String deviceId;

  /// Staff member who performed the action.
  final String userId;
  final String userName;

  /// Manager / admin who authorised the action, if applicable.
  final String? managerId;
  final String? managerName;

  final AuditAction action;
  final String entityType;
  final String entityId;
  final String? oldValueJson;
  final String? newValueJson;
  final String? reason;
  final String? ipAddress;
  final DateTime timestamp;

  @override
  String toString() =>
      'AuditLogEntry(action: ${action.name}, entity: $entityType/$entityId, user: $userName)';
}
