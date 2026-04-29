import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';

// ---------------------------------------------------------------------------
// Auth state
// ---------------------------------------------------------------------------

class AuthUser {
  final String id;
  final String name;
  final String email;
  final String role;
  final String token;

  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.token,
  });
}

class AuthState {
  final AuthUser? user;
  final bool isLoading;
  final String? error;

  const AuthState({this.user, this.isLoading = false, this.error});

  bool get isAuthenticated => user != null;

  AuthState copyWith({AuthUser? user, bool? isLoading, String? error, bool clearUser = false}) =>
      AuthState(
        user: clearUser ? null : user ?? this.user,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

// ---------------------------------------------------------------------------
// Auth notifier
// ---------------------------------------------------------------------------

class AuthNotifier extends StateNotifier<AuthState> {
  static const _keyToken = 'dash_token';
  static const _keyUserId = 'dash_user_id';
  static const _keyUserName = 'dash_user_name';
  static const _keyUserEmail = 'dash_user_email';
  static const _keyUserRole = 'dash_user_role';

  AuthNotifier() : super(const AuthState(isLoading: true)) {
    _restore();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_keyToken);
      if (token != null && token.isNotEmpty) {
        state = AuthState(
          user: AuthUser(
            id: prefs.getString(_keyUserId) ?? '',
            name: prefs.getString(_keyUserName) ?? '',
            email: prefs.getString(_keyUserEmail) ?? '',
            role: prefs.getString(_keyUserRole) ?? 'admin',
            token: token,
          ),
        );
        return;
      }
    } catch (_) {}
    state = const AuthState();
  }

  Future<void> login({
    required String email,
    required String password,
    required bool rememberMe,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final client = createApiClient();
      final result = await client.login(email: email, password: password);

      final user = AuthUser(
        id: result.userId,
        name: result.name,
        email: result.email,
        role: result.role,
        token: result.accessToken,
      );

      if (rememberMe) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyToken, result.accessToken);
        await prefs.setString(_keyUserId, result.userId);
        await prefs.setString(_keyUserName, result.name);
        await prefs.setString(_keyUserEmail, result.email);
        await prefs.setString(_keyUserRole, result.role);
      }

      state = AuthState(user: user);
    } on ApiException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
    } catch (_) {
      state = state.copyWith(isLoading: false, error: 'Login fehlgeschlagen');
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyToken);
    await prefs.remove(_keyUserId);
    await prefs.remove(_keyUserName);
    await prefs.remove(_keyUserEmail);
    await prefs.remove(_keyUserRole);
    state = const AuthState();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});

// ---------------------------------------------------------------------------
// API client provider (automatically picks up token)
// ---------------------------------------------------------------------------

final apiClientProvider = Provider<ApiClient>((ref) {
  final token = ref.watch(authProvider).user?.token;
  return createApiClient(token: token);
});

// ---------------------------------------------------------------------------
// Derived providers for convenience
// ---------------------------------------------------------------------------

final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).isAuthenticated;
});

final currentUserProvider = Provider<AuthUser?>((ref) {
  return ref.watch(authProvider).user;
});

