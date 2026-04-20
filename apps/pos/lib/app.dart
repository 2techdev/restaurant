/// Root application widget for GastroCore POS.
///
/// Uses [MaterialApp.router] with [GoRouter] for declarative navigation,
/// applies the light Kinetic theme app-wide, and wires up Flutter's
/// localization system for DE / FR / IT / EN (Swiss quadrilingual).
///
/// Pilot v3 promoted [buildKineticTheme] from a sales-shell-local override
/// to the app-level theme. `buildAppTheme` (Stitch dark) is retired but the
/// file is kept for reference + the still-used [PosColors] extension.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/providers/locale_provider.dart';
import 'package:gastrocore_pos/core/router/app_router.dart';
import 'package:gastrocore_pos/core/theme/kinetic_theme.dart';
import 'package:gastrocore_pos/features/brand_auth/presentation/providers/brand_auth_provider.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/app_settings.dart';
import 'package:gastrocore_pos/features/settings/presentation/providers/settings_provider.dart';
import 'package:gastrocore_pos/features/sync/presentation/providers/sync_provider.dart';
import 'package:gastrocore_pos/l10n/app_localizations.dart';

/// The top-level widget that configures Material theming, routing and l10n.
///
/// Uses [ConsumerStatefulWidget] so that the [GoRouter] is created once per
/// widget-tree lifetime via [createAppRouter]. This ensures that each test
/// that mounts a fresh [GastroCoreApp] gets its own independent router
/// without sharing navigation history from a previous run.
class GastroCoreApp extends ConsumerStatefulWidget {
  const GastroCoreApp({super.key});

  @override
  ConsumerState<GastroCoreApp> createState() => _GastroCoreAppState();
}

class _GastroCoreAppState extends ConsumerState<GastroCoreApp> {
  late final GoRouter _router;
  late final _AuthChangeNotifier _authNotifier;

  @override
  void initState() {
    super.initState();

    // Bridge Riverpod auth state → GoRouter Listenable for redirect refresh.
    _authNotifier = _AuthChangeNotifier(ref);

    _router = createAppRouter(
      authReader: () => (
        isInitialized: ref.read(brandAuthProvider).isInitialized,
        isAuthenticated: ref.read(brandAuthProvider).isAuthenticated,
      ),
      authListenable: _authNotifier,
    );
  }

  @override
  void dispose() {
    _authNotifier.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);

    // Activate WebSocket real-time sync and connectivity-based auto-sync.
    ref.watch(webSocketSyncClientProvider);
    ref.watch(connectivityAutoSyncProvider);

    // Resolve the user's theme preference. While SharedPreferences is
    // still loading, [AppSettings] falls back to [AppThemeMode.dark] —
    // which matches the default on a fresh install.
    final appSettings = ref.watch(appSettingsProvider).valueOrNull ??
        const AppSettings();
    final themeMode = switch (appSettings.themeMode) {
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.dark => ThemeMode.dark,
      AppThemeMode.system => ThemeMode.system,
    };

    return MaterialApp.router(
      title: 'GastroCore POS',
      debugShowCheckedModeBanner: false,
      theme: buildKineticTheme(),
      darkTheme: buildKineticThemeDark(),
      themeMode: themeMode,

      // ── Localization ──────────────────────────────────────────────────────
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      // ── Routing ───────────────────────────────────────────────────────────
      routerConfig: _router,
    );
  }
}

// ---------------------------------------------------------------------------
// Auth change notifier — bridges Riverpod → GoRouter Listenable
// ---------------------------------------------------------------------------

/// Listens to [brandAuthProvider] and calls [notifyListeners] whenever the
/// auth state changes so [GoRouter] re-evaluates its redirect.
class _AuthChangeNotifier extends ChangeNotifier {
  _AuthChangeNotifier(WidgetRef ref) {
    _removeListener = ref.listenManual(
      brandAuthProvider,
      (_, __) => notifyListeners(),
    );
  }

  late final ProviderSubscription<dynamic> _removeListener;

  @override
  void dispose() {
    _removeListener.close();
    super.dispose();
  }
}
