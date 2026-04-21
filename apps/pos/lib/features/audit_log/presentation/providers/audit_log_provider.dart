/// Riverpod providers for the Audit Log feature.
///
/// Exposes:
/// - [auditServiceProvider]       – singleton [AuditService] for all modules
/// - [auditLogFilterProvider]     – current filter state (date range, action, user)
/// - [auditLogEntriesProvider]    – filtered entries from the database
/// - [auditLogExportProvider]     – async CSV export operation state
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

// ---------------------------------------------------------------------------
// CSV Export
// ---------------------------------------------------------------------------

/// State for the CSV export operation.
sealed class AuditExportState {
  const AuditExportState();
}

class AuditExportIdle extends AuditExportState {
  const AuditExportIdle();
}

class AuditExportBusy extends AuditExportState {
  const AuditExportBusy();
}

class AuditExportSuccess extends AuditExportState {
  const AuditExportSuccess(this.filePath);
  final String filePath;
}

class AuditExportError extends AuditExportState {
  const AuditExportError(this.message);
  final String message;
}

class AuditLogExportNotifier extends StateNotifier<AuditExportState> {
  AuditLogExportNotifier(this._ref) : super(const AuditExportIdle());

  final Ref _ref;

  /// Export all audit log entries matching the current filter to a CSV file.
  ///
  /// The file is saved to the documents directory under
  /// `GastroCore/exports/audit_log_<timestamp>.csv`.
  Future<void> exportCsv() async {
    state = const AuditExportBusy();

    try {
      final db = _ref.read(databaseProvider);
      final tenantId = _ref.read(tenantIdProvider);
      final filter = _ref.read(auditLogFilterProvider);

      final entries = await db.auditLogDao.getAllEntries(
        tenantId: tenantId,
        from: filter.from,
        to: filter.to,
        action: filter.action,
        userId: filter.userId,
      );

      final csv = _buildCsv(entries);

      // Save to documents directory.
      final docsDir = await getApplicationDocumentsDirectory();
      final exportDir = Directory(
          p.join(docsDir.path, 'GastroCore', 'exports'));
      if (!exportDir.existsSync()) {
        await exportDir.create(recursive: true);
      }

      final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final file = File(p.join(exportDir.path, 'audit_log_$ts.csv'));
      await file.writeAsString(csv, flush: true);

      state = AuditExportSuccess(file.path);
    } catch (e) {
      state = AuditExportError('Export failed: $e');
    }
  }

  void reset() => state = const AuditExportIdle();

  // ---------------------------------------------------------------------------
  // CSV builder
  // ---------------------------------------------------------------------------

  static String _buildCsv(List<AuditLogEntryEntity> entries) {
    final tsFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
    final buf = StringBuffer();

    // Header row
    buf.writeln(
      'Timestamp,Action,Entity Type,Entity ID,'
      'User ID,User Name,Manager ID,Manager Name,'
      'Reason,Device ID,Old Value,New Value',
    );

    for (final e in entries) {
      buf.writeln([
        tsFormat.format(e.timestamp),
        e.action.label,
        e.entityType,
        _csvEscape(e.entityId),
        _csvEscape(e.userId),
        _csvEscape(e.userName),
        _csvEscape(e.managerId ?? ''),
        _csvEscape(e.managerName ?? ''),
        _csvEscape(e.reason ?? ''),
        _csvEscape(e.deviceId),
        _csvEscape(e.oldValueJson ?? ''),
        _csvEscape(e.newValueJson ?? ''),
      ].join(','));
    }

    return buf.toString();
  }

  /// Wrap a value in double quotes and escape internal quotes.
  static String _csvEscape(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}

final auditLogExportProvider =
    StateNotifierProvider<AuditLogExportNotifier, AuditExportState>(
  AuditLogExportNotifier.new,
);
