/// Riverpod providers for hardware payment terminal integration.
///
/// Configuration providers are intentionally left as `throw UnimplementedError`
/// and must be overridden in [ProviderScope] at app startup with real values
/// loaded from settings / database, following the same pattern as
/// [databaseProvider] and [tenantIdProvider].
///
/// Example bootstrap in main.dart:
/// ```dart
/// runApp(ProviderScope(
///   overrides: [
///     walleeConfigProvider.overrideWithValue(
///       WalleeConfig(terminalIp: '192.168.1.100', posId: 'POS1'),
///     ),
///     myposConfigProvider.overrideWithValue(
///       MyPosConfig(terminalIp: '192.168.1.101'),
///     ),
///   ],
///   child: const App(),
/// ));
/// ```
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/payment/config/mypos_config.dart';
import 'package:gastrocore_pos/core/payment/config/wallee_config.dart';
import 'package:gastrocore_pos/features/payments/data/hardware/mypos/mypos_payment_provider.dart';
import 'package:gastrocore_pos/features/payments/data/hardware/payment_engine.dart';
import 'package:gastrocore_pos/features/payments/data/hardware/wallee/wallee_payment_provider.dart';

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

/// Wallee terminal configuration.
/// Must be overridden in ProviderScope before use.
final walleeConfigProvider = Provider<WalleeConfig>((ref) {
  throw UnimplementedError('walleeConfigProvider must be overridden in ProviderScope');
});

/// MyPOS terminal configuration.
/// Must be overridden in ProviderScope before use.
final myposConfigProvider = Provider<MyPosConfig>((ref) {
  throw UnimplementedError('myposConfigProvider must be overridden in ProviderScope');
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
