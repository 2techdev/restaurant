import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:gastrocore_pos/core/payment/config/mypos_config.dart';

/// Callback type for terminal connection state changes.
typedef MyPosConnectionCallback =
    void Function(bool connected, String state, String reason);

/// Dart-side client for the MyPOS Sigma terminal over WiFi (TCP/IP).
///
/// Communicates with the native [MyPosPlugin] via MethodChannel.
/// Only TCP/IP connectivity is supported — USB and Bluetooth are excluded.
///
/// Channel names:
///   'mypos_payment'  — MethodChannel for commands
///   'mypos_logs'     — EventChannel for native log stream (debug only)
class MyPosClient {
  MyPosClient({
    required this.terminalIp,
    required this.terminalPort,
    this.onConnectionStateChanged,
  }) {
    _setupMethodCallHandler();
    if (kDebugMode) _startNativeLogListener();
  }

  factory MyPosClient.fromConfig(
    MyPosConfig config, {
    MyPosConnectionCallback? onConnectionStateChanged,
  }) {
    return MyPosClient(
      terminalIp: config.terminalIp,
      terminalPort: config.terminalPort,
      onConnectionStateChanged: onConnectionStateChanged,
    );
  }

  final String terminalIp;
  final int terminalPort;
  final MyPosConnectionCallback? onConnectionStateChanged;

  static const _channel = MethodChannel('mypos_payment');
  static const _logChannel = EventChannel('mypos_logs');

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  StreamSubscription<String>? _logSub;

  // ---------------------------------------------------------------------------
  // Setup
  // ---------------------------------------------------------------------------

  void _setupMethodCallHandler() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onConnectionChanged') {
        final args = call.arguments as Map<dynamic, dynamic>;
        final connected = args['connected'] == true;
        final state = args['state']?.toString() ?? 'UNKNOWN';
        final reason = args['reason']?.toString() ?? '';
        _isConnected = connected;
        onConnectionStateChanged?.call(connected, state, reason);
      }
      return null;
    });
  }

  void _startNativeLogListener() {
    _logSub?.cancel();
    _logSub = _logChannel
        .receiveBroadcastStream()
        .map((e) => e.toString())
        .listen((msg) => debugPrint('[MyPosNative] $msg'));
  }

  // ---------------------------------------------------------------------------
  // Connection
  // ---------------------------------------------------------------------------

  /// Configure and connect to the terminal over TCP/IP.
  Future<bool> connect() async {
    try {
      final result = await _channel.invokeMethod<Map>('configure', {
        'type': 'tcp',
        'ip': terminalIp,
        'port': terminalPort,
      });
      final success = result?['success'] == true;
      _isConnected = success;
      return success;
    } catch (e) {
      debugPrint('[MyPosClient] connect error: $e');
      _isConnected = false;
      return false;
    }
  }

  /// Disconnect from the terminal.
  Future<void> disconnect() async {
    try {
      await _channel.invokeMethod('disconnect');
    } catch (_) {}
    _logSub?.cancel();
    _logSub = null;
    _isConnected = false;
  }

  /// Query the native SDK for the real connection state.
  Future<bool> checkConnection() async {
    try {
      final result = await _channel.invokeMethod<Map>('checkRealConnection');
      _isConnected = result?['connected'] == true;
      return _isConnected;
    } catch (_) {
      _isConnected = false;
      return false;
    }
  }

  /// Send an actual PING command to verify the terminal is responsive.
  Future<bool> pingTerminal() async {
    try {
      final result = await _channel.invokeMethod<Map>('pingTerminal');
      final connected = result?['connected'] == true;
      _isConnected = connected;
      return connected;
    } catch (_) {
      _isConnected = false;
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Payments
  // ---------------------------------------------------------------------------

  /// Process a card payment.
  ///
  /// [amountCents] — amount in minor units (e.g. 1250 = CHF 12.50).
  /// [currency]    — ISO 4217 code (e.g. 'CHF').
  Future<MyPosPaymentResult> processPayment({
    required int amountCents,
    required String currency,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map>('processPayment', {
        'amount': amountCents / 100.0,
        'currency': currency,
      });
      if (result?['success'] == true) {
        return MyPosPaymentResult(
          success: true,
          transactionId: result!['transactionId']?.toString() ??
              result['rrn']?.toString() ??
              '',
          authCode: result['authCode']?.toString(),
          cardType: result['cardType']?.toString(),
          maskedPan: result['maskedPan']?.toString(),
          amountCents: amountCents,
          currency: currency,
        );
      }
      return MyPosPaymentResult(
        success: false,
        errorCode: result?['errorCode']?.toString(),
        errorMessage: result?['error']?.toString() ?? 'Payment failed',
      );
    } on PlatformException catch (e) {
      return MyPosPaymentResult(
        success: false,
        errorCode: e.code,
        errorMessage: e.message ?? 'Platform error',
      );
    } catch (e) {
      return MyPosPaymentResult(success: false, errorMessage: e.toString());
    }
  }

  /// Process a TWINT payment (CHF only).
  ///
  /// [amountCents] — amount in minor units (e.g. 1250 = CHF 12.50).
  Future<MyPosPaymentResult> processTwintPayment({required int amountCents}) async {
    try {
      final result = await _channel.invokeMethod<Map>('twintPurchase', {
        'amount': amountCents / 100.0,
      });
      if (result?['success'] == true) {
        return MyPosPaymentResult(
          success: true,
          transactionId: result!['transactionId']?.toString() ??
              result['rrn']?.toString() ??
              '',
          authCode: result['authCode']?.toString(),
          cardType: 'TWINT',
          amountCents: amountCents,
          currency: 'CHF',
        );
      }
      return MyPosPaymentResult(
        success: false,
        errorCode: result?['errorCode']?.toString(),
        errorMessage: result?['error']?.toString() ?? 'TWINT payment failed',
      );
    } on PlatformException catch (e) {
      return MyPosPaymentResult(
        success: false,
        errorCode: e.code,
        errorMessage: e.message ?? 'TWINT platform error',
      );
    } catch (e) {
      return MyPosPaymentResult(success: false, errorMessage: e.toString());
    }
  }

  /// Refund a previous transaction.
  ///
  /// [amountCents] — amount in minor units (null = full refund).
  Future<MyPosPaymentResult> processRefund({
    required String transactionId,
    int? amountCents,
    String currency = 'CHF',
  }) async {
    try {
      final result = await _channel.invokeMethod<Map>('refund', {
        'amount': amountCents != null ? amountCents / 100.0 : 0.0,
        'currency': currency,
      });
      if (result?['success'] == true) {
        return MyPosPaymentResult(
          success: true,
          transactionId: result!['transactionId']?.toString() ?? '',
          amountCents: amountCents,
          currency: currency,
        );
      }
      return MyPosPaymentResult(
        success: false,
        errorMessage: result?['error']?.toString() ?? 'Refund failed',
      );
    } on PlatformException catch (e) {
      return MyPosPaymentResult(
        success: false,
        errorCode: e.code,
        errorMessage: e.message ?? 'Refund platform error',
      );
    } catch (e) {
      return MyPosPaymentResult(success: false, errorMessage: e.toString());
    }
  }

  /// Cancel the current in-progress terminal transaction.
  Future<bool> cancelTransaction() async {
    try {
      final result = await _channel.invokeMethod<Map>('cancelPayment');
      return result?['success'] == true;
    } catch (_) {
      return false;
    }
  }

  /// End-of-day settlement (clear batch).
  Future<MyPosSettlementResult> endOfDay() async {
    try {
      final result = await _channel.invokeMethod<Map>('clearBatch');
      if (result?['success'] == true) {
        return MyPosSettlementResult(
          success: true,
          reportData: result!['status']?.toString(),
        );
      }
      return MyPosSettlementResult(
        success: false,
        errorMessage: result?['error']?.toString() ?? 'End of day failed',
      );
    } on PlatformException catch (e) {
      return MyPosSettlementResult(
        success: false,
        errorMessage: e.message ?? 'End of day platform error',
      );
    } catch (e) {
      return MyPosSettlementResult(success: false, errorMessage: e.toString());
    }
  }
}

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

class MyPosPaymentResult {
  const MyPosPaymentResult({
    required this.success,
    this.transactionId,
    this.authCode,
    this.cardType,
    this.maskedPan,
    this.amountCents,
    this.currency,
    this.errorCode,
    this.errorMessage,
  });

  final bool success;
  final String? transactionId;
  final String? authCode;
  final String? cardType;
  final String? maskedPan;
  final int? amountCents;
  final String? currency;
  final String? errorCode;
  final String? errorMessage;
}

class MyPosSettlementResult {
  const MyPosSettlementResult({
    required this.success,
    this.totalTransactions,
    this.totalAmountCents,
    this.reportData,
    this.errorMessage,
  });

  final bool success;
  final int? totalTransactions;
  final int? totalAmountCents;
  final String? reportData;
  final String? errorMessage;
}
