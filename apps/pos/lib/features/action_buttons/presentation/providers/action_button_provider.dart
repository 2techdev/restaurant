/// Riverpod providers for action buttons (SambaPOS-style function buttons).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/features/action_buttons/data/repositories/action_button_repository.dart';
import 'package:gastrocore_pos/features/action_buttons/domain/entities/action_button_entity.dart';
import 'package:gastrocore_pos/features/auth/presentation/providers/auth_provider.dart';

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

final actionButtonRepositoryProvider = Provider<ActionButtonRepository>((ref) {
  return ActionButtonRepository(ref.watch(databaseProvider));
});

// ---------------------------------------------------------------------------
// Lists
// ---------------------------------------------------------------------------

/// Streams every configured button for the current tenant — used by the
/// Settings editor (which shows active + inactive rows).
final actionButtonsProvider =
    StreamProvider<List<ActionButtonEntity>>((ref) {
  final repo = ref.watch(actionButtonRepositoryProvider);
  final tenantId = ref.watch(tenantIdProvider);
  return repo.watchAll(tenantId);
});

/// Streams only the active buttons for a given surface — used by the POS
/// shell strips to render only what the operator has enabled.
final actionButtonsByPositionProvider = StreamProvider.family<
    List<ActionButtonEntity>, ActionButtonPosition>((ref, position) {
  final repo = ref.watch(actionButtonRepositoryProvider);
  final tenantId = ref.watch(tenantIdProvider);
  return repo.watchByPosition(tenantId, position);
});

/// Active buttons for [position] that the currently logged-in user is
/// actually allowed to see. Layers [currentUserRoleProvider] on top of
/// [actionButtonsByPositionProvider] so role-gated buttons disappear
/// from the strip when a lower-privilege user logs in. Admin always
/// sees every button; a null / empty roleFilter behaves like the pre-
/// gating default and is visible to everyone.
final visibleActionButtonsByPositionProvider = Provider.family<
    List<ActionButtonEntity>, ActionButtonPosition>((ref, position) {
  final async = ref.watch(actionButtonsByPositionProvider(position));
  final all = async.valueOrNull ?? const <ActionButtonEntity>[];
  final role = ref.watch(currentUserRoleProvider);
  return all.where((b) => b.isVisibleForRole(role)).toList(growable: false);
});

// ---------------------------------------------------------------------------
// Seed
// ---------------------------------------------------------------------------

/// Fires once at app start to make sure the tenant has a reasonable set of
/// default buttons. Idempotent.
final actionButtonsSeedProvider = FutureProvider<void>((ref) async {
  final repo = ref.watch(actionButtonRepositoryProvider);
  final tenantId = ref.watch(tenantIdProvider);
  await repo.seedDefaults(tenantId);
});

// ---------------------------------------------------------------------------
// CRUD notifier
// ---------------------------------------------------------------------------

class ActionButtonActionsNotifier extends StateNotifier<AsyncValue<void>> {
  final ActionButtonRepository _repo;
  final Ref _ref;
  final _uuid = const Uuid();

  ActionButtonActionsNotifier(this._repo, this._ref)
      : super(const AsyncData(null));

  String get _tenantId => _ref.read(tenantIdProvider);

  Future<bool> create({
    required String label,
    required ActionButtonPosition position,
    required ActionButtonType actionType,
    Map<String, dynamic> actionPayload = const <String, dynamic>{},
    int? colorValue,
    String? iconName,
    List<String>? roleFilter,
  }) async {
    state = const AsyncLoading();
    try {
      final existing = await _repo.getAll(_tenantId);
      final nextSort = existing.isEmpty
          ? 0
          : existing.map((e) => e.sortOrder).reduce((a, b) => a > b ? a : b) +
              1;
      final entity = ActionButtonEntity(
        id: 'act-${_uuid.v4()}',
        tenantId: _tenantId,
        label: label,
        position: position,
        actionType: actionType,
        actionPayload: actionPayload,
        colorValue: colorValue,
        iconName: iconName,
        sortOrder: nextSort,
        roleFilter: roleFilter,
      );
      await _repo.insert(entity);
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  Future<bool> update(ActionButtonEntity entity) async {
    state = const AsyncLoading();
    try {
      await _repo.update(entity);
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  Future<bool> delete(String id) async {
    state = const AsyncLoading();
    try {
      await _repo.softDelete(id);
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  Future<bool> reorder(List<String> orderedIds) async {
    state = const AsyncLoading();
    try {
      await _repo.reorder(orderedIds);
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  Future<bool> setActive(String id, bool value) async {
    state = const AsyncLoading();
    try {
      final current = await _repo.getById(id);
      if (current == null) {
        state = const AsyncData(null);
        return false;
      }
      await _repo.update(current.copyWith(isActive: value));
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }
}

final actionButtonActionsProvider = StateNotifierProvider<
    ActionButtonActionsNotifier, AsyncValue<void>>((ref) {
  return ActionButtonActionsNotifier(
    ref.watch(actionButtonRepositoryProvider),
    ref,
  );
});
