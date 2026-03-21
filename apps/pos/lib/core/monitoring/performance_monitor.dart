/// Lightweight performance monitoring for GastroCore POS.
///
/// Wraps Sentry transactions so expensive operations (DB queries, sync push/pull,
/// payment processing) can be traced end-to-end. All calls are no-ops when
/// Sentry is disabled, so there is zero overhead in development.
library;

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'crash_reporter.dart';

/// Named operations for consistent transaction naming.
class PerfOp {
  static const dbQuery = 'db.query';
  static const dbWrite = 'db.write';
  static const syncPush = 'sync.push';
  static const syncPull = 'sync.pull';
  static const paymentProcess = 'payment.process';
  static const printReceipt = 'print.receipt';
  static const appStartup = 'app.startup';
  static const menuLoad = 'menu.load';
  static const reportGenerate = 'report.generate';
}

/// Traces a synchronous or async code block and reports it to Sentry.
///
/// Example:
/// ```dart
/// final result = await PerformanceMonitor.trace(
///   operation: PerfOp.syncPush,
///   description: 'push 42 events',
///   action: () => syncClient.push(events),
/// );
/// ```
class PerformanceMonitor {
  PerformanceMonitor._();

  /// Trace an async operation.
  ///
  /// If the operation throws, the span is marked as failed and the exception
  /// is re-thrown.
  static Future<T> trace<T>({
    required String operation,
    required Future<T> Function() action,
    String? description,
    Map<String, dynamic>? data,
  }) async {
    if (!CrashReporter.isEnabled) return action();

    final transaction = Sentry.startTransaction(
      operation,
      operation,
      description: description,
    );

    if (data != null) {
      for (final e in data.entries) {
        transaction.setData(e.key, e.value);
      }
    }

    try {
      final result = await action();
      transaction.status = const SpanStatus.ok();
      return result;
    } catch (e, s) {
      transaction.status = const SpanStatus.internalError();
      transaction.throwable = e;
      if (kDebugMode) debugPrint('[Perf] $operation failed: $e\n$s');
      rethrow;
    } finally {
      await transaction.finish();
    }
  }

  /// Trace a synchronous operation.
  static T traceSync<T>({
    required String operation,
    required T Function() action,
    String? description,
  }) {
    if (!CrashReporter.isEnabled) return action();

    final transaction = Sentry.startTransaction(
      operation,
      operation,
      description: description,
    );

    try {
      final result = action();
      transaction.status = const SpanStatus.ok();
      return result;
    } catch (e) {
      transaction.status = const SpanStatus.internalError();
      transaction.throwable = e;
      rethrow;
    } finally {
      transaction.finish();
    }
  }

  /// Measure and log the duration of an operation to the debug console.
  ///
  /// Always active, even without Sentry. Useful for local profiling.
  static Future<T> measure<T>({
    required String label,
    required Future<T> Function() action,
    int warnThresholdMs = 500,
  }) async {
    final sw = Stopwatch()..start();
    try {
      return await action();
    } finally {
      sw.stop();
      final ms = sw.elapsedMilliseconds;
      if (kDebugMode || ms >= warnThresholdMs) {
        final prefix = ms >= warnThresholdMs ? '⚠️ SLOW' : '⏱';
        debugPrint('[$prefix] $label: ${ms}ms');
      }
    }
  }
}
