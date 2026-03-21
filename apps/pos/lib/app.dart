/// Root application widget for GastroCore POS.
///
/// Uses [MaterialApp.router] with [GoRouter] for declarative navigation,
/// applies the dark POS theme from [buildAppTheme], and wires up
/// Flutter's localization system for DE / FR / IT / EN (Swiss quadrilingual).
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/providers/locale_provider.dart';
import 'package:gastrocore_pos/core/router/app_router.dart';
import 'package:gastrocore_pos/core/theme/app_theme.dart';
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

  @override
  void initState() {
    super.initState();
    _router = createAppRouter();
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);

    // Activate WebSocket real-time sync and connectivity-based auto-sync.
    ref.watch(webSocketSyncClientProvider);
    ref.watch(connectivityAutoSyncProvider);

    return MaterialApp.router(
      title: 'GastroCore POS',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),

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
