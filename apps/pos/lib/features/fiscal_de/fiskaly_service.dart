/// Fiskaly SIGN DE API v2 HTTP client.
///
/// Handles authentication (API key + secret → JWT), TSE lifecycle operations,
/// transaction signing, and export triggering. All calls go to the Fiskaly
/// KASSENSICHV middleware API v2.
///
/// Authentication tokens are cached in-memory and refreshed automatically
/// when they are within 5 minutes of expiry.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'fiskaly_models.dart';

// ---------------------------------------------------------------------------
// Exception
// ---------------------------------------------------------------------------

/// Thrown when the Fiskaly API returns a non-2xx response.
class FiskalyException implements Exception {
  const FiskalyException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() =>
      'FiskalyException($statusCode): $message';
}

// ---------------------------------------------------------------------------
// FiskalyService
// ---------------------------------------------------------------------------

/// HTTP client for the Fiskaly SIGN DE middleware API v2.
///
/// Inject a custom [http.Client] in tests to avoid real network calls.
///
/// Usage:
/// ```dart
/// final service = FiskalyService(config: myConfig);
/// await service.authenticate();
/// final tse = await service.createTse(tseId);
/// final tx  = await service.startTransaction(tseId: ..., transactionId: ..., clientId: ...);
/// final finished = await service.finishTransaction(...);
/// ```
class FiskalyService {
  FiskalyService({required this.config, http.Client? client})
      : _client = client ?? http.Client();

  /// Mutable so providers can swap config without recreating the service.
  FiskalyConfig config;

  final http.Client _client;

  // Cached JWT token.
  String? _jwtToken;
  DateTime? _tokenExpiry;

  // ---------------------------------------------------------------------------
  // Authentication
  // ---------------------------------------------------------------------------

  /// Obtains (or returns cached) JWT access token.
  ///
  /// Tokens are refreshed 5 minutes before expiry.
  Future<String> authenticate() async {
    if (_isTokenValid()) return _jwtToken!;

    final response = await _client.post(
      Uri.parse('${config.baseUrl}/auth'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'api_key': config.apiKey,
        'api_secret': config.apiSecret,
      }),
    );

    _assertSuccess(response, 'authenticate');

    final body = _decodeJson(response);
    _jwtToken = body['access_token'] as String;
    final expiresIn =
        (body['access_token_expires_in_seconds'] as num?)?.toInt() ??
            3600;
    _tokenExpiry =
        DateTime.now().add(Duration(seconds: expiresIn));
    return _jwtToken!;
  }

  /// Invalidates the cached token (e.g. on 401 response).
  void invalidateToken() {
    _jwtToken = null;
    _tokenExpiry = null;
  }

  // ---------------------------------------------------------------------------
  // TSE management
  // ---------------------------------------------------------------------------

  /// Creates a new TSE with [tseId] (UUID) or updates its description.
  ///
  /// The API uses PUT — idempotent on the same UUID.
  Future<TseInfo> createTse(
    String tseId, {
    String description = 'GastroCore POS',
  }) async {
    final token = await authenticate();
    final response = await _client.put(
      Uri.parse('${config.baseUrl}/tss/$tseId'),
      headers: _authHeaders(token),
      body: jsonEncode({'description': description}),
    );
    _assertSuccess(response, 'createTse');
    return TseInfo.fromJson(_decodeJson(response));
  }

  /// Fetches current TSE information (state, serial number, counters).
  Future<TseInfo> getTseInfo(String tseId) async {
    final token = await authenticate();
    final response = await _client.get(
      Uri.parse('${config.baseUrl}/tss/$tseId'),
      headers: _authHeaders(token),
    );
    _assertSuccess(response, 'getTseInfo');
    return TseInfo.fromJson(_decodeJson(response));
  }

  /// Transitions TSE to INITIALIZED state (sets admin PIN).
  Future<TseInfo> initializeTse(
    String tseId, {
    required String adminPin,
  }) async {
    final token = await authenticate();
    final response = await _client.patch(
      Uri.parse('${config.baseUrl}/tss/$tseId'),
      headers: _authHeaders(token),
      body: jsonEncode({
        'state': 'INITIALIZED',
        'admin_pin': adminPin,
      }),
    );
    _assertSuccess(response, 'initializeTse');
    return TseInfo.fromJson(_decodeJson(response));
  }

  /// Transitions TSE to ACTIVE state (requires admin PIN).
  Future<TseInfo> activateTse(
    String tseId, {
    required String adminPin,
  }) async {
    final token = await authenticate();
    final response = await _client.patch(
      Uri.parse('${config.baseUrl}/tss/$tseId'),
      headers: _authHeaders(token),
      body: jsonEncode({
        'state': 'ACTIVE',
        'admin_pin': adminPin,
      }),
    );
    _assertSuccess(response, 'activateTse');
    return TseInfo.fromJson(_decodeJson(response));
  }

  /// Registers a POS client/terminal with the TSE.
  Future<void> registerClient(
    String tseId,
    String clientId, {
    required String serialNumber,
  }) async {
    final token = await authenticate();
    final response = await _client.put(
      Uri.parse('${config.baseUrl}/tss/$tseId/client/$clientId'),
      headers: _authHeaders(token),
      body: jsonEncode({'serial_number': serialNumber}),
    );
    _assertSuccess(response, 'registerClient');
  }

  /// Triggers a TSE self-test (required periodically by KassenSichV).
  Future<TseInfo> runSelfTest(String tseId) async {
    final token = await authenticate();
    final response = await _client.post(
      Uri.parse('${config.baseUrl}/tss/$tseId/self_test'),
      headers: _authHeaders(token),
    );
    _assertSuccess(response, 'runSelfTest');
    return TseInfo.fromJson(_decodeJson(response));
  }

  // ---------------------------------------------------------------------------
  // Transactions
  // ---------------------------------------------------------------------------

  /// Starts a transaction on the TSE (tx_revision=1, state=ACTIVE).
  ///
  /// Each receipt must call [startTransaction] before the payment completes
  /// and [finishTransaction] after, with the signature applied to the receipt.
  Future<FiskalyTransaction> startTransaction({
    required String tseId,
    required String transactionId,
    required String clientId,
  }) async {
    final token = await authenticate();
    final response = await _client.put(
      Uri.parse(
          '${config.baseUrl}/tss/$tseId/tx/$transactionId?tx_revision=1'),
      headers: _authHeaders(token),
      body: jsonEncode({
        'state': 'ACTIVE',
        'client_id': clientId,
      }),
    );
    _assertSuccess(response, 'startTransaction');
    return FiskalyTransaction.fromJson(_decodeJson(response));
  }

  /// Finishes and signs a transaction (state=FINISHED).
  ///
  /// [txRevision] must be 2 for a simple start→finish flow; increment for
  /// any updates between start and finish.
  ///
  /// [amountsPerVatRate] is the DSFinV-K VAT breakdown used to build the
  /// process data string embedded in the signature.
  Future<FiskalyTransaction> finishTransaction({
    required String tseId,
    required String transactionId,
    required String clientId,
    required List<VatAmountPerRate> amountsPerVatRate,
    required String paymentType,
    required double paymentAmount,
    int txRevision = 2,
  }) async {
    final token = await authenticate();

    // Build amounts_per_vat_rate for Fiskaly schema.
    final vatRates = amountsPerVatRate
        .map((v) => {
              'vat_rate': v.vatRate,
              'amount': v.incl.toStringAsFixed(2),
            })
        .toList();

    final response = await _client.put(
      Uri.parse(
          '${config.baseUrl}/tss/$tseId/tx/$transactionId?tx_revision=$txRevision'),
      headers: _authHeaders(token),
      body: jsonEncode({
        'state': 'FINISHED',
        'client_id': clientId,
        'schema': {
          'standard_v1': {
            'receipt': {
              'receipt_type': 'RECEIPT',
              'amounts_per_vat_rate': vatRates,
              'amounts_per_payment_type': [
                {
                  'payment_type': paymentType,
                  'amount': paymentAmount.toStringAsFixed(2),
                },
              ],
            },
          },
        },
      }),
    );
    _assertSuccess(response, 'finishTransaction');
    return FiskalyTransaction.fromJson(_decodeJson(response));
  }

  // ---------------------------------------------------------------------------
  // Export
  // ---------------------------------------------------------------------------

  /// Triggers a DSFinV-K / TAR export on the Fiskaly backend.
  ///
  /// Returns the [ExportState] (state = PENDING initially).
  /// Poll [getExportStatus] until state = COMPLETED or FAILED.
  Future<ExportState> triggerExport(
    String tseId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final token = await authenticate();
    final body = <String, dynamic>{};
    if (startDate != null) {
      body['start_date'] = startDate.toUtc().toIso8601String();
    }
    if (endDate != null) {
      body['end_date'] = endDate.toUtc().toIso8601String();
    }
    final response = await _client.post(
      Uri.parse('${config.baseUrl}/tss/$tseId/export'),
      headers: _authHeaders(token),
      body: jsonEncode(body),
    );
    _assertSuccess(response, 'triggerExport');
    return ExportState.fromJson(_decodeJson(response));
  }

  /// Polls the status of a previously triggered export job.
  Future<ExportState> getExportStatus(
    String tseId,
    String exportId,
  ) async {
    final token = await authenticate();
    final response = await _client.get(
      Uri.parse(
          '${config.baseUrl}/tss/$tseId/export/$exportId'),
      headers: _authHeaders(token),
    );
    _assertSuccess(response, 'getExportStatus');
    return ExportState.fromJson(_decodeJson(response));
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  bool _isTokenValid() =>
      _jwtToken != null &&
      _tokenExpiry != null &&
      DateTime.now().isBefore(
        _tokenExpiry!.subtract(const Duration(minutes: 5)),
      );

  Map<String, String> _authHeaders(String token) => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  Map<String, dynamic> _decodeJson(http.Response response) =>
      jsonDecode(response.body) as Map<String, dynamic>;

  void _assertSuccess(http.Response response, String operation) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FiskalyException(
        '$operation failed: ${response.body}',
        statusCode: response.statusCode,
      );
    }
  }
}
