/// Riverpod providers for German fiscal compliance (Fiskaly SIGN DE).
///
/// Feature is gated on [countryConfigProvider] returning DE — all providers
/// are safe to reference in CH mode; they will return inert/empty state.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gastrocore_pos/core/country_config.dart';
import 'fiskaly_models.dart';
import 'fiskaly_service.dart';
import 'tse_lifecycle_service.dart';
import 'dsfinvk_export_service.dart';

// ---------------------------------------------------------------------------
// Country config provider
// ---------------------------------------------------------------------------

/// The active country configuration.
///
/// Override via ProviderScope to switch between CH and DE.
/// Defaults to Switzerland for backwards compatibility.
final countryConfigProvider = StateProvider<CountryConfig>(
  (ref) => CountryConfig.ch,
);

// ---------------------------------------------------------------------------
// FiskalyConfig provider
// ---------------------------------------------------------------------------

const _kFiskalyConfigKey = 'fiscal_de_fiskaly_config';

/// Async notifier that persists [FiskalyConfig] in SharedPreferences.
class FiskalyConfigNotifier extends AsyncNotifier<FiskalyConfig> {
  @override
  Future<FiskalyConfig> build() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kFiskalyConfigKey);
    if (raw == null) return FiskalyConfig.empty();
    try {
      return FiskalyConfig.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return FiskalyConfig.empty();
    }
  }

  Future<void> save(FiskalyConfig config) async {
    state = AsyncData(config);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kFiskalyConfigKey, config.toJsonString());
    // Refresh the service with updated config.
    ref.read(fiskalyServiceProvider).config = config;
  }
}

final fiskalyConfigProvider =
    AsyncNotifierProvider<FiskalyConfigNotifier, FiskalyConfig>(
  FiskalyConfigNotifier.new,
);

// ---------------------------------------------------------------------------
// FiskalyService provider
// ---------------------------------------------------------------------------

/// Singleton [FiskalyService] instance.
///
/// Config is set lazily — the service is created with an empty config and
/// updated via [FiskalyConfigNotifier.update] when settings are saved.
final fiskalyServiceProvider = Provider<FiskalyService>((ref) {
  return FiskalyService(config: FiskalyConfig.empty());
});

// ---------------------------------------------------------------------------
// TseLifecycleService provider
// ---------------------------------------------------------------------------

/// Singleton [TseLifecycleService] built on top of [fiskalyServiceProvider].
final tseLifecycleServiceProvider =
    Provider<TseLifecycleService>((ref) {
  final service = ref.watch(fiskalyServiceProvider);
  return TseLifecycleService(service: service);
});

// ---------------------------------------------------------------------------
// TSE state notifier
// ---------------------------------------------------------------------------

/// Async notifier representing the current [TseLifecycleState].
class TseStateNotifier extends AsyncNotifier<TseLifecycleState> {
  @override
  Future<TseLifecycleState> build() async {
    final country = ref.watch(countryConfigProvider);
    if (!country.requiresTse) return TseLifecycleState.initial;

    final lifecycle = ref.read(tseLifecycleServiceProvider);
    try {
      return await lifecycle.getState();
    } catch (_) {
      return TseLifecycleState.initial;
    }
  }

  /// Runs the full TSE initialization flow.
  Future<void> initialize() async {
    state = const AsyncLoading();
    final lifecycle = ref.read(tseLifecycleServiceProvider);
    state = await AsyncValue.guard(() => lifecycle.initialize());
  }

  /// Triggers a TSE self-test and updates state.
  Future<void> runSelfTest() async {
    state = const AsyncLoading();
    final lifecycle = ref.read(tseLifecycleServiceProvider);
    state = await AsyncValue.guard(() => lifecycle.runSelfTest());
  }

  /// Refreshes TSE state from the Fiskaly API.
  Future<void> refresh() async {
    state = const AsyncLoading();
    final lifecycle = ref.read(tseLifecycleServiceProvider);
    state = await AsyncValue.guard(() => lifecycle.getState());
  }
}

final tseStateProvider =
    AsyncNotifierProvider<TseStateNotifier, TseLifecycleState>(
  TseStateNotifier.new,
);

// ---------------------------------------------------------------------------
// Sign transaction provider (family)
// ---------------------------------------------------------------------------

/// Signs a transaction for the given [transactionId] and returns
/// [TseSignatureData] if the country requires TSE, null otherwise.
///
/// Usage:
/// ```dart
/// final sig = await ref.read(
///   signTransactionProvider(SignTransactionParams(...)).future,
/// );
/// ```
class SignTransactionParams {
  const SignTransactionParams({
    required this.transactionId,
    required this.amountsPerVatRate,
    required this.paymentType,
    required this.paymentAmount,
  });

  final String transactionId;
  final List<VatAmountPerRate> amountsPerVatRate;
  final String paymentType;
  final double paymentAmount;
}

final signTransactionProvider = FutureProvider.family<
    TseSignatureData?, SignTransactionParams>((ref, params) async {
  final country = ref.watch(countryConfigProvider);
  if (!country.requiresTse) return null;

  final lifecycle = ref.read(tseLifecycleServiceProvider);

  // Start transaction
  await lifecycle.startTransaction(params.transactionId);

  // Finish and sign
  final tx = await lifecycle.finishTransaction(
    transactionId: params.transactionId,
    amountsPerVatRate: params.amountsPerVatRate,
    paymentType: params.paymentType,
    paymentAmount: params.paymentAmount,
  );

  return tx.signature;
});

// ---------------------------------------------------------------------------
// DSFinV-K export provider
// ---------------------------------------------------------------------------

/// Singleton [DsfinvkExportService].
final dsfinvkExportServiceProvider =
    Provider<DsfinvkExportService>((_) => DsfinvkExportService());

/// State for an active DSFinV-K export job (null = no export in progress).
final exportJobProvider =
    StateProvider<ExportState?>((ref) => null);

/// Triggers a DSFinV-K export on Fiskaly and updates [exportJobProvider].
final triggerExportProvider = FutureProvider.family<ExportState, DateRange>(
  (ref, range) async {
    final lifecycle = ref.read(tseLifecycleServiceProvider);
    final job = await lifecycle.triggerExport(
      startDate: range.start,
      endDate: range.end,
    );
    ref.read(exportJobProvider.notifier).state = job;
    return job;
  },
);

/// Date range for export queries.
class DateRange {
  const DateRange({this.start, this.end});
  final DateTime? start;
  final DateTime? end;
}
