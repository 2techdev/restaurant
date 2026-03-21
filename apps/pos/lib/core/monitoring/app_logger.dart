/// Structured application logger for GastroCore POS.
///
/// A thin wrapper over Dart's `dart:developer` log that:
///  - Adds named log levels (debug, info, warning, error)
///  - Forwards errors to [CrashReporter] automatically
///  - Is a no-op for debug/info in release builds (no log spam in production)
///
/// Usage:
/// ```dart
/// AppLogger.info('sync', 'Push completed', data: {'events': 42});
/// AppLogger.error('payment', 'Terminal timeout', error: e, stack: s);
/// ```
library;

import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';

import 'crash_reporter.dart';

/// Log levels matching syslog severity.
enum LogLevel { debug, info, warning, error }

class AppLogger {
  AppLogger._();

  /// Log a debug message. Only emitted in debug mode.
  static void debug(String tag, String message, {Map<String, dynamic>? data}) {
    if (!kDebugMode) return;
    _log(LogLevel.debug, tag, message, data: data);
  }

  /// Log an informational message.
  static void info(String tag, String message, {Map<String, dynamic>? data}) {
    _log(LogLevel.info, tag, message, data: data);
  }

  /// Log a non-fatal warning. Always emitted; forwarded to Sentry.
  static void warning(
    String tag,
    String message, {
    Map<String, dynamic>? data,
    Object? error,
  }) {
    _log(LogLevel.warning, tag, message, data: data, error: error);
    if (error != null) {
      CrashReporter.captureMessage(
        '[$tag] $message${data != null ? ' $data' : ''}',
      );
    }
  }

  /// Log an error with optional exception. Always emitted; forwarded to Sentry.
  static void error(
    String tag,
    String message, {
    Object? error,
    StackTrace? stack,
    Map<String, dynamic>? data,
  }) {
    _log(LogLevel.error, tag, message, data: data, error: error);
    if (error != null) {
      CrashReporter.captureException(
        error,
        stackTrace: stack,
        hint: '[$tag] $message',
        tags: data?.map((k, v) => MapEntry(k, v.toString())),
      );
    }
  }

  static void _log(
    LogLevel level,
    String tag,
    String message, {
    Map<String, dynamic>? data,
    Object? error,
  }) {
    // In release mode skip debug/info to avoid logcat/console noise.
    if (!kDebugMode && level == LogLevel.debug) return;

    final dataStr = data != null ? ' $data' : '';
    final errorStr = error != null ? ' | error: $error' : '';
    final fullMsg = '[$tag] $message$dataStr$errorStr';

    dev.log(
      fullMsg,
      name: 'GastroCore',
      level: _dartLevel(level),
      error: error,
    );
  }

  static int _dartLevel(LogLevel l) => switch (l) {
        LogLevel.debug => 500,
        LogLevel.info => 800,
        LogLevel.warning => 900,
        LogLevel.error => 1000,
      };
}
