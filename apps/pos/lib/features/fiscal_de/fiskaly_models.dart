/// Data models for Fiskaly SIGN DE API v2 integration.
///
/// Implements the KassenSichV (Kassensicherungsverordnung) data structures
/// required for German fiscal compliance. Every receipt must carry the
/// signature fields in [TseSignatureData].
library;

import 'dart:convert';

// ---------------------------------------------------------------------------
// TSE state
// ---------------------------------------------------------------------------

/// TSE lifecycle states as defined by Fiskaly SIGN DE middleware API v2.
enum TseState {
  /// TSE object has been created in the Fiskaly backend but not yet set up.
  created,

  /// TSE has been initialized (admin PIN set, ready to activate).
  initialized,

  /// TSE is active and can sign transactions.
  active,

  /// TSE has been permanently decommissioned.
  disabled,

  /// State is unknown or not recognized.
  unknown,
}

/// Parses a Fiskaly state string into [TseState].
TseState parseTseState(String? s) => switch ((s ?? '').toUpperCase()) {
      'CREATED' => TseState.created,
      'INITIALIZED' => TseState.initialized,
      'ACTIVE' => TseState.active,
      'DISABLED' => TseState.disabled,
      _ => TseState.unknown,
    };

// ---------------------------------------------------------------------------
// FiskalyConfig
// ---------------------------------------------------------------------------

/// Configuration for the Fiskaly SIGN DE API.
///
/// Stored in SharedPreferences and loaded at app start. When [isConfigured]
/// is false the fiscal DE feature is silently skipped.
class FiskalyConfig {
  const FiskalyConfig({
    required this.apiKey,
    required this.apiSecret,
    this.environment = 'test',
    this.tseId,
    this.clientId,
    this.adminPin = '12345',
  });

  final String apiKey;
  final String apiSecret;

  /// Fiskaly environment: 'test' or 'production'.
  final String environment;

  /// TSE (Technische Sicherheitseinrichtung) UUID — set after first creation.
  final String? tseId;

  /// Client identifier for this POS terminal (must be unique per register).
  final String? clientId;

  /// TSE admin PIN (required for ACTIVE state transition).
  final String adminPin;

  /// Base URL for the Fiskaly KASSENSICHV middleware API v2.
  String get baseUrl =>
      'https://kassensichv-middleware.fiskaly.com/api/v2';

  /// Returns true when API credentials are present.
  bool get isConfigured => apiKey.isNotEmpty && apiSecret.isNotEmpty;

  FiskalyConfig copyWith({
    String? apiKey,
    String? apiSecret,
    String? environment,
    String? tseId,
    String? clientId,
    String? adminPin,
  }) =>
      FiskalyConfig(
        apiKey: apiKey ?? this.apiKey,
        apiSecret: apiSecret ?? this.apiSecret,
        environment: environment ?? this.environment,
        tseId: tseId ?? this.tseId,
        clientId: clientId ?? this.clientId,
        adminPin: adminPin ?? this.adminPin,
      );

  Map<String, dynamic> toJson() => {
        'apiKey': apiKey,
        'apiSecret': apiSecret,
        'environment': environment,
        'tseId': tseId,
        'clientId': clientId,
        'adminPin': adminPin,
      };

  factory FiskalyConfig.fromJson(Map<String, dynamic> json) => FiskalyConfig(
        apiKey: json['apiKey'] as String? ?? '',
        apiSecret: json['apiSecret'] as String? ?? '',
        environment: json['environment'] as String? ?? 'test',
        tseId: json['tseId'] as String?,
        clientId: json['clientId'] as String?,
        adminPin: json['adminPin'] as String? ?? '12345',
      );

  factory FiskalyConfig.empty() =>
      const FiskalyConfig(apiKey: '', apiSecret: '');

  String toJsonString() => jsonEncode(toJson());

  factory FiskalyConfig.fromJsonString(String s) =>
      FiskalyConfig.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

// ---------------------------------------------------------------------------
// TseInfo
// ---------------------------------------------------------------------------

/// Information about a TSE returned by the Fiskaly API.
class TseInfo {
  const TseInfo({
    required this.id,
    required this.state,
    required this.serialNumber,
    required this.signatureAlgorithm,
    required this.signatureCounter,
    this.description,
    this.createdAt,
  });

  final String id;
  final TseState state;

  /// TSE serial number (hex-encoded). Required on German receipts (§6 KassenSichV).
  final String serialNumber;

  /// Signature algorithm, e.g. 'ecdsa-plain-SHA384'.
  final String signatureAlgorithm;

  /// Cumulative number of signatures issued.
  final int signatureCounter;

  final String? description;
  final DateTime? createdAt;

  factory TseInfo.fromJson(Map<String, dynamic> json) => TseInfo(
        id: json['_id'] as String? ?? json['id'] as String? ?? '',
        state: parseTseState(json['state'] as String?),
        serialNumber: json['serial_number'] as String? ?? '',
        signatureAlgorithm:
            json['signature_algorithm'] as String? ?? '',
        signatureCounter:
            (json['signature_counter'] as num?)?.toInt() ?? 0,
        description: json['description'] as String?,
        createdAt: json['time_creation'] != null
            ? DateTime.tryParse(json['time_creation'] as String)
            : null,
      );
}

// ---------------------------------------------------------------------------
// TseSignatureData
// ---------------------------------------------------------------------------

/// Mandatory TSE signature fields for German receipts (KassenSichV §6).
///
/// All fields must be printed on every receipt issued in Germany:
///   • Transaktion-Nummer  → [transactionNumber]
///   • Signatur-Zähler     → [signatureCounter]
///   • Anfangs-Zeit        → [startTime]
///   • End-Zeit            → [endTime]
///   • Signatur            → [signatureValue] (Base64)
///   • Seriennummer        → [tseSerialNumber] (hex)
///   • Algorithmus         → [algorithm]
///   • Kassenbeleg-V1      → [processType]
class TseSignatureData {
  const TseSignatureData({
    required this.transactionNumber,
    required this.signatureCounter,
    required this.startTime,
    required this.endTime,
    required this.signatureValue,
    required this.tseSerialNumber,
    required this.algorithm,
    required this.publicKey,
    required this.processType,
    required this.processData,
  });

  /// Sequential transaction number assigned by the TSE.
  final int transactionNumber;

  /// Cumulative signature counter at time of signing.
  final int signatureCounter;

  final DateTime startTime;
  final DateTime endTime;

  /// Base64-encoded signature value.
  final String signatureValue;

  /// Hex-encoded TSE serial number.
  final String tseSerialNumber;

  /// Signature algorithm (e.g. 'ecdsa-plain-SHA384').
  final String algorithm;

  /// Base64-encoded public key of the TSE.
  final String publicKey;

  /// Fiskaly process type (e.g. 'Kassenbeleg-V1').
  final String processType;

  /// DSFinV-K process data string.
  final String processData;

  factory TseSignatureData.fromJson(Map<String, dynamic> json) {
    final sig =
        (json['signature'] as Map<String, dynamic>?) ?? const {};
    final tse =
        (json['tse'] as Map<String, dynamic>?) ?? const {};
    return TseSignatureData(
      transactionNumber:
          (json['transaction_number'] as num?)?.toInt() ?? 0,
      signatureCounter:
          (sig['signature_counter'] as num?)?.toInt() ?? 0,
      startTime: DateTime.tryParse(
              json['time_start'] as String? ?? '') ??
          DateTime.now(),
      endTime:
          DateTime.tryParse(json['time_end'] as String? ?? '') ??
              DateTime.now(),
      signatureValue: sig['value'] as String? ?? '',
      tseSerialNumber: tse['serial_number'] as String? ?? '',
      algorithm: tse['signature_algorithm'] as String? ?? '',
      publicKey: tse['public_key'] as String? ?? '',
      processType: json['process_type'] as String? ?? '',
      processData: json['process_data'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'transaction_number': transactionNumber,
        'signature_counter': signatureCounter,
        'time_start': startTime.toIso8601String(),
        'time_end': endTime.toIso8601String(),
        'signature_value': signatureValue,
        'tse_serial_number': tseSerialNumber,
        'algorithm': algorithm,
        'public_key': publicKey,
        'process_type': processType,
        'process_data': processData,
      };
}

// ---------------------------------------------------------------------------
// FiskalyTransaction
// ---------------------------------------------------------------------------

/// A Fiskaly transaction (started or finished).
class FiskalyTransaction {
  const FiskalyTransaction({
    required this.id,
    required this.transactionNumber,
    required this.state,
    this.signature,
  });

  final String id;
  final int transactionNumber;

  /// 'ACTIVE' = started, 'FINISHED' = signed and closed.
  final String state;

  /// Populated after the transaction is finished (state = 'FINISHED').
  final TseSignatureData? signature;

  bool get isActive => state == 'ACTIVE';
  bool get isFinished => state == 'FINISHED';

  factory FiskalyTransaction.fromJson(Map<String, dynamic> json) =>
      FiskalyTransaction(
        id: json['_id'] as String? ?? json['id'] as String? ?? '',
        transactionNumber:
            (json['transaction_number'] as num?)?.toInt() ?? 0,
        state: json['state'] as String? ?? '',
        signature: (json['signature'] != null ||
                json['time_start'] != null)
            ? TseSignatureData.fromJson(json)
            : null,
      );
}

// ---------------------------------------------------------------------------
// ExportState
// ---------------------------------------------------------------------------

/// State of a DSFinV-K / TAR export job.
class ExportState {
  const ExportState({
    required this.id,
    required this.state,
    this.href,
    this.startedAt,
    this.completedAt,
    this.error,
  });

  final String id;

  /// 'PENDING', 'WORKING', 'COMPLETED', 'FAILED'.
  final String state;

  /// Download URL — only set when state = 'COMPLETED'.
  final String? href;

  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? error;

  bool get isCompleted => state == 'COMPLETED';
  bool get isFailed => state == 'FAILED';
  bool get isPending => state == 'PENDING' || state == 'WORKING';

  factory ExportState.fromJson(Map<String, dynamic> json) =>
      ExportState(
        id: json['_id'] as String? ?? json['id'] as String? ?? '',
        state: json['state'] as String? ?? 'PENDING',
        href: json['href'] as String?,
        startedAt: json['time_start'] != null
            ? DateTime.tryParse(json['time_start'] as String)
            : null,
        completedAt: json['time_end'] != null
            ? DateTime.tryParse(json['time_end'] as String)
            : null,
        error: json['error'] as String?,
      );
}

// ---------------------------------------------------------------------------
// VatAmountPerRate — helper for process data
// ---------------------------------------------------------------------------

/// A tax rate + amounts tuple used when building Fiskaly process data.
class VatAmountPerRate {
  const VatAmountPerRate({
    required this.vatRate,
    required this.incl,
    required this.excl,
    required this.vat,
  });

  /// VAT rate percentage as string (e.g. '19.00' or 'NULL' for 0%).
  final String vatRate;

  /// Tax-inclusive amount in EUR (2 decimal places).
  final double incl;

  /// Tax-exclusive (net) amount in EUR.
  final double excl;

  /// VAT amount in EUR.
  final double vat;
}
