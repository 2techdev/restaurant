/// Root application widget for GastroCore KDS.
///
/// Uses the same dark theme as the POS app — kitchen displays are always
/// in a low-light environment. Wires in [kdsRouter] for KDS-only navigation
/// and enables full-screen immersive mode on startup.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/providers/locale_provider.dart';
import 'package:gastrocore_pos/core/theme/app_theme.dart';
import 'package:gastrocore_pos/features/kds_app/router/kds_router.dart';
import 'package:gastrocore_pos/features/sync/presentation/providers/sync_provider.dart';
import 'package:gastrocore_pos/l10n/app_localizations.dart';

/// The top-level widget for the KDS flavour.
class GastroCoreKdsApp extends ConsumerWidget {
  const GastroCoreKdsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);

    // KDS must react in real time to new kitchen tickets pushed by the POS.
    ref.watch(webSocketSyncClientProvider);
    ref.watch(connectivityAutoSyncProvider);

    return MaterialApp.router(
      title: 'GastroCore KDS',
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
      routerConfig: kdsRouter,
    );
  }
}
