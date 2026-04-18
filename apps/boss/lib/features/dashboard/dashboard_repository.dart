/// Repository for live dashboard metrics + payment-event stream.
///
/// TODO(boss-sprint2): wire to real `DashboardApi.getLiveMetrics` REST call
/// and the WebSocket payment topic once those endpoints exist in
/// `gastrocore_api` (commit a1e3fc0 on branch claude/compassionate-spence...
/// not yet in this branch).
///
/// The current implementation returns deterministic placeholder data so the
/// UI can be exercised end-to-end. Replace `_placeholderMetrics()` with a
/// real HTTP call and `_paymentPulses()` with a `web_socket_channel`
/// subscription when the backend is ready.
library;

import 'dart:async';
import 'dart:math';

import 'dashboard_models.dart';

class DashboardRepository {
  final Random _rng = Random();

  /// Polls the live metrics endpoint at the given interval.
  Stream<LiveMetrics> watchLiveMetrics({
    Duration interval = const Duration(seconds: 30),
  }) async* {
    yield _placeholderMetrics();
    await for (final _ in Stream<void>.periodic(interval)) {
      yield _placeholderMetrics();
    }
  }

  /// Subscribes to a stream of payment events (used to drive the pulse
  /// animation on the revenue card).
  ///
  /// TODO(boss-sprint2): swap the simulated 12-second timer for a real
  /// WebSocket subscription on `wss://api.2hub.ch/ws/payments?tenant=...`.
  Stream<PaymentEvent> watchPaymentEvents() async* {
    while (true) {
      await Future<void>.delayed(const Duration(seconds: 12));
      yield PaymentEvent(
        amountChf: 18 + _rng.nextDouble() * 80,
        at: DateTime.now(),
      );
    }
  }

  LiveMetrics _placeholderMetrics() {
    final now = DateTime.now();
    final minute = now.minute;
    final base = 1280 + (minute * 7.4);
    return LiveMetrics(
      todayRevenueChf: base,
      openTableCount: 6 + (minute % 5),
      activeOrderCount: 14 + (minute % 7),
      last15MinCovers: 9 + (minute % 4),
      top5: const [
        TopProduct(name: 'Ribeye 250g', quantity: 18, revenueChf: 882),
        TopProduct(name: 'Caesar Salad', quantity: 22, revenueChf: 396),
        TopProduct(name: 'Tiramisu', quantity: 15, revenueChf: 187.5),
        TopProduct(name: 'Espresso', quantity: 41, revenueChf: 184.5),
        TopProduct(name: 'Mineral 0.5L', quantity: 28, revenueChf: 168),
      ],
      asOf: now,
    );
  }
}
