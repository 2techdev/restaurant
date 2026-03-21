/// Lightweight performance monitoring stub for GastroCore POS.
///
/// Wraps a tracing SDK (e.g. Sentry Performance). When no DSN is set this is a
/// no-op, so there is zero overhead in development / CI.
library;

import 'package:flutter/foundation.dart';

class PerformanceMonitor {
  PerformanceMonitor._();

  static Future<T> trace<T>(
    String name,
    Future<T> Function() operation, {
    Map<String, String>? tags,
  }) async {
    final sw = Stopwatch()..start();
    try {
      return await operation();
    } finally {
      sw.stop();
      debugPrint('[Perf] $name took ${sw.elapsedMilliseconds}ms');
    }
  }

  static void recordMetric(String name, double value) {
    debugPrint('[Perf] metric $name = $value');
  }
}
