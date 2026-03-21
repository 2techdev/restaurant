import 'package:gastrocore_pos/core/payment/config/mypos_config.dart';
import 'package:gastrocore_pos/core/payment/interfaces/hardware_payment_provider.dart';
import 'package:gastrocore_pos/core/payment/models/hardware_payment_method.dart';
import 'package:gastrocore_pos/core/payment/models/hardware_payment_request.dart';
import 'package:gastrocore_pos/core/payment/models/hardware_payment_result.dart';
import 'package:gastrocore_pos/core/payment/models/hardware_payment_status.dart';
import 'mypos_client.dart';

/// MyPOS Sigma terminal provider (WiFi / TCP-IP only).
///
/// Supports:
///   - Card payments via [HardwarePaymentMethod.card]
///   - TWINT QR payments via [HardwarePaymentMethod.twint] (CHF only)
///   - Refunds
///   - End-of-day batch clear
///
/// The underlying [MyPosClient] communicates with the native [MyPosPlugin]
/// (Kotlin) via a MethodChannel. Only TCP/IP connectivity is used — USB and
/// Bluetooth are not supported in GastroCore POS.
class MyPosPaymentProvider implements HardwarePaymentProvider {
  MyPosPaymentProvider(this._config);

  /// Inject an already-connected client (e.g. from a shared connection pool).
  MyPosPaymentProvider.withClient(this._config, MyPosClient client)
      : _client = client,
        _initialized = client.isConnected,
        _externalClient = true;

  final MyPosConfig _config;
  MyPosClient? _client;
  bool _initialized = false;
  bool _externalClient = false;

  // ---------------------------------------------------------------------------
  // HardwarePaymentProvider
  // ---------------------------------------------------------------------------

  @override
  String get providerName => 'MyPOS';

  @override
  bool get isInitialized => _initialized;

  /// The underlying client (useful for subscribing to native log streams).
  MyPosClient? get client => _client;

  /// Replace the client when a reconnection is established from the outside.
  void updateClient(MyPosClient client) {
    _client = client;
    _initialized = client.isConnected;
    _externalClient = true;
  }

  @override
  Future<void> initialize() async {
    _client = MyPosClient.fromConfig(_config);
    try {
      final connected = await _client!.connect();
      _initialized = connected;
      print('[MyPosPaymentProvider] Connected via TCP/IP: $connected '
          '(${_config.terminalIp}:${_config.terminalPort})');
    } catch (e) {
      print('[MyPosPaymentProvider] Connection error: $e');
      _initialized = false;
    }
  }

  @override
  Future<HardwarePaymentResult> processPayment(HardwarePaymentRequest request) async {
    if (_client == null || !_initialized) {
      return HardwarePaymentResult.error(
        transactionId: request.reference,
        amount: request.amount,
        currency: request.currency,
        message: 'MyPOS provider not initialised',
      );
    }

    try {
      final MyPosPaymentResult myposResult;

      switch (request.paymentMethod) {
        case HardwarePaymentMethod.twint:
          // TWINT is always CHF — validate currency
          if (request.currency != 'CHF') {
            return HardwarePaymentResult.error(
              transactionId: request.reference,
              amount: request.amount,
              currency: request.currency,
              message: 'TWINT only supports CHF payments',
            );
          }
          print('[MyPosPaymentProvider] TWINT: ${request.amount} CHF');
          myposResult = await _client!.processTwintPayment(
            amountCents: request.amountMinorUnits,
          );

        case HardwarePaymentMethod.card:
          print('[MyPosPaymentProvider] Card: ${request.amount} ${_config.currency}');
          myposResult = await _client!.processPayment(
            amountCents: request.amountMinorUnits,
            currency: _config.currency,
          );
      }

      if (myposResult.success) {
        return HardwarePaymentResult(
          transactionId: myposResult.transactionId ?? '',
          status: HardwarePaymentStatus.approved,
          amount: request.amount,
          currency: request.paymentMethod == HardwarePaymentMethod.twint
              ? 'CHF'
              : _config.currency,
          authCode: myposResult.authCode,
          cardNumber: myposResult.maskedPan,
          cardType: myposResult.cardType,
          rawResponse: {
            'transactionId': myposResult.transactionId,
            'cardType': myposResult.cardType,
          },
        );
      }

      return HardwarePaymentResult(
        transactionId: request.reference,
        status: HardwarePaymentStatus.declined,
        amount: request.amount,
        currency: request.currency,
        errorMessage: myposResult.errorMessage ?? 'Payment declined',
        rawResponse: {'errorCode': myposResult.errorCode},
      );
    } catch (e) {
      print('[MyPosPaymentProvider] Payment exception: $e');
      return HardwarePaymentResult.error(
        transactionId: request.reference,
        amount: request.amount,
        currency: request.currency,
        message: 'MyPOS error: $e',
      );
    }
  }

  @override
  Future<bool> refundPayment(String transactionId, {int? amountCents}) async {
    if (_client == null || !_initialized) return false;
    try {
      final result = await _client!.processRefund(
        transactionId: transactionId,
        amountCents: amountCents,
        currency: _config.currency,
      );
      return result.success;
    } catch (e) {
      print('[MyPosPaymentProvider] Refund error: $e');
      return false;
    }
  }

  @override
  Future<bool> cancelPayment() async {
    if (_client == null) return false;
    try {
      return await _client!.cancelTransaction();
    } catch (e) {
      print('[MyPosPaymentProvider] Cancel error: $e');
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>> endOfDay() async {
    if (_client == null || !_initialized) return {};
    try {
      final result = await _client!.endOfDay();
      return {
        'success': result.success,
        'totalTransactions': result.totalTransactions,
        'totalAmountCents': result.totalAmountCents,
        'reportData': result.reportData,
        if (result.errorMessage != null) 'error': result.errorMessage,
      };
    } catch (e) {
      print('[MyPosPaymentProvider] End-of-day error: $e');
      return {};
    }
  }

  @override
  Future<void> dispose() async {
    if (!_externalClient) {
      await _client?.disconnect();
    }
    _client = null;
    _initialized = false;
  }
}
