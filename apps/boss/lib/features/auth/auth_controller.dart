/// Riverpod controller for the Boss auth flow.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gastrocore_api/gastrocore_api.dart';

import '../../app/providers.dart';
import 'auth_repository.dart';
import 'auth_state.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(gastrocoreClientProvider));
});

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(
    repository: ref.watch(authRepositoryProvider),
    tenantId: ref.watch(tenantIdProvider),
  );
});

class AuthController extends StateNotifier<AuthState> {
  final AuthRepository _repository;
  final String _tenantId;

  AuthController({
    required AuthRepository repository,
    required String tenantId,
  })  : _repository = repository,
        _tenantId = tenantId,
        super(const AuthInitial());

  Future<void> loginWithPin(String pin) async {
    state = const AuthLoading();
    try {
      final session = await _repository.loginWithPin(
        tenantId: _tenantId,
        pin: pin,
      );
      state = AuthAuthenticated(session);
    } on ApiException catch (e) {
      state = AuthFailure(e.message);
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('owner') || msg.contains('manager')) {
        state = AuthUnauthorized(msg.replaceFirst('Exception: ', ''));
      } else {
        state = AuthFailure(msg.replaceFirst('Exception: ', ''));
      }
    }
  }

  Future<void> loginWithEmail({
    required String email,
    required String password,
  }) async {
    state = const AuthLoading();
    try {
      final session = await _repository.loginWithEmail(
        email: email,
        password: password,
      );
      state = AuthAuthenticated(session);
    } on UnimplementedError catch (e) {
      state = AuthFailure(e.message ?? 'E-posta girişi henüz aktif değil.');
    } catch (e) {
      state = AuthFailure(e.toString());
    }
  }

  Future<void> logout() async {
    try {
      await _repository.logout();
    } catch (_) {
      // Best-effort logout — ignore network failures.
    }
    state = const AuthInitial();
  }
}
