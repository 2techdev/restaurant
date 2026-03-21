/// GoRouter configuration for the GastroCore Order Display Screen (ODS).
///
/// Navigation flow:
///   /ods  (main display — full-screen, no interaction)
///     ↓ long-press settings icon
///   /ods/settings
///     ↓ tap "Done"
///   /ods
library;

import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/features/ods/presentation/screens/ods_main_screen.dart';
import 'package:gastrocore_pos/features/ods/presentation/screens/ods_settings_screen.dart';

// ---------------------------------------------------------------------------
// Route constants
// ---------------------------------------------------------------------------

abstract final class OdsRoutes {
  static const String main = '/ods';
  static const String settings = '/ods/settings';
}

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------

final GoRouter odsRouter = GoRouter(
  initialLocation: OdsRoutes.main,
  routes: [
    GoRoute(
      path: OdsRoutes.main,
      builder: (context, state) => const OdsMainScreen(),
    ),
    GoRoute(
      path: OdsRoutes.settings,
      builder: (context, state) => const OdsSettingsScreen(),
    ),
  ],
);
