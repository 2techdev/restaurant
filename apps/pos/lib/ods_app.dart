/// Root application widget for GastroCore Order Display Screen (ODS).
///
/// Dark theme optimised for TV/monitor display.
/// Wires in [odsRouter] and activates the WebSocket sync client so the
/// display updates in real time whenever the POS, Waiter, or Kiosk apps
/// change an order's status.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/providers/locale_provider.dart';
import 'package:gastrocore_pos/features/ods/router/ods_router.dart';
import 'package:gastrocore_pos/features/ods/theme/ods_theme.dart';
import 'package:gastrocore_pos/features/sync/presentation/providers/sync_provider.dart';
import 'package:gastrocore_pos/l10n/app_localizations.dart';

/// The top-level widget for the ODS flavour.
class GastroCoreOdsApp extends ConsumerWidget {
  const GastroCoreOdsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);

    // Activate WebSocket client for real-time order status updates.
    ref.watch(webSocketSyncClientProvider);

    // Activate connectivity-based auto-sync.
    ref.watch(connectivityAutoSyncProvider);

    return MaterialApp.router(
      title: 'GastroCore Order Display',
      debugShowCheckedModeBanner: false,
      theme: buildOdsTheme(),

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
      routerConfig: odsRouter,
    );
  }
}
