/// Crash reporting wrapper for GastroCore POS, backed by Sentry.
///
/// DSN is injected at build time via `--dart-define=SENTRY_DSN=...`.
/// When the DSN is empty (local dev, CI), Sentry is never initialised
/// and all capture/breadcrumb calls are no-ops. The rest of the app
/// is decoupled from the Sentry SDK via this class.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

class CrashReporter {
  CrashReporter._();

  static bool _initialised = false;

  static const _dsn = String.fromEnvironment('SENTRY_DSN');
  static const _environment = String.fromEnvironment(
    'SENTRY_ENVIRONMENT',
    defaultValue: kReleaseMode ? 'production' : 'development',
  );
  static const _release = String.fromEnvironment(
    'SENTRY_RELEASE',
    defaultValue: 'gastrocore-pos@unknown',
  );

  static bool get isEnabled => _dsn.isNotEmpty;

  /// Runs [appRunner] inside Sentry's zone when enabled, otherwise
  /// just executes it directly. Should be called from `main()` in
  /// place of `runApp`.
  static Future<void> runGuarded(FutureOr<void> Function() appRunner) async {
    if (!isEnabled) {
      debugPrint('[CrashReporter] SENTRY_DSN not set — running without crash reporting');
      await appRunner();
      return;
    }

    await SentryFlutter.init(
      (options) {
        options.dsn = _dsn;
        options.environment = _environment;
        options.release = _release;
        options.tracesSampleRate = kReleaseMode ? 0.1 : 1.0;
        options.attachStacktrace = true;
        options.sendDefaultPii = false;
        options.debug = !kReleaseMode;
      },
      appRunner: appRunner,
    );
    _initialised = true;
  }

  /// Legacy initialiser retained for callers that still use the old API.
  /// Prefer [runGuarded]. This is a no-op when [runGuarded] has already
  /// set up Sentry.
  static Future<void> init() async {
    if (!isEnabled || _initialised) return;
    _initialised = true;
    await SentryFlutter.init((options) {
      options.dsn = _dsn;
      options.environment = _environment;
      options.release = _release;
    });
  }

  static void captureException(Object exception, {StackTrace? stackTrace}) {
    if (!isEnabled) {
      debugPrint('[CrashReporter] exception (not sent): $exception\n$stackTrace');
      return;
    }
    Sentry.captureException(exception, stackTrace: stackTrace);
  }

  static void captureMessage(String message) {
    if (!isEnabled) return;
    Sentry.captureMessage(message);
  }

  static void setUser({required String id, String? email, String? name}) {
    if (!isEnabled) return;
    Sentry.configureScope((scope) {
      scope.setUser(SentryUser(id: id, email: email, username: name));
    });
  }

  static void clearUser() {
    if (!isEnabled) return;
    Sentry.configureScope((scope) => scope.setUser(null));
  }

  static void addBreadcrumb(String message, {Map<String, dynamic>? data}) {
    if (!isEnabled) return;
    Sentry.addBreadcrumb(Breadcrumb(message: message, data: data));
  }
}
