/// Riverpod providers for the Backup & Restore feature.
///
/// Exposes:
/// - [backupServiceProvider]   – singleton [BackupService]
/// - [backupListProvider]      – async list of [BackupInfo], newest first
/// - [backupOperationProvider] – async state of the current backup/restore op
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/services/backup_service.dart';
import 'package:gastrocore_pos/features/audit_log/presentation/providers/audit_log_provider.dart';

// ---------------------------------------------------------------------------
// BackupService singleton
// ---------------------------------------------------------------------------

final backupServiceProvider = Provider<BackupService>((_) => BackupService());

// ---------------------------------------------------------------------------
// Backup list
// ---------------------------------------------------------------------------

/// Reloads every time [createBackup] or [deleteBackup] completes.
final backupListProvider = FutureProvider<List<BackupInfo>>((ref) async {
  final svc = ref.watch(backupServiceProvider);
  return svc.listBackups();
});

// ---------------------------------------------------------------------------
// Operation state (create / restore / delete)
// ---------------------------------------------------------------------------

sealed class BackupOpState {
  const BackupOpState();
}

class BackupOpIdle extends BackupOpState {
  const BackupOpIdle();
}

class BackupOpBusy extends BackupOpState {
  const BackupOpBusy(this.message);
  final String message;
}

class BackupOpSuccess extends BackupOpState {
  const BackupOpSuccess(this.message);
  final String message;
}

class BackupOpError extends BackupOpState {
  const BackupOpError(this.message);
  final String message;
}

class BackupOperationNotifier extends StateNotifier<BackupOpState> {
  BackupOperationNotifier(this._ref) : super(const BackupOpIdle());

  final Ref _ref;

  BackupService get _svc => _ref.read(backupServiceProvider);

  Future<void> createBackup() async {
    state = const BackupOpBusy('Creating backup…');
    try {
      final info = await _svc.createBackup();
      _ref.invalidate(backupListProvider);
      // Audit log
      await _ref.read(auditServiceProvider).logBackupCreated(info.name);
      state = BackupOpSuccess('Backup created: ${info.name}  (${info.sizeLabel})');
    } catch (e) {
      state = BackupOpError('Backup failed: $e');
    }
  }

  Future<void> restoreBackup(BackupInfo backup) async {
    state = const BackupOpBusy('Restoring backup…');
    try {
      await _svc.restoreBackup(backup);
      // Audit log
      await _ref.read(auditServiceProvider).logBackupRestored(backup.name);
      state = BackupOpSuccess(
        'Restore complete. Please restart the app to apply changes.',
      );
    } catch (e) {
      state = BackupOpError('Restore failed: $e');
    }
  }

  Future<void> deleteBackup(BackupInfo backup) async {
    state = const BackupOpBusy('Deleting backup…');
    try {
      await _svc.deleteBackup(backup);
      _ref.invalidate(backupListProvider);
      state = const BackupOpSuccess('Backup deleted.');
    } catch (e) {
      state = BackupOpError('Delete failed: $e');
    }
  }

  void reset() => state = const BackupOpIdle();
}

final backupOperationProvider =
    StateNotifierProvider<BackupOperationNotifier, BackupOpState>(
  BackupOperationNotifier.new,
);
