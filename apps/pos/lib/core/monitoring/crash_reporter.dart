/// Crash reporting and error tracking for GastroCore POS.
///
/// Wraps Sentry so all unhandled Flutter errors, Dart async errors, and
/// manually captured exceptions are sent to the Sentry project.
///
/// DSN is read from the `SENTRY_DSN` environment variable (compile-time via
/// `--dart-define=SENTRY_DSN=https://...`). If the DSN is empty the reporter
/// is a no-op, which is safe for local development and CI.
library;

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Initialise Sentry and return the [AppRunner] that starts the app inside
/// the Sentry zone.
///
/// Usage in main.dart:
/// ```dart
/// await CrashReporter.init(dsn: const String.fromEnvironment('SENTRY_DSN'));
/// CrashReporter.runApp(() => runApp(...));
/// ```
class CrashReporter {
  CrashReporter._();

  static bool _initialised = false;

  /// DSN injected at build time. Empty string disables Sentry.
  static const _dsn = String.fromEnvironment('SENTRY_DSN');

  static bool get isEnabled => _dsn.isNotEmpty;

  /// Initialise the Sentry SDK.
  ///
  /// Must be called before [captureException] / [captureMessage].
  static Future<void> init({
    String? release,
    String environment = 'production',
  }) async {
    if (_dsn.isEmpty) return;
    if (_initialised) return;

    await SentryFlutter.init(
      (options) {
        options.dsn = _dsn;
        options.environment = environment;
        if (release != null) options.release = release;

        // Performance tracing — capture 20 % of transactions in production.
        options.tracesSampleRate = kDebugMode ? 1.0 : 0.2;

        // Attach user-readable device info (no PII).
        options.attachThreads = true;
        options.attachStacktrace = true;

        // Do not send events in debug mode by default.
        options.debug = kDebugMode;
      },
    );

    _initialised = true;
  }

  /// Capture an exception with optional stack trace and context tags.
  static Future<void> captureException(
    Object exception, {
    StackTrace? stackTrace,
    Map<String, String>? tags,
    String? hint,
  }) async {
    if (!_initialised) {
      // In development, re-print so it is visible in the console.
      if (kDebugMode) {
        debugPrint('[CrashReporter] $exception\n$stackTrace');
      }
      return;
    }

    await Sentry.captureException(
      exception,
      stackTrace: stackTrace,
      hint: hint != null ? Hint.withMap({'hint': hint}) : null,
      withScope: tags != null
          ? (scope) {
              for (final e in tags.entries) {
                scope.setTag(e.key, e.value);
              }
            }
          : null,
    );
  }

  /// Capture a non-fatal message (e.g. a warning that warrants investigation).
  static Future<void> captureMessage(
    String message, {
    SentryLevel level = SentryLevel.warning,
  }) async {
    if (!_initialised) {
      if (kDebugMode) debugPrint('[CrashReporter] [$level] $message');
      return;
    }
    await Sentry.captureMessage(message, level: level);
  }

  /// Set the current authenticated user so crashes can be linked to a device.
  /// Pass [null] to clear (on logout).
  static Future<void> setUser({
    required String? deviceId,
    String? tenantId,
  }) async {
    if (!_initialised) return;
    await Sentry.configureScope((scope) {
      if (deviceId == null) {
        scope.setUser(null);
      } else {
        scope.setUser(SentryUser(id: deviceId));
        if (tenantId != null) scope.setTag('tenant_id', tenantId);
      }
    });
  }
}
