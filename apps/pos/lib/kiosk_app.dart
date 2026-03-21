/// Root application widget for GastroCore Kiosk.
///
/// Uses a warm light theme optimised for customer-facing large-screen
/// kiosk hardware. Wires in [kioskRouter] for kiosk-only navigation
/// and wraps all screens in an inactivity-timeout listener that
/// returns to the welcome screen after 60 seconds of no interaction.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/features/kiosk/presentation/providers/kiosk_provider.dart';
import 'package:gastrocore_pos/features/kiosk/router/kiosk_router.dart';
import 'package:gastrocore_pos/features/kiosk/theme/kiosk_theme.dart';
import 'package:gastrocore_pos/features/sync/presentation/providers/sync_provider.dart';
import 'package:gastrocore_pos/l10n/app_localizations.dart';

/// Duration of inactivity before auto-returning to the welcome screen.
const _kInactivityTimeout = Duration(seconds: 60);

/// The top-level widget for the Kiosk flavour.
class GastroCoreKioskApp extends ConsumerStatefulWidget {
  const GastroCoreKioskApp({super.key});

  @override
  ConsumerState<GastroCoreKioskApp> createState() => _GastroCoreKioskAppState();
}

class _GastroCoreKioskAppState extends ConsumerState<GastroCoreKioskApp> {
  Timer? _inactivityTimer;

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    super.dispose();
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(_kInactivityTimeout, _onInactivityTimeout);
  }

  void _onInactivityTimeout() {
    if (kioskRouter.routerDelegate.currentConfiguration.matches.isNotEmpty) {
      kioskRouter.go(KioskRoutes.welcome);
    }
    ref.read(kioskSessionProvider.notifier).reset();
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(kioskLocaleProvider);

    // Pull menu / availability updates from the cloud in real time so the
    // kiosk always shows current prices and stock status.
    ref.watch(webSocketSyncClientProvider);
    ref.watch(connectivityAutoSyncProvider);

    return Listener(
      onPointerDown: (_) => _resetInactivityTimer(),
      child: MaterialApp.router(
        title: 'GastroCore Kiosk',
        debugShowCheckedModeBanner: false,
        theme: buildKioskTheme(),

        // ── Localization ────────────────────────────────────────────────────
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],

        // ── Routing ─────────────────────────────────────────────────────────
        routerConfig: kioskRouter,
      ),
    );
  }
}
