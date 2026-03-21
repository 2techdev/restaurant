/// Root application widget for GastroCore Waiter.
///
/// Uses the same theme and localisation as the POS app but wires in the
/// waiter-specific [waiterRouter] so navigation stays within the waiter
/// feature set.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/providers/locale_provider.dart';
import 'package:gastrocore_pos/core/theme/app_theme.dart';
import 'package:gastrocore_pos/features/sync/presentation/providers/sync_provider.dart';
import 'package:gastrocore_pos/features/waiter/router/waiter_router.dart';
import 'package:gastrocore_pos/l10n/app_localizations.dart';

/// The top-level widget for the Waiter flavour.
class GastroCoreWaiterApp extends ConsumerWidget {
  const GastroCoreWaiterApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);

    // Waiter needs real-time table and order updates from the POS.
    ref.watch(webSocketSyncClientProvider);
    ref.watch(connectivityAutoSyncProvider);

    return MaterialApp.router(
      title: 'GastroCore Waiter',
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
      routerConfig: waiterRouter,
    );
  }
}
