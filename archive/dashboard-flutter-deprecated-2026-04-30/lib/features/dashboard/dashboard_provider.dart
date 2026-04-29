import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/models.dart';
import '../../core/auth/auth_provider.dart';

// ---------------------------------------------------------------------------
// Stats
// ---------------------------------------------------------------------------

final dashboardStatsProvider = FutureProvider.autoDispose<DashboardStats>((ref) async {
  final client = ref.watch(apiClientProvider);
  return client.getStats();
});

// ---------------------------------------------------------------------------
// Revenue chart
// ---------------------------------------------------------------------------

final revenuePeriodProvider = StateProvider.autoDispose<String>((ref) => '7d');

final revenueDataProvider = FutureProvider.autoDispose<List<RevenuePoint>>((ref) async {
  final client = ref.watch(apiClientProvider);
  final period = ref.watch(revenuePeriodProvider);
  return client.getRevenue(period: period);
});
