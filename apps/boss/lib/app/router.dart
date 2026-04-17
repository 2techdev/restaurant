/// go_router configuration for the Boss app with owner-role guard.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_controller.dart';
import '../features/auth/auth_state.dart';
import '../features/auth/login_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/home/home_shell.dart';
import '../features/reports/zreport_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/staff/staff_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/login',
    refreshListenable: _RouterListenable(ref),
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final loggedIn = auth is AuthAuthenticated && !auth.session.isExpired;
      final loggingIn = state.matchedLocation == '/login';

      if (!loggedIn && !loggingIn) return '/login';
      if (loggedIn && loggingIn) return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) {
          return HomeShell(
            currentIndex: _indexFor(state.matchedLocation),
            onTap: (i) => context.go(_routeFor(i)),
            child: child,
          );
        },
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (_, __) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/zreport',
            builder: (_, __) => const ZReportScreen(),
          ),
          GoRoute(
            path: '/staff',
            builder: (_, __) => const StaffScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, __) => const SettingsScreen(),
          ),
        ],
      ),
    ],
  );
});

int _indexFor(String location) {
  if (location.startsWith('/zreport')) return 1;
  if (location.startsWith('/staff')) return 2;
  if (location.startsWith('/settings')) return 3;
  return 0;
}

String _routeFor(int index) {
  switch (index) {
    case 1:
      return '/zreport';
    case 2:
      return '/staff';
    case 3:
      return '/settings';
    case 0:
    default:
      return '/dashboard';
  }
}

class _RouterListenable extends ChangeNotifier {
  _RouterListenable(Ref ref) {
    ref.listen<AuthState>(
      authControllerProvider,
      (_, __) => notifyListeners(),
    );
  }
}
