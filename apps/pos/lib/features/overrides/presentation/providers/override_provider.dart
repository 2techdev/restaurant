/// Riverpod providers for the manager override feature.
///
/// [overrideRepositoryProvider] supplies the singleton repository.
/// [managerOverrideProvider] exposes an async notifier that drives the
/// PIN-verification flow: pending → verifying → approved | rejected.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/features/auth/domain/entities/user_entity.dart';
import 'package:gastrocore_pos/features/overrides/data/repositories/override_repository_impl.dart';
import 'package:gastrocore_pos/features/overrides/domain/entities/override_action.dart';

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

final overrideRepositoryProvider = Provider<OverrideRepositoryImpl>((ref) {
  final db = ref.watch(databaseProvider);
  return OverrideRepositoryImpl(db);
});

// ---------------------------------------------------------------------------
// Override state
// ---------------------------------------------------------------------------

/// Transient state for a single in-flight override approval request.
sealed class OverrideState {
  const OverrideState();
}

/// No override request in progress.
class OverrideIdle extends OverrideState {
  const OverrideIdle();
}

/// PIN being entered / verification in progress.
class OverrideVerifying extends OverrideState {
  const OverrideVerifying();
}

/// Manager PIN accepted; [approver] is the authenticated manager/admin.
class OverrideApproved extends OverrideState {
  final UserEntity approver;
  const OverrideApproved(this.approver);
}

/// PIN rejected (wrong PIN or insufficient role).
class OverrideRejected extends OverrideState {
  final String message;
  const OverrideRejected(this.message);
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

/// Drives the manager PIN verification flow.
///
/// Usage:
/// ```dart
/// final approved = await ref.read(managerOverrideProvider.notifier)
///     .requestOverride(pinHash: hash);
/// ```
final managerOverrideProvider =
    StateNotifierProvider<ManagerOverrideNotifier, OverrideState>((ref) {
  return ManagerOverrideNotifier(ref);
});

class ManagerOverrideNotifier extends StateNotifier<OverrideState> {
  final Ref _ref;

  ManagerOverrideNotifier(this._ref) : super(const OverrideIdle());

  /// Verify [pinHash] against the DB.
  ///
  /// Returns the [UserEntity] of the approver on success, or `null` if
  /// the PIN is wrong or the user lacks the required role.
  Future<UserEntity?> requestOverride(String pinHash) async {
    state = const OverrideVerifying();
    final repo = _ref.read(overrideRepositoryProvider);
    final tenantId = _ref.read(tenantIdProvider);

    final approver = await repo.verifyManagerPin(tenantId, pinHash);
    if (approver != null) {
      state = OverrideApproved(approver);
    } else {
      state = const OverrideRejected('Geçersiz yönetici PIN\'i');
    }
    return approver;
  }

  /// Persist an override log entry after the operation succeeds.
  Future<OverrideLogEntity> logOverride({
    required UserEntity requestedByUser,
    required UserEntity approver,
    required OverrideAction action,
    required String entityType,
    required String entityId,
    required String reason,
    String? notes,
    Map<String, dynamic> metadata = const {},
  }) async {
    final repo = _ref.read(overrideRepositoryProvider);
    final tenantId = _ref.read(tenantIdProvider);
    final deviceId = _ref.read(deviceIdProvider);

    return repo.createAndLogOverride(
      tenantId: tenantId,
      deviceId: deviceId,
      requestedByUserId: requestedByUser.id,
      requestedByName: requestedByUser.name,
      approver: approver,
      action: action,
      entityType: entityType,
      entityId: entityId,
      reason: reason,
      notes: notes,
      metadata: metadata,
    );
  }

  /// Reset to idle (e.g. when dialog is dismissed).
  void reset() => state = const OverrideIdle();
}

// ---------------------------------------------------------------------------
// Override log list
// ---------------------------------------------------------------------------

/// All override log entries for the current tenant, newest first.
final overrideLogsProvider =
    FutureProvider.family<List<OverrideLogEntity>, String?>(
  (ref, entityId) async {
    final repo = ref.watch(overrideRepositoryProvider);
    final tenantId = ref.watch(tenantIdProvider);
    return repo.getOverrideLogs(tenantId, entityId: entityId);
  },
);
