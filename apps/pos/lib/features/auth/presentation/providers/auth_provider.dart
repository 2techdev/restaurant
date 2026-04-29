/// Riverpod providers for the authentication feature.
///
/// Exposes the [AuthRepositoryImpl], the currently logged-in user, and a
/// users list for the PIN-entry login screen. The [CurrentUserNotifier]
/// manages login / logout state transitions.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:gastrocore_pos/features/auth/domain/entities/permission.dart';
import 'package:gastrocore_pos/features/auth/domain/entities/user_entity.dart';

/// Outcome of a PIN-only login attempt. [success] resolves to a user;
/// [invalidPin] means the PIN did not match any active user; [pinCollision]
/// means multiple users share the same PIN — admin must reassign.
enum LoginResult { success, invalidPin, pinCollision }

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

/// Provides a singleton [AuthRepositoryImpl] backed by the app database.
final authRepositoryProvider = Provider<AuthRepositoryImpl>((ref) {
  final db = ref.watch(databaseProvider);
  return AuthRepositoryImpl(db);
});

// ---------------------------------------------------------------------------
// Current user (login state)
// ---------------------------------------------------------------------------

/// Manages the currently authenticated user.
///
/// `null` means no user is logged in (show login screen).
final currentUserProvider =
    StateNotifierProvider<CurrentUserNotifier, UserEntity?>((ref) {
  return CurrentUserNotifier(ref);
});

class CurrentUserNotifier extends StateNotifier<UserEntity?> {
  final Ref _ref;

  CurrentUserNotifier(this._ref) : super(null);

  /// Attempt to log in with a [pinHash]. Returns a [LoginResult] so the UI
  /// can distinguish an invalid PIN from a PIN collision (two users sharing
  /// the same PIN — admin must resolve).
  Future<LoginResult> loginWithPin(String pinHash) async {
    final repo = _ref.read(authRepositoryProvider);
    final tenantId = _ref.read(tenantIdProvider);
    try {
      final user = await repo.getUserByPin(tenantId, pinHash);
      if (user == null) return LoginResult.invalidPin;
      state = user;
      return LoginResult.success;
    } on PinCollisionException {
      return LoginResult.pinCollision;
    }
  }

  /// Set the current user directly (e.g. from a saved session).
  void setUser(UserEntity user) {
    state = user;
  }

  /// Log out the current user.
  void logout() {
    state = null;
  }
}

// ---------------------------------------------------------------------------
// Role + permission gates
// ---------------------------------------------------------------------------

/// Effective role of the currently authenticated user.
///
/// Defaults to [UserRole.cashier] (kasiyer) when no user is logged in — this
/// matches the pilot expectation that ungated surfaces behave like a cashier
/// terminal rather than an admin one.  Derived from [currentUserProvider].
final currentUserRoleProvider = Provider<UserRole>((ref) {
  final user = ref.watch(currentUserProvider);
  return user?.role ?? UserRole.cashier;
});

/// Returns `true` when the current user's role is permitted to perform [p].
///
/// Usage in widgets:
/// ```dart
/// final allowed = ref.watch(canProvider(Permission.storno));
/// ```
final canProvider = Provider.family<bool, Permission>((ref, p) {
  final role = ref.watch(currentUserRoleProvider);
  return roleCan(role, p);
});

// ---------------------------------------------------------------------------
// Users list (for login screen)
// ---------------------------------------------------------------------------

/// All active users for the current tenant. Used to display the PIN-entry
/// login grid where each user appears as a selectable tile.
final usersListProvider = FutureProvider<List<UserEntity>>((ref) async {
  final repo = ref.watch(authRepositoryProvider);
  final tenantId = ref.watch(tenantIdProvider);
  return repo.getAllUsers(tenantId);
});
