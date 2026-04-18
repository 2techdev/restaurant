/// Riverpod providers for brand-level JWT authentication.
///
/// Manages the brand/store login session that sits *above* the individual
/// staff PIN login. On app launch the app checks whether a valid stored
/// session exists; if so it skips the brand login screen.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/features/brand_auth/data/services/brand_auth_service.dart';
import 'package:gastrocore_pos/features/brand_auth/data/services/token_storage.dart';
import 'package:gastrocore_pos/features/brand_auth/domain/entities/auth_result.dart';
import 'package:gastrocore_pos/features/brand_auth/domain/entities/register_request.dart';
import 'package:gastrocore_pos/features/brand_auth/domain/entities/store_context.dart';

// ---------------------------------------------------------------------------
// Infrastructure providers
// ---------------------------------------------------------------------------

final tokenStorageProvider = Provider<TokenStorage>((ref) {
  return const TokenStorage();
});

final brandAuthServiceProvider = Provider<BrandAuthService>((ref) {
  final service = BrandAuthService();
  ref.onDispose(service.dispose);
  return service;
});

// ---------------------------------------------------------------------------
// Brand auth state
// ---------------------------------------------------------------------------

/// The overall state of the brand authentication session.
class BrandAuthState {
  const BrandAuthState({
    this.storeContext,
    this.isLoading = false,
    this.error,
    this.isInitialized = false,
  });

  /// Non-null when authenticated.
  final StoreContext? storeContext;
  final bool isLoading;
  final String? error;

  /// True after the initial token check on app startup has completed.
  final bool isInitialized;

  bool get isAuthenticated => storeContext != null;

  BrandAuthState copyWith({
    StoreContext? storeContext,
    bool? clearContext,
    bool? isLoading,
    String? error,
    bool? clearError,
    bool? isInitialized,
  }) {
    return BrandAuthState(
      storeContext: (clearContext ?? false) ? null : storeContext ?? this.storeContext,
      isLoading: isLoading ?? this.isLoading,
      error: (clearError ?? false) ? null : error ?? this.error,
      isInitialized: isInitialized ?? this.isInitialized,
    );
  }
}

/// Notifier that manages the brand auth lifecycle.
class BrandAuthNotifier extends StateNotifier<BrandAuthState> {
  BrandAuthNotifier({
    required TokenStorage storage,
    required BrandAuthService service,
  })  : _storage = storage,
        _service = service,
        super(const BrandAuthState());

  final TokenStorage _storage;
  final BrandAuthService _service;

  // ---------------------------------------------------------------------------
  // Startup: restore session
  // ---------------------------------------------------------------------------

  /// Called on app launch to restore a previously saved session.
  ///
  /// If a stored [StoreContext] and refresh token exist, the session is
  /// considered valid and we skip the brand login screen.
  /// Returns `true` when a valid session was restored.
  Future<bool> restoreSession() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final ctx = await _storage.readStoreContext();
      final refreshToken = await _storage.readRefreshToken();

      if (ctx != null && refreshToken != null && refreshToken.isNotEmpty) {
        // Local/demo mode: 'local' is a sentinel set by loginAsLocalDemo().
        // No server call needed — restore directly without any network access.
        if (refreshToken == 'local') {
          state = BrandAuthState(
            storeContext: ctx,
            isInitialized: true,
          );
          return true;
        }

        // Try to refresh the access token to verify validity.
        // On failure (e.g. token expired > 1 year) fall through to login.
        try {
          final newAccess = await _service.refreshToken(refreshToken);
          await _storage.updateAccessToken(newAccess);
        } catch (_) {
          // Refresh failed — check if offline mode is allowed.
          final rememberMe = await _storage.readRememberMe();
          if (!rememberMe) {
            // Not in offline/remember mode: require fresh login.
            await _storage.clearAll();
            state = const BrandAuthState(isInitialized: true);
            return false;
          }
          // Offline remember mode: allow access with cached context.
        }

        state = BrandAuthState(
          storeContext: ctx.copyWith(isOnlineMode: true),
          isInitialized: true,
        );
        return true;
      }
    } catch (_) {}

    state = const BrandAuthState(isInitialized: true);
    return false;
  }

  // ---------------------------------------------------------------------------
  // Login
  // ---------------------------------------------------------------------------

  Future<bool> login(
    String email,
    String password, {
    bool rememberMe = false,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final result = await _service.login(email, password);
      await _persist(result, rememberMe: rememberMe);
      state = BrandAuthState(
        storeContext: result.storeContext,
        isInitialized: true,
      );
      return true;
    } on AuthException catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.message,
        clearContext: true,
      );
      return false;
    } catch (e, st) {
      // ignore: avoid_print
      print('[BrandAuth] unexpected login error: $e\n$st');
      state = state.copyWith(
        isLoading: false,
        error: 'Beklenmeyen hata: $e',
        clearContext: true,
      );
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Register
  // ---------------------------------------------------------------------------

  Future<bool> register(RegisterRequest request) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final result = await _service.register(request);
      await _persist(result, rememberMe: true);
      state = BrandAuthState(
        storeContext: result.storeContext,
        isInitialized: true,
      );
      return true;
    } on AuthException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
      return false;
    } catch (e, st) {
      // ignore: avoid_print
      print('[BrandAuth] unexpected register error: $e\n$st');
      state = state.copyWith(
        isLoading: false,
        error: 'Kayıt hatası: $e',
      );
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Logout
  // ---------------------------------------------------------------------------

  Future<void> logout() async {
    await _storage.clearAll();
    state = const BrandAuthState(isInitialized: true);
  }

  // ---------------------------------------------------------------------------
  // Local / demo mode (no server required)
  // ---------------------------------------------------------------------------

  /// Activate a local-only session that bypasses brand auth entirely.
  ///
  /// This is the entry point for the free offline tier. No network call is
  /// made; a synthetic [StoreContext] with [isOnlineMode] = false is created.
  /// The session is persisted to secure storage so it survives app restarts —
  /// the 'local' refresh-token sentinel is detected by [restoreSession] and
  /// skips any server refresh, keeping the app fully offline.
  /// Cloud sync remains disabled until the user connects a real account.
  Future<void> loginAsLocalDemo() async {
    const ctx = StoreContext(
      brandId: 'local',
      storeId: 'local',
      storeName: 'Demo Restaurant',
      brandName: 'GastroCore Free',
      userRole: BrandUserRole.owner,
      isOnlineMode: false,
    );
    // Persist with sentinel tokens so restoreSession() can reload this session
    // on the next app launch without any network access.
    await _storage.saveTokens(
      accessToken: 'local',
      refreshToken: 'local',
      storeContext: ctx,
      rememberMe: true,
    );
    state = BrandAuthState(
      storeContext: ctx,
      isInitialized: true,
    );
  }

  // ---------------------------------------------------------------------------
  // Update last sync timestamp
  // ---------------------------------------------------------------------------

  Future<void> markSynced() async {
    final now = DateTime.now();
    await _storage.updateLastSync(now);
    if (state.storeContext != null) {
      state = state.copyWith(
        storeContext: state.storeContext!.copyWith(lastSyncAt: now),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Future<void> _persist(AuthResult result, {required bool rememberMe}) async {
    await _storage.saveTokens(
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
      storeContext: result.storeContext,
      rememberMe: rememberMe,
    );
  }
}

/// Global brand auth state provider.
final brandAuthProvider =
    StateNotifierProvider<BrandAuthNotifier, BrandAuthState>((ref) {
  return BrandAuthNotifier(
    storage: ref.watch(tokenStorageProvider),
    service: ref.watch(brandAuthServiceProvider),
  );
});

/// Convenience: current [StoreContext] (null when not authenticated).
final storeContextProvider = Provider<StoreContext?>((ref) {
  return ref.watch(brandAuthProvider).storeContext;
});

/// Convenience: whether brand auth has been initialized (startup check done).
final brandAuthInitializedProvider = Provider<bool>((ref) {
  return ref.watch(brandAuthProvider).isInitialized;
});
