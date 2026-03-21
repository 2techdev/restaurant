/// Riverpod providers for the Home / Dashboard screen.
///
/// [dashboardSummaryProvider] – auto-disposing FutureProvider that fetches
/// a fresh [DashboardSummaryEntity] on every mount and on manual invalidation
/// (e.g. after a shift change or after returning from the order-center).
///
/// [hardwareStatusProvider] – exposes printer and payment-terminal connection
/// state.  Currently returns simulated values; wire it to the real hardware
/// providers once those are implemented.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/features/home/data/repositories/dashboard_repository.dart';
import 'package:gastrocore_pos/features/home/domain/entities/dashboard_summary.dart';

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

/// Singleton [DashboardRepository] backed by the app database.
final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  return DashboardRepository(ref.watch(databaseProvider));
});

// ---------------------------------------------------------------------------
// Dashboard summary
// ---------------------------------------------------------------------------

/// Full [DashboardSummaryEntity] for the current tenant.
///
/// Auto-disposes when the screen is no longer in the tree, ensuring fresh data
/// on every visit. Call `ref.invalidate(dashboardSummaryProvider)` to trigger
/// a manual refresh (e.g. after closing an order or changing shift state).
final dashboardSummaryProvider =
    FutureProvider.autoDispose<DashboardSummaryEntity>((ref) async {
  final repo = ref.watch(dashboardRepositoryProvider);
  final tenantId = ref.watch(tenantIdProvider);
  return repo.getDashboardSummary(tenantId);
});

// ---------------------------------------------------------------------------
// Hardware status
// ---------------------------------------------------------------------------

/// Connection status for peripheral hardware.
class HardwareStatus {
  /// True when the thermal receipt printer is reachable.
  final bool printerConnected;

  /// True when the payment terminal (MyPOS / Wallee) is reachable.
  final bool terminalConnected;

  const HardwareStatus({
    required this.printerConnected,
    required this.terminalConnected,
  });
}

/// Provider for [HardwareStatus].
///
/// Currently returns simulated disconnected state.
/// Replace the body with real connectivity checks once the printing and
/// payment-terminal providers are fully implemented.
final hardwareStatusProvider = Provider<HardwareStatus>((ref) {
  // TODO: wire to real printer provider and payment terminal provider.
  return const HardwareStatus(
    printerConnected: false,
    terminalConnected: false,
  );
});
