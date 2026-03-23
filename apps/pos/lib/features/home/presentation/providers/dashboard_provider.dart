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
import 'package:gastrocore_pos/core/printing/printing_provider.dart';
import 'package:gastrocore_pos/features/home/data/repositories/dashboard_repository.dart';
import 'package:gastrocore_pos/features/home/domain/entities/dashboard_summary.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/payment_settings.dart';
import 'package:gastrocore_pos/features/settings/presentation/providers/settings_provider.dart';

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
/// Reads live printer connectivity from [printerStatusProvider].
/// Payment terminal wiring is pending a terminal SDK integration.
final hardwareStatusProvider = Provider<HardwareStatus>((ref) {
  final printerStatus = ref.watch(printerStatusProvider);
  final paymentSettings =
      ref.watch(paymentSettingsProvider).valueOrNull;
  // Terminal is "connected" when a non-none gateway is configured.
  // Full live connectivity detection requires vendor SDKs (Wallee/myPOS),
  // so we use gateway != none as a proxy for "terminal set up".
  final terminalConfigured =
      paymentSettings?.activeGateway != null &&
          paymentSettings!.activeGateway != PaymentGateway.none;
  return HardwareStatus(
    printerConnected: printerStatus.valueOrNull?.isConnected ?? false,
    terminalConnected: terminalConfigured,
  );
});
