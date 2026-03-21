import 'package:gastrocore_pos/core/payment/interfaces/hardware_payment_provider.dart';
import 'package:gastrocore_pos/core/payment/models/hardware_payment_method.dart';
import 'package:gastrocore_pos/core/payment/models/hardware_payment_request.dart';
import 'package:gastrocore_pos/core/payment/models/hardware_payment_result.dart';
import 'package:gastrocore_pos/core/payment/models/hardware_payment_status.dart';

/// Routes payment requests to the appropriate hardware provider.
///
/// Routing rules:
///   - [HardwarePaymentMethod.twint] → always [MyPOS] (TWINT runs exclusively
///     through the MyPOS terminal, CHF only)
///   - [HardwarePaymentMethod.card]  → primary provider, then fallback provider
///     if the primary fails to initialise or returns a technical failure
///
/// Fallback semantics:
///   A fallback provider is tried **only** for technical failures
///   (status = [HardwarePaymentStatus.failed]).
///   Declined or cancelled results are returned immediately — do not retry
///   a genuinely declined card on a different terminal.
///
/// Usage:
/// ```dart
/// final engine = PaymentEngine(
///   primaryProvider: walleeProvider,
///   fallbackProvider: myposProvider,  // optional
/// );
/// await engine.initialize();
/// final result = await engine.processPayment(request);
/// ```
class PaymentEngine {
  PaymentEngine({
    required this.primaryProvider,
    this.fallbackProvider,
    this.myposProvider,
  });

  /// Primary card payment terminal (typically Wallee).
  final HardwarePaymentProvider primaryProvider;

  /// Optional fallback terminal used when primary has a technical failure.
  final HardwarePaymentProvider? fallbackProvider;

  /// Provider for TWINT payments (must be MyPOS).
  /// If null, TWINT requests are routed to [primaryProvider].
  final HardwarePaymentProvider? myposProvider;

  bool _initialized = false;
  bool get isInitialized => _initialized;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Initialise all configured providers in parallel.
  Future<void> initialize() async {
    final futures = <Future<void>>[primaryProvider.initialize()];
    if (fallbackProvider != null && fallbackProvider != primaryProvider) {
      futures.add(fallbackProvider!.initialize());
    }
    if (myposProvider != null &&
        myposProvider != primaryProvider &&
        myposProvider != fallbackProvider) {
      futures.add(myposProvider!.initialize());
    }
    await Future.wait(futures);
    _initialized = true;
    print('[PaymentEngine] Initialised — primary: ${primaryProvider.providerName}'
        '${fallbackProvider != null ? ", fallback: ${fallbackProvider!.providerName}" : ""}');
  }

  /// Dispose all providers.
  Future<void> dispose() async {
    await Future.wait([
      primaryProvider.dispose(),
      if (fallbackProvider != null) fallbackProvider!.dispose(),
      if (myposProvider != null && myposProvider != fallbackProvider)
        myposProvider!.dispose(),
    ]);
    _initialized = false;
  }

  // ---------------------------------------------------------------------------
  // Payment
  // ---------------------------------------------------------------------------

  /// Process a payment request, applying routing and fallback logic.
  Future<HardwarePaymentResult> processPayment(HardwarePaymentRequest request) async {
    // TWINT → always MyPOS (CHF only)
    if (request.paymentMethod == HardwarePaymentMethod.twint) {
      final twintProvider = myposProvider ?? primaryProvider;
      return _processWithProvider(twintProvider, request, isTwint: true);
    }

    // Card → primary with optional fallback
    final primaryResult = await _processWithProvider(primaryProvider, request);

    if (!primaryResult.isFailed || fallbackProvider == null) {
      return primaryResult;
    }

    // Primary had a technical failure → try fallback
    print('[PaymentEngine] Primary failed, trying fallback: ${fallbackProvider!.providerName}');
    final fallbackResult = await _processWithProvider(fallbackProvider!, request);
    return fallbackResult;
  }

  Future<HardwarePaymentResult> _processWithProvider(
    HardwarePaymentProvider provider,
    HardwarePaymentRequest request, {
    bool isTwint = false,
  }) async {
    if (!provider.isInitialized) {
      try {
        await provider.initialize();
      } catch (e) {
        return HardwarePaymentResult.error(
          transactionId: request.reference,
          amount: request.amount,
          currency: request.currency,
          message: '${provider.providerName} could not initialise: $e',
        );
      }
    }

    final result = await provider.processPayment(request);

    if (isTwint && result.isApproved) {
      print('[PaymentEngine] TWINT approved via ${provider.providerName}');
    } else if (result.isApproved) {
      print('[PaymentEngine] Approved via ${provider.providerName}');
    } else {
      print('[PaymentEngine] ${provider.providerName} → ${result.status.name}: ${result.errorMessage}');
    }

    return result;
  }

  // ---------------------------------------------------------------------------
  // Other operations
  // ---------------------------------------------------------------------------

  /// Cancel an in-progress transaction on all active providers.
  Future<bool> cancelPayment() async {
    bool cancelled = false;
    try {
      cancelled = await primaryProvider.cancelPayment();
    } catch (_) {}

    if (fallbackProvider != null && fallbackProvider!.isInitialized) {
      try {
        await fallbackProvider!.cancelPayment();
      } catch (_) {}
    }

    return cancelled;
  }

  /// Refund via the provider that originally processed the transaction.
  ///
  /// Pass [providerName] to force routing to a specific provider.
  Future<bool> refundPayment(
    String transactionId, {
    int? amountCents,
    String? providerName,
  }) async {
    HardwarePaymentProvider target = primaryProvider;

    if (providerName != null) {
      if (fallbackProvider?.providerName == providerName) {
        target = fallbackProvider!;
      } else if (myposProvider?.providerName == providerName) {
        target = myposProvider!;
      }
    }

    return target.refundPayment(transactionId, amountCents: amountCents);
  }

  /// Run end-of-day settlement on all providers.
  Future<Map<String, Map<String, dynamic>>> endOfDay() async {
    final results = <String, Map<String, dynamic>>{};

    results[primaryProvider.providerName] = await primaryProvider.endOfDay();

    if (fallbackProvider != null &&
        fallbackProvider != primaryProvider &&
        fallbackProvider!.isInitialized) {
      results[fallbackProvider!.providerName] = await fallbackProvider!.endOfDay();
    }

    if (myposProvider != null &&
        myposProvider != primaryProvider &&
        myposProvider != fallbackProvider &&
        myposProvider!.isInitialized) {
      results[myposProvider!.providerName] = await myposProvider!.endOfDay();
    }

    return results;
  }
}
