/// Crash reporting stub for GastroCore POS.
///
/// Sentry integration is optional. When `SENTRY_DSN` is not set (local dev,
/// CI), this is a no-op. Wire up a real crash reporter (e.g. sentry_flutter)
/// by adding the dependency to pubspec.yaml and replacing the stub below.
library;

import 'package:flutter/foundation.dart';

class CrashReporter {
  CrashReporter._();

  static bool _initialised = false;

  static const _dsn = String.fromEnvironment('SENTRY_DSN');

  static bool get isEnabled => _dsn.isNotEmpty;

  static Future<void> init() async {
    if (!isEnabled || _initialised) return;
    _initialised = true;
    // TODO: initialise Sentry / other crash reporter here.
    debugPrint('[CrashReporter] initialised (stub — no-op)');
  }

  static void captureException(Object exception, {StackTrace? stackTrace}) {
    if (!isEnabled) return;
    debugPrint('[CrashReporter] exception: $exception\n$stackTrace');
  }

  static void captureMessage(String message) {
    if (!isEnabled) return;
    debugPrint('[CrashReporter] message: $message');
  }

  static void setUser({required String id, String? email, String? name}) {
    debugPrint('[CrashReporter] setUser: $id');
  }

  static void clearUser() {
    debugPrint('[CrashReporter] clearUser');
  }

  static void addBreadcrumb(String message, {Map<String, dynamic>? data}) {
    debugPrint('[CrashReporter] breadcrumb: $message');
  }
}
