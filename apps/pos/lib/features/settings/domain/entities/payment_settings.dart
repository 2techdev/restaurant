/// Payment gateway configuration settings entity.
///
/// Supports Wallee (LTI protocol) and MyPOS terminals.
/// Only one gateway can be active at a time.
library;

import 'dart:convert';

enum PaymentGateway {
  none,
  wallee,
  mypos;

  String get label => switch (this) {
        none => 'No terminal (manual)',
        wallee => 'Wallee',
        mypos => 'MyPOS',
      };

  static PaymentGateway fromString(String s) =>
      PaymentGateway.values.firstWhere(
        (e) => e.name == s,
        orElse: () => PaymentGateway.none,
      );
}

/// Wallee payment terminal configuration (LTI protocol).
class WalleeConfig {
  const WalleeConfig({
    this.terminalIp = '',
    this.terminalPort = 50000,
    this.posId = '',
  });

  /// Terminal IP address on the local network.
  final String terminalIp;

  /// LTI TCP port (Wallee default: 50000).
  final int terminalPort;

  /// POS identifier registered on the Wallee platform.
  final String posId;

  WalleeConfig copyWith({
    String? terminalIp,
    int? terminalPort,
    String? posId,
  }) =>
      WalleeConfig(
        terminalIp: terminalIp ?? this.terminalIp,
        terminalPort: terminalPort ?? this.terminalPort,
        posId: posId ?? this.posId,
      );

  Map<String, dynamic> toJson() => {
        'terminalIp': terminalIp,
        'terminalPort': terminalPort,
        'posId': posId,
      };

  factory WalleeConfig.fromJson(Map<String, dynamic> json) => WalleeConfig(
        terminalIp: (json['terminalIp'] as String?) ?? '',
        terminalPort: (json['terminalPort'] as int?) ?? 50000,
        posId: (json['posId'] as String?) ?? '',
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WalleeConfig &&
          terminalIp == other.terminalIp &&
          terminalPort == other.terminalPort &&
          posId == other.posId;

  @override
  int get hashCode => Object.hash(terminalIp, terminalPort, posId);
}

/// MyPOS payment terminal configuration.
///
/// When [enabled] is true, the KART and TWINT methods on the payment
/// screen route directly through the MyPOS Sigma terminal over WiFi
/// (TCP/IP). Cashier doesn't see the manual numpad — the terminal owns
/// the UI from there (insert/swipe/contactless, PIN entry, QR for TWINT)
/// and we close the ticket only once the device returns an approved
/// transaction id. When false (default), KART stays one-tap and TWINT
/// is treated as a manual confirmation (operator says "ödendi").
class MyPosConfig {
  const MyPosConfig({
    this.enabled = false,
    this.ip = '192.168.1.131',
    this.port = 60180,
    this.currency = 'CHF',
    this.language = 'de',
    this.merchantId = '',
    this.terminalId = '',
    this.timeoutSeconds = 120,
  });

  /// Master switch. When false the existing manual KART / TWINT flow is
  /// used (terminal not contacted).
  final bool enabled;

  /// Terminal IP address on the local network.
  final String ip;

  /// TCP port for MyPOS SlaveSDK (Sigma default: 60180).
  final int port;

  /// ISO 4217 currency code for card payments. TWINT is always CHF
  /// regardless of this setting.
  final String currency;

  /// Terminal UI language code: `de`, `fr`, `it`, `en`.
  final String language;

  /// MyPOS-provided merchant identifier (optional in current SDK build —
  /// reserved for future tenant routing).
  final String merchantId;

  /// MyPOS-provided terminal identifier (optional — reserved).
  final String terminalId;

  /// Transaction timeout in seconds passed to the terminal.
  final int timeoutSeconds;

  MyPosConfig copyWith({
    bool? enabled,
    String? ip,
    int? port,
    String? currency,
    String? language,
    String? merchantId,
    String? terminalId,
    int? timeoutSeconds,
  }) =>
      MyPosConfig(
        enabled: enabled ?? this.enabled,
        ip: ip ?? this.ip,
        port: port ?? this.port,
        currency: currency ?? this.currency,
        language: language ?? this.language,
        merchantId: merchantId ?? this.merchantId,
        terminalId: terminalId ?? this.terminalId,
        timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'ip': ip,
        'port': port,
        'currency': currency,
        'language': language,
        'merchantId': merchantId,
        'terminalId': terminalId,
        'timeoutSeconds': timeoutSeconds,
      };

  factory MyPosConfig.fromJson(Map<String, dynamic> json) => MyPosConfig(
        enabled: (json['enabled'] as bool?) ?? false,
        ip: (json['ip'] as String?) ?? '192.168.1.131',
        port: (json['port'] as int?) ?? 60180,
        currency: (json['currency'] as String?) ?? 'CHF',
        language: (json['language'] as String?) ?? 'de',
        merchantId: (json['merchantId'] as String?) ?? '',
        terminalId: (json['terminalId'] as String?) ?? '',
        timeoutSeconds: (json['timeoutSeconds'] as int?) ?? 120,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MyPosConfig &&
          enabled == other.enabled &&
          ip == other.ip &&
          port == other.port &&
          currency == other.currency &&
          language == other.language &&
          merchantId == other.merchantId &&
          terminalId == other.terminalId &&
          timeoutSeconds == other.timeoutSeconds;

  @override
  int get hashCode => Object.hash(
        enabled,
        ip,
        port,
        currency,
        language,
        merchantId,
        terminalId,
        timeoutSeconds,
      );
}

/// EcoCash V4.2 cash recycler kiosk configuration.
///
/// The kiosk speaks HTTP/JSON on port 8080 over the local network. When
/// [enabled] is true, the BAR (cash) tender on the payment screen routes
/// through the kiosk: the device accepts notes/coins from the customer and
/// auto-dispenses change, instead of the cashier manually entering the
/// tendered amount on the numpad. When false the cash flow is unchanged.
class CashCollectorConfig {
  const CashCollectorConfig({
    this.enabled = false,
    this.baseUrl = 'http://192.168.1.149:8080/',
    this.deviceId = '00141',
    this.clientId = '2',
    this.tokenPass = '123456',
    this.currency = 'CHF',
  });

  /// Master switch. When false the existing manual cash flow is used.
  final bool enabled;

  /// Base URL of the EcoCashSerivce1117 service (trailing slash optional).
  final String baseUrl;

  /// Device identifier provisioned on the kiosk (e.g. "00141").
  final String deviceId;

  /// Terminal / client identifier (e.g. "2"). Also used as `user_name`.
  final String clientId;

  /// Cleartext token password (MD5'd on the wire). Change from default in
  /// every production deployment.
  final String tokenPass;

  /// ISO 4217 currency code for display formatting (CHF for Swiss pilot).
  final String currency;

  CashCollectorConfig copyWith({
    bool? enabled,
    String? baseUrl,
    String? deviceId,
    String? clientId,
    String? tokenPass,
    String? currency,
  }) =>
      CashCollectorConfig(
        enabled: enabled ?? this.enabled,
        baseUrl: baseUrl ?? this.baseUrl,
        deviceId: deviceId ?? this.deviceId,
        clientId: clientId ?? this.clientId,
        tokenPass: tokenPass ?? this.tokenPass,
        currency: currency ?? this.currency,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'baseUrl': baseUrl,
        'deviceId': deviceId,
        'clientId': clientId,
        'tokenPass': tokenPass,
        'currency': currency,
      };

  factory CashCollectorConfig.fromJson(Map<String, dynamic> json) =>
      CashCollectorConfig(
        enabled: (json['enabled'] as bool?) ?? false,
        baseUrl: (json['baseUrl'] as String?) ?? 'http://192.168.1.149:8080/',
        deviceId: (json['deviceId'] as String?) ?? '00141',
        clientId: (json['clientId'] as String?) ?? '2',
        tokenPass: (json['tokenPass'] as String?) ?? '123456',
        currency: (json['currency'] as String?) ?? 'CHF',
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CashCollectorConfig &&
          enabled == other.enabled &&
          baseUrl == other.baseUrl &&
          deviceId == other.deviceId &&
          clientId == other.clientId &&
          tokenPass == other.tokenPass &&
          currency == other.currency;

  @override
  int get hashCode =>
      Object.hash(enabled, baseUrl, deviceId, clientId, tokenPass, currency);
}

/// Top-level payment settings aggregating gateway selection and per-gateway
/// configurations.
class PaymentSettings {
  const PaymentSettings({
    this.activeGateway = PaymentGateway.none,
    this.wallee = const WalleeConfig(),
    this.mypos = const MyPosConfig(),
    this.cashCollector = const CashCollectorConfig(),
  });

  /// Which hardware gateway is currently active.
  final PaymentGateway activeGateway;

  /// Wallee terminal configuration (persisted even when not active).
  final WalleeConfig wallee;

  /// MyPOS terminal configuration (persisted even when not active).
  final MyPosConfig mypos;

  /// EcoCash cash recycler configuration. Independent of [activeGateway]
  /// (cash collector handles BAR, the gateway handles KARTE/TWINT).
  final CashCollectorConfig cashCollector;

  PaymentSettings copyWith({
    PaymentGateway? activeGateway,
    WalleeConfig? wallee,
    MyPosConfig? mypos,
    CashCollectorConfig? cashCollector,
  }) =>
      PaymentSettings(
        activeGateway: activeGateway ?? this.activeGateway,
        wallee: wallee ?? this.wallee,
        mypos: mypos ?? this.mypos,
        cashCollector: cashCollector ?? this.cashCollector,
      );

  Map<String, dynamic> toJson() => {
        'activeGateway': activeGateway.name,
        'wallee': wallee.toJson(),
        'mypos': mypos.toJson(),
        'cashCollector': cashCollector.toJson(),
      };

  factory PaymentSettings.fromJson(Map<String, dynamic> json) =>
      PaymentSettings(
        activeGateway: PaymentGateway.fromString(
          (json['activeGateway'] as String?) ?? 'none',
        ),
        wallee: json['wallee'] != null
            ? WalleeConfig.fromJson(json['wallee'] as Map<String, dynamic>)
            : const WalleeConfig(),
        mypos: json['mypos'] != null
            ? MyPosConfig.fromJson(json['mypos'] as Map<String, dynamic>)
            : const MyPosConfig(),
        cashCollector: json['cashCollector'] != null
            ? CashCollectorConfig.fromJson(
                json['cashCollector'] as Map<String, dynamic>)
            : const CashCollectorConfig(),
      );

  String toJsonString() => jsonEncode(toJson());

  factory PaymentSettings.fromJsonString(String s) =>
      PaymentSettings.fromJson(jsonDecode(s) as Map<String, dynamic>);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PaymentSettings &&
          activeGateway == other.activeGateway &&
          wallee == other.wallee &&
          mypos == other.mypos &&
          cashCollector == other.cashCollector;

  @override
  int get hashCode => Object.hash(activeGateway, wallee, mypos, cashCollector);
}
