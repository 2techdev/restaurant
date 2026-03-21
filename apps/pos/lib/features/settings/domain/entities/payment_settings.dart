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
class MyPosConfig {
  const MyPosConfig({
    this.ip = '',
    this.port = 50100,
    this.currency = 'CHF',
  });

  /// Terminal IP address on the local network.
  final String ip;

  /// TCP port for MyPOS communication (default: 50100).
  final int port;

  /// ISO 4217 currency code (default: CHF for Switzerland).
  final String currency;

  MyPosConfig copyWith({
    String? ip,
    int? port,
    String? currency,
  }) =>
      MyPosConfig(
        ip: ip ?? this.ip,
        port: port ?? this.port,
        currency: currency ?? this.currency,
      );

  Map<String, dynamic> toJson() => {
        'ip': ip,
        'port': port,
        'currency': currency,
      };

  factory MyPosConfig.fromJson(Map<String, dynamic> json) => MyPosConfig(
        ip: (json['ip'] as String?) ?? '',
        port: (json['port'] as int?) ?? 50100,
        currency: (json['currency'] as String?) ?? 'CHF',
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MyPosConfig &&
          ip == other.ip &&
          port == other.port &&
          currency == other.currency;

  @override
  int get hashCode => Object.hash(ip, port, currency);
}

/// Top-level payment settings aggregating gateway selection and per-gateway
/// configurations.
class PaymentSettings {
  const PaymentSettings({
    this.activeGateway = PaymentGateway.none,
    this.wallee = const WalleeConfig(),
    this.mypos = const MyPosConfig(),
  });

  /// Which hardware gateway is currently active.
  final PaymentGateway activeGateway;

  /// Wallee terminal configuration (persisted even when not active).
  final WalleeConfig wallee;

  /// MyPOS terminal configuration (persisted even when not active).
  final MyPosConfig mypos;

  PaymentSettings copyWith({
    PaymentGateway? activeGateway,
    WalleeConfig? wallee,
    MyPosConfig? mypos,
  }) =>
      PaymentSettings(
        activeGateway: activeGateway ?? this.activeGateway,
        wallee: wallee ?? this.wallee,
        mypos: mypos ?? this.mypos,
      );

  Map<String, dynamic> toJson() => {
        'activeGateway': activeGateway.name,
        'wallee': wallee.toJson(),
        'mypos': mypos.toJson(),
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
          mypos == other.mypos;

  @override
  int get hashCode => Object.hash(activeGateway, wallee, mypos);
}
