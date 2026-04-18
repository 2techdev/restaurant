/// Riverpod providers for the live dashboard.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dashboard_models.dart';
import 'dashboard_repository.dart';

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  return DashboardRepository();
});

final liveMetricsProvider = StreamProvider<LiveMetrics>((ref) {
  return ref.watch(dashboardRepositoryProvider).watchLiveMetrics();
});

final paymentEventsProvider = StreamProvider<PaymentEvent>((ref) {
  return ref.watch(dashboardRepositoryProvider).watchPaymentEvents();
});
