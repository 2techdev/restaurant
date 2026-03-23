import 'package:flutter/foundation.dart';
import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:gastrocore_pos/core/payment/config/wallee_config.dart';
import 'package:gastrocore_pos/core/payment/interfaces/hardware_payment_provider.dart';
import 'package:gastrocore_pos/core/payment/models/hardware_payment_request.dart';
import 'package:gastrocore_pos/core/payment/models/hardware_payment_result.dart';
import 'package:gastrocore_pos/core/payment/models/hardware_payment_status.dart';
import 'lti_client.dart';

/// Wallee LTI terminal provider.
///
/// Communicates with a Wallee payment terminal using the Local Till Interface
/// (LTI 2.52) protocol over TCP/XML on [WalleeConfig.ltiPort] (default 50000).
///
/// ### trxSyncNumber (LTI spec requirement)
/// The trxSyncNumber is persisted across app restarts via SharedPreferences.
/// - It is included in every financial request XML.
/// - It is incremented ONLY after a terminal response is received
///   (success or decline). On connection/timeout errors it is NOT incremented
///   so the same transaction can be retried with the same number.
/// - If the terminal receives a duplicate trxSyncNumber it automatically
///   voids the previous transaction — this is an important safety mechanism.
class WalleePaymentProvider implements HardwarePaymentProvider {
  WalleePaymentProvider(this._config);

  final WalleeConfig _config;
  LtiClient? _client;
  bool _initialized = false;

  /// Persisted across restarts so the terminal can detect duplicates/retries.
  int _trxSyncNumber = 1;

  static const _prefKeyTrxSync = 'wallee_trx_sync_number';

  // ---------------------------------------------------------------------------
  // HardwarePaymentProvider
  // ---------------------------------------------------------------------------

  @override
  String get providerName => 'Wallee';

  @override
  bool get isInitialized => _initialized;

  @override
  Future<void> initialize() async {
    _client = LtiClient(
      host: _config.terminalIp,
      port: _config.ltiPort,
      transactionTimeoutSeconds: _config.transactionTimeoutSeconds,
    );
    final prefs = await SharedPreferences.getInstance();
    _trxSyncNumber = prefs.getInt(_prefKeyTrxSync) ?? 1;
    _initialized = true;
    debugPrint('[WalleePaymentProvider] Initialised — terminal ${_config.terminalIp}:${_config.ltiPort}, trxSync: $_trxSyncNumber');
  }

  @override
  Future<HardwarePaymentResult> processPayment(HardwarePaymentRequest request) async {
    if (_client == null) {
      return HardwarePaymentResult.error(
        transactionId: request.reference,
        amount: request.amount,
        currency: request.currency,
        message: 'Wallee provider not initialised',
      );
    }

    try {
      final currencyCode = request.currency == 'CHF' ? 756 : 978;

      final xml = _client!.buildFinancialTrxRequestXml(
        posId: _config.posId,
        amountMinorUnits: request.amountMinorUnits,
        currencyNumeric: currencyCode,
        trxSyncNumber: _trxSyncNumber,
        merchantReference: request.reference,
        transactionType: 0, // purchase
      );

      final responseXml = await _client!.sendLtiMessage(xml);
      // Response received → increment counter (success or decline).
      await _incrementTrxSync();

      final approved = _parseSuccess(responseXml);

      if (approved) {
        return HardwarePaymentResult(
          transactionId: request.reference,
          status: HardwarePaymentStatus.approved,
          amount: request.amount,
          currency: request.currency,
          authCode: _parseField(responseXml, 'ep2AuthCode'),
          cardNumber: _parseField(responseXml, 'cardNumber'),
          cardType: _parseField(responseXml, 'cardAppLabel'),
          terminalId: _parseField(responseXml, 'ep2TrmId'),
          entryMethod: _parseField(responseXml, 'paymentEntryMethod'),
          rawResponse: {'xml': responseXml},
        );
      } else {
        final msg = _parseField(responseXml, 'errorMessage') ??
            _parseField(responseXml, 'resultText') ??
            'Payment declined';
        return HardwarePaymentResult(
          transactionId: request.reference,
          status: HardwarePaymentStatus.declined,
          amount: request.amount,
          currency: request.currency,
          errorMessage: msg,
          rawResponse: {'xml': responseXml},
        );
      }
    } on TimeoutException {
      // Do NOT increment trxSyncNumber — same number must be used on retry.
      return HardwarePaymentResult.error(
        transactionId: request.reference,
        amount: request.amount,
        currency: request.currency,
        message: 'Terminal did not respond within ${_config.transactionTimeoutSeconds}s',
      );
    } on StateError catch (e) {
      if (e.message.contains('closed connection')) {
        return HardwarePaymentResult.error(
          transactionId: request.reference,
          amount: request.amount,
          currency: request.currency,
          message: 'Terminal closed connection unexpectedly — check terminal status.',
        );
      }
      return HardwarePaymentResult.error(
        transactionId: request.reference,
        amount: request.amount,
        currency: request.currency,
        message: e.message,
      );
    } catch (e) {
      return HardwarePaymentResult.error(
        transactionId: request.reference,
        amount: request.amount,
        currency: request.currency,
        message: 'Payment error: $e',
      );
    }
  }

  @override
  Future<bool> refundPayment(String transactionId, {int? amountCents}) async {
    if (_client == null) return false;
    if (amountCents == null || amountCents <= 0) return false;

    try {
      final xml = _client!.buildFinancialTrxRequestXml(
        posId: _config.posId,
        amountMinorUnits: amountCents,
        currencyNumeric: 756, // CHF
        trxSyncNumber: _trxSyncNumber,
        merchantReference: 'REFUND-$transactionId',
        transactionType: 2, // refund
      );
      final responseXml = await _client!.sendLtiMessage(xml);
      await _incrementTrxSync();

      return responseXml.contains('<result>0</result>') ||
          responseXml.contains('Successful') ||
          responseXml.contains('approved');
    } catch (e) {
      debugPrint('[WalleePaymentProvider] Refund error: $e');
      return false;
    }
  }

  @override
  Future<bool> cancelPayment() async {
    if (_client == null) return false;
    try {
      final responseXml = await _client!.sendAbort(posId: _config.posId);
      final lower = responseXml.toLowerCase();
      if (lower.contains('errornotification') || lower.contains('error')) {
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('[WalleePaymentProvider] Cancel error: $e');
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>> endOfDay() async {
    if (_client == null) return {};
    try {
      final responseXml = await _client!.sendEndOfDay(posId: _config.posId);
      return {
        'xml': responseXml,
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      debugPrint('[WalleePaymentProvider] End-of-day error: $e');
      return {};
    }
  }

  @override
  Future<void> dispose() async {
    _client = null;
    _initialized = false;
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  Future<void> _incrementTrxSync() async {
    _trxSyncNumber++;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefKeyTrxSync, _trxSyncNumber);
  }

  /// Returns true when the LTI response indicates an authorised transaction.
  ///
  /// Priority: trxResult (0=success) → ep2AuthResult (0=approved)
  ///           → ep2AuthResponseCode ("00"=approved)
  bool _parseSuccess(String xml) {
    if (xml.contains('errorNotification')) return false;

    // 1. trxResult
    for (final pattern in [
      RegExp(r'<vcs-pos:trxResult>\s*(\d+)\s*</vcs-pos:trxResult>'),
      RegExp(r'<trxResult>\s*(\d+)\s*</trxResult>'),
      RegExp(r'<[\w-]+:trxResult>\s*(\d+)\s*</[\w-]+:trxResult>'),
    ]) {
      final m = pattern.firstMatch(xml);
      if (m != null) return m.group(1)!.trim() == '0';
    }

    // 2. ep2AuthResult
    for (final pattern in [
      RegExp(r'<vcs-pos:ep2AuthResult>\s*(\d+)\s*</vcs-pos:ep2AuthResult>'),
      RegExp(r'<ep2AuthResult>\s*(\d+)\s*</ep2AuthResult>'),
    ]) {
      final m = pattern.firstMatch(xml);
      if (m != null) return m.group(1)!.trim() == '0';
    }

    // 3. ep2AuthResponseCode
    for (final pattern in [
      RegExp(r'<vcs-pos:ep2AuthResponseCode>\s*([^<]+)\s*</vcs-pos:ep2AuthResponseCode>'),
      RegExp(r'<ep2AuthResponseCode>\s*([^<]+)\s*</ep2AuthResponseCode>'),
    ]) {
      final m = pattern.firstMatch(xml);
      if (m != null) return m.group(1)!.trim() == '00';
    }

    return false;
  }

  /// Extract the value of an XML element, handling namespaced tags.
  String? _parseField(String xml, String fieldName) {
    for (final pattern in [
      RegExp('<$fieldName>\\s*([^<]*)\\s*</$fieldName>', caseSensitive: false),
      RegExp('<vcs-pos:$fieldName>\\s*([^<]*)\\s*</vcs-pos:$fieldName>', caseSensitive: false),
      RegExp('<[\\w-]+:$fieldName>\\s*([^<]*)\\s*</[\\w-]+:$fieldName>', caseSensitive: false),
    ]) {
      final m = pattern.firstMatch(xml);
      if (m != null) return m.group(1)?.trim();
    }
    return null;
  }
}
