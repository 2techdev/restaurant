/// Riverpod providers for hardware payment terminal integration.
///
/// Configuration providers derive live values from [paymentSettingsProvider]
/// (backed by SharedPreferences via SettingsRepository). The user edits
/// terminal IP / port / POS ID in the Settings screen; those values flow
/// directly into the hardware-side [WalleeConfig] and [MyPosConfig]
/// consumed by [PaymentEngine].
///
/// While the settings repository is still loading (first frame), we fall
/// back to empty-IP configs — the engine's connection attempts will fail
/// fast and surface a "terminal unreachable" error in the UI, which is the
/// correct behaviour for an unconfigured install.
///
/// Settings and hardware layers each define their own `WalleeConfig` /
/// `MyPosConfig` with different field names (settings uses `ip`/`port`,
/// hardware uses `terminalIp`/`ltiPort` / `terminalPort`). We bridge them
/// here via aliased imports and a mapper at provider construction.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/payment/config/mypos_config.dart';
import 'package:gastrocore_pos/core/payment/config/wallee_config.dart';
import 'package:gastrocore_pos/features/payments/data/hardware/mypos/mypos_payment_provider.dart';
import 'package:gastrocore_pos/features/payments/data/hardware/payment_engine.dart';
import 'package:gastrocore_pos/features/payments/data/hardware/wallee/wallee_payment_provider.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/payment_settings.dart'
    as settings;
import 'package:gastrocore_pos/features/settings/presentation/providers/settings_provider.dart';

// ---------------------------------------------------------------------------
// Configuration — derived from settings
// ---------------------------------------------------------------------------

/// Wallee terminal configuration derived from [paymentSettingsProvider].
///
/// Returns a config with empty `terminalIp` while settings are still
/// loading; callers should treat that as "not yet configured" and surface
/// an error rather than attempting to connect.
final walleeConfigProvider = Provider<WalleeConfig>((ref) {
  final async = ref.watch(paymentSettingsProvider);
  final s = async.valueOrNull?.wallee ?? const settings.WalleeConfig();
  return WalleeConfig(
    terminalIp: s.terminalIp,
    posId: s.posId,
    ltiPort: s.terminalPort,
  );
});

/// MyPOS terminal configuration derived from [paymentSettingsProvider].
final myposConfigProvider = Provider<MyPosConfig>((ref) {
  final async = ref.watch(paymentSettingsProvider);
  final s = async.valueOrNull?.mypos ?? const settings.MyPosConfig();
  return MyPosConfig(
    terminalIp: s.ip,
    terminalPort: s.port,
    currency: s.currency,
  );
});

/// The active payment gateway selected in settings.
///
/// The payment UI consults this to decide whether card/debit buttons should
/// trigger the hardware terminal or fall back to manual entry.
final activePaymentGatewayProvider = Provider<settings.PaymentGateway>((ref) {
  final async = ref.watch(paymentSettingsProvider);
  return async.valueOrNull?.activeGateway ?? settings.PaymentGateway.none;
});

// ---------------------------------------------------------------------------
// Providers — individual terminal providers
// ---------------------------------------------------------------------------

/// Wallee LTI payment provider (uninitialised).
///
/// Call [WalleePaymentProvider.initialize] before processing payments,
/// or use [paymentEngineProvider] which initialises all providers.
final walleePaymentProvider = Provider<WalleePaymentProvider>((ref) {
  final config = ref.watch(walleeConfigProvider);
  final provider = WalleePaymentProvider(config);
  ref.onDispose(provider.dispose);
  return provider;
});

/// MyPOS WiFi payment provider (uninitialised).
final myposPaymentProvider = Provider<MyPosPaymentProvider>((ref) {
  final config = ref.watch(myposConfigProvider);
  final provider = MyPosPaymentProvider(config);
  ref.onDispose(provider.dispose);
  return provider;
});

// ---------------------------------------------------------------------------
// Payment Engine
// ---------------------------------------------------------------------------

/// Fully configured [PaymentEngine].
///
/// - Primary provider : Wallee (card payments via LTI/TCP)
/// - TWINT provider   : MyPOS (TWINT via SlaveSDK)
/// - Fallback provider: MyPOS (card fallback if Wallee is unavailable)
///
/// The engine is **not** initialised at construction time.
/// Call [PaymentEngine.initialize] once (e.g. in a startup provider or
/// from a controller) before processing the first payment.
final paymentEngineProvider = Provider<PaymentEngine>((ref) {
  final wallee = ref.watch(walleePaymentProvider);
  final mypos = ref.watch(myposPaymentProvider);

  final engine = PaymentEngine(
    primaryProvider: wallee,
    fallbackProvider: mypos,
    myposProvider: mypos,
  );

  ref.onDispose(engine.dispose);
  return engine;
});

// ---------------------------------------------------------------------------
// Async initialisation notifier
// ---------------------------------------------------------------------------

/// Initialises the [PaymentEngine] and exposes its readiness as async state.
///
/// Watch this provider in the payment UI to wait for terminal readiness:
/// ```dart
/// final state = ref.watch(paymentEngineInitProvider);
/// state.when(
///   data: (_) => PaymentScreen(),
///   loading: () => TerminalConnectingSpinner(),
///   error: (e, _) => TerminalErrorView(error: e),
/// );
/// ```
final paymentEngineInitProvider = FutureProvider<void>((ref) async {
  final engine = ref.watch(paymentEngineProvider);
  await engine.initialize();
});
