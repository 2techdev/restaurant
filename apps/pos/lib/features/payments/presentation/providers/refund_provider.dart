/// Riverpod providers for the refund (iade) feature.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/features/auth/domain/entities/user_entity.dart';
import 'package:gastrocore_pos/features/overrides/domain/entities/override_action.dart';
import 'package:gastrocore_pos/features/overrides/presentation/providers/override_provider.dart';
import 'package:gastrocore_pos/features/payments/data/repositories/refund_repository_impl.dart';

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

final refundRepositoryProvider = Provider<RefundRepositoryImpl>((ref) {
  final db = ref.watch(databaseProvider);
  return RefundRepositoryImpl(db);
});

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

sealed class RefundOperationState {
  const RefundOperationState();
}

class RefundIdle extends RefundOperationState {
  const RefundIdle();
}

class RefundProcessing extends RefundOperationState {
  const RefundProcessing();
}

class RefundSuccess extends RefundOperationState {
  final RefundResult result;
  const RefundSuccess(this.result);
}

class RefundFailure extends RefundOperationState {
  final String message;
  const RefundFailure(this.message);
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

final refundOperationProvider =
    StateNotifierProvider<RefundNotifier, RefundOperationState>((ref) {
  return RefundNotifier(ref);
});

class RefundNotifier extends StateNotifier<RefundOperationState> {
  final Ref _ref;

  RefundNotifier(this._ref) : super(const RefundIdle());

  /// Process a refund after manager approval.
  ///
  /// [orderItemIds] empty = full order refund.
  Future<bool> processRefund({
    required String ticketId,
    required List<String> orderItemIds,
    required String reason,
    required String refundMethod,
    required UserEntity requestedBy,
    required UserEntity approvedBy,
    String? notes,
  }) async {
    state = const RefundProcessing();
    try {
      final repo = _ref.read(refundRepositoryProvider);
      final tenantId = _ref.read(tenantIdProvider);
      final deviceId = _ref.read(deviceIdProvider);

      final result = await repo.processRefund(
        ticketId: ticketId,
        tenantId: tenantId,
        deviceId: deviceId,
        orderItemIds: orderItemIds,
        reason: reason,
        refundMethodStr: refundMethod,
        approvedByUserId: approvedBy.id,
        requestedByUserId: requestedBy.id,
        notes: notes,
      );

      // Log the override.
      await _ref.read(managerOverrideProvider.notifier).logOverride(
            requestedByUser: requestedBy,
            approver: approvedBy,
            action: orderItemIds.isEmpty
                ? OverrideAction.refundTicket
                : OverrideAction.refundItem,
            entityType: orderItemIds.isEmpty ? 'ticket' : 'order_item',
            entityId: ticketId,
            reason: reason,
            notes: notes,
            metadata: {
              'refundAmount': result.refundAmount,
              'itemCount': result.refundedItemIds.length,
              'method': refundMethod,
            },
          );

      state = RefundSuccess(result);
      return true;
    } catch (e) {
      state = RefundFailure(e.toString());
      return false;
    }
  }

  void reset() => state = const RefundIdle();
}
