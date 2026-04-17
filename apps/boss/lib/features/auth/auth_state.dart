/// Boss session state — authenticated owner + token + expiry.
library;

import 'package:gastrocore_models/gastrocore_models.dart';

/// Roles that grant access to the Boss app.
///
/// Backend currently exposes [UserRole.admin] and [UserRole.manager] only;
/// once the dedicated `owner` role lands (Sprint 2), update this set.
const ownerRoles = <UserRole>{UserRole.admin, UserRole.manager};

bool isOwnerRole(UserRole role) => ownerRoles.contains(role);

class BossSession {
  final UserEntity user;
  final String token;
  final DateTime expiresAt;

  const BossSession({
    required this.user,
    required this.token,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get hasOwnerAccess => isOwnerRole(user.role);
}

sealed class AuthState {
  const AuthState();
}

class AuthInitial extends AuthState {
  const AuthInitial();
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

class AuthAuthenticated extends AuthState {
  final BossSession session;
  const AuthAuthenticated(this.session);
}

class AuthUnauthorized extends AuthState {
  final String message;
  const AuthUnauthorized(this.message);
}

class AuthFailure extends AuthState {
  final String message;
  const AuthFailure(this.message);
}
