/// GoRouter configuration for the GastroCore KDS app.
///
/// Navigation flow:
///   /kds/login  →  /kds/main  (full-screen ticket grid)
///                      ↓ filter icon
///              /kds/station-filter
///                      ↓ settings icon
///              /kds/settings
library;

import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/features/kds_app/presentation/screens/kds_login_screen.dart';
import 'package:gastrocore_pos/features/kds_app/presentation/screens/kds_main_screen.dart';
import 'package:gastrocore_pos/features/kds_app/presentation/screens/kds_station_filter_screen.dart';
import 'package:gastrocore_pos/features/kds_app/presentation/screens/kds_settings_screen.dart';
import 'package:gastrocore_pos/features/stations/presentation/screens/station_settings_screen.dart';

// ---------------------------------------------------------------------------
// Route constants
// ---------------------------------------------------------------------------

abstract final class KdsRoutes {
  static const String login = '/kds/login';
  static const String main = '/kds/main';
  static const String stationFilter = '/kds/station-filter';
  static const String stationManage = '/kds/station-manage';
  static const String settings = '/kds/settings';
}

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------

final GoRouter kdsRouter = GoRouter(
  initialLocation: KdsRoutes.login,
  routes: [
    GoRoute(
      path: '/',
      redirect: (_, __) => KdsRoutes.login,
    ),
    GoRoute(
      path: KdsRoutes.login,
      builder: (context, state) => const KdsLoginScreen(),
    ),
    GoRoute(
      path: KdsRoutes.main,
      builder: (context, state) => const KdsMainScreen(),
    ),
    GoRoute(
      path: KdsRoutes.stationFilter,
      builder: (context, state) => const KdsStationFilterScreen(),
    ),
    GoRoute(
      path: KdsRoutes.stationManage,
      builder: (context, state) => const StationSettingsScreen(),
    ),
    GoRoute(
      path: KdsRoutes.settings,
      builder: (context, state) => const KdsSettingsScreen(),
    ),
  ],
);
