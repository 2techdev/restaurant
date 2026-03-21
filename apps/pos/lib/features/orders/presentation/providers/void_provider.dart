/// Riverpod providers for the void (iptal) feature.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/features/auth/domain/entities/user_entity.dart';
import 'package:gastrocore_pos/features/orders/data/repositories/void_repository_impl.dart';
import 'package:gastrocore_pos/features/overrides/domain/entities/override_action.dart';
import 'package:gastrocore_pos/features/overrides/presentation/providers/override_provider.dart';

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

final voidRepositoryProvider = Provider<VoidRepositoryImpl>((ref) {
  final db = ref.watch(databaseProvider);
  return VoidRepositoryImpl(db);
});

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

sealed class VoidOperationState {
  const VoidOperationState();
}

class VoidIdle extends VoidOperationState {
  const VoidIdle();
}

class VoidProcessing extends VoidOperationState {
  const VoidProcessing();
}

class VoidSuccess extends VoidOperationState {
  final VoidResult result;
  const VoidSuccess(this.result);
}

class VoidFailure extends VoidOperationState {
  final String message;
  const VoidFailure(this.message);
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

final voidOperationProvider =
    StateNotifierProvider<VoidNotifier, VoidOperationState>((ref) {
  return VoidNotifier(ref);
});

class VoidNotifier extends StateNotifier<VoidOperationState> {
  final Ref _ref;

  VoidNotifier(this._ref) : super(const VoidIdle());

  /// Void a single order item after manager approval.
  Future<bool> voidItem({
    required String orderItemId,
    required String reason,
    required UserEntity requestedBy,
    required UserEntity approvedBy,
    String? notes,
  }) async {
    state = const VoidProcessing();
    try {
      final repo = _ref.read(voidRepositoryProvider);
      final tenantId = _ref.read(tenantIdProvider);
      final deviceId = _ref.read(deviceIdProvider);

      final result = await repo.voidOrderItem(
        orderItemId: orderItemId,
        reason: reason,
        approvedByUserId: approvedBy.id,
        requestedByUserId: requestedBy.id,
        tenantId: tenantId,
        deviceId: deviceId,
        notes: notes,
      );

      // Log the override entry.
      await _ref.read(managerOverrideProvider.notifier).logOverride(
            requestedByUser: requestedBy,
            approver: approvedBy,
            action: OverrideAction.voidItem,
            entityType: 'order_item',
            entityId: orderItemId,
            reason: reason,
            notes: notes,
            metadata: {'ticketId': result.ticketId},
          );

      state = VoidSuccess(result);
      return true;
    } catch (e) {
      state = VoidFailure(e.toString());
      return false;
    }
  }

  /// Void an entire ticket after manager approval.
  Future<bool> voidTicket({
    required String ticketId,
    required String reason,
    required UserEntity requestedBy,
    required UserEntity approvedBy,
    String? notes,
  }) async {
    state = const VoidProcessing();
    try {
      final repo = _ref.read(voidRepositoryProvider);
      final tenantId = _ref.read(tenantIdProvider);
      final deviceId = _ref.read(deviceIdProvider);

      final result = await repo.voidTicket(
        ticketId: ticketId,
        reason: reason,
        approvedByUserId: approvedBy.id,
        requestedByUserId: requestedBy.id,
        tenantId: tenantId,
        deviceId: deviceId,
        notes: notes,
      );

      await _ref.read(managerOverrideProvider.notifier).logOverride(
            requestedByUser: requestedBy,
            approver: approvedBy,
            action: OverrideAction.voidTicket,
            entityType: 'ticket',
            entityId: ticketId,
            reason: reason,
            notes: notes,
            metadata: {'voidedItemCount': result.voidedItemIds.length},
          );

      state = VoidSuccess(result);
      return true;
    } catch (e) {
      state = VoidFailure(e.toString());
      return false;
    }
  }

  void reset() => state = const VoidIdle();
}
