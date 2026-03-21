/// Riverpod providers for the Audit Log feature.
///
/// Exposes:
/// - [auditServiceProvider]       – singleton [AuditService] for all modules
/// - [auditLogFilterProvider]     – current filter state (date range, action, user)
/// - [auditLogEntriesProvider]    – filtered entries from the database
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/core/services/audit_service.dart';
import 'package:gastrocore_pos/features/audit_log/domain/entities/audit_action.dart';
import 'package:gastrocore_pos/features/audit_log/domain/entities/audit_log_entry_entity.dart';

// ---------------------------------------------------------------------------
// AuditService singleton
// ---------------------------------------------------------------------------

/// Central [AuditService] shared across all modules.
///
/// Every feature that needs to record an auditable event reads this provider.
final auditServiceProvider = Provider<AuditService>((ref) {
  final db = ref.watch(databaseProvider);
  final tenantId = ref.watch(tenantIdProvider);
  final deviceId = ref.watch(deviceIdProvider);
  return AuditService(db: db, tenantId: tenantId, deviceId: deviceId);
});

// ---------------------------------------------------------------------------
// Filter state
// ---------------------------------------------------------------------------

/// Immutable filter options for the Audit Log screen.
class AuditLogFilter {
  const AuditLogFilter({
    this.from,
    this.to,
    this.action,
    this.userId,
  });

  final DateTime? from;
  final DateTime? to;
  final AuditAction? action;
  final String? userId;

  AuditLogFilter copyWith({
    Object? from = _sentinel,
    Object? to = _sentinel,
    Object? action = _sentinel,
    Object? userId = _sentinel,
  }) {
    return AuditLogFilter(
      from: from == _sentinel ? this.from : from as DateTime?,
      to: to == _sentinel ? this.to : to as DateTime?,
      action: action == _sentinel ? this.action : action as AuditAction?,
      userId: userId == _sentinel ? this.userId : userId as String?,
    );
  }

  static const _sentinel = Object();
}

class AuditLogFilterNotifier extends StateNotifier<AuditLogFilter> {
  AuditLogFilterNotifier() : super(const AuditLogFilter());

  void setFrom(DateTime? date) => state = state.copyWith(from: date);
  void setTo(DateTime? date) => state = state.copyWith(to: date);
  void setAction(AuditAction? action) => state = state.copyWith(action: action);
  void setUserId(String? userId) => state = state.copyWith(userId: userId);
  void reset() => state = const AuditLogFilter();
}

final auditLogFilterProvider =
    StateNotifierProvider<AuditLogFilterNotifier, AuditLogFilter>(
  (_) => AuditLogFilterNotifier(),
);

// ---------------------------------------------------------------------------
// Filtered entries
// ---------------------------------------------------------------------------

/// Audit log entries filtered by [auditLogFilterProvider], newest first.
///
/// Refreshed automatically when the filter changes.
final auditLogEntriesProvider =
    FutureProvider<List<AuditLogEntryEntity>>((ref) async {
  final db = ref.watch(databaseProvider);
  final tenantId = ref.watch(tenantIdProvider);
  final filter = ref.watch(auditLogFilterProvider);

  return db.auditLogDao.getEntries(
    tenantId: tenantId,
    from: filter.from,
    to: filter.to,
    action: filter.action,
    userId: filter.userId,
  );
});
